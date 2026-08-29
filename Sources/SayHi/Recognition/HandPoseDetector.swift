import Vision
import CoreVideo
import CoreGraphics

/// A detected hand: joint locations in Vision-normalized coordinates
/// (0...1, origin at the image's lower-left) plus per-joint confidence.
struct HandPose {
    var joints: [VNHumanHandPoseObservation.JointName: CGPoint]
    var confidences: [VNHumanHandPoseObservation.JointName: Float]
    var chirality: VNChirality
    /// Pixel dimensions of the analyzed frame, for aspect-correct overlay mapping.
    var imageSize: CGSize

    subscript(_ name: VNHumanHandPoseObservation.JointName) -> CGPoint? {
        joints[name]
    }

    /// The side of the *user's body* this hand belongs to.
    ///
    /// `CameraManager` mirrors the analysis frames so they match the mirrored
    /// (selfie-style) preview, which means Vision sees a real right hand as a
    /// left one. The reported chirality is therefore flipped back here.
    var userHandSide: HandSide? {
        switch chirality {
        case .left:  return .right
        case .right: return .left
        default:     return nil
        }
    }
}

/// Smooths Vision's per-frame chirality into a stable side.
///
/// Chirality flickers on ambiguous poses — a fist seen straight on looks much
/// the same either way. Since the side is part of the binding key, a single
/// flickered frame would look like a *different* gesture and restart the hold
/// timer, so nothing would ever fire. A majority vote over a short rolling
/// window absorbs that, and ties keep the current decision (hysteresis).
struct ChiralitySmoother {
    private var samples: [HandSide] = []
    private var current: HandSide?
    private let windowSize = 9

    /// Feed one frame's raw side (nil when Vision is unsure) and get the
    /// stabilised side back.
    mutating func update(_ side: HandSide?) -> HandSide? {
        // `nil` samples simply don't vote — they don't discard the window.
        if let side { samples.append(side) }
        if samples.count > windowSize {
            samples.removeFirst(samples.count - windowSize)
        }
        let left = samples.filter { $0 == .left }.count
        let right = samples.count - left
        if left > right { current = .left } else if right > left { current = .right }
        return current
    }

    mutating func reset() {
        samples.removeAll()
        current = nil
    }
}

/// Wraps VNDetectHumanHandPoseRequest for single-hand detection.
/// Call `detect(in:)` off the main thread — Vision work is CPU-heavy.
final class HandPoseDetector {

    /// Joints with confidence below this are treated as missing.
    private let minimumJointConfidence: Float = 0.3

    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        return request
    }()

    /// Returns the most confident hand in the frame, or nil if none is found.
    func detect(in pixelBuffer: CVPixelBuffer) -> HandPose? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first,
              let recognized = try? observation.recognizedPoints(.all) else {
            return nil
        }

        var joints: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
        var confidences: [VNHumanHandPoseObservation.JointName: Float] = [:]
        for (name, point) in recognized where point.confidence >= minimumJointConfidence {
            joints[name] = point.location
            confidences[name] = point.confidence
        }
        guard !joints.isEmpty else { return nil }
        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                               height: CVPixelBufferGetHeight(pixelBuffer))
        return HandPose(joints: joints, confidences: confidences,
                        chirality: observation.chirality, imageSize: imageSize)
    }
}
