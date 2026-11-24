import SwiftUI

/// The couple's crest above Home's photography, lit rather than pressed.
///
/// Every other screen carries its own crest as part of the page itself — see
/// `crestCorner()` — so it travels with the header instead of hovering over the words
/// as they pass beneath it.
struct ScreenChrome: View {
    /// Space a screen's own header must leave clear at the top.
    static let contentReserve: CGFloat = 58

    let showsCrest: Bool
    /// Opens the host area; the pill shows only to the couple and co-hosts.
    var onHost: (() -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Wide screens have rounder corners and a camera cut-out near the top-left, so the
    /// controls sit further in there. Both values are on top of the safe area.
    private var isWide: Bool { horizontalSizeClass == .regular }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsCrest {
                HStack(spacing: 8) {
                    WeddingSwitcherCapsule()
                        .fixedSize()
                    if WeddingContext.shared.isHost, let onHost {
                        HostPill(action: onHost)
                            .fixedSize()
                            .transition(.opacity)
                    }
                }
                .padding(.top, isWide ? 10 : 6)
            }

            Spacer(minLength: 0)

            if showsCrest {
                CoupleCrest(finish: .lit)
            }
        }
        .padding(.horizontal, isWide ? 28 : 16)
        .padding(.top, isWide ? 8 : 2)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

extension View {
    /// Sets the crest into the page's own top-right corner, so it belongs to the header
    /// and leaves with it rather than sitting on the glass while the page slides past.
    func crestCorner(
        width: CGFloat = 116,
        surface: Color = BrandPalette.background,
        isHoldable: Bool = true
    ) -> some View {
        overlay(alignment: .topTrailing) {
            CoupleCrest(width: width, finish: .pressed(surface), isHoldable: isHoldable)
                .padding(.top, 2)
                .padding(.trailing, 16)
        }
    }
}

/// The crest as a letterpress impression: struck into the paper rather than printed on
/// it, exactly as a die would leave it.
///
/// The face of the mark is the paper's own colour, so there is no ink at all. What you
/// read is only the edge of the impression — a crisp dark line where the recess falls
/// away and a crisp light one where the lip catches the room. Both are hard-edged, never
/// blurred; softness is what makes a stamp look like a drop shadow instead of a press.
struct CrestWatermark: View {
    /// How the crest meets what is behind it.
    enum Finish: Equatable {
        /// Struck into a solid surface — pass the exact colour it sits on.
        case pressed(Color)
        /// Laid over photography, where there is no paper to press into.
        case lit
    }

    var width: CGFloat = 116
    var finish: Finish = .pressed(BrandPalette.background)

    /// How deep the die went. Scaled to the mark, so a small crest is lightly struck.
    private var depth: CGFloat {
        max(0.75, (width / 116) * 1.2)
    }

    private var theme: WeddingTheme { ActiveWedding.snapshot.resolvedTheme }

    var body: some View {
        Group {
            if theme.hasBundledCrest || theme.crestURL != nil {
                switch finish {
                case .pressed(let surface):
                    ZStack {
                        crest(BrandPalette.embossShadow.opacity(0.6))
                            .offset(x: depth, y: depth)

                        crest(BrandPalette.embossLight.opacity(0.9))
                            .offset(x: -depth, y: -depth)

                        crest(surface)
                    }

                case .lit:
                    crest(Color(hex: 0xFDFAF3).opacity(0.4))
                        .shadow(color: Color.black.opacity(0.35), radius: 12, y: 3)
                }
            } else {
                WeddingMonogram(width: width * 0.66, isLit: finish == .lit)
                    .frame(width: width)
            }
        }
        .frame(width: width)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func crest(_ color: Color) -> some View {
        if let url = theme.crestURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(color)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        } else {
            Image("crest")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(color)
        }
    }
}

/// For a wedding without a crest: the couple's two initials in the theme's display face
/// inside a thin accent ring, with the year beneath.
struct WeddingMonogram: View {
    var width: CGFloat
    var isLit: Bool = false

    private var wedding: WeddingSnapshot { ActiveWedding.snapshot }

    private var year: String? {
        guard let start = wedding.start else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = wedding.timeZone
        return String(calendar.component(.year, from: start))
    }

    private var letters: String {
        let initials = wedding.initials
        guard initials.count == 2 else { return initials }
        return "\(initials.prefix(1))\u{2009}&\u{2009}\(initials.suffix(1))"
    }

    var body: some View {
        let ring = isLit ? Color(hex: 0xFDFAF3).opacity(0.7) : BrandPalette.gold
        let ink = isLit ? Color(hex: 0xFDFAF3).opacity(0.92) : BrandPalette.goldDeep
        VStack(spacing: width * 0.06) {
            ZStack {
                Circle().strokeBorder(ring, lineWidth: max(0.75, width / 110))
                Text(letters)
                    .font(Font(BrandFont.themedFont(.playfairItalic, size: width * 0.28, weight: 500, textStyle: .title2, maxSize: width * 0.28)))
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(width * 0.14)
            }
            .frame(width: width, height: width)
            if let year {
                Text(year)
                    .font(BrandLabel.font(size: max(8, width * 0.1), weight: .semibold))
                    .tracking(max(1, width * 0.03))
                    .foregroundStyle(ink.opacity(0.85))
            }
        }
        .shadow(color: isLit ? Color.black.opacity(0.3) : .clear, radius: 10, y: 2)
    }
}
