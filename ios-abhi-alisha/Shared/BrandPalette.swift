import SwiftUI
import UIKit

/// One wedding's colours, picked by its theme preset.
nonisolated struct BrandThemeColors: Sendable, Equatable {
    let background: UInt32
    let card: UInt32
    let accent: UInt32
    let ink: UInt32
    /// Accent dark enough to read as text on the background.
    let accentText: UInt32
    let isDark: Bool

    /// A mix of two colours, `amount` of the way from `a` to `b`.
    static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ value: UInt32, _ shift: UInt32) -> Double { Double((value >> shift) & 0xFF) }
        func blend(_ shift: UInt32) -> UInt32 {
            UInt32((channel(a, shift) * (1 - amount) + channel(b, shift) * amount).rounded()) << shift
        }
        return blend(16) | blend(8) | blend(0)
    }

    var body: UInt32 { Self.mix(ink, background, 0.32) }
    var muted: UInt32 { Self.mix(ink, background, 0.45) }
    var hairline: UInt32 { Self.mix(accent, background, 0.62) }
    var accentPale: UInt32 { Self.mix(accent, background, 0.45) }
}

/// The four presets a couple can choose from, and the theme in use right now.
nonisolated enum BrandTheme {
    static let ivory = colors(WeddingTheme.ivoryLight, isDark: false)
    static let blush = colors(WeddingTheme.blushLight, isDark: false)
    static let emerald = colors(WeddingTheme.emeraldLight, isDark: false)
    static let midnight = colors(WeddingTheme.midnightTokens, isDark: true)

    static let presetIDs = WeddingTheme.presetIDs

    static func colors(_ tokens: WeddingTheme.Tokens, isDark: Bool) -> BrandThemeColors {
        BrandThemeColors(background: tokens.bg, card: tokens.card, accent: tokens.accent, ink: tokens.ink, accentText: tokens.accentText, isDark: isDark)
    }

    /// A preset's light look (its only look for midnight), for previews and pickers.
    static func colors(for preset: String) -> BrandThemeColors {
        switch preset.lowercased() {
        case "blush": return blush
        case "emerald": return emerald
        case "midnight": return midnight
        default: return ivory
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var override: WeddingTheme?

    /// The theme in use: the app sets it when a wedding opens; the widgets read the
    /// current wedding's.
    static var theme: WeddingTheme {
        get {
            lock.lock()
            defer { lock.unlock() }
            return override ?? ActiveWedding.snapshot.resolvedTheme
        }
        set {
            lock.lock()
            override = newValue
            lock.unlock()
        }
    }

    static var preset: String { theme.preset }

    static var current: BrandThemeColors {
        let theme = theme
        let dark = theme.forcedDark ?? false
        return colors(theme.tokens(dark: dark), isDark: dark)
    }
}

/// The wedding's colour palette. Every colour resolves at draw time from the current
/// wedding's theme and the light or dark setting it follows.
enum BrandPalette {
    static let gold = themed { $0.accent }
    static let goldDeep = themed { $0.accentText }
    static let goldPale = themed { WeddingTheme.mix($0.accent, $0.bg, 0.45) }

    static let ink = themed { $0.ink }
    static let body = themed { $0.muted }

    /// Muted tone for unselected tab items.
    static let tabInactive = themed { WeddingTheme.mix($0.muted, $0.bg, 0.22) }

    static let background = themed { $0.bg }
    static let card = themed { $0.card }
    static let hairline = themed { $0.hairline }

    /// Behind the hero photograph while it loads.
    static let heroFallback = themedFull { tokens, dark in dark ? tokens.card : WeddingTheme.mix(tokens.ink, 0x000000, 0.2) }

    /// The two edges of a letterpress impression: the shadow gathering in the recess and
    /// the light catching the lip of it.
    static let embossShadow = themedFull { tokens, dark in dark ? 0x000000 : WeddingTheme.mix(tokens.accent, tokens.ink, 0.35) }
    static let embossLight = themedFull { tokens, dark in dark ? WeddingTheme.mix(tokens.muted, tokens.bg, 0.45) : 0xFFFFFF }

    /// A muted, dusty red for things that have slipped past their day.
    static let overdue = adaptive(light: 0xA65A4E, dark: 0xD68B7E)

    static let sikhAmber = adaptive(light: 0xD79A2B, dark: 0xE3A93C)
    static let hinduGarnet = adaptive(light: 0x8E2C3B, dark: 0xB9455A)

    /// Whether the theme is drawing dark right now, for the given traits.
    static func isDark(_ traits: UITraitCollection) -> Bool {
        BrandTheme.theme.forcedDark ?? (traits.userInterfaceStyle == .dark)
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            isDark(traits) ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    private static func themed(_ pick: @escaping @Sendable (WeddingTheme.Tokens) -> UInt32) -> Color {
        themedFull { tokens, _ in pick(tokens) }
    }

    private static func themedFull(_ pick: @escaping @Sendable (WeddingTheme.Tokens, Bool) -> UInt32) -> Color {
        Color(UIColor { traits in
            let dark = isDark(traits)
            return UIColor(hex: pick(BrandTheme.theme.tokens(dark: dark), dark))
        })
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

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
