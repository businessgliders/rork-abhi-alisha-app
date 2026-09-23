import SwiftUI
import UIKit

/// The wedding's fixed colour palette. Light values come from the brand guide;
/// dark values are warm, low-glare counterparts so the editorial mood survives dark mode.
enum BrandPalette {
    static let gold = adaptive(light: 0xC2A24C, dark: 0xD3B463)
    static let goldDeep = adaptive(light: 0xA9873C, dark: 0xBE9A48)
    static let goldPale = adaptive(light: 0xE3CE92, dark: 0xEBD9A6)

    static let ink = adaptive(light: 0x2B2622, dark: 0xF3EDE1)
    static let body = adaptive(light: 0x6D6459, dark: 0xB6AB9A)

    /// Muted warm grey-brown for unselected tab items — never pure grey.
    static let tabInactive = adaptive(light: 0x8B8175, dark: 0x968C7E)

    static let background = adaptive(light: 0xFBF8F2, dark: 0x14110E)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x1E1A16)
    static let hairline = adaptive(light: 0xECE4D5, dark: 0x342E26)

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
