import AVKit
import SwiftUI

/// Plays one of the couple's uploaded films full screen, with its caption beneath.
struct GalleryVideoPlayer: View {
    let photo: GalleryPhoto

    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(BrandPalette.goldPale)
            }
        }
        .overlay(alignment: .bottom) {
            if let caption = photo.trimmedCaption {
                Text(caption)
                    .brandFont(.bodyItalic)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40)
            }
        }
        .overlay(alignment: .topTrailing) {
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
        .statusBarHidden()
        .onAppear {
            guard let url = photo.movieURL else { return }
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
