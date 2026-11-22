//
//  WorkflowAttentionDot.swift
//  boringNotch
//
//  Pulsierender Punkt rechts neben der geschlossenen Notch, wenn eine
//  Frage oder Freigabe im Workflow-Tab auf eine Antwort wartet.
//

import Defaults
import SwiftUI

@MainActor
struct WorkflowAttentionDot: View {
    @ObservedObject private var store = WorkflowStore.shared
    @Default(.workflowClosedIndicator) private var workflowClosedIndicator
    @Default(.showWorkflowTab) private var showWorkflowTab

    @State private var isPulsing = false

    private let dotSize: CGFloat = 7
    /// #e0b654
    private let dotColor = Color(red: 224 / 255, green: 182 / 255, blue: 84 / 255)

    var body: some View {
        if showWorkflowTab && workflowClosedIndicator && store.needsYouCount > 0 {
            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)
                .scaleEffect(isPulsing ? 1.2 : 0.8)
                .opacity(isPulsing ? 1.0 : 0.45)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
                .onDisappear { isPulsing = false }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
