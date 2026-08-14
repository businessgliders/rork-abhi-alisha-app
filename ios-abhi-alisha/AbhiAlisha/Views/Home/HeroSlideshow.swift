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

    /// Only photographs already in hand are shown, so a slide is never blank.
    private var readyPhotos: [GalleryPhoto] {
        photos.filter { images[$0.id] != nil }
    }

    var body: some View {
        ZStack {
            Color(BrandPalette.heroFallback)

            HeroSlide(image: Image("tropical_ocean_dusk"), scale: 1)
                .opacity(activeID == nil ? 1 : 0)
                .animation(.easeInOut(duration: crossfade), value: activeID == nil)

            ForEach(readyPhotos) { photo in
                if let image = images[photo.id] {
                    HeroSlide(image: Image(uiImage: image), scale: scales[photo.id] ?? 1)
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

/// One hero photograph, filling the hero edge to edge from its centre and clipped to
/// the hero's bounds.
private struct HeroSlide: View {
    let image: Image
    let scale: CGFloat

    var body: some View {
        // A sized colour anchors the layout so the filled crop never widens the hero;
        // the photograph rides above it and is clipped to those exact bounds.
        Color.clear
            .overlay {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(scale, anchor: .center)
                    .allowsHitTesting(false)
            }
            .clipped()
    }
}
