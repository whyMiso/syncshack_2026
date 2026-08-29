import AppKit
import SwiftUI

/// The three states worth telling apart at a glance.
enum IndicatorState: Equatable {
    case off      // camera stopped
    case paused   // watching, but actions won't run
    case active   // fully live

    var label: String {
        switch self {
        case .off:    return "Off"
        case .paused: return "Paused"
        case .active: return "Active"
        }
    }

    var colour: Color {
        switch self {
        case .off:    return .secondary
        case .paused: return .orange
        case .active: return .green
        }
    }

    /// Glass tint for the pill itself.
    ///
    /// `nil` for off on purpose: an untinted pill reads as genuinely inert,
    /// which is exactly what "off" means. Tinting it grey would just look
    /// like a third colour.
    var tint: Color? {
        switch self {
        case .off:    return nil
        case .paused: return .orange
        case .active: return .green
        }
    }
}

/// Holds just the indicator's state.
///
/// Deliberately separate from `AppState`: that publishes on every analysed
/// frame (~24×/s), and an always-on-screen overlay bound to it would re-render
/// continuously to draw a dot that hardly ever changes.
@MainActor
final class StatusIndicatorModel: ObservableObject {
    @Published var state: IndicatorState = .off
}

/// A small always-on-top pill in the top-right corner showing whether gesture
/// control is off, watching, or live — readable from any app.
@MainActor
final class StatusIndicatorController {

    private let model = StatusIndicatorModel()
    private var panel: NSPanel?
    private var resizeObserver: NSObjectProtocol?

    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
    }

    /// Updates the state and shows or hides the pill accordingly.
    func update(state: IndicatorState, visible: Bool) {
        model.state = state

        guard visible else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? buildPanel()
        self.panel = panel
        sizeAndAnchor(panel)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 34),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // Click-through: this sits on screen permanently, so it must never
        // swallow a click meant for whatever is underneath it.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: StatusIndicatorView().environmentObject(model))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        // "Active" and "Paused" are wider than "Off", and SwiftUI relays out
        // after the state is set rather than during it. Without re-anchoring on
        // resize the pill keeps its old left edge and grows off the screen.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel else { return }
                    self.anchorTopRight(panel)
                }
            }
        return panel
    }

    /// Lays the label out, sizes the panel to it, then re-anchors.
    private func sizeAndAnchor(_ panel: NSPanel) {
        if let host = panel.contentView {
            host.layoutSubtreeIfNeeded()
            panel.setContentSize(host.fittingSize)
        }
        anchorTopRight(panel)
    }

    /// Top-right of the primary display, just under the menu bar.
    ///
    /// Anchors the *right* edge, so a wider label grows leftward instead of
    /// off the side of the screen.
    ///
    /// Pinned to the primary screen rather than following the mouse: a status
    /// light that jumps between displays is harder to find than one that stays.
    private func anchorTopRight(_ panel: NSPanel) {
        guard let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.maxX - size.width - 8,
                                     y: area.maxY - size.height - 4))
    }
}

struct StatusIndicatorView: View {
    @EnvironmentObject private var model: StatusIndicatorModel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.state.colour)
                .frame(width: 7, height: 7)
            Text(model.state.label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        // Tinted by state so the pill reads from across the screen before the
        // label itself is legible. Never interactive: the panel is
        // click-through, so hover and press feedback would be a lie.
        .glassCapsule(tint: model.state.tint)
        .glassShadow(radius: 8, y: 2)
        .padding(10)         // room for the shadow inside the panel
        .fixedSize()
    }
}
