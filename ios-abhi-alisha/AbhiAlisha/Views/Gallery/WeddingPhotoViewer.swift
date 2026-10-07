import Photos
import SwiftUI
import UIKit

/// Saves a photograph into the guest's library, asking only for permission to add.
nonisolated enum PhotoLibrarySaver {
    enum Outcome: Sendable {
        case saved
        case denied
        case failed
    }

    static func save(_ data: Data) async -> Outcome {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return .saved
        } catch {
            return .failed
        }
    }
}

/// Full screen: swipe between a celebration's photographs, pinch to zoom, read the
/// caption, save to Photos or share.
struct WeddingPhotoViewer: View {
    let photos: [WeddingPhoto]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var index: Int
    @State private var currentImage: UIImage?
    @State private var toast: String?
    @State private var isSaving = false
    @State private var isShowingSettingsHint = false

    init(photos: [WeddingPhoto], startIndex: Int) {
        self.photos = photos
        _index = State(initialValue: photos.indices.contains(startIndex) ? startIndex : 0)
    }

    private var current: WeddingPhoto? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                    ZoomablePhoto(url: photo.fullURL)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) { bottomBar }
        .overlay(alignment: .topTrailing) { closeButton }
        .overlay(alignment: .top) { topLine }
        .statusBarHidden()
        .animation(.softFade, value: toast)
        .onChange(of: index) { _, _ in BrandHaptics.tick() }
        .task(id: index) { await loadCurrent() }
        .alert("Allow adding photos", isPresented: $isShowingSettingsHint) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("To save wedding photos, allow Abhi & Alisha to add to your Photos in Settings.")
        }
    }

    private func loadCurrent() async {
        currentImage = nil
        let urls = (index - 2...index + 2)
            .filter { photos.indices.contains($0) }
            .compactMap { photos[$0].fullURL }
        ImageCache.shared.prefetch(urls)
        guard let url = current?.fullURL else { return }
        let image = await ImageCache.shared.image(for: url)
        guard !Task.isCancelled else { return }
        currentImage = image
    }

    // MARK: - Chrome

    @ViewBuilder
    private var topLine: some View {
        if let toast {
            Text(toast)
                .font(BrandLabel.font(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                .padding(.top, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if photos.count > 1 {
            Text("\(index + 1) / \(photos.count)")
                .font(BrandLabel.font(size: 10, weight: .medium))
                .tracking(1.8)
                .foregroundStyle(Color.white.opacity(0.6))
                .monospacedDigit()
                .padding(.top, 26)
                .accessibilityHidden(true)
        }
    }

    private var closeButton: some View {
        Button {
            BrandHaptics.tick()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.16)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .padding(.trailing, 18)
        .padding(.top, 14)
        .accessibilityLabel("Close")
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            if let caption = current?.caption {
                Text(caption)
                    .brandFont(.bodyItalic)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
                    .transition(.opacity)
                    .id(current?.id)
            }

            HStack(spacing: 14) {
                Button(action: save) {
                    viewerAction(title: "Save", symbol: "arrow.down.to.line", isBusy: isSaving)
                }
                .buttonStyle(PressableStyle())
                .disabled(currentImage == nil || isSaving)
                .opacity(currentImage == nil ? 0.5 : 1)
                .accessibilityLabel("Save to Photos")

                if let image = currentImage {
                    let picture = Image(uiImage: image)
                    ShareLink(
                        item: picture,
                        preview: SharePreview(current?.caption ?? "Abhi & Alisha · Wedding Week", image: picture)
                    ) {
                        viewerAction(title: "Share", symbol: "square.and.arrow.up", isBusy: false)
                    }
                    .buttonStyle(PressableStyle())
                } else {
                    viewerAction(title: "Share", symbol: "square.and.arrow.up", isBusy: false)
                        .opacity(0.5)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.bottom, 30)
        .animation(.softFade, value: index)
    }

    private func viewerAction(title: String, symbol: String, isBusy: Bool) -> some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView().controlSize(.small).tint(Color.white)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
            }
            Text(title)
                .font(BrandLabel.font(size: 11.5, weight: .semibold))
                .tracking(1.3)
                .textCase(.uppercase)
        }
        .foregroundStyle(Color.white)
        .frame(width: 132, height: 46)
        .background(Capsule().fill(Color.white.opacity(0.14)))
        .overlay(Capsule().stroke(Color(hex: 0xE0C982).opacity(0.55), lineWidth: 0.75))
    }

    private func save() {
        guard let image = currentImage, let data = image.jpegData(compressionQuality: 0.95) else { return }
        BrandHaptics.soft()
        isSaving = true
        Task {
            let outcome = await PhotoLibrarySaver.save(data)
            isSaving = false
            switch outcome {
            case .saved:
                BrandHaptics.tick()
                show("Saved to Photos")
            case .denied:
                isShowingSettingsHint = true
            case .failed:
                show("That photo couldn't be saved")
            }
        }
    }

    private func show(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if toast == text { toast = nil }
        }
    }
}
