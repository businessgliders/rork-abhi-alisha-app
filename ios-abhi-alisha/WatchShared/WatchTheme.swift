import CoreText
import SwiftUI

/// The watch's fixed palette: pure black, wedding gold, warm cream. Nothing adapts
/// here — the watch face is always dark, so the letterpress mood holds at a glance.
enum WatchTheme {
    static let gold = Color(hex: 0xC2A24C)
    static let goldDeep = Color(hex: 0xA9873C)
    static let cream = Color(hex: 0xF3EDE1)
    static let creamDim = Color(hex: 0x9C9285)
    static let hairline = Color(hex: 0x3A3226)

    private static var didRegister = false

    /// Registers the bundled brand fonts for this process — the app and the widget
    /// extension each carry their own copies.
    static func registerFontsIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        let names = [
            "PlayfairDisplay-Italic",
            "PlayfairDisplay",
            "CormorantGaramond",
            "CormorantGaramond-Italic"
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Font {
    /// Playfair Display Italic — names and numerals.
    static func watchPlayfair(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        WatchTheme.registerFontsIfNeeded()
        return .custom("PlayfairDisplay-Italic", size: size).weight(weight)
    }

    /// Cormorant Garamond — quiet details.
    static func watchCormorant(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        WatchTheme.registerFontsIfNeeded()
        return .custom("CormorantGaramond-Light", size: size).weight(weight)
    }
}
