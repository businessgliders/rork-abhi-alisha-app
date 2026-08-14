import SwiftUI

/// "Gallery" — the couple's photographs and films, filtered by their own categories and
/// laid out as a two-column masonry in each picture's natural proportions.
///
/// Photographs are cached to disk, so the grid opens instantly and works offline.
/// Anything that fails to load is quietly left out rather than shown as a broken frame.
struct GalleryView: View {
    @Environment(ContentStore.self) private var content
    @Environment(\.openURL) private var openURL

    @State private var selectedSlug: String?
    @State private var aspects: [String: CGFloat] = [:]
    @State private var failed: Set<String> = []
    @State private var viewer: GalleryViewerContext?
    @State private var playing: GalleryPhoto?

    /// Everything in the chosen category that is still worth showing.
    private var items: [GalleryPhoto] {
        content.galleryPhotos(in: selectedSlug).filter { !failed.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                categoryRow
                    .padding(.top, 20)

                if items.isEmpty {
                    emptyState
                } else {
                    masonry
                        .padding(.horizontal, 22)
                        .padding(.top, 22)
                }
            }
            .padding(.top, ScreenChrome.contentReserve)
            .padding(.bottom, FloatingTabBar.contentReserve + 24)
            .crestCorner()
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .animation(.softFade, value: selectedSlug)
        .fullScreenCover(item: $viewer) { context in
            GalleryViewer(items: context.items, startIndex: context.index)
        }
        .fullScreenCover(item: $playing) { photo in
            GalleryVideoPlayer(photo: photo)
        }
        .task(id: content.galleryPhotos.count) {
            await measure()
        }
        .task {
            await content.refreshIfNeeded()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Memories")

            Text("Gallery")
                .brandFont(.screenTitle)
                .foregroundStyle(BrandPalette.ink)

            GoldRule(width: 58, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }

    /// "All" plus each of the couple's own categories, underlined in gold when active.
    private var categoryRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 22) {
                categoryButton(title: "All", slug: nil)

                ForEach(content.populatedGalleryCategories) { category in
                    categoryButton(title: category.name ?? "", slug: category.slug)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 22, for: .scrollContent)
    }

    private func categoryButton(title: String, slug: String?) -> some View {
        let isSelected = slug == selectedSlug

        return Button {
            guard !isSelected else { return }
            BrandHaptics.tick()
            withAnimation(.calm) { selectedSlug = slug }
        } label: {
            VStack(spacing: 7) {
                Text(title.uppercased())
                    .font(BrandLabel.font(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .tracking(1.9)
                    .foregroundStyle(isSelected ? BrandPalette.goldDeep : BrandPalette.tabInactive)
                    .lineLimit(1)

                Rectangle()
                    .fill(isSelected ? BrandPalette.gold : Color.clear)
                    .frame(height: 1)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            IconWatermark(key: .sparkle, size: 80, opacity: 0.3)

            Text("Photographs from the celebrations will be gathered here.")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Masonry

    private var masonry: some View {
        let columns = balancedColumns(items)

        return HStack(alignment: .top, spacing: 9) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: 9) {
                    ForEach(column) { item in
                        GalleryTile(
                            photo: item,
                            aspect: aspects[item.id] ?? 0.8,
                            onTap: { open(item) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    /// Splits the run into two columns of roughly equal height, keeping the couple's order.
    private func balancedColumns(_ items: [GalleryPhoto]) -> [[GalleryPhoto]] {
        var columns: [[GalleryPhoto]] = [[], []]
        var heights: [CGFloat] = [0, 0]

        for item in items {
            let aspect = aspects[item.id] ?? 0.8
            let height = 1 / max(aspect, 0.35)
            let target = heights[0] <= heights[1] ? 0 : 1
            columns[target].append(item)
            heights[target] += height
        }
        return columns
    }

    // MARK: - Behaviour

    private func open(_ item: GalleryPhoto) {
        BrandHaptics.soft()
        switch item.kind {
        case .image:
            let stills = items.filter { $0.kind == .image }
            guard let index = stills.firstIndex(of: item) else { return }
            viewer = GalleryViewerContext(items: stills, index: index)
        case .video:
            guard item.movieURL != nil else { return }
            playing = item
        case .youtube:
            guard let url = item.youtubeWatchURL else { return }
            openURL(url)
        }
    }

    /// Loads every poster once to learn its proportions, and remembers the ones that
    /// never arrive so their tile is dropped from the grid.
    private func measure() async {
        for item in content.galleryPhotos {
            guard aspects[item.id] == nil, !failed.contains(item.id) else { continue }
            guard let url = item.posterURL else {
                if !item.isPlayable { failed.insert(item.id) }
                continue
            }
            let image = await ImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            if let image, image.size.height > 0 {
                withAnimation(.softFade) {
                    aspects[item.id] = image.size.width / image.size.height
                }
            } else if !item.isPlayable {
                failed.insert(item.id)
            } else {
                aspects[item.id] = 16.0 / 9.0
            }
        }
    }
}

/// The photographs to page through, and where to start.
struct GalleryViewerContext: Identifiable {
    let items: [GalleryPhoto]
    let index: Int

    var id: String { (items.indices.contains(index) ? items[index].id : "viewer") }
}

// MARK: - Tile

/// One frame in the grid: the picture in its own proportions, with a gold play glyph
/// over anything that moves.
private struct GalleryTile: View {
    let photo: GalleryPhoto
    let aspect: CGFloat
    let onTap: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        Button(action: onTap) {
            BrandPalette.hairline.opacity(0.7)
                .aspectRatio(aspect, contentMode: .fit)
                .overlay {
                    RemoteImage(url: photo.posterURL, contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .clipShape(shape)
                .overlay(shape.stroke(BrandPalette.hairline, lineWidth: 0.75))
                .overlay {
                    if photo.kind != .image {
                        PlayGlyph()
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let caption = photo.trimmedCaption { return caption }
        return photo.kind == .image ? "Photograph" : "Film"
    }
}

/// A hairline gold play mark, small enough to leave the picture alone.
private struct PlayGlyph: View {
    var body: some View {
        Image(systemName: "play")
            .symbolVariant(.none)
            .font(.system(size: 15, weight: .light))
            .foregroundStyle(Color(hex: 0xFDFAF3))
            .frame(width: 46, height: 46)
            .background(Circle().fill(Color.black.opacity(0.34)))
            .overlay(Circle().stroke(Color(hex: 0xE0C982).opacity(0.75), lineWidth: 1))
            .allowsHitTesting(false)
    }
}
