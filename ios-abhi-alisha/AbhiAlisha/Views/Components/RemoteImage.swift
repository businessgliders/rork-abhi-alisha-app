import SwiftUI
import UIKit

/// A photograph loaded through `ImageCache`, so it appears instantly the second time
/// and keeps working with no connection.
///
/// A picture already held in memory is handed over during the very first layout pass,
/// so it is drawn straight away — no placeholder frame, no fade, nothing to notice.
///
/// `.fit` keeps the photograph's natural proportions inside the width it is given.
/// `.fill` must always be used inside an `.overlay` on a sized `Color`, never on its own.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    var transitionDuration: Double = 0.5
    @ViewBuilder var placeholder: Placeholder

    @State private var image: UIImage?

    init(
        url: URL?,
        contentMode: ContentMode = .fit,
        transitionDuration: Double = 0.5,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.transitionDuration = transitionDuration
        self.placeholder = placeholder()
        _image = State(initialValue: ImageCache.shared.cached(for: url))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .animation(.easeInOut(duration: transitionDuration), value: image == nil)
        .task(id: url) {
            guard let url else { return }

            // Already in hand — swap it in with no animation at all.
            if let ready = ImageCache.shared.cached(for: url) {
                var silent = Transaction()
                silent.disablesAnimations = true
                withTransaction(silent) { image = ready }
                return
            }

            let loaded = await ImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

extension RemoteImage where Placeholder == PhotoPlaceholder {
    init(url: URL?, contentMode: ContentMode = .fit, aspectRatio: CGFloat? = nil) {
        self.init(url: url, contentMode: contentMode) {
            PhotoPlaceholder(aspectRatio: aspectRatio)
        }
    }
}

/// A calm, matte stand-in while a photograph loads — never a spinner over content.
struct PhotoPlaceholder: View {
    var aspectRatio: CGFloat?

    var body: some View {
        BrandPalette.hairline.opacity(0.7)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                IconWatermark(key: .sparkle, size: 44, opacity: 0.35)
            }
    }
}

/// A bare matte panel, for places where a photograph is expected within a moment and a
/// mark of any kind would only read as a flicker.
struct QuietPhotoPlaceholder: View {
    var body: some View {
        BrandPalette.hairline.opacity(0.7)
    }
}
