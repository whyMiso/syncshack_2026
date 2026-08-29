import AppKit
import SwiftUI

/// A small floating panel shown near the top of the screen while a gesture is
/// being held or right after an action fires — so you get feedback even when
/// SayHi isn't the frontmost app.
///
/// The panel is borderless, non-activating, click-through, floats above
/// normal windows, and follows you across Spaces and full-screen apps.
@MainActor
final class HUDController {

    private unowned let appState: AppState
    private var panel: NSPanel?

    private static let panelSize = NSSize(width: 380, height: 80)

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if panel == nil { panel = buildPanel() }
        guard let panel else { return }
        position(panel)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // the SwiftUI capsule draws its own shadow
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: GestureHUDView()
            .environmentObject(appState)
            .environmentObject(appState.settings))
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = host
        return panel
    }

    /// Horizontally centred on the screen the mouse is on, at the edge the
    /// user picked in Settings.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let y: CGFloat
        switch appState.settings.hudPosition {
        case .top:    y = frame.maxY - Self.panelSize.height - 16
        case .bottom: y = frame.minY + 16
        }
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.panelSize.width / 2, y: y))
    }
}

extension AppState.TriggerEvent.Kind {
    /// Green ran, orange failed, blue-grey recognised but deliberately not run.
    var bannerColor: Color {
        switch self {
        case .success:    return Color.green.opacity(0.92)
        case .failure:    return Color.orange.opacity(0.92)
        case .suppressed: return Color.secondary.opacity(0.92)
        }
    }
}

/// The HUD's content: hold progress while a gesture builds up, then the
/// trigger confirmation banner.
struct GestureHUDView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Group {
            if let event = app.lastEvent {
                HStack(spacing: 10) {
                    Text(event.gesture.symbol).font(.title2)
                    Text("\(event.binding.displayName) → \(event.message)")
                        .font(.callout).fontWeight(.medium)
                        .lineLimit(2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(event.kind.bannerColor, in: Capsule())
                .shadow(radius: 8, y: 2)
            } else if case .holding(let binding, let since) = app.machineSnapshot.phase {
                HStack(spacing: 12) {
                    Text(binding.gesture.symbol).font(.title)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hold \(binding.displayName)…")
                            .font(.callout).fontWeight(.medium)
                        HoldProgressBar(since: since,
                                        duration: settings.config.holdDuration,
                                        width: 160)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
                .shadow(radius: 8, y: 2)
            } else if case .cooldown(let fired, _) = app.machineSnapshot.phase {
                // Bridges the gap between the hold completing and the action
                // reporting back, so the bar is seen full.
                HStack(spacing: 12) {
                    Text(fired.gesture.symbol).font(.title)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(fired.displayName) triggered")
                            .font(.callout).fontWeight(.medium)
                        CompletedHoldBar(width: 160)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
                .shadow(radius: 8, y: 2)
            }
        }
        .frame(width: 380, height: 80)
    }
}
