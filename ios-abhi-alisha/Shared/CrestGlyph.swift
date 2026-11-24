import SwiftUI

/// The wedding's crest as a small single-colour glyph: the bundled crest, the couple's
/// uploaded crest, or their initials when there is none.
struct CrestGlyph: View {
    var color: Color
    /// Widgets can't load images from the network, so they show initials instead.
    var allowsRemote: Bool = true

    private var wedding: WeddingSnapshot { ActiveWedding.snapshot }

    var body: some View {
        let theme = wedding.resolvedTheme
        if theme.hasBundledCrest {
            Image("crest")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(color)
        } else if allowsRemote, let url = theme.crestURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.renderingMode(.template).resizable().aspectRatio(contentMode: .fit).foregroundStyle(color)
                } else {
                    initials
                }
            }
        } else {
            initials
        }
    }

    private var initials: some View {
        GeometryReader { proxy in
            Text(wedding.initials)
                .font(Font(BrandFont.themedFont(.playfairItalic, size: max(8, proxy.size.height * 0.5), weight: 500)))
                .foregroundStyle(color)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
