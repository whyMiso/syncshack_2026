import AppKit
import SwiftUI

/// A small always-on-top camera view with the hand skeleton drawn on it, so
/// you can see what SayHi sees while working in another app.
///
/// Unlike the HUD and cheat sheet this one is draggable, so it can be parked
/// wherever it doesn't cover anything important. Its position is remembered.
@MainActor
final class CameraOverlayController {

    private unowned let appState: AppState
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?

    /// Height of the status strip drawn under the preview.
    private static let statusHeight: CGFloat = 30

    var isVisible: Bool { panel?.isVisible ?? false }

    init(appState: AppState) {
        self.appState = appState
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = self.panel ?? buildPanel()
        self.panel = panel
        applySize(to: panel)
        place(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Re-applies the size preset while the overlay is open.
    func refreshSize() {
        guard let panel, panel.isVisible else { return }
        applySize(to: panel)
    }

    private func applySize(to panel: NSPanel) {
        let preview = appState.settings.cameraOverlaySize.preview
        let size = NSSize(width: preview.width, height: preview.height + Self.statusHeight)
        // Keep the top-left corner anchored so resizing doesn't walk the panel
        // down the screen.
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft)
    }

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 240),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = CameraOverlayView(statusHeight: Self.statusHeight)
            .environmentObject(appState)
            .environmentObject(appState.settings)

        let host = NSHostingView(rootView: root)
        let container = DragToMoveView()
        container.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        panel.contentView = container

        // Remember wherever the user parks it.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel else { return }
                    self.appState.settings.cameraOverlayOrigin = panel.frame.origin
                }
            }
        return panel
    }

    /// Restores the saved position, falling back to the lower-right corner.
    /// A saved position off-screen (a display was unplugged) is discarded.
    private func place(_ panel: NSPanel) {
        let size = panel.frame.size
        if let saved = appState.settings.cameraOverlayOrigin {
            let rect = NSRect(origin: saved, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                panel.setFrameOrigin(saved)
                return
            }
        }
        guard let frame = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 24,
                                     y: frame.minY + 24))
    }
}

/// Makes the whole borderless panel draggable.
///
/// `isMovableByWindowBackground` is unreliable once an `NSHostingView` covers
/// the window, because SwiftUI's view claims the click. Overriding `hitTest`
/// to always return this container routes every mouse-down here instead —
/// safe precisely because the overlay contains nothing clickable.
private final class DragToMoveView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

struct CameraOverlayView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore

    let statusHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            preview
            status
        }
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.18)))
    }

    @ViewBuilder
    private var preview: some View {
        let size = settings.cameraOverlaySize.preview
        Group {
            if app.isEnabled, app.cameraAuthorization == .authorized {
                CameraPreviewView(cameraManager: app.cameraManager,
                                  hand: app.currentHand,
                                  showLandmarks: settings.showLandmarks)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "video.slash").font(.title2)
                    Text("Gesture control is off")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var status: some View {
        HStack(spacing: 6) {
            Text(app.currentReading.gesture.symbol)
            Text(label)
                .font(.caption).fontWeight(.medium)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let side = app.currentHandSide {
                Text(side.shortName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: statusHeight)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var label: String {
        guard app.isEnabled else { return "Paused" }
        if app.currentHand == nil { return "No hand detected" }
        guard app.currentReading.gesture != .unknown else { return "No gesture" }
        return "\(app.currentReading.gesture.displayName) · \(Int(app.currentReading.confidence * 100))%"
    }
}
