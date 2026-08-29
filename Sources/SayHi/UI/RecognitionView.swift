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
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .animation(Motion.enter, value: app.lastEvent?.id)

            statusBar

            if app.showDebugPanel {
                DebugPanelView()
            }
        }
        .padding(16)
    }

    // MARK: Camera area

    @ViewBuilder
    private var cameraArea: some View {
        InsetCard(cornerRadius: 14, style: .recessed) {
            Group {
                if !app.isEnabled {
                    placeholder(icon: "video.slash",
                                title: "Gesture control is off",
                                detail: "Turn it on to start the camera. Hand recognition runs entirely on this Mac.")
                } else if app.cameraAuthorization == .denied || app.cameraAuthorization == .restricted {
                    placeholder(icon: "exclamationmark.triangle",
                                title: "Camera access denied",
                                detail: "Allow SayHi in System Settings → Privacy & Security → Camera, then re-enable gesture control.")
                } else {
                    CameraPreviewView(session: app.cameraManager.session,
                                      hand: app.currentHand,
                                      showLandmarks: settings.showLandmarks)
                }
            }
            .frame(minHeight: 320)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func placeholder(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
            Text(title).textRole(.primary)
            Text(detail)
                .textRole(.body, tint: Palette.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(24)
    }

    /// Outcome reads from an icon and a label rather than a colour — there is
    /// one accent in this UI and it is spoken for.
    private func triggerBanner(_ event: AppState.TriggerEvent) -> some View {
        HStack(spacing: 10) {
            GestureGlyph(gesture: event.gesture, size: 18)
            Text("\(event.binding.displayName) → \(event.message)")
                .textRole(.bodyEmphasis)
                .lineLimit(2)
            Image(systemName: outcomeSymbol(event.kind))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassSurface(cornerRadius: Radius.compact, scrim: 0.55, depth: .compact)
        .padding(.horizontal, 16)
    }

    private func outcomeSymbol(_ kind: AppState.TriggerEvent.Kind) -> String {
        switch kind {
        case .success:    return "checkmark"
        case .failure:    return "exclamationmark.triangle"
        case .suppressed: return "minus"
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        InsetCard(cornerRadius: 12) {
            HStack(spacing: 16) {
                HStack(spacing: 10) {
                    GestureGlyph(gesture: app.currentReading.gesture, size: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(readingTitle)
                            .textRole(.bodyEmphasis)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            if let side = app.currentHandSide {
                                FieldLabel(side.shortName + " hand")
                            } else if app.currentHand != nil {
                                // Actions are keyed by hand, so an undetermined
                                // side means nothing can fire — say so explicitly.
                                FieldLabel("Hand side unclear", tint: Palette.inkFaint)
                            }
                            FieldLabel("\(Int(app.currentReading.confidence * 100))% confident",
                                       tint: Palette.inkFaint)
                        }
                    }
                }
                .frame(width: 230, alignment: .leading)

                Rectangle().fill(Palette.hairline).frame(width: 1, height: 32)

                progressSection

                Spacer()

                ToggleChip(title: "Debug", isOn: app.showDebugPanel) {
                    app.showDebugPanel.toggle()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var readingTitle: String {
        guard app.currentReading.gesture != .unknown else {
            return app.currentHand == nil ? "No hand detected" : "No gesture"
        }
        return app.currentReading.gesture.displayName
    }

    @ViewBuilder
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            switch app.machineSnapshot.phase {
            case .holding(let binding, let since):
                FieldLabel("Hold \(binding.displayName)")
                HoldProgressBar(since: since,
                                duration: settings.config.holdDuration,
                                width: 200)
            case .cooldown:
                // Keep the completed bar on screen through the cooldown so the
                // hold visibly finishes instead of disappearing at ~90%.
                FieldLabel("Triggered — cooling down")
                CompletedHoldBar(width: 200)
            case .awaitingRearm(let binding):
                FieldLabel("Relax hand to re-arm")
                Text(binding.displayName)
                    .textRole(.body, tint: Palette.inkMuted)
                    .lineLimit(1)
            case .idle:
                FieldLabel(app.isEnabled ? "Ready" : "Paused")
                Text(app.isEnabled ? "Show a gesture" : "Recognition is off")
                    .textRole(.body, tint: Palette.inkMuted)
                    .lineLimit(1)
            }
        }
        .frame(width: 210, alignment: .leading)
    }
}

/// Developer panel: finger scores, candidate, frames, armed/cooldown state.
struct DebugPanelView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        InsetCard(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("Debug")
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
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
                .font(.system(size: 11, design: .monospaced))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fingerCell(_ label: String, _ value: Double?) -> some View {
        debugCell(label, value.map { String(format: "%+.2f", $0) } ?? "–")
    }

    private func debugCell(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label + ":").foregroundStyle(Palette.inkFaint)
            Text(value).foregroundStyle(Palette.ink)
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
