import AVFoundation
import CoreVideo

/// Owns the AVCaptureSession and delivers throttled pixel buffers to a handler.
///
/// The camera can deliver 30–60 fps but hand-pose detection only needs ~12 fps
/// to feel responsive, so frames are dropped before any Vision work happens.
/// All session mutation happens on `sessionQueue`; frames arrive on `videoQueue`.
final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    /// Called on `videoQueue` with each frame that survives throttling.
    var frameHandler: ((CVPixelBuffer) -> Void)?

    /// Analysis rate. The preview layer still renders at full camera rate.
    var targetFramesPerSecond: Double = 12

    private let sessionQueue = DispatchQueue(label: "com.sayhi.camera.session")
    private let videoQueue = DispatchQueue(label: "com.sayhi.camera.frames", qos: .userInitiated)
    private var isConfigured = false
    private var lastProcessedAt: CFAbsoluteTime = 0

    // MARK: Authorization

    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    // MARK: Lifecycle

    func start() {
        sessionQueue.async { [self] in
            configureIfNeeded()
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 640x480 is plenty for hand-pose landmarks and keeps CPU cost low.
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        // Mirror the analysis frames so they match the mirrored preview the
        // user sees — landmark overlays then line up without extra math.
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        isConfigured = true
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastProcessedAt >= 1.0 / targetFramesPerSecond else { return }
        lastProcessedAt = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameHandler?(pixelBuffer)
    }
}
