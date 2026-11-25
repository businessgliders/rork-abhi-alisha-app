import AVFoundation
import SwiftUI
import UIKit

/// Scans the QR code on a printed or shared invite. The code holds
/// https://milniapp.com/j/CODE; a bare code is accepted too.
struct MilniQRScannerSheet: View {
    let onCode: (String) -> Void

    enum Access { case checking, allowed, denied, unavailable }

    @State private var access: Access = .checking
    @State private var hint: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch access {
            case .checking:
                ProgressView().tint(Milni.champagne)
            case .allowed:
                QRCameraView { value in
                    if let code = Self.code(from: value) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onCode(code)
                    } else {
                        hint = "That QR code isn't a Milni invitation."
                    }
                }
                .ignoresSafeArea()
                viewfinder
            case .denied:
                message(
                    title: "Camera access is off",
                    body: "Allow camera access in Settings to scan the QR code on your invite. You can also type the code instead.",
                    action: "Open Settings"
                ) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .unavailable:
                message(
                    title: "No camera found",
                    body: "This device doesn't have a camera we can use. Type the code from your invite instead.",
                    action: nil,
                    perform: nil
                )
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.white.opacity(0.14)))
                    }
                    .accessibilityLabel("Close")
                }
                .padding(20)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .task { await checkAccess() }
    }

    private var viewfinder: some View {
        VStack(spacing: 22) {
            Spacer()
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Milni.champagne, lineWidth: 1.5)
                .frame(width: 240, height: 240)
                .milniSheen(period: 2.4, intensity: 0.18)
            Text(hint ?? "Point at the QR code on your invite")
                .font(Milni.inter(15, weight: 500))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .animation(.easeInOut, value: hint)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private func message(title: String, body: String, action: String?, perform: (() -> Void)?) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "camera")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Milni.champagne)
            Text(title)
                .font(Milni.cormorant(30))
                .foregroundStyle(.white)
            Text(body)
                .font(Milni.inter(15))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            if let action, let perform {
                Button(action, action: perform)
                    .buttonStyle(MilniButtonStyle(kind: .primary, ink: Milni.champagne, paper: Milni.midnight))
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 36)
    }

    private func checkAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = QRCameraView.hasCamera ? .allowed : .unavailable
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            access = granted ? (QRCameraView.hasCamera ? .allowed : .unavailable) : .denied
        default:
            access = .denied
        }
    }

    static func code(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return WeddingContext.joinCode(from: url)
        }
        let code = WeddingContext.normalize(trimmed)
        return (6...10).contains(code.count) && code.count == trimmed.count ? code : nil
    }
}

/// The live camera with a QR metadata reader.
struct QRCameraView: UIViewRepresentable {
    let onScan: (String) -> Void

    static var deviceTypes: [AVCaptureDevice.DeviceType] {
        [.builtInWideAngleCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera, .external]
    }

    static var hasCamera: Bool { device != nil }

    static var device: AVCaptureDevice? {
        let back = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back).devices
        if let first = back.first { return first }
        return AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .unspecified).devices.first
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.configure(view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "milni.qr.session")
        private let onScan: (String) -> Void
        private var lastValue: String?
        private var lastTime = Date.distantPast

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func configure(_ view: PreviewView) {
            guard let device = QRCameraView.device,
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                if output.availableMetadataObjectTypes.contains(.qr) {
                    output.metadataObjectTypes = [.qr]
                }
            }
            session.commitConfiguration()
            view.previewLayer.session = session
            let session = self.session
            queue.async { session.startRunning() }
        }

        func stop() {
            let session = self.session
            queue.async { session.stopRunning() }
        }

        nonisolated func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }
            MainActor.assumeIsolated {
                // The same code is read many times a second; report it once.
                guard value != lastValue || Date().timeIntervalSince(lastTime) > 2.5 else { return }
                lastValue = value
                lastTime = Date()
                onScan(value)
            }
        }
    }
}
