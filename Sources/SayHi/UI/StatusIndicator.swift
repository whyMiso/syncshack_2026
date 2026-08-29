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

    /// State is carried by the dot's fill and the label beside it rather than
    /// by hue, so it survives a one-accent palette — and reads for anyone who
    /// can't tell green from orange.
    var dot: StateDot.Level {
        switch self {
        case .off:    return .off
        case .paused: return .muted
        case .active: return .on
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

    private unowned let settings: SettingsStore
    private let model = StatusIndicatorModel()
    private var panel: NSPanel?
    private var resizeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    deinit {
        for obs in [resizeObserver, moveObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(obs)
        }
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
        sizeAndPlace(panel)
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
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // The pill is draggable, so unlike a purely informational overlay it
        // can't be `ignoresMouseEvents`. Instead the container below claims a
        // click only when it lands on the visible chip; the transparent shadow
        // margin stays click-through, so it never blocks what's underneath.
        let host = NSHostingView(rootView: StatusIndicatorView().environmentObject(model))
        let container = ChipDragView()
        container.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        panel.contentView = container
        panel.setContentSize(host.fittingSize)

        // Remember wherever the user parks it.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel else { return }
                    // Store the right edge, not the left origin: the label
                    // width changes between states, and anchoring the right
                    // edge keeps the pill visually put as it grows or shrinks.
                    self.settings.statusIndicatorOrigin =
                        CGPoint(x: panel.frame.maxX, y: panel.frame.origin.y)
                }
            }

        // A resize while parked in the default corner must re-anchor to the
        // right edge; a resize while parked at a saved spot is handled by
        // sizeAndPlace. Only the default-corner case needs an observer.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel,
                          self.settings.statusIndicatorOrigin == nil else { return }
                    self.anchorTopRight(panel)
                }
            }
        return panel
    }

    /// Lays the label out, sizes the panel to it, then places it — at the
    /// user's saved spot if it still lands on a screen, else the default corner.
    ///
    /// Anchoring the *right* edge matters here: SwiftUI relays out after a
    /// state change rather than during it, so a wider label ("Paused" vs "Off")
    /// grows leftward from the saved point instead of drifting rightward off
    /// whatever edge the pill was parked against.
    private func sizeAndPlace(_ panel: NSPanel) {
        if let host = panel.contentView?.subviews.first ?? panel.contentView {
            host.layoutSubtreeIfNeeded()
            panel.setContentSize(host.fittingSize)
        }

        if let savedRight = settings.statusIndicatorOrigin {
            // savedRight.x is the parked right edge; place the current width so
            // that edge stays put whatever the label now reads.
            let size = panel.frame.size
            let origin = clampOnScreen(CGPoint(x: savedRight.x - size.width, y: savedRight.y),
                                       size: size)
            panel.setFrameOrigin(origin)
        } else {
            anchorTopRight(panel)
        }
    }

    /// Nudges an origin back onto the nearest screen if a display was unplugged
    /// and the saved spot is now in dead space.
    private func clampOnScreen(_ origin: CGPoint, size: NSSize) -> CGPoint {
        let rect = NSRect(origin: origin, size: size)
        if NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) { return origin }
        guard let area = NSScreen.main?.visibleFrame else { return origin }
        return CGPoint(x: area.maxX - size.width, y: area.maxY - size.height)
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
        // The panel is larger than the chip by the shadow margin, so the
        // margin is subtracted back out to keep the chip itself 8pt in.
        panel.setFrameOrigin(NSPoint(x: area.maxX - size.width + Layout.chipInset.trailing - 8,
                                     y: area.maxY - size.height + Layout.chipInset.bottom - 6))
    }
}

/// Makes the pill draggable while leaving its transparent shadow margin
/// click-through. `performDrag` moves the whole borderless panel; the chip has
/// nothing else clickable inside it, so taking every hit on the chip is safe.
private final class ChipDragView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // The visible chip is inset from the panel by the shadow margin. A hit
        // outside that inset is on transparent padding and should pass through.
        return chipRect.contains(convert(point, from: superview)) ? self : nil
    }

    /// The opaque chip, inset from the panel by the transparent shadow margin.
    private var chipRect: NSRect {
        NSRect(x: Layout.chipInset.leading,
               y: Layout.chipInset.bottom,
               width: bounds.width - Layout.chipInset.leading - Layout.chipInset.trailing,
               height: bounds.height - Layout.chipInset.top - Layout.chipInset.bottom)
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(chipRect, cursor: .openHand)
    }
}

struct StatusIndicatorView: View {
    @EnvironmentObject private var model: StatusIndicatorModel

    var body: some View {
        HStack(spacing: 7) {
            StateDot(level: model.state.dot)
            FieldLabel(model.state.label)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .glassSurface(cornerRadius: Radius.chip, scrim: 0.55, depth: .compact)
        .padding(Layout.chipInset)
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}
