import SwiftUI

/// The five sections of the app.
enum AppTab: String, CaseIterable, Hashable, Identifiable {
    case home
    case schedule
    case story
    case gallery
    case resort

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .schedule: return "Schedule"
        case .story: return "Story"
        case .gallery: return "Gallery"
        case .resort: return "Resort"
        }
    }

    /// Outline-only SF Symbols — the fill variants are never used.
    var symbolName: String {
        switch self {
        case .home: return "house"
        case .schedule: return "sparkles"
        case .story: return "heart"
        case .gallery: return "photo.on.rectangle.angled"
        case .resort: return "bed.double"
        }
    }
}

/// A floating Liquid Glass pill, inset from every edge, that content scrolls beneath.
/// This is the only glass surface in the app; cards stay matte.
struct FloatingTabBar: View {
    @Binding var selection: AppTab

    /// Height of the pill itself.
    static let barHeight: CGFloat = 58
    /// Inset from the screen edges and the bottom safe area.
    static let edgeInset: CGFloat = 13
    /// Space scrolling content must reserve so the last element clears the bar.
    static let contentReserve: CGFloat = barHeight + edgeInset + 18

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    select(tab)
                } label: {
                    item(for: tab)
                }
                .buttonStyle(TabItemStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(tab == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: Self.barHeight)
        .background(glassSurface)
        .overlay(rimLight)
        .overlay(topGloss)
        .clipShape(Capsule(style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 22, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
        .padding(.horizontal, Self.edgeInset)
        .padding(.bottom, Self.edgeInset)
    }

    // MARK: - Items

    private func item(for tab: AppTab) -> some View {
        let isSelected = tab == selection

        return VStack(spacing: 5) {
            Image(systemName: tab.symbolName)
                .symbolVariant(.none)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 20, weight: isSelected ? .regular : .light))
                .foregroundStyle(isSelected ? BrandPalette.goldDeep : BrandPalette.tabInactive)
                .frame(height: 22)
                .shadow(
                    color: isSelected ? BrandPalette.gold.opacity(0.35) : .clear,
                    radius: isSelected ? 7 : 0
                )

            Text(tab.title.uppercased())
                .font(BrandLabel.font(size: 8.5, weight: isSelected ? .semibold : .medium))
                .tracking(0.9)
                .foregroundStyle(isSelected ? BrandPalette.goldDeep : BrandPalette.tabInactive)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.barHeight)
        .contentShape(Rectangle())
        .animation(.calm, value: isSelected)
    }

    private func select(_ tab: AppTab) {
        guard tab != selection else { return }
        BrandHaptics.tick()
        withAnimation(.calm) {
            selection = tab
        }
    }

    // MARK: - Glass

    @ViewBuilder
    private var glassSurface: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular, in: .capsule)
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(BrandPalette.card.opacity(0.22))
                )
        }
    }

    /// Hairline rim that catches light along the top edge.
    private var rimLight: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.12),
                        BrandPalette.gold.opacity(0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }

    /// A soft inner gloss so the pill reads as glass rather than a flat blur.
    private var topGloss: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            .padding(1)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}

/// Barely-there press feedback for the glass bar.
private struct TabItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
