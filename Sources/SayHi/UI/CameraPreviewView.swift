import AppKit
import AVFoundation
import SwiftUI
import Vision

/// Live camera preview with the detected hand skeleton drawn on top.
///
/// Implemented as an NSView so landmark points can be converted with
/// `AVCaptureVideoPreviewLayer.layerPointConverted(fromCaptureDevicePoint:)`,
/// which handles aspect-ratio letterboxing exactly.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    var hand: HandPose?
    var showLandmarks: Bool

    func makeNSView(context: Context) -> PreviewNSView {
        PreviewNSView(session: session)
    }

    func updateNSView(_ view: PreviewNSView, context: Context) {
        view.render(hand: showLandmarks ? hand : nil)
    }
}

final class PreviewNSView: NSView {

    private let previewLayer: AVCaptureVideoPreviewLayer
    private let skeletonLayer = CAShapeLayer()
    private let jointLayer = CAShapeLayer()

    /// Finger chains used to draw the skeleton (wrist out to each tip).
    private static let chains: [[VNHumanHandPoseObservation.JointName]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
    ]

    private var mirroringApplied = false

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true

        previewLayer.videoGravity = .resizeAspect
        ensureMirroring()
        layer?.addSublayer(previewLayer)

        // White rather than green/yellow: the rest of the UI is white at a
        // few opacities and one blue, and a green skeleton is a third hue
        // doing no work that weight and size don't already do.
        skeletonLayer.strokeColor = NSColor.white.withAlphaComponent(0.65).cgColor
        skeletonLayer.fillColor = nil
        skeletonLayer.lineWidth = 1.5
        skeletonLayer.lineCap = .round
        jointLayer.fillColor = NSColor.white.withAlphaComponent(0.95).cgColor
        jointLayer.strokeColor = nil
        layer?.addSublayer(skeletonLayer)
        layer?.addSublayer(jointLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        skeletonLayer.frame = bounds
        jointLayer.frame = bounds
        CATransaction.commit()
    }

    /// The preview layer's connection doesn't exist until the session is
    /// configured, which happens asynchronously after this view may already be
    /// on screen — so mirroring is retried until it can be applied. Without it
    /// the preview and the analyzed frames disagree and the overlay flips.
    private func ensureMirroring() {
        guard !mirroringApplied,
              let connection = previewLayer.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
        mirroringApplied = true
    }

    /// Aspect-fit rectangle the video occupies inside this view (matching
    /// `.resizeAspect` letterboxing), in view/layer coordinates.
    private func videoRect(for imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2,
                      y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    func render(hand: HandPose?) {
        ensureMirroring()
        guard let hand else {
            skeletonLayer.path = nil
            jointLayer.path = nil
            return
        }

        // The analyzed frames are mirrored to match the mirrored preview, and
        // Vision's normalized coordinates (origin lower-left, y up) match
        // macOS layer coordinates in a non-flipped view — so mapping is a
        // direct scale into the aspect-fit video rect, no flips needed.
        let rect = videoRect(for: hand.imageSize)
        func layerPoint(_ joint: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let p = hand[joint] else { return nil }
            return CGPoint(x: rect.minX + p.x * rect.width,
                           y: rect.minY + p.y * rect.height)
        }

        let bones = CGMutablePath()
        let joints = CGMutablePath()
        for chain in Self.chains {
            var previous: CGPoint?
            for name in chain {
                guard let point = layerPoint(name) else { previous = nil; continue }
                if let previous {
                    bones.move(to: previous)
                    bones.addLine(to: point)
                }
                joints.addEllipse(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
                previous = point
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        skeletonLayer.path = bones
        jointLayer.path = joints
        CATransaction.commit()
    }
}
