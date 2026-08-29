import AppKit
import SwiftUI

/// A "press the keys you want" field. Click it, press a combination, and it
/// captures the exact key plus modifiers — no dropdown, no modifier toggles.
///
/// While recording, a local event monitor swallows key-downs so the captured
/// keystroke (Space, ⌘Q, arrows…) doesn't leak into the app underneath. Escape
/// cancels; ⌫/Delete clears back to unset.
struct KeyRecorderField: View {
    @Binding var combo: KeyCombo
    /// Shown when nothing is captured yet.
    var placeholder: String = "Not set"

    @State private var recording = false
    @State private var monitor: Any?
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: recording ? "record.circle" : "keyboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(recording ? Palette.accent : Palette.inkFaint)
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(recording ? Palette.inkMuted
                                     : (hasCombo ? Palette.ink : Palette.inkFaint))
                Spacer(minLength: 8)
                if hasCombo && !recording {
                    Text("Click to change")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(recording ? Palette.accent.opacity(0.12)
                          : (hovering ? Palette.fillHover : Color.white.opacity(0.03)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(recording ? Palette.accent.opacity(0.7) : Palette.hairline,
                                  lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onDisappear(perform: stop)   // never leave a monitor installed
    }

    private var hasCombo: Bool { combo.keyCode != nil }

    private var label: String {
        if recording { return "Press keys… (⎋ to cancel)" }
        return hasCombo ? combo.displayString : placeholder
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape cancels without changing the binding.
            if event.keyCode == 53 { self.stop(); return nil }
            if let captured = KeyCombo.from(event: event) {
                self.combo = captured
                self.stop()
            }
            // Swallow the event so the keystroke doesn't reach the app beneath.
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
