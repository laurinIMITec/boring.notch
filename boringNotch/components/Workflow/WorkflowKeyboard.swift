//
//  WorkflowKeyboard.swift
//  boringNotch
//
//  Kleines Singleton, das steuert, ob die Notch-Fenster Tastatur-Fokus
//  annehmen duerfen. Nur solange ein Textfeld im Workflow-Tab bearbeitet
//  wird, darf das Notch-Fenster key werden (canBecomeMain bleibt false).
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class WorkflowKeyboard: ObservableObject {
    static let shared = WorkflowKeyboard()

    /// True, solange ein Textfeld im Workflow-Tab den Fokus hat.
    @Published var isEditing: Bool = false

    /// Notch-Fenster, das waehrend der Bearbeitung key wird (weak, um
    /// Zyklen mit NSWindow zu vermeiden).
    private weak var editingWindow: NSWindow?

    private init() {}

    /// Textfeld hat den Fokus bekommen: App aktivieren und das Notch-Fenster
    /// key machen, damit Tastatureingaben ankommen.
    func beginEditing(in window: NSWindow?) {
        if let window {
            editingWindow = window
        }
        isEditing = true
        NSApp.activate(ignoringOtherApps: true)
        editingWindow?.makeKey()
    }

    /// Bearbeitung beenden (Senden, Escape, Tab-Wechsel, Notch zu):
    /// Fenster darf nicht mehr key werden und gibt den Fokus ab.
    func endEditing() {
        guard isEditing else { return }
        isEditing = false
        editingWindow?.makeFirstResponder(nil)
        editingWindow?.resignKey()
        editingWindow = nil
    }
}

// MARK: - Window accessor

/// Holt das NSWindow einer SwiftUI-View (z. B. der Workflow-Zeile).
@MainActor
struct WorkflowWindowAccessor: NSViewRepresentable {
    let onChange: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> WorkflowWindowCaptureView {
        let view = WorkflowWindowCaptureView()
        view.onWindowChange = onChange
        return view
    }

    func updateNSView(_ nsView: WorkflowWindowCaptureView, context: Context) {
        nsView.onWindowChange = onChange
    }
}

final class WorkflowWindowCaptureView: NSView {
    var onWindowChange: (@MainActor (NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
