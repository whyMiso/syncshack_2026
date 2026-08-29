import AppKit
import SwiftUI

/// A floating panel listing every gesture and the action bound to it, so the
/// eighteen bindings don't have to be memorised. Toggled by a global hotkey
/// and shown above other apps, since that is where you need it.
@MainActor
final class CheatSheetController {

    private unowned let appState: AppState
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    init(appState: AppState) {
        self.appState = appState
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = self.panel ?? buildPanel()
        self.panel = panel
        centre(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false            // the SwiftUI card draws its own
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = CheatSheetView(dismiss: { [weak self] in self?.hide() })
            .environmentObject(appState)
            .environmentObject(appState.settings)
            .environmentObject(appState.mappingStore)

        let host = NSHostingView(rootView: root)
        host.frame.size = host.fittingSize
        panel.setContentSize(host.fittingSize)
        panel.contentView = host
        return panel
    }

    /// Centred on whichever screen the pointer is on.
    private func centre(_ panel: NSPanel) {
        // Re-measure: mappings may have changed since it was last shown.
        if let host = panel.contentView {
            panel.setContentSize(host.fittingSize)
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.midY - size.height / 2))
    }
}

struct CheatSheetView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var mappingStore: GestureMappingStore

    var dismiss: () -> Void

    private let gestureColumn: CGFloat = 150
    private let actionColumn: CGFloat = 175

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            columnTitles
            ForEach(Gesture.assignable) { gesture in
                row(for: gesture)
            }
            Divider()
            footer
        }
        .padding(22)
        .frame(width: 560)
        .glassCard(radius: GlassMetrics.panelRadius)
        .glassShadow(radius: 30, y: 12)
        .padding(16)                       // room for the shadow inside the panel
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Gesture Shortcuts").font(.title3).bold()
            Spacer()
            Label(statusText, systemImage: statusIcon)
                .font(.caption)
                .foregroundStyle(statusColour)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                // Clear rather than regular: this chip sits *on* the card's
                // own glass, and stacking two regular layers muddies both.
                .glassCapsule(tone: .clear, tint: statusTint)
        }
        .padding(.bottom, 12)
    }

    private var columnTitles: some View {
        HStack(spacing: 8) {
            Text("Gesture").frame(width: gestureColumn, alignment: .leading)
            Text("🫲 Left hand").frame(width: actionColumn, alignment: .leading)
            Text("🫱 Right hand").frame(width: actionColumn, alignment: .leading)
        }
        .font(.caption).fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
    }

    private func row(for gesture: Gesture) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Text(gesture.symbol)
                Text(gesture.displayName).font(.callout)
            }
            .frame(width: gestureColumn, alignment: .leading)

            ForEach(HandSide.allCases) { hand in
                actionLabel(mappingStore.action(for: gesture, hand: hand))
                    .frame(width: actionColumn, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
    }

    private func actionLabel(_ action: GestureAction) -> some View {
        Text(action == .none ? "—" : action.displayName)
            .font(.callout)
            .foregroundStyle(action == .none ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var footer: some View {
        HStack {
            Text("Hold a gesture for \(settings.config.holdDuration, specifier: "%.1f")s to trigger it.")
            Spacer()
            Text("\(settings.cheatSheetHotKey.displayString) or click to close")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 10)
    }

    // MARK: Status line

    private var statusText: String {
        guard app.isEnabled else { return "Gesture control off" }
        return settings.actionsEnabled ? "Active" : "Watching — actions paused"
    }

    private var statusIcon: String {
        guard app.isEnabled else { return "hand.raised.slash" }
        return settings.actionsEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
    }

    private var statusColour: Color {
        guard app.isEnabled else { return .secondary }
        return settings.actionsEnabled ? .green : .orange
    }

    /// As `statusColour`, but nil when off so the chip stays untinted.
    private var statusTint: Color? {
        guard app.isEnabled else { return nil }
        return settings.actionsEnabled ? .green : .orange
    }
}
