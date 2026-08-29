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

    /// The card, before the margin the SwiftUI shadow needs.
    private static let cardSize = NSSize(width: 380, height: 72)
    private static var panelSize: NSSize {
        NSSize(width: cardSize.width + Layout.shadowWidth,
               height: cardSize.height + Layout.shadowHeight)
    }

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
        panel.hasShadow = false  // the SwiftUI card draws its own
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: GestureHUDView(cardSize: Self.cardSize)
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
        let size = Self.panelSize
        // The shadow margin is empty space, so the card — not the panel — is
        // what should sit 16pt from the edge.
        let y: CGFloat
        switch appState.settings.hudPosition {
        case .top:    y = frame.maxY - size.height + Layout.shadowInset.bottom - 16
        case .bottom: y = frame.minY - Layout.shadowInset.bottom + 16
        }
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: y))
    }
}

/// The HUD's content: hold progress while a gesture builds up, then the
/// trigger confirmation banner.
struct GestureHUDView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore

    var cardSize: NSSize

    /// Outcome is carried by an icon and a label rather than by a colour —
    /// there is one accent in this UI and it belongs to the primary action.
    private func outcomeSymbol(_ kind: AppState.TriggerEvent.Kind) -> String {
        switch kind {
        case .success:    return "checkmark"
        case .failure:    return "exclamationmark.triangle"
        case .suppressed: return "minus"
        }
    }

    private func outcomeLabel(_ kind: AppState.TriggerEvent.Kind) -> String {
        switch kind {
        case .success:    return "Ran"
        case .failure:    return "Failed"
        case .suppressed: return "Not run"
        }
    }

    var body: some View {
        card
            .frame(width: cardSize.width, height: cardSize.height)
            .glassSurface(cornerRadius: Radius.compact, scrim: 0.52)
            .padding(Layout.shadowInset)
            .environment(\.colorScheme, .dark)
            .frame(width: cardSize.width + Layout.shadowWidth,
                   height: cardSize.height + Layout.shadowHeight)
    }

    private var barWidth: CGFloat { cardSize.width - 16 - 22 - 12 - 16 }

    @ViewBuilder
    private var card: some View {
        if let event = app.lastEvent {
            row(gesture: event.gesture) {
                Text("\(event.binding.displayName) → \(event.message)")
                    .textRole(.bodyEmphasis)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Image(systemName: outcomeSymbol(event.kind))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Palette.inkMuted)
                    FieldLabel(outcomeLabel(event.kind))
                }
            }
            .id(event.id)
            .transition(.opacity)
        } else if case .holding(let binding, let since) = app.machineSnapshot.phase {
            row(gesture: binding.gesture) {
                Text("Hold \(binding.displayName)")
                    .textRole(.bodyEmphasis)
                    .lineLimit(1)
                HoldProgressBar(since: since,
                                duration: settings.config.holdDuration,
                                width: barWidth)
            }
        } else if case .cooldown(let fired, _) = app.machineSnapshot.phase {
            // Bridges the gap between the hold completing and the action
            // reporting back, so the bar is seen full.
            row(gesture: fired.gesture) {
                Text("\(fired.displayName) triggered")
                    .textRole(.bodyEmphasis)
                    .lineLimit(1)
                CompletedHoldBar(width: barWidth)
            }
        } else {
            Color.clear
        }
    }

    private func row<Content: View>(gesture: Gesture,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            GestureGlyph(gesture: gesture, size: 22)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .animation(Motion.chunk, value: app.lastEvent?.id)
    }
}
