//
//  WorkflowStore.swift
//  boringNotch
//
//  Beobachtbarer Store fuer den Workflow-Tab: Long-Poll, Drosselung und Aktionen.
//

import Combine
import Foundation

@MainActor
final class WorkflowStore: ObservableObject {
    enum Connection: Equatable, Sendable {
        case notRunning
        case connecting
        case connected
        case error(String)
    }

    static let shared = WorkflowStore()

    @Published private(set) var state: WorkflowState?
    @Published private(set) var connection: Connection = .notRunning
    @Published var lastActionError: String?

    private let client: WorkflowClient
    private var pollTask: Task<Void, Never>?
    private var isActive = false
    private var lastRev: Int?
    private var backoffAttempt = 0

    private static let backoffSeconds: [UInt64] = [2, 5, 10, 30]
    private static let throttledInterval: UInt64 = 5_000_000_000
    private static let longPollWait = 8000

    init(client: WorkflowClient = WorkflowClient()) {
        self.client = client
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        if state == nil {
            connection = .connecting
        }
        pollTask = Task { [weak self] in
            guard let self = self else { return }
            await self.runLoop()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        lastRev = nil
    }

    /// Aktiver Tab/offene Notch: Long-Poll. Sonst normaler GET alle 5 s (Badge).
    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active

        guard pollTask != nil else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self = self else { return }
            await self.runLoop()
        }
    }

    // MARK: - Derived state

    var needsYouCount: Int {
        state?.counts.needsYou ?? 0
    }

    /// approval/question, working, waiting, idle; `ended` nur bei `showEnded`.
    func sortedSessions(showEnded: Bool = false) -> [WorkflowSession] {
        guard let sessions = state?.sessions else { return [] }

        return sessions
            .filter { showEnded || $0.normalizedStatus != "ended" }
            .sorted { left, right in
                let leftRank = Self.rank(for: left)
                let rightRank = Self.rank(for: right)
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return (left.updatedAt ?? 0) > (right.updatedAt ?? 0)
            }
    }

    private static func rank(for session: WorkflowSession) -> Int {
        switch session.normalizedStatus {
        case "approval", "question":
            return 0
        case "working":
            return 1
        case "waiting":
            return 2
        case "ended":
            return 4
        default:
            return 3
        }
    }

    // MARK: - Actions

    func approve(session: WorkflowSession) async {
        guard let pending = session.pending, !pending.id.isEmpty else {
            lastActionError = "Keine offene Aktion"
            return
        }
        let action: [String: Any] = [
            "type": "decide",
            "sessionId": session.actionKey,
            "pendingId": pending.id,
            "behavior": "allow"
        ]
        await perform(action)
    }

    func deny(session: WorkflowSession) async {
        guard let pending = session.pending, !pending.id.isEmpty else {
            lastActionError = "Keine offene Aktion"
            return
        }
        let action: [String: Any] = [
            "type": "decide",
            "sessionId": session.actionKey,
            "pendingId": pending.id,
            "behavior": "deny"
        ]
        await perform(action)
    }

    func answer(session: WorkflowSession, text: String) async {
        guard let pending = session.pending, !pending.id.isEmpty else {
            lastActionError = "Keine offene Aktion"
            return
        }
        let action: [String: Any] = [
            "type": "answer",
            "sessionId": session.actionKey,
            "pendingId": pending.id,
            "answer": text
        ]
        await perform(action)
    }

    func reply(session: WorkflowSession, text: String) async {
        guard let pending = session.pending, !pending.id.isEmpty else {
            lastActionError = "Keine offene Aktion"
            return
        }
        let action: [String: Any] = [
            "type": "reply",
            "sessionId": session.actionKey,
            "pendingId": pending.id,
            "text": text
        ]
        await perform(action)
    }

    func stop(session: WorkflowSession) async {
        let action: [String: Any] = [
            "type": "stop",
            "sessionId": session.actionKey,
            "mode": "soft"
        ]
        await perform(action)
    }

    private func perform(_ action: [String: Any]) async {
        do {
            let result = try await client.send(action: action)
            if result.ok {
                lastActionError = nil
            } else if let reason = result.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !reason.isEmpty {
                lastActionError = reason
            } else {
                lastActionError = "Aktion fehlgeschlagen"
            }
        } catch is CancellationError {
            return
        } catch {
            lastActionError = Self.message(for: error)
        }

        // Nach jeder Aktion sofort neu laden.
        await refreshNow()
    }

    // MARK: - Polling

    private func runLoop() async {
        backoffAttempt = 0

        while !Task.isCancelled {
            do {
                let newState: WorkflowState
                if isActive {
                    newState = try await client.fetchState(since: lastRev, wait: Self.longPollWait)
                } else {
                    newState = try await client.fetchState()
                }

                guard !Task.isCancelled else { break }
                apply(newState)
                backoffAttempt = 0

                if !isActive {
                    try? await Task.sleep(nanoseconds: Self.throttledInterval)
                }
            } catch is CancellationError {
                break
            } catch {
                guard !Task.isCancelled else { break }
                connection = Self.connection(for: error)
                // Nach Fehlern wieder mit einem vollstaendigen GET beginnen.
                lastRev = nil
                let seconds = Self.backoffSeconds[min(backoffAttempt, Self.backoffSeconds.count - 1)]
                backoffAttempt += 1
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
        }
    }

    private func refreshNow() async {
        do {
            let newState = try await client.fetchState()
            apply(newState)
        } catch is CancellationError {
            return
        } catch {
            connection = Self.connection(for: error)
        }
    }

    private func apply(_ newState: WorkflowState) {
        state = newState
        lastRev = newState.rev
        connection = .connected
    }

    // MARK: - Error mapping

    private static func connection(for error: Error) -> Connection {
        if let clientError = error as? WorkflowClientError, case .notRunning = clientError {
            return .notRunning
        }
        return .error(message(for: error))
    }

    private static func message(for error: Error) -> String {
        guard let clientError = error as? WorkflowClientError else {
            return "Unbekannter Fehler"
        }
        switch clientError {
        case .notRunning:
            return "Workflow-App läuft nicht"
        case .unauthorized:
            return "Nicht autorisiert"
        case .http(let statusCode):
            return "HTTP \(statusCode)"
        case .decoding:
            return "Ungültige Antwort"
        case .transport:
            return "Keine Verbindung"
        }
    }
}
