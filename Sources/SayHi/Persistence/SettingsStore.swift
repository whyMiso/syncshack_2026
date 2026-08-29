import Foundation
import SwiftUI

/// Where the floating HUD appears.
enum HUDPosition: String, Codable, CaseIterable, Identifiable {
    case top
    case bottom

    var id: String { rawValue }
    var displayName: String { self == .top ? "Top of screen" : "Bottom of screen" }
}

/// Preset sizes for the floating camera overlay. 4:3 to match the capture.
enum OverlaySize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var preview: CGSize {
        switch self {
        case .small:  return CGSize(width: 200, height: 150)
        case .medium: return CGSize(width: 280, height: 210)
        case .large:  return CGSize(width: 380, height: 285)
        }
    }
}

/// User settings: recognition tuning (`config`) plus behaviour preferences.
/// Backed by UserDefaults and written through to `GestureConfig.shared` so the
/// classifier and state machine pick changes up immediately.
@MainActor
final class SettingsStore: ObservableObject {

    /// Recognition thresholds and timings.
    @Published var config: GestureConfig {
        didSet {
            guard config != oldValue else { return }
            GestureConfig.shared = config
            persistConfig()
        }
    }

    /// Master switch for *executing* actions. When off, gestures are still
    /// recognised and shown — nothing is run. Useful for practising gestures
    /// or tuning thresholds without firing off screenshots and app launches.
    @Published var actionsEnabled: Bool {
        didSet { defaults.set(actionsEnabled, forKey: Keys.actionsEnabled) }
    }

    /// System-wide hotkey that shows/hides the gesture cheat sheet.
    @Published var cheatSheetHotKey: KeyCombo {
        didSet {
            guard cheatSheetHotKey != oldValue else { return }
            if let data = try? JSONEncoder().encode(cheatSheetHotKey) {
                defaults.set(data, forKey: Keys.cheatSheetHotKey)
            }
        }
    }

    /// Whether that hotkey is registered at all.
    @Published var cheatSheetHotKeyEnabled: Bool {
        didSet { defaults.set(cheatSheetHotKeyEnabled, forKey: Keys.cheatSheetEnabled) }
    }

    /// Whether the floating camera overlay is on screen. Persisted so it
    /// comes back where it was left.
    @Published var cameraOverlayVisible: Bool {
        didSet { defaults.set(cameraOverlayVisible, forKey: Keys.overlayVisible) }
    }

    @Published var cameraOverlaySize: OverlaySize {
        didSet { defaults.set(cameraOverlaySize.rawValue, forKey: Keys.overlaySize) }
    }

    /// Drops the overlay's status strip so the window is only the camera
    /// picture — 30pt shorter at every size preset.
    ///
    /// What it costs is the gesture name, confidence and hand side. Those are
    /// still readable elsewhere (the corner status pill, the floating HUD, the
    /// Camera tab), which is what makes losing them here reasonable.
    @Published var cameraOverlayCompact: Bool {
        didSet { defaults.set(cameraOverlayCompact, forKey: Keys.overlayCompact) }
    }

    /// System-wide hotkey that shows/hides the camera overlay.
    @Published var cameraOverlayHotKey: KeyCombo {
        didSet {
            guard cameraOverlayHotKey != oldValue else { return }
            if let data = try? JSONEncoder().encode(cameraOverlayHotKey) {
                defaults.set(data, forKey: Keys.overlayHotKey)
            }
        }
    }

    /// Where the user last dragged the overlay to, in screen coordinates.
    var cameraOverlayOrigin: CGPoint? {
        get {
            guard let dict = defaults.dictionary(forKey: Keys.overlayOrigin),
                  let x = dict["x"] as? Double, let y = dict["y"] as? Double else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            guard let newValue else { return }
            defaults.set(["x": newValue.x, "y": newValue.y], forKey: Keys.overlayOrigin)
        }
    }

    /// Small always-on-top pill in the top-right corner showing on/off state.
    @Published var showStatusIndicator: Bool {
        didSet { defaults.set(showStatusIndicator, forKey: Keys.statusIndicator) }
    }

    /// Show the floating HUD when SayHi isn't the frontmost app.
    @Published var showHUD: Bool {
        didSet { defaults.set(showHUD, forKey: Keys.showHUD) }
    }

    @Published var hudPosition: HUDPosition {
        didSet { defaults.set(hudPosition.rawValue, forKey: Keys.hudPosition) }
    }

    /// Draw the hand skeleton over the camera preview.
    @Published var showLandmarks: Bool {
        didSet { defaults.set(showLandmarks, forKey: Keys.showLandmarks) }
    }

    /// Turn gesture control on automatically when the app launches.
    @Published var startRecognitionAtLaunch: Bool {
        didSet { defaults.set(startRecognitionAtLaunch, forKey: Keys.startAtLaunch) }
    }

    /// ⌥⌘G — "G for gestures", and not a combination macOS reserves.
    static let defaultCheatSheetHotKey = KeyCombo(keyName: "G", command: true, option: true)
    /// ⌥⌘C — "C for camera".
    static let defaultCameraOverlayHotKey = KeyCombo(keyName: "C", command: true, option: true)

    private let defaults: UserDefaults

    private enum Keys {
        static let config = "recognitionConfig"
        static let actionsEnabled = "actionsEnabled"
        static let showHUD = "showHUD"
        static let hudPosition = "hudPosition"
        static let showLandmarks = "showLandmarks"
        static let startAtLaunch = "startRecognitionAtLaunch"
        static let analysisRateLifted = "analysisRateLiftedFrom12"
        static let cheatSheetHotKey = "cheatSheetHotKey"
        static let cheatSheetEnabled = "cheatSheetHotKeyEnabled"
        static let overlayVisible = "cameraOverlayVisible"
        static let overlaySize = "cameraOverlaySize"
        static let overlayCompact = "cameraOverlayCompact"
        static let overlayHotKey = "cameraOverlayHotKey"
        static let overlayOrigin = "cameraOverlayOrigin"
        static let statusIndicator = "showStatusIndicator"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // `object(forKey:)` distinguishes "never set" from "set to false",
        // which `bool(forKey:)` cannot.
        func flag(_ key: String, default fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }

        if let data = defaults.data(forKey: Keys.config),
           let decoded = try? JSONDecoder().decode(GestureConfig.self, from: data) {
            config = decoded
        } else {
            config = GestureConfig()
        }

        actionsEnabled = flag(Keys.actionsEnabled, default: true)
        cheatSheetHotKeyEnabled = flag(Keys.cheatSheetEnabled, default: true)
        if let data = defaults.data(forKey: Keys.cheatSheetHotKey),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            cheatSheetHotKey = combo
        } else {
            cheatSheetHotKey = SettingsStore.defaultCheatSheetHotKey
        }
        cameraOverlayVisible = flag(Keys.overlayVisible, default: false)
        cameraOverlaySize = (defaults.string(forKey: Keys.overlaySize)
            .flatMap(OverlaySize.init(rawValue:))) ?? .medium
        cameraOverlayCompact = flag(Keys.overlayCompact, default: false)
        if let data = defaults.data(forKey: Keys.overlayHotKey),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            cameraOverlayHotKey = combo
        } else {
            cameraOverlayHotKey = SettingsStore.defaultCameraOverlayHotKey
        }
        showStatusIndicator = flag(Keys.statusIndicator, default: true)
        showHUD = flag(Keys.showHUD, default: true)
        showLandmarks = flag(Keys.showLandmarks, default: true)
        startRecognitionAtLaunch = flag(Keys.startAtLaunch, default: false)
        hudPosition = (defaults.string(forKey: Keys.hudPosition)
            .flatMap(HUDPosition.init(rawValue:))) ?? .top

        liftLegacyAnalysisRate()

        // Publish the loaded config to the recognition pipeline.
        GestureConfig.shared = config
    }

    /// The analysis rate originally defaulted to a very conservative 12 fps.
    /// Measured on-device, hand-pose detection costs about 3 ms per frame, so
    /// that 83 ms gap between frames was nearly all of the input latency while
    /// saving almost no CPU.
    ///
    /// The whole config persists as one blob, so a saved 12 was written the
    /// moment *any* slider moved and can't be told apart from a deliberate
    /// choice. This lifts it once, and records that it has done so, so it
    /// never overrides the value again if it is set back deliberately.
    private func liftLegacyAnalysisRate() {
        guard !defaults.bool(forKey: Keys.analysisRateLifted) else { return }
        defaults.set(true, forKey: Keys.analysisRateLifted)
        guard config.analysisFramesPerSecond <= 12 else { return }
        config.analysisFramesPerSecond = GestureConfig.defaults.analysisFramesPerSecond
        persistConfig()
    }

    /// Restore factory recognition thresholds, leaving mappings and
    /// behaviour preferences alone.
    func resetRecognitionDefaults() {
        config = GestureConfig.defaults
    }

    var hasCustomRecognitionSettings: Bool {
        config != GestureConfig.defaults
    }

    private func persistConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Keys.config)
    }
}
