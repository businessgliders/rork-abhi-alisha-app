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

/// The four presets a couple can choose from. Ivory is the house style.
nonisolated enum BrandTheme {
    static let ivory = BrandThemeColors(background: 0xF7F3EC, card: 0xFFFDF8, accent: 0xB08D57, ink: 0x17130F, accentText: 0x7A5C2E, isDark: false)
    static let blush = BrandThemeColors(background: 0xF6E9E6, card: 0xFFF8F6, accent: 0xB56E6E, ink: 0x3A2326, accentText: 0x8A4A4C, isDark: false)
    static let emerald = BrandThemeColors(background: 0xE5EDE8, card: 0xF6FAF7, accent: 0x3F6E5A, ink: 0x14281F, accentText: 0x2E5544, isDark: false)
    static let midnight = BrandThemeColors(background: 0x1B2033, card: 0x232A42, accent: 0xC9A96A, ink: 0xF4EBDC, accentText: 0xC9B48D, isDark: true)

    static let presetIDs = ["ivory", "blush", "emerald", "midnight"]

    static func colors(for preset: String) -> BrandThemeColors {
        switch preset.lowercased() {
        case "blush": return blush
        case "emerald": return emerald
        case "midnight": return midnight
        default: return ivory
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var override: String?

    /// The preset in use: the app sets it when a wedding opens; the widgets read the
    /// current wedding's.
    static var preset: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return override ?? ActiveWedding.snapshot.preset
        }
        set {
            lock.lock()
            override = newValue
            lock.unlock()
        }
    }

    static var current: BrandThemeColors { colors(for: preset) }
}

/// The wedding's colour palette. Every colour resolves at draw time from the current
/// wedding's preset. Ivory keeps warm, low-glare counterparts in dark mode; the other
/// presets hold their own colours whatever the phone's setting.
enum BrandPalette {
    static let gold = themed(light: 0xC2A24C, dark: 0xD3B463) { $0.accent }
    static let goldDeep = themed(light: 0xA9873C, dark: 0xBE9A48) { $0.accentText }
    static let goldPale = themed(light: 0xE3CE92, dark: 0xEBD9A6) { $0.accentPale }

    static let ink = themed(light: 0x2B2622, dark: 0xF3EDE1) { $0.ink }
    static let body = themed(light: 0x6D6459, dark: 0xB6AB9A) { $0.body }

    /// Muted warm grey-brown for unselected tab items — never pure grey.
    static let tabInactive = themed(light: 0x8B8175, dark: 0x968C7E) { $0.muted }

    static let background = themed(light: 0xFBF8F2, dark: 0x14110E) { $0.background }
    static let card = themed(light: 0xFFFFFF, dark: 0x1E1A16) { $0.card }
    static let hairline = themed(light: 0xECE4D5, dark: 0x342E26) { $0.hairline }

    /// Warm ink used behind the hero photograph while it loads.
    static let heroFallback = Color(hex: 0x1B211F)

    /// The two edges of a letterpress impression: the shadow gathering in the recess and
    /// the light catching the lip of it. Warm on paper, near-black on the dark palette.
    static let embossShadow = adaptive(light: 0x9C8862, dark: 0x000000)
    static let embossLight = adaptive(light: 0xFFFFFF, dark: 0x6C6152)

    /// A muted, dusty red for things that have slipped past their day.
    static let overdue = adaptive(light: 0xA65A4E, dark: 0xD68B7E)

    static let sikhAmber = adaptive(light: 0xD79A2B, dark: 0xE3A93C)
    static let hinduGarnet = adaptive(light: 0x8E2C3B, dark: 0xB9455A)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    /// Ivory in light mode uses the house colours; ivory in dark mode keeps the warm
    /// dark palette; every other preset uses its own colours.
    private static func themed(
        light: UInt32,
        dark: UInt32,
        _ pick: @escaping @Sendable (BrandThemeColors) -> UInt32
    ) -> Color {
        Color(UIColor { traits in
            let preset = BrandTheme.preset.lowercased()
            if preset == "ivory" || !BrandTheme.presetIDs.contains(preset) {
                if traits.userInterfaceStyle == .dark { return UIColor(hex: dark) }
                return UIColor(hex: pick(BrandTheme.ivory))
            }
            return UIColor(hex: pick(BrandTheme.colors(for: preset)))
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
