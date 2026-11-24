import AVFoundation
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
        return true
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

// MARK: - Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onLayer: (AVCaptureVideoPreviewLayer) -> Void

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        onLayer(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    // swiftlint:disable:next force_cast
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
