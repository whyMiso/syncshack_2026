import Combine
import AVFoundation
import SwiftUI

/// Preferences: trigger timing, recognition sensitivity, feedback and startup.
struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var app: AppState
    @State private var showAdvanced = false
    @State private var cameraGranted = false
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.actionsEnabled) {
                    Text("Run actions")
                    Text("Turn off to keep recognising gestures without running anything — useful for practising or tuning thresholds.")
                }
            } header: {
                Text("Actions")
            }

            Section {
                PermissionRow(name: "Camera",
                              detail: "Required — this is how SayHi sees your hand.",
                              granted: cameraGranted,
                              pane: "Privacy_Camera")
                PermissionRow(name: "Screen Recording",
                              detail: "Only needed for the Screenshot action.",
                              granted: screenRecordingGranted,
                              pane: "Privacy_ScreenCapture")
                PermissionRow(name: "Accessibility",
                              detail: "Only needed for Keyboard Shortcut actions.",
                              granted: accessibilityGranted,
                              pane: "Privacy_Accessibility")
            } header: {
                Text("Permissions")
            } footer: {
                Text("macOS only applies a newly granted permission when the app next launches — if one still shows as missing after granting it, quit and reopen SayHi.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                SliderRow(title: "Hold to trigger",
                          detail: "How long a gesture must be held steady before it fires.",
                          value: $settings.config.holdDuration,
                          range: 0.2...2.5, step: 0.05, unit: "s")

                SliderRow(title: "Cooldown",
                          detail: "Nothing can fire for this long after a trigger.",
                          value: $settings.config.cooldown,
                          range: 0.2...6, step: 0.1, unit: "s")

                SliderRow(title: "Re-arm delay",
                          detail: "After firing, the same gesture must be gone this long before it can fire again.",
                          value: $settings.config.rearmDuration,
                          range: 0...2, step: 0.05, unit: "s")

                SliderRow(title: "Dropout tolerance",
                          detail: "Ignore detection gaps shorter than this so a steady hand isn't interrupted.",
                          value: $settings.config.dropoutGrace,
                          range: 0...1, step: 0.05, unit: "s")
            } header: {
                Text("Triggering")
            } footer: {
                Text("Total time from showing a gesture to it firing again: about \(totalCycle, specifier: "%.1f")s.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                SliderRow(title: "Minimum confidence",
                          detail: "Higher means gestures must match more precisely. Raise this if actions fire by accident.",
                          value: $settings.config.minimumReadingConfidence,
                          range: 0.05...0.9, step: 0.05, unit: "")

                SliderRow(title: "Analysis frame rate",
                          detail: "Frames analysed per second. Detection itself costs only ~3 ms, so the gap between frames is what sets responsiveness — lowering this saves little CPU but makes gestures feel sluggish.",
                          value: $settings.config.analysisFramesPerSecond,
                          range: 5...30, step: 1, unit: " fps", decimals: 0)
            } header: {
                Text("Recognition")
            }

            Section {
                Toggle(isOn: $settings.cheatSheetHotKeyEnabled) {
                    Text("Global shortcut for the gesture list")
                    Text("Pops up a panel listing every gesture and its action, over whatever app you're in. Press again to dismiss.")
                }

                if settings.cheatSheetHotKeyEnabled {
                    Picker("Key", selection: $settings.cheatSheetHotKey.keyName) {
                        ForEach(KeyCombo.orderedKeyNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    HStack(spacing: 14) {
                        Toggle("⌘", isOn: $settings.cheatSheetHotKey.command)
                        Toggle("⇧", isOn: $settings.cheatSheetHotKey.shift)
                        Toggle("⌥", isOn: $settings.cheatSheetHotKey.option)
                        Toggle("⌃", isOn: $settings.cheatSheetHotKey.control)
                        Spacer()
                        Button("Show now") { app.toggleCheatSheet() }
                            .controlSize(.small)
                    }
                    .toggleStyle(.button)

                    if !settings.cheatSheetHotKey.hasModifier {
                        Label("Pick at least one modifier — a bare key would be captured system-wide.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    } else if app.cheatSheetHotKeyConflicted {
                        Label("\(settings.cheatSheetHotKey.displayString) is already used by another app — choose a different combination.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Label("\(settings.cheatSheetHotKey.displayString) is registered.",
                              systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
            } header: {
                Text("Gesture list")
            } footer: {
                Text("This shortcut works without Accessibility permission.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $settings.cameraOverlayVisible) {
                    Text("Show camera overlay")
                    Text("A small always-on-top camera view with the hand tracking drawn on it. Drag it anywhere — its position is remembered.")
                }

                Picker("Size", selection: $settings.cameraOverlaySize) {
                    ForEach(OverlaySize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .disabled(!settings.cameraOverlayVisible)

                Picker("Key", selection: $settings.cameraOverlayHotKey.keyName) {
                    ForEach(KeyCombo.orderedKeyNames, id: \.self) { Text($0).tag($0) }
                }
                HStack(spacing: 14) {
                    Toggle("⌘", isOn: $settings.cameraOverlayHotKey.command)
                    Toggle("⇧", isOn: $settings.cameraOverlayHotKey.shift)
                    Toggle("⌥", isOn: $settings.cameraOverlayHotKey.option)
                    Toggle("⌃", isOn: $settings.cameraOverlayHotKey.control)
                    Spacer()
                }
                .toggleStyle(.button)

                if !settings.cameraOverlayHotKey.hasModifier {
                    Label("Pick at least one modifier — a bare key would be captured system-wide.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else if app.cameraOverlayHotKeyConflicted {
                    Label("\(settings.cameraOverlayHotKey.displayString) is already used by another app.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Label("\(settings.cameraOverlayHotKey.displayString) toggles the overlay.",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            } header: {
                Text("Camera overlay")
            }

            Section {
                Toggle(isOn: $settings.showStatusIndicator) {
                    Text("Status indicator in the corner")
                    Text("A small pill in the top-right of the main display showing Active, Paused or Off. Always on top, and click-through so it never blocks anything underneath.")
                }
                Toggle("Show floating HUD over other apps", isOn: $settings.showHUD)
                Picker("HUD position", selection: $settings.hudPosition) {
                    ForEach(HUDPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .disabled(!settings.showHUD)
                Toggle("Draw hand skeleton on preview", isOn: $settings.showLandmarks)
            } header: {
                Text("Feedback")
            }

            Section {
                Toggle("Turn on gesture control when SayHi launches",
                       isOn: $settings.startRecognitionAtLaunch)
            } header: {
                Text("Startup")
            }

            Section(isExpanded: $showAdvanced) {
                Text("These control the shape rules themselves. Turn on Debug on the Camera tab to watch the live scores while adjusting.")
                    .font(.caption).foregroundStyle(.secondary)

                SliderRow(title: "Finger extended above",
                          detail: "Extension score at which a finger counts as straight.",
                          value: $settings.config.fingerExtendedMin,
                          range: 0.1...0.8, step: 0.01, unit: "", decimals: 2)

                SliderRow(title: "Finger folded below",
                          detail: "Extension score at which a finger counts as curled.",
                          value: $settings.config.fingerFoldedMax,
                          range: -0.1...0.5, step: 0.01, unit: "", decimals: 2)

                SliderRow(title: "Thumb extended above",
                          detail: "Thumb-to-index-knuckle distance for an extended thumb.",
                          value: $settings.config.thumbExtendedMin,
                          range: 0.4...1.6, step: 0.05, unit: "", decimals: 2)

                SliderRow(title: "Thumb folded below",
                          detail: "Below this the thumb counts as tucked into a fist.",
                          value: $settings.config.thumbFoldedMax,
                          range: 0.2...1.2, step: 0.05, unit: "", decimals: 2)

                SliderRow(title: "Pinch distance (OK sign)",
                          detail: "How close thumb and index tips must be to count as touching.",
                          value: $settings.config.pinchMax,
                          range: 0.1...1.0, step: 0.05, unit: "", decimals: 2)
            } header: {
                Text("Advanced recognition thresholds")
            }

            Section {
                HStack {
                    Button("Reset recognition settings") {
                        settings.resetRecognitionDefaults()
                    }
                    .disabled(!settings.hasCustomRecognitionSettings)
                    Spacer()
                    Text("Gesture mappings are not affected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Label("Hand recognition runs entirely on this Mac. Camera images are not stored or transmitted.",
                      systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshPermissions)
        .onReceive(permissionTimer) { _ in refreshPermissions() }
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

/// One permission's live status, with a jump straight to its System Settings pane.
private struct PermissionRow: View {
    let name: String
    let detail: String
    let granted: Bool
    /// System Settings anchor, e.g. "Privacy_ScreenCapture".
    let pane: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Open…") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
                    NSWorkspace.shared.open(url)
                }
                .controlSize(.small)
            }
        }
    }
}

/// A labelled slider with a live value readout and an explanatory subtitle.
private struct SliderRow: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit: String = ""
    var decimals: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(formatted)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private var formatted: String {
        String(format: "%.\(decimals)f%@", value, unit)
    }
}
