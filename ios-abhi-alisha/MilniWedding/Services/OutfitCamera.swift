import AVFoundation
import UIKit

/// A still camera for outfit photos: one capture session on its own queue, the photo
/// handed back as JPEG data. Works with the phone's own camera and with any external one.
nonisolated final class OutfitCamera: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "outfits.camera")
    private var completion: (@Sendable (Data?) -> Void)?
    private var isConfigured = false

    /// Starts the camera. Reports false when there is no camera to use.
    func start(_ done: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            if !isConfigured { configure() }
            let hasCamera = !session.inputs.isEmpty
            if hasCamera, !session.isRunning { session.startRunning() }
            done(hasCamera)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture(_ done: @escaping @Sendable (Data?) -> Void) {
        queue.async { [self] in
            guard completion == nil,
                  let connection = output.connection(with: .video),
                  connection.isEnabled, connection.isActive else {
                done(nil)
                return
            }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            completion = done
            let settings = AVCapturePhotoSettings()
            if output.supportedFlashModes.contains(.auto) {
                settings.flashMode = .auto
            }
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { [self] in
            let finish = completion
            completion = nil
            finish?(data)
        }
    }

    private func configure() {
        isConfigured = true
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }
        guard let device = Self.bestCamera(),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
    }

    /// The built-in back camera first, then anything else that can see, including an
    /// external camera.
    private static func bestCamera() -> AVCaptureDevice? {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(iOS 17.0, *) {
            types.append(.external)
        }
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        ).devices
        return devices.first { $0.position == .back } ?? devices.first
    }
}
