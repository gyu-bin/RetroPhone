import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// Owns the AVCaptureSession. Every session/device mutation happens on `queue` (never the main
/// thread). Callers hand in `@Sendable` completions and hop back to the main actor themselves.
nonisolated final class CaptureEngine: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "RetroPhone.camera.session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var inFlight: [Int64: PhotoCaptureDelegate] = [:]
    /// Live "old phone" preview: frames from this output are filtered and drawn over the plain preview.
    let livePreview = LiveFilterPreview()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "RetroPhone.camera.frames", qos: .userInitiated)
    private let movieOutput = AVCaptureMovieFileOutput()
    private var audioInput: AVCaptureDeviceInput?
    private var movieDelegate: MovieRecordingDelegate?

    /// Attaches the camera with `deviceID` (replacing any current camera). Calls back on the
    /// session queue with success.
    func configure(deviceID: String, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            completion(self.reconfigure(deviceID: deviceID))
        }
    }

    private func reconfigure(deviceID: String) -> Bool {
        guard let device = AVCaptureDevice(uniqueID: deviceID),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        let old = input
        if let old { session.removeInput(old) }
        guard session.canAddInput(newInput) else {
            if let old, session.canAddInput(old) { session.addInput(old) }
            return false
        }
        session.addInput(newInput)
        input = newInput
        if !session.outputs.contains(photoOutput) {
            guard session.canAddOutput(photoOutput) else { return false }
            session.addOutput(photoOutput)
        }
        // Optional: without it the plain (unfiltered) preview is shown.
        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(livePreview, queue: videoQueue)
            session.addOutput(videoOutput)
        }
        return true
    }

    /// Switches the session between photo and video capture. Video adds the movie output and, when
    /// the microphone is allowed, the audio input. Calls back on the session queue with success.
    func setVideoMode(_ video: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            self.session.beginConfiguration()
            if video {
                if self.session.canSetSessionPreset(.high) { self.session.sessionPreset = .high }
                if self.audioInput == nil, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                   let mic = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: mic),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.audioInput = input
                }
                if !self.session.outputs.contains(self.movieOutput), self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                }
            } else {
                if self.session.outputs.contains(self.movieOutput) { self.session.removeOutput(self.movieOutput) }
                if let audio = self.audioInput { self.session.removeInput(audio); self.audioInput = nil }
                if self.session.canSetSessionPreset(.photo) { self.session.sessionPreset = .photo }
            }
            self.session.commitConfiguration()
            completion(!video || self.session.outputs.contains(self.movieOutput))
        }
    }

    /// Starts recording a movie; `completion` gets the finished file (or nil on failure).
    func startRecording(rotationAngle: CGFloat, completion: @escaping @Sendable (URL?) -> Void) {
        queue.async {
            guard self.session.isRunning, !self.movieOutput.isRecording,
                  let connection = self.movieOutput.connection(with: .video) else {
                completion(nil)
                return
            }
            if connection.isVideoRotationAngleSupported(rotationAngle) { connection.videoRotationAngle = rotationAngle }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            let delegate = MovieRecordingDelegate { url in
                completion(url)
                self.queue.async { self.movieDelegate = nil }
            }
            self.movieDelegate = delegate
            self.movieOutput.startRecording(to: url, recordingDelegate: delegate)
        }
    }

    func stopRecording() {
        queue.async { if self.movieOutput.isRecording { self.movieOutput.stopRecording() } }
    }

    /// Matches the filtered frames to the on-screen preview (rotation, front-camera mirroring).
    func setPreviewGeometry(rotationAngle: CGFloat, mirrored: Bool) {
        queue.async {
            guard let connection = self.videoOutput.connection(with: .video) else { return }
            if connection.isVideoRotationAngleSupported(rotationAngle) { connection.videoRotationAngle = rotationAngle }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }
    }

    func start() {
        queue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Tap-to-focus/expose. `point` is in capture-device coordinates (0…1).
    func focus(at point: CGPoint) {
        queue.async {
            guard let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {
                // Device busy; ignore the tap.
            }
        }
    }

    /// Captures one photo. `completion` receives the encoded file data (HEIC or JPEG) or nil.
    func capture(flash: AVCaptureDevice.FlashMode,
                 rotationAngle: CGFloat,
                 preferHEVC: Bool,
                 willCapture: @escaping @Sendable () -> Void,
                 completion: @escaping @Sendable (Data?) -> Void) {
        queue.async {
            guard self.session.isRunning, let connection = self.photoOutput.connection(with: .video) else {
                completion(nil)
                return
            }
            if connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
            let codecs = self.photoOutput.availablePhotoCodecTypes
            let settings: AVCapturePhotoSettings
            if preferHEVC, codecs.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else if codecs.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.flashMode = self.photoOutput.supportedFlashModes.contains(flash) ? flash : .off

            let id = settings.uniqueID
            let delegate = PhotoCaptureDelegate(willCapture: willCapture) { data in
                completion(data)
                self.queue.async { self.inFlight[id] = nil }
            }
            self.inFlight[id] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

/// AVCapturePhotoCaptureDelegate callbacks arrive on an AVFoundation queue, so this class is
/// nonisolated and only forwards Sendable values.
nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let willCapture: @Sendable () -> Void
    private let completion: @Sendable (Data?) -> Void
    private var data: Data?

    init(willCapture: @escaping @Sendable () -> Void, completion: @escaping @Sendable (Data?) -> Void) {
        self.willCapture = willCapture
        self.completion = completion
        super.init()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapture()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if error == nil { data = photo.fileDataRepresentation() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        completion(data)
    }
}

/// Movie recording callbacks arrive on an AVFoundation queue; only the file URL is passed on.
nonisolated final class MovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let completion: @Sendable (URL?) -> Void
    init(completion: @escaping @Sendable (URL?) -> Void) { self.completion = completion }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        // A recording that stopped for a limit (disk, duration) still produced a usable file.
        let finished = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        completion(finished && FileManager.default.fileExists(atPath: outputFileURL.path) ? outputFileURL : nil)
    }
}

// MARK: - Live filtered preview

/// Receives camera frames, applies the selected retro look (a light preview variant) and hands
/// the rendered image to `onFrame`. Runs on the video-frame queue; `preset` and `onFrame` are
/// guarded by a lock because they're set from the main thread.
nonisolated final class LiveFilterPreview: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _preset: RetroFilterPreset?
    private var _onFrame: (@Sendable (CGImage) -> Void)?
    private let context = CIContext(options: [.cacheIntermediates: false])
    /// Longest edge of the rendered preview frame, in pixels.
    private let maxEdge: CGFloat = 1080

    var preset: RetroFilterPreset? {
        get { lock.withLock { _preset } }
        set { lock.withLock { _preset = newValue } }
    }

    var onFrame: (@Sendable (CGImage) -> Void)? {
        get { lock.withLock { _onFrame } }
        set { lock.withLock { _onFrame = newValue } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let preset, let onFrame, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if let image = render(CIImage(cvPixelBuffer: pixels), preset: preset) { onFrame(image) }
    }

    /// Downscales and applies the preview variant of `preset`. Also used for the still demo image.
    func render(_ input: CIImage, preset: RetroFilterPreset) -> CGImage? {
        let extent = input.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = min(1, maxEdge / max(extent.width, extent.height))
        var image = input.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        if scale < 1 { image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
        let output = preset.apply(to: image, preview: true, pixelScale: scale)
        return context.createCGImage(output, from: output.extent)
    }
}

// MARK: - Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var live: LiveFilterPreview
    /// When false the filtered layer is hidden and the plain camera preview shows through.
    var filtered: Bool
    /// DEBUG simulator demo: a still image shown instead of the (missing) camera feed.
    var demoImage: CGImage? = nil
    var onLayer: (AVCaptureVideoPreviewLayer) -> Void

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        onLayer(view.previewLayer)
        let layer = view.filteredLayer
        live.onFrame = { [weak layer] image in
            DispatchQueue.main.async { layer?.contents = image }
        }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.demoLayer.contents = demoImage
        uiView.demoLayer.isHidden = demoImage == nil
        uiView.filteredLayer.isHidden = !filtered
        if !filtered { uiView.filteredLayer.contents = nil }
    }

    static func dismantleUIView(_ uiView: CameraPreviewUIView, coordinator: ()) {
        uiView.filteredLayer.contents = nil
    }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    // swiftlint:disable:next force_cast
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    let demoLayer = CALayer()
    let filteredLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        for sub in [demoLayer, filteredLayer] {
            sub.contentsGravity = .resizeAspectFill
            sub.masksToBounds = true
            sub.actions = ["contents": NSNull(), "hidden": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer.addSublayer(sub)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        demoLayer.frame = bounds
        filteredLayer.frame = bounds
    }
}
