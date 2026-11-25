import SwiftUI
import UIKit

/// The Home hero: the couple's own photographs, crossfading slowly with a barely
/// perceptible drift. No controls, no dots — it simply breathes behind the names.
///
/// Every photograph fills the hero edge to edge, centred and clipped to its bounds —
/// no letterbox, no backdrop, no empty band. The crop at the edges is intended; the
/// subjects stay centred in frame.
///
/// Photographs come from the gallery's hero sequence and are cached to disk, so after
/// the first viewing the slideshow runs with no connection. With nothing cached yet the
/// bundled dusk photograph carries the screen.
struct HeroSlideshow: View {
    let photos: [GalleryPhoto]

    /// Seconds each photograph is held before the next one begins to appear.
    private let holdDuration: Double = 6
    /// Seconds the two photographs overlap.
    private let crossfade: Double = 1.5
    /// Kept very small so faces stay comfortably inside the frame.
    private let driftScale: CGFloat = 1.03

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var images: [String: UIImage] = [:]
    @State private var activeID: String?
    @State private var scales: [String: CGFloat] = [:]
    /// Where the faces sit in each photograph (unit coordinates, top-left origin).
    @State private var focuses: [String: CGPoint] = [:]

    /// Only photographs already in hand are shown, so a slide is never blank.
    private var readyPhotos: [GalleryPhoto] {
        photos.filter { images[$0.id] != nil }
    }

    var body: some View {
        ZStack {
            Color(BrandPalette.heroFallback)

            HeroSlide(image: Image("tropical_ocean_dusk"), imageSize: nil, focus: nil, scale: 1)
                .opacity(activeID == nil ? 1 : 0)
                .animation(.easeInOut(duration: crossfade), value: activeID == nil)

            ForEach(readyPhotos) { photo in
                if let image = images[photo.id] {
                    HeroSlide(
                        image: Image(uiImage: image),
                        imageSize: image.size,
                        focus: focuses[photo.id],
                        scale: scales[photo.id] ?? 1
                    )
                        .opacity(photo.id == activeID ? 1 : 0)
                        .animation(.easeInOut(duration: crossfade), value: activeID)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: photos.map(\.id).joined()) {
            await loadAll()
        }
        .task(id: photos.map(\.id).joined()) {
            await runSlideshow()
        }
    }

    // MARK: - Loading

    private func loadAll() async {
        for photo in photos {
            guard let url = photo.url, images[photo.id] == nil else { continue }
            let image = await ImageCache.shared.image(for: url)
            guard !Task.isCancelled, let image else { continue }
            // The face check finishes before the photo is shown, so it never jumps.
            focuses[photo.id] = await FaceFocus.shared.focus(for: photo.id, image: image)
            guard !Task.isCancelled else { return }
            images[photo.id] = image
            if activeID == nil {
                scales[photo.id] = 1
                withAnimation(.easeInOut(duration: crossfade)) {
                    activeID = photo.id
                }
                beginDrift(for: photo.id)
            }
        }
    }

    // MARK: - Advancing

    private func runSlideshow() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(holdDuration))
            guard !Task.isCancelled else { return }

            let ready = readyPhotos
            guard ready.count > 1, let activeID,
                  let current = ready.firstIndex(where: { $0.id == activeID }) else { continue }

            let next = ready[(current + 1) % ready.count]

            // Reset the incoming photograph while it is still invisible, one frame
            // before its drift begins, so the zoom always starts from rest.
            scales[next.id] = 1
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: crossfade)) {
                self.activeID = next.id
            }
            beginDrift(for: next.id)
        }
    }

    private func beginDrift(for id: String) {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: holdDuration + crossfade)) {
            scales[id] = driftScale
        }
    }
}

/// One hero photograph, filling the hero edge to edge and clipped to its bounds. When
/// faces were found the crop slides toward them (never past the photo's edge), so on
/// wide screens the couple stays in frame; otherwise it stays centred.
private struct HeroSlide: View {
    let image: Image
    let imageSize: CGSize?
    let focus: CGPoint?
    let scale: CGFloat

    var body: some View {
        // A sized colour anchors the layout so the filled crop never widens the hero;
        // the photograph rides above it and is clipped to those exact bounds.
        Color.clear
            .overlay {
                GeometryReader { proxy in
                    let box = proxy.size
                    if let imageSize, imageSize.width > 0, imageSize.height > 0 {
                        let fill = max(box.width / imageSize.width, box.height / imageSize.height)
                        let drawn = CGSize(width: imageSize.width * fill, height: imageSize.height * fill)
                        let point = focus ?? CGPoint(x: 0.5, y: 0.5)
                        let spareX = max(drawn.width - box.width, 0) / 2
                        let spareY = max(drawn.height - box.height, 0) / 2
                        let dx = min(max((0.5 - point.x) * drawn.width, -spareX), spareX)
                        let dy = min(max((0.5 - point.y) * drawn.height, -spareY), spareY)
                        image
                            .resizable()
                            .frame(width: drawn.width, height: drawn.height)
                            .scaleEffect(scale, anchor: .center)
                            .position(x: box.width / 2 + dx, y: box.height / 2 + dy)
                    } else {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .scaleEffect(scale, anchor: .center)
                            .frame(width: box.width, height: box.height)
                    }
                }
                .allowsHitTesting(false)
            }
            .clipped()
    }
}
