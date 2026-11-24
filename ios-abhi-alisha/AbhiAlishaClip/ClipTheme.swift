import CoreText
import SwiftUI
import UIKit

/// The wedding's colours and faces, read from `weddings.theme`. Unknown or missing
/// themes fall back to Ivory.
nonisolated struct ClipTheme: Sendable, Hashable {
    nonisolated struct Tokens: Sendable, Hashable {
        var bg: UInt32
        var card: UInt32
        var ink: UInt32
        var muted: UInt32
        var accent: UInt32
        var accentText: UInt32
        var hairline: UInt32
    }

    var preset: String = "ivory"
    var appearance: String = "system"
    var displayIsPlayfair = false
    var displayIsItalic = false
    var bodyIsInter = true
    var light: Tokens?
    var dark: Tokens?

    static let ivoryLight = Tokens(bg: 0xF7F3EC, card: 0xFFFDF8, ink: 0x17130F, muted: 0x5E554B, accent: 0xB08D57, accentText: 0x7A5C2E, hairline: 0xE6DCCB)
    static let ivoryDark = Tokens(bg: 0x121110, card: 0x1D1A16, ink: 0xF3EDE2, muted: 0xB4AA98, accent: 0xC9A961, accentText: 0xC9A961, hairline: 0x3A3326)
    static let blushLight = Tokens(bg: 0xF6E9E6, card: 0xFFF8F6, ink: 0x3A2326, muted: 0x6B4A4D, accent: 0xB56E6E, accentText: 0x8E4F4F, hairline: 0xEBD6D2)
    static let blushDark = Tokens(bg: 0x1C1415, card: 0x281D1F, ink: 0xF6E9E6, muted: 0xC9AFAF, accent: 0xD49A9A, accentText: 0xD49A9A, hairline: 0x43302F)
    static let emeraldLight = Tokens(bg: 0xE5EDE8, card: 0xF6FAF7, ink: 0x14281F, muted: 0x3E5248, accent: 0x3F6E5A, accentText: 0x2F5444, hairline: 0xCCDBD2)
    static let emeraldDark = Tokens(bg: 0x0F1714, card: 0x18231E, ink: 0xE5EDE8, muted: 0xA9BDB2, accent: 0x7FB59A, accentText: 0x7FB59A, hairline: 0x2A3A32)
    static let midnight = Tokens(bg: 0x1B2033, card: 0x232A42, ink: 0xF4EBDC, muted: 0xB7A98F, accent: 0xC9A96A, accentText: 0xC9A96A, hairline: 0x343C58)

    static let ivory = ClipTheme()

    var forcedDark: Bool? {
        if preset == "midnight" { return true }
        switch appearance {
        case "light": return false
        case "dark": return true
        default: return nil
        }
    }

    func tokens(dark wantsDark: Bool) -> Tokens {
        let isDark = forcedDark ?? wantsDark
        let builtIn: (Tokens, Tokens)
        switch preset {
        case "blush": builtIn = (Self.blushLight, Self.blushDark)
        case "emerald": builtIn = (Self.emeraldLight, Self.emeraldDark)
        case "midnight": builtIn = (Self.midnight, Self.midnight)
        default: builtIn = (Self.ivoryLight, Self.ivoryDark)
        }
        return isDark ? (dark ?? builtIn.1) : (light ?? builtIn.0)
    }

    static func parse(_ value: Any?) -> ClipTheme {
        var dict = value as? [String: Any]
        if dict == nil, let text = value as? String, let data = text.data(using: .utf8) {
            dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        guard let dict else { return .ivory }
        var theme = ClipTheme()
        let preset = (dict["preset"] as? String)?.lowercased() ?? "ivory"
        theme.preset = ["ivory", "blush", "emerald", "midnight", "custom"].contains(preset) ? preset : "ivory"
        if let appearance = (dict["appearance"] as? String)?.lowercased(), ["system", "light", "dark"].contains(appearance) {
            theme.appearance = appearance
        }
        if let fonts = dict["fonts"] as? [String: Any] {
            theme.displayIsPlayfair = (fonts["display"] as? String)?.lowercased().contains("playfair") == true
            theme.displayIsItalic = (fonts["display_style"] as? String)?.lowercased() == "italic"
            if let body = fonts["body"] as? String { theme.bodyIsInter = body.lowercased().contains("inter") }
        }
        theme.light = tokens(dict["light"])
        theme.dark = tokens(dict["dark"])
        return theme
    }

    private static func tokens(_ value: Any?) -> Tokens? {
        guard let dict = value as? [String: Any],
              let bg = hex(dict["background"]) ?? hex(dict["bg"]),
              let ink = hex(dict["ink"]), let accent = hex(dict["accent"]) else { return nil }
        return Tokens(
            bg: bg,
            card: hex(dict["card"]) ?? bg,
            ink: ink,
            muted: hex(dict["body"]) ?? hex(dict["muted"]) ?? ink,
            accent: accent,
            accentText: hex(dict["accentText"]) ?? hex(dict["accent_text"]) ?? accent,
            hairline: hex(dict["hairline"]) ?? accent
        )
    }

    private static func hex(_ value: Any?) -> UInt32? {
        guard var text = (value as? String)?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 else { return nil }
        return UInt32(text, radix: 16)
    }
}

extension Color {
    init(clipHex value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// The resolved colours for the current light or dark appearance.
struct ClipPalette {
    let bg: Color
    let card: Color
    let ink: Color
    let muted: Color
    let accent: Color
    let accentText: Color
    let hairline: Color

    init(_ tokens: ClipTheme.Tokens) {
        bg = Color(clipHex: tokens.bg)
        card = Color(clipHex: tokens.card)
        ink = Color(clipHex: tokens.ink)
        muted = Color(clipHex: tokens.muted)
        accent = Color(clipHex: tokens.accent)
        accentText = Color(clipHex: tokens.accentText)
        hairline = Color(clipHex: tokens.hairline)
    }
}

/// Playfair Display Italic and Cormorant Garamond, bundled small, scaled with Dynamic Type.
enum ClipFont {
    private static var didRegister = false

    static func register() {
        guard !didRegister else { return }
        didRegister = true
        let urls = ["PlayfairDisplay-Italic", "CormorantGaramond"].compactMap {
            Bundle.main.url(forResource: $0, withExtension: "ttf")
        }
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { _, _ in true }
    }

    private static let weightAxis = 2_003_265_652

    private static func font(_ name: String, size: CGFloat, weight: CGFloat?, style: UIFont.TextStyle) -> Font {
        register()
        var descriptor = UIFontDescriptor(fontAttributes: [.name: name])
        if let weight {
            let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
            descriptor = descriptor.addingAttributes([variation: [weightAxis: weight]])
        }
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size)))
    }

    /// Headings: the wedding's display face (Playfair italic for A&A).
    static func display(_ size: CGFloat, theme: ClipTheme, style: UIFont.TextStyle = .title1) -> Font {
        if theme.displayIsPlayfair && theme.displayIsItalic {
            return font("PlayfairDisplay-Italic", size: size, weight: nil, style: style)
        }
        return font("CormorantGaramond-Light", size: size * 1.1, weight: 450, style: style)
    }

    /// Reading text: Cormorant, or the system face for themes that use Inter.
    static func body(_ size: CGFloat, theme: ClipTheme, style: UIFont.TextStyle = .body) -> Font {
        if theme.bodyIsInter {
            return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size * 0.86)))
        }
        return font("CormorantGaramond-Light", size: size, weight: 500, style: style)
    }

    /// Small-caps gold labels.
    static func label(_ size: CGFloat = 11) -> Font {
        Font(UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: size, weight: .semibold)))
            .smallCaps()
    }
}
