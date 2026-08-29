import Combine
import AVFoundation
import SwiftUI

/// Preferences: trigger timing, recognition sensitivity, feedback and startup.
///
/// Hand-built rather than a `Form`: the grouped form style brings its own
/// opaque group backgrounds, header weights and blue tinted controls, none of
/// which match the rest of the app.
struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var app: AppState
    @State private var showAdvanced = false
    @State private var cameraGranted = false
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                actions
                permissions
                triggering
                recognition
                gestureList
                cameraOverlay
                feedback
                startup
                advanced
                reset
                privacy
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear(perform: refreshPermissions)
        .onReceive(permissionTimer) { _ in refreshPermissions() }
    }

    // MARK: Sections

    private var actions: some View {
        SettingsGroup("Actions") {
            SettingsRow(title: "Run actions",
                        detail: "Turn off to keep recognising gestures without running anything — useful for practising or tuning thresholds.") {
                SwitchControl(isOn: $settings.actionsEnabled)
            }
        }
    }

    private var permissions: some View {
        SettingsGroup("Permissions",
                      footer: "macOS only applies a newly granted permission when the app next launches — if one still shows as missing after granting it, quit and reopen SayHi.") {
            PermissionRow(name: "Camera",
                          detail: "Required — this is how SayHi sees your hand.",
                          granted: cameraGranted,
                          pane: "Privacy_Camera")
            Hairline()
            PermissionRow(name: "Screen Recording",
                          detail: "Only needed for the Screenshot action.",
                          granted: screenRecordingGranted,
                          pane: "Privacy_ScreenCapture")
            Hairline()
            PermissionRow(name: "Accessibility",
                          detail: "Only needed for Keyboard Shortcut actions.",
                          granted: accessibilityGranted,
                          pane: "Privacy_Accessibility")
        }
    }

    private var triggering: some View {
        SettingsGroup("Triggering",
                      footer: String(format: "Total time from showing a gesture to it firing again: about %.1fs.", totalCycle)) {
            SliderRow(title: "Hold to trigger",
                      detail: "How long a gesture must be held steady before it fires.",
                      value: $settings.config.holdDuration,
                      range: 0.2...2.5, step: 0.05, unit: "s")
            Hairline()
            SliderRow(title: "Cooldown",
                      detail: "Nothing can fire for this long after a trigger.",
                      value: $settings.config.cooldown,
                      range: 0.2...6, step: 0.1, unit: "s")
            Hairline()
            SliderRow(title: "Re-arm delay",
                      detail: "After firing, the same gesture must be gone this long before it can fire again.",
                      value: $settings.config.rearmDuration,
                      range: 0...2, step: 0.05, unit: "s")
            Hairline()
            SliderRow(title: "Dropout tolerance",
                      detail: "Ignore detection gaps shorter than this so a steady hand isn't interrupted.",
                      value: $settings.config.dropoutGrace,
                      range: 0...1, step: 0.05, unit: "s")
        }
    }

    private var recognition: some View {
        SettingsGroup("Recognition") {
            SliderRow(title: "Minimum confidence",
                      detail: "Higher means gestures must match more precisely. Raise this if actions fire by accident.",
                      value: $settings.config.minimumReadingConfidence,
                      range: 0.05...0.9, step: 0.05)
            Hairline()
            SliderRow(title: "Analysis frame rate",
                      detail: "Frames analysed per second. Detection itself costs only ~3 ms, so the gap between frames is what sets responsiveness — lowering this saves little CPU but makes gestures feel sluggish.",
                      value: $settings.config.analysisFramesPerSecond,
                      range: 5...30, step: 1, unit: " fps", decimals: 0)
        }
    }

    private var gestureList: some View {
        SettingsGroup("Gesture list",
                      footer: "This shortcut works without Accessibility permission.") {
            SettingsRow(title: "Global shortcut for the gesture list",
                        detail: "Pops up a panel listing every gesture and its action, over whatever app you're in. Press again to dismiss.") {
                SwitchControl(isOn: $settings.cheatSheetHotKeyEnabled)
            }

            if settings.cheatSheetHotKeyEnabled {
                Hairline()
                HotKeyRow(combo: $settings.cheatSheetHotKey,
                          conflicted: app.cheatSheetHotKeyConflicted,
                          registeredNote: "toggles the gesture list") {
                    PanelButton(title: "Show now", icon: "square.on.square") {
                        app.toggleCheatSheet()
                    }
                }
            }
        }
    }

    private var cameraOverlay: some View {
        SettingsGroup("Camera overlay") {
            SettingsRow(title: "Show camera overlay",
                        detail: "A small always-on-top camera view with the hand tracking drawn on it. Drag it anywhere — its position is remembered.") {
                SwitchControl(isOn: $settings.cameraOverlayVisible)
            }
            Hairline()
            SettingsRow(title: "Size") {
                MenuChip(options: OverlaySize.allCases,
                         title: \.displayName,
                         selection: $settings.cameraOverlaySize,
                         enabled: settings.cameraOverlayVisible)
            }
            Hairline()
            HotKeyRow(combo: $settings.cameraOverlayHotKey,
                      conflicted: app.cameraOverlayHotKeyConflicted,
                      registeredNote: "toggles the overlay") { EmptyView() }
        }
    }

    private var feedback: some View {
        SettingsGroup("Feedback") {
            SettingsRow(title: "Status indicator in the corner",
                        detail: "A small pill in the top-right of the main display showing Active, Paused or Off. Always on top, and click-through so it never blocks anything underneath.") {
                SwitchControl(isOn: $settings.showStatusIndicator)
            }
            Hairline()
            SettingsRow(title: "Floating HUD over other apps") {
                SwitchControl(isOn: $settings.showHUD)
            }
            Hairline()
            SettingsRow(title: "HUD position") {
                MenuChip(options: HUDPosition.allCases,
                         title: \.displayName,
                         selection: $settings.hudPosition,
                         enabled: settings.showHUD)
            }
            Hairline()
            SettingsRow(title: "Draw hand skeleton on preview") {
                SwitchControl(isOn: $settings.showLandmarks)
            }
        }
    }

    private var startup: some View {
        SettingsGroup("Startup") {
            SettingsRow(title: "Turn on gesture control when SayHi launches") {
                SwitchControl(isOn: $settings.startRecognitionAtLaunch)
            }
        }
    }

    private var advanced: some View {
        SettingsGroup("Advanced recognition thresholds") {
            SettingsRow(title: "Shape rules",
                        detail: "These control the shape rules themselves. Turn on Debug on the Camera tab to watch the live scores while adjusting.") {
                PanelButton(title: showAdvanced ? "Hide" : "Show",
                            icon: showAdvanced ? "chevron.up" : "chevron.down") {
                    withAnimation(Motion.enter) { showAdvanced.toggle() }
                }
            }

            if showAdvanced {
                Hairline()
                SliderRow(title: "Finger extended above",
                          detail: "Extension score at which a finger counts as straight.",
                          value: $settings.config.fingerExtendedMin,
                          range: 0.1...0.8, step: 0.01)
                Hairline()
                SliderRow(title: "Finger folded below",
                          detail: "Extension score at which a finger counts as curled.",
                          value: $settings.config.fingerFoldedMax,
                          range: -0.1...0.5, step: 0.01)
                Hairline()
                SliderRow(title: "Thumb extended above",
                          detail: "Thumb-to-index-knuckle distance for an extended thumb.",
                          value: $settings.config.thumbExtendedMin,
                          range: 0.4...1.6, step: 0.05)
                Hairline()
                SliderRow(title: "Thumb folded below",
                          detail: "Below this the thumb counts as tucked into a fist.",
                          value: $settings.config.thumbFoldedMax,
                          range: 0.2...1.2, step: 0.05)
                Hairline()
                SliderRow(title: "Pinch distance (OK sign)",
                          detail: "How close thumb and index tips must be to count as touching.",
                          value: $settings.config.pinchMax,
                          range: 0.1...1.0, step: 0.05)
            }
        }
    }

    private var reset: some View {
        InsetCard(cornerRadius: 12) {
            HStack(spacing: 14) {
                PanelButton(title: "Reset recognition settings",
                            icon: "arrow.counterclockwise",
                            enabled: settings.hasCustomRecognitionSettings) {
                    settings.resetRecognitionDefaults()
                }
                Text("Gesture mappings are not affected.")
                    .textRole(.body, tint: Palette.inkMuted)
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private var privacy: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
            Text("Hand recognition runs entirely on this Mac. Camera images are not stored or transmitted.")
                .textRole(.body, tint: Palette.inkFaint)
        }
        .padding(.leading, 2)
    }

    // MARK: Permission status
    //
    // Polled rather than observed: these are granted in System Settings, an
    // entirely separate process, so there is nothing to subscribe to.

    private var permissionTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    }

    private func refreshPermissions() {
        cameraGranted = CameraManager.authorizationStatus == .authorized
        screenRecordingGranted = ActionExecutor.isScreenRecordingAuthorized
        accessibilityGranted = ActionExecutor.isAccessibilityTrusted
    }

    /// Hold + cooldown + re-arm, i.e. the fastest possible repeat of one gesture.
    private var totalCycle: Double {
        settings.config.holdDuration + settings.config.cooldown + settings.config.rearmDuration
    }
}

// MARK: - Building blocks

/// An 11px label, a card of rows, and an optional footnote.
private struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FieldLabel(title).padding(.leading, 2)
            InsetCard(cornerRadius: 12) {
                VStack(spacing: 0) { content }
            }
            if let footer {
                Text(footer)
                    .textRole(.body, tint: Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
            }
        }
    }
}

/// Title, optional explanation, and a control on the right.
private struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    init(title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).textRole(.bodyEmphasis)
                if let detail {
                    Text(detail)
                        .textRole(.body, tint: Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

/// One permission's live status, with a jump straight to its System Settings pane.
private struct PermissionRow: View {
    let name: String
    let detail: String
    let granted: Bool
    /// System Settings anchor, e.g. "Privacy_ScreenCapture".
    let pane: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            // Granted is a quiet tick, missing is a louder mark at full ink —
            // the contrast does the work a red/green pair used to.
            Image(systemName: granted ? "checkmark.circle" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(granted ? Palette.inkMuted : Palette.ink)
                .frame(height: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).textRole(.bodyEmphasis)
                Text(detail).textRole(.body, tint: Palette.inkMuted)
            }
            Spacer(minLength: 12)
            if !granted {
                PanelButton(title: "Open…", icon: "arrow.up.forward.app") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

/// Key plus modifiers, with a live line saying whether it actually registered.
private struct HotKeyRow<Extra: View>: View {
    @Binding var combo: KeyCombo
    let conflicted: Bool
    let registeredNote: String
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FieldLabel("Shortcut")
                Spacer(minLength: 12)
                modifier("⌘", \.command)
                modifier("⇧", \.shift)
                modifier("⌥", \.option)
                modifier("⌃", \.control)
                MenuChip(options: KeyCombo.orderedKeyNames,
                         title: { $0 },
                         selection: $combo.keyName)
                extra
            }
            status
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func modifier(_ symbol: String, _ path: WritableKeyPath<KeyCombo, Bool>) -> some View {
        ToggleChip(title: symbol, isOn: combo[keyPath: path], showsDot: false) {
            combo[keyPath: path].toggle()
        }
    }

    @ViewBuilder
    private var status: some View {
        if !combo.hasModifier {
            note(ok: false, "Pick at least one modifier — a bare key would be captured system-wide.")
        } else if conflicted {
            note(ok: false, "\(combo.displayString) is already used by another app — choose a different combination.")
        } else {
            note(ok: true, "\(combo.displayString) \(registeredNote).")
        }
    }

    private func note(ok: Bool, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark" : "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .medium))
            Text(text).font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ok ? Palette.inkMuted : Palette.ink)
    }
}

/// A labelled slider with a live value readout and an explanatory subtitle.
///
/// The step is applied through the binding rather than handed to `Slider`,
/// because passing a step makes macOS draw a tick strip under the track.
private struct SliderRow: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit: String = ""
    var decimals: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Text(title).textRole(.bodyEmphasis)
                Spacer(minLength: 12)
                Text(formatted)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.inkMuted)
                    .monospacedDigit()
            }
            Slider(value: snapped, in: range)
                .controlSize(.small)
                .tint(Color.white.opacity(0.82))
            Text(detail)
                .textRole(.body, tint: Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private var snapped: Binding<Double> {
        Binding(get: { value },
                set: { new in
                    guard step > 0 else { value = new; return }
                    value = min(range.upperBound,
                                max(range.lowerBound, (new / step).rounded() * step))
                })
    }

    private var formatted: String {
        String(format: "%.\(decimals)f%@", value, unit)
    }
}
