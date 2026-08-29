import SwiftUI

/// The live camera screen: preview, current gesture, hold progress,
/// trigger confirmations, and the optional debug panel.
struct RecognitionView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .top) {
                cameraArea
                if let event = app.lastEvent {
                    triggerBanner(event)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: app.lastEvent)

            statusBar

            if app.showDebugPanel {
                DebugPanelView()
            }
        }
        .padding()
    }

    // MARK: Camera area

    @ViewBuilder
    private var cameraArea: some View {
        Group {
            if !app.isEnabled {
                placeholder(icon: "video.slash",
                            title: "Gesture Control is off",
                            detail: "Turn it on to start the camera. Hand recognition runs entirely on this Mac.")
            } else if app.cameraAuthorization == .denied || app.cameraAuthorization == .restricted {
                placeholder(icon: "exclamationmark.triangle",
                            title: "Camera access denied",
                            detail: "Allow SayHi in System Settings → Privacy & Security → Camera, then re-enable gesture control.")
            } else {
                CameraPreviewView(cameraManager: app.cameraManager,
                                  hand: app.currentHand,
                                  showLandmarks: settings.showLandmarks)
            }
        }
        .frame(minHeight: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func placeholder(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding()
    }

    private func triggerBanner(_ event: AppState.TriggerEvent) -> some View {
        Label {
            Text("\(event.binding.displayName) → \(event.message)")
                .fontWeight(.medium)
        } icon: {
            Text(event.gesture.symbol)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(event.kind.bannerColor, in: Capsule())
        .foregroundStyle(.white)
        .shadow(radius: 4)
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Text(app.currentReading.gesture.symbol).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.currentReading.gesture == .unknown
                         ? (app.currentHand == nil ? "No hand detected" : "No gesture")
                         : app.currentReading.gesture.displayName)
                        .font(.headline)
                    HStack(spacing: 6) {
                        if let side = app.currentHandSide {
                            Text("\(side.symbol) \(side.shortName)")
                                .font(.caption).fontWeight(.medium)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.tint.opacity(0.18), in: Capsule())
                        } else if app.currentHand != nil {
                            // Actions are keyed by hand, so an undetermined
                            // side means nothing can fire — say so explicitly.
                            Text("Hand side unclear")
                                .font(.caption).fontWeight(.medium)
                                .foregroundStyle(.orange)
                        }
                        Text("Confidence \(Int(app.currentReading.confidence * 100))%")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 220, alignment: .leading)

            Divider().frame(height: 32)

            progressSection

            Spacer()

            Toggle("Debug", isOn: $app.showDebugPanel)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch app.machineSnapshot.phase {
            case .holding(let binding, let since):
                Text("Hold \(binding.displayName)…")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HoldProgressBar(since: since,
                                duration: settings.config.holdDuration,
                                width: 180)
            case .cooldown:
                // Keep the completed bar on screen through the cooldown so the
                // hold visibly finishes instead of disappearing at ~90%.
                Text("Triggered — cooling down")
                    .font(.caption).foregroundStyle(.green).lineLimit(1)
                CompletedHoldBar(width: 180)
            case .awaitingRearm(let binding):
                Text("Relax hand to re-arm \(binding.displayName)")
                    .font(.caption).foregroundStyle(.orange).lineLimit(2)
            case .idle:
                Text(app.isEnabled ? "Ready — show a gesture" : "Paused")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 200, alignment: .leading)
    }
}

/// Developer panel: finger scores, candidate, frames, armed/cooldown state.
struct DebugPanelView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug").font(.caption).bold().foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                GridRow {
                    fingerCell("Index", app.fingerStates.index)
                    fingerCell("Middle", app.fingerStates.middle)
                    fingerCell("Ring", app.fingerStates.ring)
                    fingerCell("Little", app.fingerStates.little)
                    fingerCell("Pinch", app.fingerStates.pinch)
                }
                GridRow {
                    fingerCell("Thumb spread", app.fingerStates.thumbSpread)
                    fingerCell("Thumb rise", app.fingerStates.thumbRise)
                    debugCell("Frames", "\(app.machineSnapshot.consecutiveFrames)")
                    debugCell("Armed", app.machineSnapshot.isArmed ? "yes" : "no")
                }
                GridRow {
                    debugCell("Candidate", app.currentReading.gesture.rawValue)
                    debugCell("Confidence", String(format: "%.2f", app.currentReading.confidence))
                    debugCell("Phase", phaseName)
                    debugCell("Hand", handName)
                }
            }
            .font(.system(.caption, design: .monospaced))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func fingerCell(_ label: String, _ value: Double?) -> some View {
        debugCell(label, value.map { String(format: "%+.2f", $0) } ?? "–")
    }

    private func debugCell(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":").foregroundStyle(.secondary)
            Text(value)
        }
    }

    private var phaseName: String {
        switch app.machineSnapshot.phase {
        case .idle: return "idle"
        case .holding: return "holding"
        case .cooldown: return "cooldown"
        case .awaitingRearm: return "rearm"
        }
    }

    /// Stabilised side, with the raw per-frame reading in parentheses so
    /// chirality flicker is visible while tuning.
    private var handName: String {
        let smoothed = app.currentHandSide?.shortName.lowercased() ?? "–"
        let raw = app.currentHand?.userHandSide?.shortName.lowercased() ?? "?"
        return "\(smoothed) (\(raw))"
    }
}
