//
//  WorkflowView.swift
//  boringNotch
//
//  Liste der Workflow-Sitzungen inklusive direkter Aktionen.
//

import Defaults
import Foundation
import SwiftUI

@MainActor
struct WorkflowView: View {
    @ObservedObject private var store = WorkflowStore.shared
    @Default(.workflowShowEnded) private var showEnded: Bool

    private var sessions: [WorkflowSession] {
        store.sortedSessions(showEnded: showEnded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = store.lastActionError, !error.isEmpty {
                errorBanner(error)
            }

            if sessions.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(sessions) { session in
                            WorkflowSessionRow(session: session, store: store)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .onAppear { store.setActive(true) }
        .onDisappear { store.setActive(false) }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.orange.opacity(0.12))
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 20, weight: .light))
            Text(emptyStateTitle)
                .font(.system(size: 12, weight: .medium))
            Text(emptyStateMessage)
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var emptyStateIcon: String {
        switch store.connection {
        case .notRunning:
            return "bolt.slash"
        case .connecting:
            return "bolt.horizontal.circle"
        case .error:
            return "wifi.exclamationmark"
        case .connected:
            return "checkmark.circle"
        }
    }

    private var emptyStateTitle: String {
        switch store.connection {
        case .notRunning:
            return "Workflow-App läuft nicht"
        case .connecting:
            return "Verbinde mit der Workflow-App …"
        case .error:
            return "Keine Verbindung"
        case .connected:
            return "Keine aktiven Sitzungen"
        }
    }

    private var emptyStateMessage: String {
        switch store.connection {
        case .notRunning:
            return "Starte die lokale Workflow-App, um Sitzungen hier zu sehen."
        case .connecting:
            return "Die Sitzungsliste wird gleich geladen."
        case .error(let message):
            return message
        case .connected:
            return showEnded
                ? "Es gibt derzeit keine Sitzungen."
                : "Aktiviere „Beendete Sitzungen anzeigen“ in den Einstellungen, um auch abgeschlossene Sitzungen zu sehen."
        }
    }
}

// MARK: - Row

@MainActor
private struct WorkflowSessionRow: View {
    let session: WorkflowSession
    @ObservedObject var store: WorkflowStore

    @State private var answerText = ""
    @State private var replyText = ""
    @State private var stopConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                WorkflowStatusDot(status: session.normalizedStatus, color: statusColor)

                Text(displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(statusLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(statusColor.opacity(0.15)))

                Spacer(minLength: 6)

                if let costText {
                    Text(costText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if let summaryText {
                Text(summaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            actions
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .secondarySystemFill).opacity(0.35))
        )
        .opacity(session.normalizedStatus == "ended" ? 0.6 : 1)
        .onChange(of: session.normalizedStatus) { _, _ in
            stopConfirmation = false
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        switch session.normalizedStatus {
        case "approval":
            HStack(spacing: 6) {
                actionButton("Erlauben", tint: .green, prominent: true) {
                    await store.approve(session: session)
                }
                actionButton("Ablehnen", tint: .red, prominent: false) {
                    await store.deny(session: session)
                }
            }
        case "question":
            questionActions
        case "working":
            stopAction
        default:
            if isReplyPending {
                replyActions
            }
        }
    }

    @ViewBuilder
    private var questionActions: some View {
        let options = questionOptions
        if options.isEmpty {
            inputField(placeholder: "Antwort …", text: $answerText) {
                await store.answer(session: session, text: answerText)
                answerText = ""
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        actionButton(option, tint: .accentColor, prominent: false) {
                            await store.answer(session: session, text: option)
                        }
                    }
                }
            }
            .frame(height: 22)
        }
    }

    @ViewBuilder
    private var replyActions: some View {
        inputField(placeholder: "Antwort an die Sitzung …", text: $replyText) {
            await store.reply(session: session, text: replyText)
            replyText = ""
        }
    }

    @ViewBuilder
    private var stopAction: some View {
        if stopConfirmation {
            HStack(spacing: 6) {
                actionButton("Wirklich stoppen?", tint: .red, prominent: true) {
                    stopConfirmation = false
                    await store.stop(session: session)
                }
                Button("Abbrechen") {
                    stopConfirmation = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        } else {
            actionButton("Stoppen", tint: .red, prominent: false) {
                stopConfirmation = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    stopConfirmation = false
                }
            }
        }
    }

    // MARK: Inputs

    private func inputField(
        placeholder: String,
        text: Binding<String>,
        onSubmit: @escaping () async -> Void
    ) -> some View {
        let isDisabled = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return HStack(spacing: 6) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                )
                .onSubmit {
                    guard !isDisabled else { return }
                    Task { await onSubmit() }
                }

            actionButton("Senden", tint: .accentColor, prominent: true) {
                await onSubmit()
            }
        }
    }

    private func actionButton(
        _ title: String,
        tint: Color,
        prominent: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(prominent ? tint.opacity(0.85) : tint.opacity(0.15))
                )
                .foregroundStyle(prominent ? Color.white : tint)
        }
        .buttonStyle(.plain)
    }

    // MARK: Derived data

    private var pending: WorkflowPending? { session.pending }

    private var isReplyPending: Bool {
        guard let kind = pending?.kind?.lowercased() else { return false }
        return kind == "reply"
    }

    private var questionOptions: [String] {
        pending?.questions?.flatMap(\.optionLabels) ?? []
    }

    private var displayTitle: String {
        if let project = session.project?.trimmingCharacters(in: .whitespacesAndNewlines),
           !project.isEmpty {
            return project
        }
        if let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let cwd = session.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cwd.isEmpty {
            return (cwd as NSString).lastPathComponent
        }
        return "Sitzung"
    }

    private var summaryText: String? {
        if let summary = pending?.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }
        if let input = pending?.inputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !input.isEmpty {
            return input
        }
        if let activity = session.activity?.trimmingCharacters(in: .whitespacesAndNewlines),
           !activity.isEmpty {
            return activity
        }
        if let tool = session.tool?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tool.isEmpty {
            return tool
        }
        if let prompt = session.lastPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            return prompt
        }
        return nil
    }

    private var costText: String? {
        guard let cost = session.cost, cost > 0 else { return nil }
        return String(format: "$%.2f", cost)
    }

    private var statusLabel: String {
        switch session.normalizedStatus {
        case "working":
            return "arbeitet"
        case "approval":
            return "braucht Freigabe"
        case "question":
            return "Frage an dich"
        case "waiting":
            return "wartet"
        case "ended":
            return "beendet"
        default:
            return "fertig"
        }
    }

    private var statusColor: Color {
        switch session.normalizedStatus {
        case "working":
            return Color(red: 0x96 / 255.0, green: 0xbd / 255.0, blue: 0x99 / 255.0)
        case "approval", "question":
            return Color(red: 0xe0 / 255.0, green: 0xb6 / 255.0, blue: 0x54 / 255.0)
        case "waiting":
            return Color(red: 0x9e / 255.0, green: 0xbb / 255.0, blue: 0xd3 / 255.0)
        default:
            return Color(red: 0x9a / 255.0, green: 0x93 / 255.0, blue: 0x87 / 255.0)
        }
    }
}

// MARK: - Status dot

private struct WorkflowStatusDot: View {
    let status: String
    let color: Color

    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(status == "ended" ? 0.6 : 1)
            .scaleEffect(status == "working" && pulsing ? 1.35 : 1)
            .animation(
                status == "working"
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : nil,
                value: pulsing
            )
            .onAppear {
                if status == "working" {
                    pulsing = true
                }
            }
    }
}

#Preview {
    WorkflowView()
        .frame(width: 620, height: 190)
}
