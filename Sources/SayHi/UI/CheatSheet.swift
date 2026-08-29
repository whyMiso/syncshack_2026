import AppKit
import SwiftUI

/// A floating panel listing every gesture and the action bound to it, so the
/// twenty-six bindings don't have to be memorised. Toggled by a global hotkey
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
        // Deliberately not `makeKeyAndOrderFront`: the panel is summoned by a
        // global hotkey, often mid-sentence in another app. Taking key focus
        // on show would swallow the next keystrokes. Clicking the panel makes
        // it key (see `PalettePanel`), which is when the filter field is
        // actually wanted.
        panel.orderFrontRegardless()
    }

    func hide() {
        // Hand focus back before disappearing, or the app underneath is left
        // without a key window.
        if panel?.isKeyWindow == true { panel?.resignKey() }
        panel?.orderOut(nil)
    }

    private func buildPanel() -> NSPanel {
        let panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false            // the SwiftUI card draws its own
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
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

/// A borderless panel still has to be allowed to take key focus, or the
/// filter field can never be typed into.
private final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - View

struct CheatSheetView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var mappingStore: GestureMappingStore

    var dismiss: () -> Void

    @State private var query = ""
    @State private var shown = false

    private let cardWidth: CGFloat = 560
    private let inset: CGFloat = 14

    var body: some View {
        ZStack {
            // Clicking the shadow margin dismisses; the card itself doesn't,
            // because it now contains things worth clicking.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            card
        }
        .padding(Layout.shadowInset)
        .environment(\.colorScheme, .dark)
        .panelEntrance(shown)
        .onAppear { shown = true }
        .onExitCommand(perform: dismiss)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            summary
            Hairline()
            columnTitles
            list
            Hairline()
            actionRow
            field
        }
        .frame(width: cardWidth)
        .glassSurface(cornerRadius: Radius.panel, scrim: 0.52)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            AppMark()
            FieldLabel("Gesture Shortcuts", tint: Palette.ink)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                StateDot(level: statusLevel)
                FieldLabel(statusText)
            }

            IconButton(symbol: "xmark", help: "Close") { dismiss() }
                .padding(.trailing, -6)
        }
        .padding(.horizontal, inset)
        .frame(height: 48)
    }

    // MARK: Summary — the panel's primary text

    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch summaryState {
            case .event(let event):
                Text("\(event.binding.displayName) → \(event.message)")
                    .textRole(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(event.id)                      // fade each new chunk in
                    .transition(.opacity)
                FieldLabel(outcomeLabel(event.kind))

            case .holding(let binding, let since):
                Text("Holding \(binding.gesture.displayName) — \(binding.hand.shortName.lowercased()) hand")
                    .textRole(.primary)
                    .lineLimit(1)
                HoldProgressBar(since: since,
                                duration: settings.config.holdDuration,
                                width: cardWidth - inset * 2)

            case .cooldown(let binding):
                Text("\(binding.displayName) triggered")
                    .textRole(.primary)
                    .lineLimit(1)
                CompletedHoldBar(width: cardWidth - inset * 2)

            case .idle:
                Text(idleParagraph)
                    .textRole(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(.horizontal, inset)
        .padding(.vertical, 14)
        .animation(Motion.chunk, value: app.lastEvent?.id)
    }

    private enum SummaryState {
        case event(AppState.TriggerEvent)
        case holding(GestureBinding, Date)
        case cooldown(GestureBinding)
        case idle
    }

    private var summaryState: SummaryState {
        if let event = app.lastEvent { return .event(event) }
        switch app.machineSnapshot.phase {
        case .holding(let binding, let since): return .holding(binding, since)
        case .cooldown(let fired, _):          return .cooldown(fired)
        default:                               return .idle
        }
    }

    private var idleParagraph: String {
        let bound = mappingStore.assignedCount
        let total = Gesture.assignable.count * HandSide.allCases.count
        let hold = String(format: "%.1f", settings.config.holdDuration)
        return "\(bound) of \(total) hand positions are bound to an action. "
             + "Hold one for \(hold) seconds to run it — the bar fills while you hold, "
             + "and relaxing your hand early cancels it."
    }

    private func outcomeLabel(_ kind: AppState.TriggerEvent.Kind) -> String {
        switch kind {
        case .success:    return "Ran"
        case .failure:    return "Did not run"
        case .suppressed: return "Recognised, not run"
        }
    }

    // MARK: List

    private var columnTitles: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 18, height: 1)
            FieldLabel("Gesture").frame(maxWidth: .infinity, alignment: .leading)
            FieldLabel("Left hand").frame(width: 164, alignment: .leading)
            FieldLabel("Right hand").frame(width: 164, alignment: .leading)
        }
        .padding(.horizontal, inset)
        .frame(height: 30)
    }

    @ViewBuilder
    private var list: some View {
        let matches = filtered
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                if matches.isEmpty {
                    Text("Nothing matches “\(query)”")
                        .textRole(.body, tint: Palette.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else {
                    ForEach(matches) { gesture in
                        GestureRow(gesture: gesture)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .frame(height: 296)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var filtered: [Gesture] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return Gesture.assignable }
        return Gesture.assignable.filter { gesture in
            if gesture.displayName.lowercased().contains(needle) { return true }
            return HandSide.allCases.contains { hand in
                let action = mappingStore.action(for: gesture, hand: hand)
                return action != .none && action.displayName.lowercased().contains(needle)
            }
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: 8) {
            PanelButton(title: app.isEnabled ? "Turn off" : "Turn on",
                        icon: app.isEnabled ? "pause" : "play") {
                app.isEnabled.toggle()
            }
            PanelButton(title: settings.actionsEnabled ? "Pause actions" : "Resume actions",
                        icon: settings.actionsEnabled ? "hand.raised" : "bolt",
                        enabled: app.isEnabled) {
                settings.actionsEnabled.toggle()
            }
            PanelButton(title: "Camera",
                        icon: settings.cameraOverlayVisible ? "camera.fill" : "camera") {
                app.toggleCameraOverlay()
            }

            Spacer(minLength: 8)

            FieldLabel(settings.cheatSheetHotKey.displayString + " to close",
                       tint: Palette.inkFaint)
        }
        .padding(.horizontal, inset)
        .frame(height: 52)
    }

    private var field: some View {
        PanelField(text: $query,
                   placeholder: "Filter gestures and actions",
                   sendHelp: "Open the full editor") {
            openEditor()
        }
        .padding(.horizontal, inset)
        .padding(.bottom, inset)
    }

    /// Brings the main window forward so a binding can actually be changed.
    private func openEditor() {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "SayHi" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Status

    private var statusText: String {
        guard app.isEnabled else { return "Off" }
        return settings.actionsEnabled ? "Active" : "Paused"
    }

    private var statusLevel: StateDot.Level {
        guard app.isEnabled else { return .off }
        return settings.actionsEnabled ? .on : .muted
    }
}

/// One gesture and both of its bindings.
private struct GestureRow: View {
    @EnvironmentObject private var mappingStore: GestureMappingStore

    let gesture: Gesture

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            GestureGlyph(gesture: gesture, size: 18)
                .frame(width: 18)

            Text(gesture.displayName)
                .textRole(.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(HandSide.allCases) { hand in
                action(mappingStore.action(for: gesture, hand: hand))
                    .frame(width: 164, alignment: .leading)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(hovering ? Palette.fillHover : .clear)
        }
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }

    private func action(_ action: GestureAction) -> some View {
        Text(action == .none ? "—" : action.displayName)
            .textRole(.body, tint: action == .none ? Palette.inkFaint : Palette.inkMuted)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
