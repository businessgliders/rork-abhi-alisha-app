import SwiftUI

/// One photograph at full definition, filling the screen it is given.
///
/// Pinch or double tap to zoom; panning is only claimed once it is actually zoomed in,
/// so an un-zoomed swipe carries through to the next photograph in the pager. Swiping a
/// page away leaves it as it was found, so coming back to it starts fresh.
struct ZoomablePhoto: View {
    let url: URL?
    var maximumScale: CGFloat = 5

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var isZoomed: Bool { scale > 1.02 }

    var body: some View {
        GeometryReader { proxy in
            RemoteImage(url: url, contentMode: .fit, transitionDuration: 0.3) {
                ProgressView().tint(BrandPalette.goldPale)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value.magnification, 1), maximumScale)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if !isZoomed { recentre() }
                    }
            )
            .simultaneousGesture(isZoomed ? panGesture : nil)
            .onTapGesture(count: 2) {
                withAnimation(.calm) {
                    if isZoomed {
                        scale = 1
                        lastScale = 1
                        recentre()
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                    }
                }
            }
        }
        .onDisappear(perform: restore)
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func recentre() {
        withAnimation(.calm) { offset = .zero }
        lastOffset = .zero
    }

    private func restore() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
