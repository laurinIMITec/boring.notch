//
//  WorkflowModels.swift
//  boringNotch
//
//  Tolerante Decodable-Modelle fuer den Workflow-Tab (API-Vertrag siehe brief.md).
//

import Foundation

// MARK: - JSONValue

/// Beliebiger JSON-Wert, z. B. fuer `pending.input` oder Frage-Optionen.
enum JSONValue: Decodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    /// Nur echte Strings werden angezeigt; alles andere wird weggelassen.
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

// MARK: - Session

struct WorkflowSession: Decodable, Identifiable, Equatable, Sendable {
    /// Aktions-ID (`sessionId` im POST-Body).
    let key: String
    /// Das optionale `id`-Feld der API (nicht die Identifiable-ID).
    let sessionId: String
    let project: String?
    let title: String?
    let cwd: String?
    let status: String?
    let activity: String?
    let tool: String?
    let lastPrompt: String?
    let host: String?
    let source: String?
    /// Millisekunden seit Epoch.
    let updatedAt: Double?
    /// Millisekunden seit Epoch.
    let startedAt: Double?
    let cost: Double?
    let pending: WorkflowPending?
    let pendingCount: Int?

    enum CodingKeys: String, CodingKey {
        case key
        case sessionId = "id"
        case project
        case title
        case cwd
        case status
        case activity
        case tool
        case lastPrompt
        case host
        case source
        case updatedAt
        case startedAt
        case cost
        case pending
        case pendingCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = container.tolerant(.key) ?? ""
        sessionId = container.tolerant(.sessionId) ?? ""
        project = container.tolerant(.project)
        title = container.tolerant(.title)
        cwd = container.tolerant(.cwd)
        status = container.tolerant(.status)
        activity = container.tolerant(.activity)
        tool = container.tolerant(.tool)
        lastPrompt = container.tolerant(.lastPrompt)
        host = container.tolerant(.host)
        source = container.tolerant(.source)
        updatedAt = container.tolerant(.updatedAt)
        startedAt = container.tolerant(.startedAt)
        cost = container.tolerant(.cost)
        pending = container.tolerant(.pending)
        pendingCount = container.tolerant(.pendingCount)
    }

    /// Identifiable ueber `key`, mit `id` als Fallback.
    var id: String { key.isEmpty ? sessionId : key }

    /// ID fuer `/api/action`.
    var actionKey: String { id }

    /// Status inkl. Aliase (`permission` -> `approval`, `answer` -> `waiting`).
    var normalizedStatus: String {
        switch (status ?? "").lowercased() {
        case "permission", "approval":
            return "approval"
        case "answer", "waiting":
            return "waiting"
        case "working":
            return "working"
        case "question":
            return "question"
        case "idle":
            return "idle"
        case "ended":
            return "ended"
        case let value where !value.isEmpty:
            return value
        default:
            return "idle"
        }
    }
}

// MARK: - Pending

struct WorkflowPending: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let kind: String?
    let summary: String?
    let tool: String?
    let input: JSONValue?
    let context: String?
    let expiresAt: Double?
    let questions: [WorkflowQuestion]?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case summary
        case tool
        case input
        case context
        case expiresAt
        case questions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.tolerant(.id) ?? ""
        kind = container.tolerant(.kind)
        summary = container.tolerant(.summary)
        tool = container.tolerant(.tool)
        input = container.tolerant(.input)
        context = container.tolerant(.context)
        expiresAt = container.tolerant(.expiresAt)

        let entries: [Lossy<WorkflowQuestion>] = container.tolerant(.questions) ?? []
        questions = entries.compactMap(\.value)
    }

    /// `input` nur anzeigen, wenn es wirklich ein String ist.
    var inputText: String? { input?.stringValue }
}

// MARK: - Question

struct WorkflowQuestion: Decodable, Equatable, Sendable {
    let question: String
    let header: String?
    let multiSelect: Bool?
    let options: [JSONValue]?

    enum CodingKeys: String, CodingKey {
        case question
        case header
        case multiSelect
        case options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        question = container.tolerant(.question) ?? ""
        header = container.tolerant(.header)
        multiSelect = container.tolerant(.multiSelect)
        options = container.tolerant(.options)
    }

    /// Optionen als Text: Strings direkt, Objekte ueber `label`.
    var optionLabels: [String] {
        (options ?? []).compactMap { option in
            switch option {
            case .string(let label):
                return label
            case .object(let object):
                return object["label"]?.stringValue
            default:
                return nil
            }
        }
    }
}

// MARK: - Counts

struct WorkflowCounts: Decodable, Equatable, Sendable {
    let running: Int
    let open: Int
    let needsYou: Int

    enum CodingKeys: String, CodingKey {
        case running
        case open
        case needsYou
    }

    init(running: Int = 0, open: Int = 0, needsYou: Int = 0) {
        self.running = running
        self.open = open
        self.needsYou = needsYou
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        running = container.tolerant(.running) ?? 0
        open = container.tolerant(.open) ?? 0
        needsYou = container.tolerant(.needsYou) ?? 0
    }
}

// MARK: - State

struct WorkflowState: Decodable, Equatable, Sendable {
    let version: String?
    let rev: Int
    let sessions: [WorkflowSession]
    let counts: WorkflowCounts

    enum CodingKeys: String, CodingKey {
        case version
        case rev
        case sessions
        case counts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = container.tolerant(.version)
        rev = container.tolerant(.rev) ?? 0

        let entries: [Lossy<WorkflowSession>] = container.tolerant(.sessions) ?? []
        sessions = entries.compactMap(\.value)

        let decodedCounts: WorkflowCounts? = container.tolerant(.counts)
        counts = decodedCounts ?? WorkflowCounts()
    }
}

// MARK: - Action result

struct WorkflowActionResult: Decodable, Equatable, Sendable {
    let ok: Bool
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = container.tolerant(.ok) ?? false
        reason = container.tolerant(.reason)
    }
}

// MARK: - Tolerantes Decoding

/// Dekodiert ein Array-Element einzeln fehlertolerant; ungueltige Elemente werden uebersprungen.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    /// Liefert `nil` statt zu werfen, wenn ein Feld fehlt oder einen unerwarteten Typ hat.
    func tolerant<Value: Decodable>(_ key: Key) -> Value? {
        (try? decodeIfPresent(Value.self, forKey: key)) ?? nil
    }
}
