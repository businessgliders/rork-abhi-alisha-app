import SwiftUI
import UIKit

/// The widgets' palette: the app's cream paper by day, a deep navy by night, gold
/// throughout. The Live Activity is always the night version, whatever the phone is set to.
nonisolated enum WidgetPalette {
    static let paper = adaptive(light: 0xFBF8F2, dark: 0x0E1626)
    static let ink = adaptive(light: 0x2B2622, dark: 0xF4EEE2)
    static let body = adaptive(light: 0x6D6459, dark: 0xA7A08E)
    static let gold = adaptive(light: 0xC2A24C, dark: 0xD3B463)
    static let goldDeep = adaptive(light: 0xA9873C, dark: 0xC2A24C)
    static let hairline = adaptive(light: 0xE4DAC6, dark: 0x22314B)

    /// Always-dark values, for the Lock Screen activity and the Dynamic Island.
    static let night = Color(hex: 0x0E1626)
    static let nightInk = Color(hex: 0xF4EEE2)
    static let nightBody = Color(hex: 0xA7A08E)
    static let nightGold = Color(hex: 0xD3B463)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension BrandFontSpec {
    /// Sizes tuned for a widget's small canvas — capped tightly so the largest Dynamic
    /// Type settings never push a number off its tile.
    static let widgetNumeral = BrandFontSpec(.playfairItalic, size: 50, weight: 500, textStyle: .largeTitle, maxSize: 56)
    static let widgetNumeralWord = BrandFontSpec(.playfairItalic, size: 32, weight: 500, textStyle: .title1, maxSize: 38)
    static let widgetTitle = BrandFontSpec(.playfairItalic, size: 22, weight: 500, textStyle: .title3, maxSize: 27)
    static let widgetTitleSmall = BrandFontSpec(.playfairItalic, size: 17, weight: 500, textStyle: .subheadline, maxSize: 21)
    static let widgetBody = BrandFontSpec(.cormorant, size: 16, weight: 500, textStyle: .footnote, maxSize: 20)
    static let widgetBodySmall = BrandFontSpec(.cormorant, size: 14, weight: 500, textStyle: .caption1, maxSize: 17)
    static let accessoryNumeral = BrandFontSpec(.playfairItalic, size: 23, weight: 500, textStyle: .title3, maxSize: 26)
    static let accessoryTitle = BrandFontSpec(.playfairItalic, size: 16, weight: 500, textStyle: .subheadline, maxSize: 19)
}

/// The small letterspaced caps the app uses above every heading.
struct WidgetEyebrow: View {
    let text: String
    var size: CGFloat = 8.5
    var color: Color = WidgetPalette.goldDeep

    var body: some View {
        Text(text.uppercased())
            .font(BrandLabel.font(size: size, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// The couple's crest, set faintly into a corner the way it is on every screen.
struct WidgetCrest: View {
    var width: CGFloat = 74
    var opacity: Double = 0.13

    var body: some View {
        Image("crest")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width)
            .foregroundStyle(WidgetPalette.gold.opacity(opacity))
            .accessibilityHidden(true)
    }
}

/// A short gold hairline, the app's quiet divider.
struct WidgetRule: View {
    var width: CGFloat = 26
    var opacity: Double = 0.7

    var body: some View {
        Rectangle()
            .fill(WidgetPalette.gold.opacity(opacity))
            .frame(width: width, height: 1)
    }
}
