import SwiftUI
import UIKit

/// Full-screen look at the couple's photographs: swipe left and right between them the
/// way Photos does it, pinch to zoom, and read the caption only when there is one.
///
/// It opens on the picture that was tapped — never on the first one — and the pictures
/// on either side are warmed as you go, so paging is seamless.
struct GalleryViewer: View {
    let items: [GalleryPhoto]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss

    @State private var index: Int

    init(items: [GalleryPhoto], startIndex: Int) {
        self.items = items
        self.startIndex = startIndex
        _index = State(initialValue: items.indices.contains(startIndex) ? startIndex : 0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                    ZoomablePhoto(url: item.posterURL)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) { caption }
        .overlay(alignment: .topTrailing) { closeButton }
        .overlay(alignment: .top) { counter }
        .statusBarHidden()
        .onChange(of: index) { _, _ in
            BrandHaptics.tick()
            warmNeighbours()
        }
        .onAppear(perform: warmNeighbours)
    }

    /// Keeps the two pictures on either side ready, so a swipe never waits on the network.
    private func warmNeighbours() {
        let urls = (index - 2...index + 2)
            .filter { items.indices.contains($0) }
            .compactMap { items[$0].posterURL }
        ImageCache.shared.prefetch(urls)
    }

    @ViewBuilder
    private var caption: some View {
        if items.indices.contains(index), let text = items[index].trimmedCaption {
            Text(text)
                .brandFont(.bodyItalic)
                .foregroundStyle(Color.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
                .padding(.bottom, 44)
                .transition(.opacity)
                .animation(.softFade, value: index)
        }
    }

    @ViewBuilder
    private var counter: some View {
        if items.count > 1 {
            Text("\(index + 1) / \(items.count)")
                .font(BrandLabel.font(size: 10, weight: .medium))
                .tracking(1.8)
                .foregroundStyle(Color.white.opacity(0.6))
                .monospacedDigit()
                .padding(.top, 22)
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
}
