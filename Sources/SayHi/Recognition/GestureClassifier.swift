import Foundation
import Vision
import CoreGraphics

/// Per-finger geometry extracted from a hand pose, exposed for the debug panel.
struct FingerStates {
    /// Continuous extension score per finger (positive = extended).
    var index: Double?
    var middle: Double?
    var ring: Double?
    var little: Double?
    /// dist(thumbTip, indexMCP) / handScale — how far the thumb is from the palm.
    var thumbSpread: Double?
    /// Vertical rise of thumb tip over thumb MCP / handScale (positive = up).
    var thumbRise: Double?
    /// dist(thumbTip, indexTip) / handScale — small when pinching (OK sign).
    var pinch: Double?
}

/// Classifies a `HandPose` into a `Gesture` using landmark geometry —
/// relative joint positions normalized by hand size, not raised-finger counts.
struct GestureClassifier {

    var config: GestureConfig { GestureConfig.shared }

    struct Result {
        var reading: GestureReading
        var fingers: FingerStates
    }

    func classify(_ pose: HandPose) -> Result {
        var fingers = FingerStates()

        // Hand scale: wrist → middle MCP. Falls back to index MCP if occluded.
        guard let wrist = pose[.wrist],
              let scaleAnchor = pose[.middleMCP] ?? pose[.indexMCP] else {
            return Result(reading: .none, fingers: fingers)
        }
        let scale = wrist.distance(to: scaleAnchor)
        guard scale > 0.02 else {  // hand too small / degenerate detection
            return Result(reading: .none, fingers: fingers)
        }

        // Extension score: how far beyond the PIP joint the tip reaches, from
        // the wrist's point of view. Straight finger ≈ 0.5–0.9, curled ≈ ≤ 0.
        func extensionScore(tip: VNHumanHandPoseObservation.JointName,
                            pip: VNHumanHandPoseObservation.JointName) -> Double? {
            guard let tipPoint = pose[tip], let pipPoint = pose[pip] else { return nil }
            return (wrist.distance(to: tipPoint) - wrist.distance(to: pipPoint)) / scale
        }

        fingers.index  = extensionScore(tip: .indexTip,  pip: .indexPIP)
        fingers.middle = extensionScore(tip: .middleTip, pip: .middlePIP)
        fingers.ring   = extensionScore(tip: .ringTip,   pip: .ringPIP)
        fingers.little = extensionScore(tip: .littleTip, pip: .littlePIP)

        if let thumbTip = pose[.thumbTip], let indexMCP = pose[.indexMCP] {
            fingers.thumbSpread = thumbTip.distance(to: indexMCP) / scale
        }
        if let thumbTip = pose[.thumbTip], let thumbMP = pose[.thumbMP] {
            // Vision coordinates have y increasing upward, so this is "how far
            // the thumb tip rises above its base joint" in the real world.
            fingers.thumbRise = (thumbTip.y - thumbMP.y) / scale
        }
        if let thumbTip = pose[.thumbTip], let indexTip = pose[.indexTip] {
            fingers.pinch = thumbTip.distance(to: indexTip) / scale
        }

        let reading = classify(fingers: fingers, pose: pose, scale: scale)
        return Result(reading: reading, fingers: fingers)
    }

    // MARK: - Rules

    private func classify(fingers f: FingerStates, pose: HandPose, scale: Double) -> GestureReading {
        let cfg = config

        // Need at least the four finger scores to say anything meaningful.
        guard let index = f.index, let middle = f.middle,
              let ring = f.ring, let little = f.little else {
            return .none
        }

        func extended(_ s: Double) -> Bool { s >= cfg.fingerExtendedMin }
        func folded(_ s: Double) -> Bool { s <= cfg.fingerFoldedMax }

        // Margin of a score past its threshold, mapped to 0...1.
        // Used to build a confidence value that reflects how decisively the
        // hand matches the rule, not just that it barely crossed a threshold.
        func marginConfidence(_ margins: [Double]) -> Double {
            guard !margins.isEmpty else { return 0 }
            let avg = margins.reduce(0, +) / Double(margins.count)
            return min(1.0, max(0.0, avg / 0.25))
        }

        let allFourFolded = folded(index) && folded(middle) && folded(ring) && folded(little)
        let allFourExtended = extended(index) && extended(middle) && extended(ring) && extended(little)

        // OK sign: thumb and index tips meet in a ring while the other three
        // stay extended. Checked first because the pinch is highly specific —
        // no other gesture brings those two tips together.
        if let pinch = f.pinch, pinch <= cfg.pinchMax,
           extended(middle), extended(ring), extended(little) {
            let conf = marginConfidence([
                (cfg.pinchMax - pinch) * 2,  // pinch range is tighter than the
                                             // finger scores, so weight it up
                middle - cfg.fingerExtendedMin, ring - cfg.fingerExtendedMin,
                little - cfg.fingerExtendedMin,
            ])
            return gated(.ok, conf)
        }

        // Thumbs up: four fingers curled, thumb clearly away from the palm and
        // rising upward. Checked before fist because a fist is its fallback.
        if allFourFolded,
           let spread = f.thumbSpread, spread >= cfg.thumbExtendedMin,
           let rise = f.thumbRise, rise >= cfg.thumbUpVerticalMin {
            let conf = marginConfidence([
                cfg.fingerFoldedMax - index, cfg.fingerFoldedMax - middle,
                cfg.fingerFoldedMax - ring, cfg.fingerFoldedMax - little,
                spread - cfg.thumbExtendedMin, rise - cfg.thumbUpVerticalMin,
            ])
            return gated(.thumbsUp, conf)
        }

        // Thumbs down: the mirror of thumbs up — thumb extended but hanging
        // below its base joint.
        if allFourFolded,
           let spread = f.thumbSpread, spread >= cfg.thumbExtendedMin,
           let rise = f.thumbRise, -rise >= cfg.thumbDownVerticalMin {
            let conf = marginConfidence([
                cfg.fingerFoldedMax - index, cfg.fingerFoldedMax - middle,
                cfg.fingerFoldedMax - ring, cfg.fingerFoldedMax - little,
                spread - cfg.thumbExtendedMin, -rise - cfg.thumbDownVerticalMin,
            ])
            return gated(.thumbsDown, conf)
        }

        // Fist: everything curled toward the palm, thumb tucked in.
        if allFourFolded, (f.thumbSpread ?? 0) <= cfg.thumbFoldedMax {
            let conf = marginConfidence([
                cfg.fingerFoldedMax - index, cfg.fingerFoldedMax - middle,
                cfg.fingerFoldedMax - ring, cfg.fingerFoldedMax - little,
                cfg.thumbFoldedMax - (f.thumbSpread ?? 0),
            ])
            return gated(.fist, conf)
        }

        // Open palm: all four fingers straight. Thumb is deliberately ignored —
        // people vary a lot in how far they splay it.
        if allFourExtended {
            let conf = marginConfidence([
                index - cfg.fingerExtendedMin, middle - cfg.fingerExtendedMin,
                ring - cfg.fingerExtendedMin, little - cfg.fingerExtendedMin,
            ])
            return gated(.openPalm, conf)
        }

        // Three: index, middle and ring straight with the little finger curled.
        // This is the index-middle-ring "three"; the thumb-index-middle version
        // reads as a peace sign here, since peace ignores the thumb.
        if extended(index), extended(middle), extended(ring), folded(little) {
            let conf = marginConfidence([
                index - cfg.fingerExtendedMin, middle - cfg.fingerExtendedMin,
                ring - cfg.fingerExtendedMin, cfg.fingerFoldedMax - little,
            ])
            return gated(.three, conf)
        }

        // Peace: index + middle straight, ring + little curled.
        if extended(index), extended(middle), folded(ring), folded(little) {
            let conf = marginConfidence([
                index - cfg.fingerExtendedMin, middle - cfg.fingerExtendedMin,
                cfg.fingerFoldedMax - ring, cfg.fingerFoldedMax - little,
            ])
            return gated(.peace, conf)
        }

        // Rock / horns: index + little straight with the two middle fingers
        // curled down.
        if extended(index), folded(middle), folded(ring), extended(little) {
            let conf = marginConfidence([
                index - cfg.fingerExtendedMin, little - cfg.fingerExtendedMin,
                cfg.fingerFoldedMax - middle, cfg.fingerFoldedMax - ring,
            ])
            return gated(.rock, conf)
        }

        // Call me / shaka: thumb and little extended, the middle three curled.
        if folded(index), folded(middle), folded(ring), extended(little),
           let spread = f.thumbSpread, spread >= cfg.thumbExtendedMin {
            let conf = marginConfidence([
                little - cfg.fingerExtendedMin, spread - cfg.thumbExtendedMin,
                cfg.fingerFoldedMax - index, cfg.fingerFoldedMax - middle,
                cfg.fingerFoldedMax - ring,
            ])
            return gated(.callMe, conf)
        }

        // Pointing: only the index straight. Direction comes from the dominant
        // axis of the tip relative to its PIP joint, and a diagonal favouring
        // neither axis is rejected rather than assigned a direction at random.
        if extended(index), folded(middle), folded(ring), folded(little),
           let tip = pose[.indexTip], let pip = pose[.indexPIP] {
            let dx = (tip.x - pip.x) / scale
            let dy = (tip.y - pip.y) / scale
            let shape = [index - cfg.fingerExtendedMin,
                         cfg.fingerFoldedMax - middle,
                         cfg.fingerFoldedMax - ring,
                         cfg.fingerFoldedMax - little]

            if abs(dy) >= cfg.pointAxisRatio * abs(dx), abs(dy) >= cfg.pointUpVerticalMin {
                let conf = marginConfidence(shape + [abs(dy) - cfg.pointUpVerticalMin])
                return gated(dy > 0 ? .pointUp : .pointDown, conf)
            }
            // Frames are mirrored to match the preview, so +x is the user's right.
            if abs(dx) >= cfg.pointAxisRatio * abs(dy), abs(dx) >= cfg.pointUpVerticalMin {
                let conf = marginConfidence(shape + [abs(dx) - cfg.pointUpVerticalMin])
                return gated(dx > 0 ? .pointRight : .pointLeft, conf)
            }
        }

        return .none
    }

    /// Discards low-confidence matches so borderline hands read as unknown.
    private func gated(_ gesture: Gesture, _ confidence: Double) -> GestureReading {
        guard confidence >= config.minimumReadingConfidence else { return .none }
        return GestureReading(gesture: gesture, confidence: confidence)
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        let dx = x - other.x, dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
