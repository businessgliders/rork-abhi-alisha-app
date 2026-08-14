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

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 0)

            if showsCrest {
                CrestWatermark(finish: .lit)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

extension View {
    /// Sets the crest into the page's own top-right corner, so it belongs to the header
    /// and leaves with it rather than sitting on the glass while the page slides past.
    func crestCorner(width: CGFloat = 116, surface: Color = BrandPalette.background) -> some View {
        overlay(alignment: .topTrailing) {
            CrestWatermark(width: width, finish: .pressed(surface))
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

    var body: some View {
        Group {
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
        }
        .frame(width: width)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func crest(_ color: Color) -> some View {
        Image("crest")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(color)
    }
}
