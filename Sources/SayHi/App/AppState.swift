import AVFoundation
import Combine
import Foundation
import SwiftUI

/// Central coordinator: owns the camera → detection → classification →
/// debounce → action pipeline and publishes UI-facing state.
///
/// Threading: frames arrive on the camera's video queue, where Vision and
/// classification run. Results hop to the main actor for state-machine
/// bookkeeping, UI publishing, and action execution.
@MainActor
final class AppState: ObservableObject {

    // MARK: Master switch

    @Published var isEnabled = false {
        didSet {
            guard oldValue != isEnabled else { return }
            isEnabled ? startPipeline() : stopPipeline()
        }
    }

    // MARK: Published recognition state (for RecognitionView / debug panel)

    @Published private(set) var cameraAuthorization = CameraManager.authorizationStatus
    @Published private(set) var currentReading: GestureReading = .none
    @Published private(set) var machineSnapshot = GestureStateMachine.Snapshot(
        phase: .idle, holdProgress: 0, consecutiveFrames: 0, isArmed: true)
    @Published private(set) var currentHand: HandPose?
    /// Stabilised side of the hand in view, in the user's own terms.
    @Published private(set) var currentHandSide: HandSide?
    @Published private(set) var fingerStates = FingerStates()
    /// Banner shown after an action fires, e.g. "✊ FIST → Screenshot saved".
    @Published private(set) var lastEvent: TriggerEvent?
    @Published var showDebugPanel = false

    struct TriggerEvent: Identifiable, Equatable {
        enum Kind { case success, failure, suppressed }

        let id = UUID()
        var binding: GestureBinding
        var message: String
        var kind: Kind
        var date: Date

        var gesture: Gesture { binding.gesture }
    }

    // MARK: Pipeline components

    let cameraManager = CameraManager()
    let mappingStore = GestureMappingStore()
    let settings = SettingsStore()
    private var stateMachine = GestureStateMachine()
    private var chiralitySmoother = ChiralitySmoother()
    private let executor = ActionExecutor()
    /// Floating on-screen feedback shown when SayHi's window isn't in view.
    private lazy var hud = HUDController(appState: self)
    /// Pop-up reference sheet of every gesture and its action.
    private lazy var cheatSheet = CheatSheetController(appState: self)
    private var cheatSheetHotKey: GlobalHotKey?
    /// Draggable always-on-top camera view.
    private lazy var cameraOverlay = CameraOverlayController(appState: self)
    private var cameraOverlayHotKey: GlobalHotKey?
    /// Always-on-top on/off pill in the top-right corner.
    private let statusIndicator = StatusIndicatorController()

    /// True when the configured cheat-sheet hotkey could not be registered,
    /// which in practice means another app already owns that combination.
    @Published private(set) var cheatSheetHotKeyConflicted = false
    @Published private(set) var cameraOverlayHotKeyConflicted = false

    private var bannerDismissTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        cameraManager.targetFramesPerSecond = settings.config.analysisFramesPerSecond

        executor.toggleActionsHandler = { [weak self] in
            guard let self else { return false }
            self.settings.actionsEnabled.toggle()
            return self.settings.actionsEnabled
        }

        executor.stopCameraHandler = { [weak self] in
            self?.isEnabled = false
        }

        // Re-throttle the camera when the analysis rate is changed in Settings.
        settings.$config
            .map(\.analysisFramesPerSecond)
            .removeDuplicates()
            .sink { [weak self] fps in
                self?.cameraManager.targetFramesPerSecond = fps
            }
            .store(in: &cancellables)

        // Settings live in their own store, but several views read them
        // through AppState — forward changes so those views refresh.
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        mappingStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Detector and classifier live on the camera's video queue, not the
        // main actor — captured locally so Vision work never touches the UI thread.
        let detector = HandPoseDetector()
        let classifier = GestureClassifier()
        cameraManager.frameHandler = { [weak self] pixelBuffer in
            let pose = detector.detect(in: pixelBuffer)
            let result = pose.map { classifier.classify($0) }
            Task { @MainActor [weak self] in
                self?.handleResult(result, pose: pose)
            }
        }

        // Re-register the cheat-sheet hotkey whenever it is changed or toggled.
        settings.$cheatSheetHotKey
            .removeDuplicates()
            .combineLatest(settings.$cheatSheetHotKeyEnabled.removeDuplicates())
            .sink { [weak self] combo, enabled in
                // Deferred: this fires during SettingsStore's own publish, and
                // registering touches AppKit state the run loop is mid-way through.
                DispatchQueue.main.async {
                    self?.registerCheatSheetHotKey(combo, enabled: enabled)
                }
            }
            .store(in: &cancellables)

        // Same for the camera overlay's hotkey.
        settings.$cameraOverlayHotKey
            .removeDuplicates()
            .sink { [weak self] combo in
                DispatchQueue.main.async { self?.registerCameraOverlayHotKey(combo) }
            }
            .store(in: &cancellables)

        // Keep the overlay in step with its setting, so the menu bar, Settings
        // and the hotkey all drive the same switch.
        settings.$cameraOverlayVisible
            .removeDuplicates()
            .sink { [weak self] visible in
                DispatchQueue.main.async { self?.applyCameraOverlayVisibility(visible) }
            }
            .store(in: &cancellables)

        settings.$cameraOverlaySize
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.cameraOverlay.refreshSize() }
            }
            .store(in: &cancellables)

        // The status pill only changes when one of these two switches does,
        // which is why it doesn't observe AppState's per-frame publishing.
        $isEnabled
            .removeDuplicates()
            .combineLatest(settings.$actionsEnabled.removeDuplicates(),
                           settings.$showStatusIndicator.removeDuplicates())
            .sink { [weak self] _, _, _ in
                DispatchQueue.main.async { self?.refreshStatusIndicator() }
            }
            .store(in: &cancellables)

        // Property observers don't fire during init, so the pipeline is
        // started on the next main-actor turn rather than by assigning here.
        if settings.startRecognitionAtLaunch {
            Task { @MainActor [weak self] in self?.isEnabled = true }
        }
    }

    // MARK: - Pipeline control

    private func startPipeline() {
        switch CameraManager.authorizationStatus {
        case .authorized:
            cameraAuthorization = .authorized
            cameraManager.start()
        case .notDetermined:
            CameraManager.requestAccess { [weak self] granted in
                guard let self else { return }
                self.cameraAuthorization = CameraManager.authorizationStatus
                if granted, self.isEnabled {
                    self.cameraManager.start()
                } else {
                    self.isEnabled = false
                }
            }
        default:
            cameraAuthorization = CameraManager.authorizationStatus
            isEnabled = false
        }
    }

    private func stopPipeline() {
        cameraManager.stop()
        stateMachine.reset()
        chiralitySmoother.reset()
        currentReading = .none
        currentHand = nil
        currentHandSide = nil
        machineSnapshot = stateMachine.snapshot()
        // Not a flat `hide()`: the camera-off action raises its banner and
        // *then* stops the pipeline, so the HUD has to be re-evaluated rather
        // than dismissed outright. `updateHUD` decides which case this is.
        updateHUD()
    }

    // MARK: - Frame results (main actor)

    private func handleResult(_ result: GestureClassifier.Result?, pose: HandPose?) {
        guard isEnabled else { return }

        let reading = result?.reading ?? .none
        currentReading = reading
        currentHand = pose
        fingerStates = result?.fingers ?? FingerStates()

        let now = Date()

        if let pose {
            currentHandSide = chiralitySmoother.update(pose.userHandSide)
        } else {
            chiralitySmoother.reset()
            currentHandSide = nil
        }

        // A gesture only counts once we know which hand made it — the hand is
        // half of the binding key.
        var binding: GestureBinding?
        if reading.gesture != .unknown, let side = currentHandSide {
            binding = GestureBinding(gesture: reading.gesture, hand: side)
        }

        if let fired = stateMachine.process(binding, at: now) {
            trigger(fired)
        }

        machineSnapshot = stateMachine.snapshot(at: now)
        updateHUD()
    }

    // MARK: - Cheat sheet

    func toggleCheatSheet() {
        cheatSheet.toggle()
    }

    private func registerCheatSheetHotKey(_ combo: KeyCombo, enabled: Bool) {
        // Release the old registration first — Carbon refuses a duplicate
        // combination, so re-registering over ourselves would always fail.
        cheatSheetHotKey = nil

        guard enabled, let keyCode = combo.keyCode, combo.hasModifier else {
            cheatSheetHotKeyConflicted = false
            return
        }
        cheatSheetHotKey = GlobalHotKey(keyCode: keyCode,
                                        carbonModifiers: combo.carbonModifiers) { [weak self] in
            self?.toggleCheatSheet()
        }
        cheatSheetHotKeyConflicted = (cheatSheetHotKey == nil)
        if cheatSheetHotKeyConflicted {
            NSLog("SayHi: could not register cheat-sheet hotkey %@ — already in use",
                  combo.displayString)
        }
    }

    // MARK: - Status indicator

    private func refreshStatusIndicator() {
        let state: IndicatorState
        if !isEnabled {
            state = .off
        } else {
            state = settings.actionsEnabled ? .active : .paused
        }
        statusIndicator.update(state: state, visible: settings.showStatusIndicator)
    }

    // MARK: - Camera overlay

    func toggleCameraOverlay() {
        settings.cameraOverlayVisible.toggle()
    }

    private func applyCameraOverlayVisibility(_ visible: Bool) {
        visible ? cameraOverlay.show() : cameraOverlay.hide()
    }

    private func registerCameraOverlayHotKey(_ combo: KeyCombo) {
        cameraOverlayHotKey = nil
        guard let keyCode = combo.keyCode, combo.hasModifier else {
            cameraOverlayHotKeyConflicted = false
            return
        }
        cameraOverlayHotKey = GlobalHotKey(keyCode: keyCode,
                                           carbonModifiers: combo.carbonModifiers) { [weak self] in
            self?.toggleCameraOverlay()
        }
        cameraOverlayHotKeyConflicted = (cameraOverlayHotKey == nil)
        if cameraOverlayHotKeyConflicted {
            NSLog("SayHi: could not register camera-overlay hotkey %@ — already in use",
                  combo.displayString)
        }
    }

    // MARK: - Floating HUD

    /// Shows the system-wide HUD while a gesture hold is under way or a
    /// trigger banner is up — but only when the SayHi window isn't visible,
    /// where the in-window UI already shows the same feedback.
    private func updateHUD() {
        guard settings.showHUD else { hud.hide(); return }

        // The HUD normally exists only while the pipeline is running. One
        // message is exempt: the camera-off confirmation is raised by the very
        // action that stops the pipeline, and it is the only thing on screen
        // saying where to switch the camera back on.
        guard isEnabled || isCameraOffNotice else { hud.hide(); return }

        // While paused, only the pause switch itself shows in the HUD. Popping
        // the overlay up for every other gesture would defeat the point of
        // pausing, which is to move your hands without anything reacting.
        if !settings.actionsEnabled, !involvesPauseSwitch { hud.hide(); return }

        var wantsBar = false
        switch machineSnapshot.phase {
        case .holding:
            // A tiny progress threshold keeps stray one-frame detections from
            // flashing the HUD.
            wantsBar = machineSnapshot.holdProgress > 0.1
        case .cooldown:
            // Stay up through the cooldown. Actions report asynchronously, so
            // otherwise the HUD would blink out at the trigger moment and
            // reappear a beat later with the result banner.
            wantsBar = true
        default:
            break
        }
        let wantsHUD = (wantsBar || lastEvent != nil) && !isMainWindowVisible
        wantsHUD ? hud.show() : hud.hide()
    }

    /// True when the gesture being held, or the one that just fired, is the
    /// pause switch — the only thing allowed to surface while paused.
    private var involvesPauseSwitch: Bool {
        if let held = machineSnapshot.holding,
           mappingStore.action(for: held) == .toggleActions { return true }
        if let event = lastEvent,
           mappingStore.action(for: event.binding) == .toggleActions { return true }
        return false
    }

    /// True when the banner currently up is the camera-off confirmation — the
    /// one notice allowed to outlive the pipeline that produced it.
    private var isCameraOffNotice: Bool {
        guard let event = lastEvent else { return false }
        return mappingStore.action(for: event.binding) == .stopCamera
    }

    private var isMainWindowVisible: Bool {
        NSApp.isActive && NSApp.windows.contains { $0.isVisible && $0.title == "SayHi" }
    }

    // MARK: - Action execution

    private func trigger(_ binding: GestureBinding) {
        let action = mappingStore.action(for: binding)

        // The pause switch is handled before the actions-enabled gate, because
        // it has to keep working *while* paused — otherwise pausing would be a
        // one-way trip needing the keyboard to undo.
        if action == .toggleActions {
            executor.execute(action) { [weak self] outcome in
                guard case .success(let description) = outcome else { return }
                self?.showBanner(TriggerEvent(binding: binding, message: description,
                                              kind: .success, date: Date()))
            }
            return
        }

        guard action != .none else {
            showBanner(TriggerEvent(binding: binding,
                                    message: "recognised — no action assigned",
                                    kind: .suppressed, date: Date()))
            return
        }

        // Actions paused: report what *would* have run so the recognition
        // loop can still be practised and tuned safely.
        guard settings.actionsEnabled else {
            showBanner(TriggerEvent(binding: binding,
                                    message: "\(action.displayName) — actions paused",
                                    kind: .suppressed, date: Date()))
            return
        }

        executor.execute(action) { [weak self] outcome in
            let event: TriggerEvent
            switch outcome {
            case .success(let description):
                event = TriggerEvent(binding: binding, message: description,
                                     kind: .success, date: Date())
            case .failure(let message):
                event = TriggerEvent(binding: binding, message: message,
                                     kind: .failure, date: Date())
            }
            self?.showBanner(event)
        }
    }

    private func showBanner(_ event: TriggerEvent) {
        lastEvent = event
        updateHUD()
        bannerDismissTask?.cancel()
        bannerDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.lastEvent = nil
            self?.updateHUD()
        }
    }
}
