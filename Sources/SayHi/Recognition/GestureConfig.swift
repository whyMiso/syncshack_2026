import Foundation

/// Every tunable threshold in one place. All distance thresholds are expressed
/// relative to hand size (wrist → middle-finger MCP distance), so recognition
/// does not depend on how far the hand is from the camera.
///
/// `shared` is read from the camera's video queue (classifier) and written
/// from the main thread (settings UI), so access is lock-protected.
struct GestureConfig: Codable, Equatable {

    private static let lock = NSLock()
    private static var _shared = GestureConfig()

    static var shared: GestureConfig {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _shared
        }
        set {
            lock.lock()
            _shared = newValue
            lock.unlock()
        }
    }

    /// Factory settings, for the "Reset to defaults" button.
    static let defaults = GestureConfig()

    // MARK: Finger extension
    // A finger's "extension score" is (dist(tip, wrist) − dist(pip, wrist)) / handScale.
    // Straight fingers put the tip well beyond the PIP joint; curled fingers
    // pull the tip back toward (or behind) it.

    /// Score above which a finger counts as extended.
    var fingerExtendedMin: Double = 0.35
    /// Score below which a finger counts as folded.
    var fingerFoldedMax: Double = 0.15

    // MARK: Thumb

    /// dist(thumbTip, indexMCP) / handScale above which the thumb counts as extended.
    var thumbExtendedMin: Double = 0.9
    /// Below this, the thumb is considered tucked against the hand.
    var thumbFoldedMax: Double = 0.6
    /// For thumbs-up: vertical rise of thumb tip over thumb MCP, / handScale.
    var thumbUpVerticalMin: Double = 0.45
    /// For thumbs-down: thumb tip must sit at least this far *below* its base
    /// joint (negative rise), / handScale.
    var thumbDownVerticalMin: Double = 0.35

    // MARK: Pinch (OK sign)

    /// dist(thumbTip, indexTip) / handScale below which the two are "touching".
    var pinchMax: Double = 0.45

    // MARK: Direction checks

    /// How far the index tip must sit from the index PIP, along whichever axis
    /// it favours, for a point to register (/ handScale).
    var pointUpVerticalMin: Double = 0.2
    /// The dominant axis must beat the other by this factor, so a 45° point is
    /// rejected rather than assigned an arbitrary direction.
    var pointAxisRatio: Double = 1.4

    // MARK: Quality gates

    /// Overall reading confidence below which a frame is treated as "unknown".
    var minimumReadingConfidence: Double = 0.35

    // MARK: Debounce / state machine

    /// How long a gesture must be held before it triggers.
    var holdDuration: TimeInterval = 0.8
    /// Brief detection dropouts shorter than this don't reset the hold.
    var dropoutGrace: TimeInterval = 0.25
    /// After a trigger, no gesture can fire again for this long.
    var cooldown: TimeInterval = 1.5
    /// After cooldown, the *same* gesture must first disappear for this long
    /// (hand relaxed or changed) before it is armed again.
    var rearmDuration: TimeInterval = 0.4

    // MARK: Camera

    /// Frames analysed per second. Hand-pose detection measures at ~3 ms per
    /// frame, so the gap between frames — not the detection itself — is what
    /// sets input latency. 24 fps keeps that gap to ~42 ms for roughly 8% of
    /// one core.
    var analysisFramesPerSecond: Double = 24

    // MARK: - Codable

    init() {}

    /// Decoded field-by-field with fallbacks so that adding a new setting in a
    /// future version doesn't discard everything the user has already tuned.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = GestureConfig()

        // `try?` flattens the optional, so this is nil for both a missing key
        // and a malformed value — either way, fall back to the default.
        func value(_ key: CodingKeys, _ fallback: Double) -> Double {
            (try? container.decodeIfPresent(Double.self, forKey: key)) ?? fallback
        }

        fingerExtendedMin = value(.fingerExtendedMin, fallback.fingerExtendedMin)
        fingerFoldedMax = value(.fingerFoldedMax, fallback.fingerFoldedMax)
        thumbExtendedMin = value(.thumbExtendedMin, fallback.thumbExtendedMin)
        thumbFoldedMax = value(.thumbFoldedMax, fallback.thumbFoldedMax)
        thumbUpVerticalMin = value(.thumbUpVerticalMin, fallback.thumbUpVerticalMin)
        thumbDownVerticalMin = value(.thumbDownVerticalMin, fallback.thumbDownVerticalMin)
        pinchMax = value(.pinchMax, fallback.pinchMax)
        pointUpVerticalMin = value(.pointUpVerticalMin, fallback.pointUpVerticalMin)
        pointAxisRatio = value(.pointAxisRatio, fallback.pointAxisRatio)
        minimumReadingConfidence = value(.minimumReadingConfidence, fallback.minimumReadingConfidence)
        holdDuration = value(.holdDuration, fallback.holdDuration)
        dropoutGrace = value(.dropoutGrace, fallback.dropoutGrace)
        cooldown = value(.cooldown, fallback.cooldown)
        rearmDuration = value(.rearmDuration, fallback.rearmDuration)
        analysisFramesPerSecond = value(.analysisFramesPerSecond, fallback.analysisFramesPerSecond)
    }
}
