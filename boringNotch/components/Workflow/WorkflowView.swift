//
//  WorkflowView.swift
//  boringNotch
//
//  Liste der Workflow-Sitzungen inklusive direkter Aktionen.
//

import AppKit
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
        .onDisappear {
            store.setActive(false)
            // Tab-Wechsel/Notch zu: Bearbeitung beenden.
            WorkflowKeyboard.shared.endEditing()
        }
        .onExitCommand {
            // Escape beendet die Bearbeitung auch dann, wenn das Textfeld
            // den Tastatur-Fokus bereits verloren hat.
            WorkflowKeyboard.shared.endEditing()
        }
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

    private enum InputField: Hashable {
        case answer
        case reply
    }

    @State private var answerText = ""
    @State private var replyText = ""
    @State private var stopConfirmation = false
    @State private var notchWindow: NSWindow?
    @FocusState private var focusedInput: InputField?

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

            if let expandedContext {
                // Frage/Antwort-Kontext vollstaendig lesbar (mehrzeilig, scrollbar).
                contextCard(expandedContext)
            } else if let summaryText {
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
        .background(
            WorkflowWindowAccessor { window in
                if notchWindow !== window {
                    notchWindow = window
                }
            }
        )
        .opacity(session.normalizedStatus == "ended" ? 0.6 : 1)
        .onChange(of: session.normalizedStatus) { _, _ in
            stopConfirmation = false
            if focusedInput != nil {
                cancelEditing()
            }
        }
        .onChange(of: focusedInput) { _, newValue in
            if newValue != nil {
                WorkflowKeyboard.shared.beginEditing(in: notchWindow)
            } else {
                WorkflowKeyboard.shared.endEditing()
            }
        }
        .onDisappear {
            if focusedInput != nil {
                cancelEditing()
            }
        }
    }

    private func contextCard(_ text: String) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 104)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.35))
        )
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
            inputField(placeholder: "Antwort …", text: $answerText, field: .answer) {
                let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                await store.answer(session: session, text: trimmed)
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
        inputField(placeholder: "Antwort an die Sitzung …", text: $replyText, field: .reply) {
            let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            await store.reply(session: session, text: trimmed)
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
        field: InputField,
        onSubmit: @escaping () async -> Void
    ) -> some View {
        let isDisabled = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return HStack(spacing: 6) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($focusedInput, equals: field)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                )
                .onSubmit {
                    guard !isDisabled else { return }
                    send(field: field, onSubmit: onSubmit)
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        // Fenster key machen, bevor der Fokus gesetzt wird.
                        WorkflowKeyboard.shared.beginEditing(in: notchWindow)
                        focusedInput = field
                    }
                )

            actionButton("Senden", tint: .accentColor, prominent: true) {
                guard !isDisabled else { return }
                send(field: field, onSubmit: onSubmit)
            }
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.45 : 1)
        }
        .onExitCommand {
            // Escape bricht ab: Text verwerfen und Fokus abgeben.
            text.wrappedValue = ""
            cancelEditing()
        }
    }

    /// Sendet den Text und beendet die Bearbeitung (Fokus/Key-Status zurueck).
    private func send(field: InputField, onSubmit: @escaping () async -> Void) {
        if focusedInput == field {
            focusedInput = nil
        }
        WorkflowKeyboard.shared.endEditing()
        Task { await onSubmit() }
    }

    /// Bricht die Bearbeitung ab und gibt den Tastatur-Fokus frei.
    private func cancelEditing() {
        focusedInput = nil
        WorkflowKeyboard.shared.endEditing()
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

    /// Bei Frage/Antwort den vollstaendigen Kontext anzeigen (sonst nil).
    private var expandedContext: String? {
        let kind = pending?.kind?.lowercased()
        let isContextKind = kind == "reply" || kind == "question"
            || session.normalizedStatus == "question"
        guard isContextKind else { return nil }

        if let context = pending?.context?.trimmingCharacters(in: .whitespacesAndNewlines),
           !context.isEmpty {
            return context
        }
        if let summary = pending?.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }
        if let questions = pending?.questions,
           let question = questions
            .map(\.question)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return question
        }
        return nil
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
