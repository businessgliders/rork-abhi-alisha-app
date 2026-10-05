import AVFoundation
import SwiftUI
import UIKit

/// Full-screen camera for one outfit photo: frame it, take it, then keep it or retake.
struct OutfitCameraView: View {
    let onCapture: (UIImage) -> Void

    private enum Stage: Equatable {
        case checking
        case denied
        case unavailable
        case live
        case review
    }

    @State private var camera = OutfitCamera()
    @State private var stage: Stage = .checking
    @State private var captured: UIImage?
    @State private var isCapturing = false
    @State private var flash = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch stage {
            case .checking:
                Color.black
            case .denied:
                message(
                    title: "Camera access is off",
                    detail: "Allow the camera in Settings to photograph your outfit, or choose a photo from your library instead.",
                    showsSettings: true
                )
            case .unavailable:
                message(
                    title: "No camera found",
                    detail: "Choose a photo from your library instead.",
                    showsSettings: false
                )
            case .live:
                OutfitCameraPreview(session: camera.session)
                    .ignoresSafeArea()
                    .overlay(Color.white.opacity(flash ? 0.7 : 0).ignoresSafeArea().allowsHitTesting(false))
                    .overlay(alignment: .bottom) { shutter }
            case .review:
                if let captured {
                    Image(uiImage: captured)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottom) { reviewBar }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(PressableStyle())
            .padding(.leading, 18)
            .padding(.top, 12)
            .accessibilityLabel("Close camera")
        }
        .animation(.softFade, value: stage)
        .task { await begin() }
        .onDisappear { camera.stop() }
    }

    private var shutter: some View {
        Button {
            takePhoto()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color(hex: 0xE0C982), lineWidth: 2)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(Color(hex: 0xFFFBF1))
                    .frame(width: 64, height: 64)
                    .scaleEffect(isCapturing ? 0.86 : 1)
            }
            .animation(.easeOut(duration: 0.18), value: isCapturing)
        }
        .buttonStyle(.plain)
        .disabled(isCapturing)
        .padding(.bottom, 40)
        .accessibilityLabel("Take photo")
    }

    private var reviewBar: some View {
        HStack(spacing: 14) {
            Button {
                BrandHaptics.tick()
                captured = nil
                stage = .live
            } label: {
                Text("Retake")
                    .font(BrandLabel.font(size: 12.5, weight: .semibold))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(PressableStyle())

            GoldActionButton(title: "Use photo", systemImage: "checkmark") {
                guard let captured else { return }
                onCapture(captured)
                dismiss()
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
    }

    private func message(title: String, detail: String, showsSettings: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "camera")
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(Color(hex: 0xE0C982))
            Text(title)
                .brandFont(.eventTitleSmall)
                .foregroundStyle(Color(hex: 0xFDFAF3))
            Text(detail)
                .brandFont(.bodyItalic)
                .foregroundStyle(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if showsSettings {
                GoldActionButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 36)
    }

    private func begin() async {
        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            status = granted ? .authorized : .denied
        }
        guard status == .authorized else {
            stage = .denied
            return
        }
        let camera = camera
        let hasCamera = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            camera.start { continuation.resume(returning: $0) }
        }
        stage = hasCamera ? .live : .unavailable
    }

    private func takePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        BrandHaptics.soft()
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        let camera = camera
        Task {
            let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                camera.capture { continuation.resume(returning: $0) }
            }
            withAnimation(.easeOut(duration: 0.3)) { flash = false }
            isCapturing = false
            guard let data, let image = UIImage(data: data) else { return }
            captured = image
            stage = .review
        }
    }
}

/// The live camera picture; the preview layer is the view's own layer so it always fits.
private struct OutfitCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // The layer class is fixed above, so this cast always holds.
            layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
        }
    }
}
