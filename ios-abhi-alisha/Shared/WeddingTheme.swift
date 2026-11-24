import Foundation

/// A wedding's look, read from `weddings.theme`: its preset, light/dark behaviour, fonts,
/// crest and the two colour sets. Shared by the app, the widgets and the Watch.
nonisolated struct WeddingTheme: Codable, Hashable, Sendable {
    /// The seven colours a screen is painted with.
    nonisolated struct Tokens: Codable, Hashable, Sendable {
        var bg: UInt32
        var card: UInt32
        var ink: UInt32
        var muted: UInt32
        var accent: UInt32
        var accentText: UInt32
        var hairline: UInt32
    }

    var preset: String
    /// "system", "light" or "dark".
    var appearance: String
    var displayFont: String
    /// "italic" or "normal".
    var displayStyle: String
    var bodyFont: String
    var labelFont: String
    /// `bundled:aa-crest`, an image URL, or nil for the auto monogram.
    var crest: String?
    var light: Tokens?
    var dark: Tokens?

    // MARK: Built-in palettes

    static let ivoryLight = Tokens(bg: 0xF7F3EC, card: 0xFFFDF8, ink: 0x17130F, muted: 0x5E554B, accent: 0xB08D57, accentText: 0x7A5C2E, hairline: 0xE6DCCB)
    static let ivoryDark = Tokens(bg: 0x121110, card: 0x1D1A16, ink: 0xF3EDE2, muted: 0xB4AA98, accent: 0xC9A961, accentText: 0xC9A961, hairline: 0x3A3326)
    static let blushLight = Tokens(bg: 0xF6E9E6, card: 0xFFF8F6, ink: 0x3A2326, muted: 0x6B4A4D, accent: 0xB56E6E, accentText: 0x8E4F4F, hairline: 0xEBD6D2)
    static let blushDark = Tokens(bg: 0x1C1415, card: 0x281D1F, ink: 0xF6E9E6, muted: 0xC9AFAF, accent: 0xD49A9A, accentText: 0xD49A9A, hairline: 0x43302F)
    static let emeraldLight = Tokens(bg: 0xE5EDE8, card: 0xF6FAF7, ink: 0x14281F, muted: 0x3E5248, accent: 0x3F6E5A, accentText: 0x2F5444, hairline: 0xCCDBD2)
    static let emeraldDark = Tokens(bg: 0x0F1714, card: 0x18231E, ink: 0xE5EDE8, muted: 0xA9BDB2, accent: 0x7FB59A, accentText: 0x7FB59A, hairline: 0x2A3A32)
    static let midnightTokens = Tokens(bg: 0x1B2033, card: 0x232A42, ink: 0xF4EBDC, muted: 0xB7A98F, accent: 0xC9A96A, accentText: 0xC9A96A, hairline: 0x343C58)

    static let presetIDs = ["ivory", "blush", "emerald", "midnight"]

    /// Used only until Abhi & Alisha's saved theme has been read once (a phone updating
    /// from an earlier build): the same values their `weddings.theme` row holds.
    static let abhiAlishaFallback = WeddingTheme(
        preset: "custom",
        appearance: "system",
        displayFont: "Playfair Display",
        displayStyle: "italic",
        bodyFont: "Cormorant Garamond",
        labelFont: "Inter",
        crest: "bundled:aa-crest",
        light: Tokens(bg: 0xF8F6F1, card: 0xFFFFFF, ink: 0x1C1A17, muted: 0x6B6358, accent: 0xB3964F, accentText: 0x8A6F33, hairline: 0xE8DFCC),
        dark: Tokens(bg: 0x121110, card: 0x1D1A16, ink: 0xF3EDE2, muted: 0xB4AA98, accent: 0xC9A961, accentText: 0xC9A961, hairline: 0x3A3326)
    )

    /// A built-in preset: Cormorant Garamond display (upright), Inter for body and labels.
    static func preset(_ id: String) -> WeddingTheme {
        let key = presetIDs.contains(id.lowercased()) ? id.lowercased() : "ivory"
        return WeddingTheme(
            preset: key,
            appearance: key == "midnight" ? "dark" : "system",
            displayFont: "Cormorant Garamond",
            displayStyle: "normal",
            bodyFont: "Inter",
            labelFont: "Inter",
            crest: nil,
            light: nil,
            dark: nil
        )
    }

    /// The built-in pair for a preset name.
    static func builtIn(_ preset: String) -> (light: Tokens, dark: Tokens) {
        switch preset.lowercased() {
        case "blush": return (blushLight, blushDark)
        case "emerald": return (emeraldLight, emeraldDark)
        case "midnight": return (midnightTokens, midnightTokens)
        default: return (ivoryLight, ivoryDark)
        }
    }

    var isMidnight: Bool { preset.lowercased() == "midnight" }

    /// Forced light or dark, or nil to follow the phone.
    var forcedDark: Bool? {
        if isMidnight { return true }
        switch appearance.lowercased() {
        case "light": return false
        case "dark": return true
        default: return nil
        }
    }

    /// The colours for light or dark, falling back to the preset's built-in ones.
    func tokens(dark wantsDark: Bool) -> Tokens {
        let isDark = forcedDark ?? wantsDark
        let fallback = Self.builtIn(isMidnight ? "midnight" : (preset.lowercased() == "custom" ? "ivory" : preset))
        if isDark { return dark ?? fallback.dark }
        return light ?? fallback.light
    }

    var hasBundledCrest: Bool { crest?.lowercased().hasPrefix("bundled:") == true }

    var crestURL: URL? {
        guard let crest, !hasBundledCrest, crest.lowercased().hasPrefix("http") else { return nil }
        return URL(string: crest)
    }

    /// True when the display face is Playfair Display.
    var displayIsPlayfair: Bool { displayFont.lowercased().contains("playfair") }
    var displayIsItalic: Bool { displayStyle.lowercased() == "italic" }
    var bodyIsInter: Bool { bodyFont.lowercased().contains("inter") }
    /// Custom themes keep the system label face; presets use their label font (Inter).
    var labelIsInter: Bool { preset.lowercased() != "custom" && labelFont.lowercased().contains("inter") }

    // MARK: Parsing

    /// Reads `weddings.theme` (a JSON object or a JSON string). Unknown shapes give ivory.
    static func parse(_ value: Any?) -> WeddingTheme {
        var dict = value as? [String: Any]
        if dict == nil, let text = value as? String, let data = text.data(using: .utf8) {
            dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        guard let dict else { return preset("ivory") }
        let presetID = (dict["preset"] as? String)?.lowercased() ?? "ivory"
        var theme = presetID == "custom" ? preset("ivory") : preset(presetID)
        theme.preset = presetID == "custom" || presetIDs.contains(presetID) ? presetID : "ivory"
        if let appearance = dict["appearance"] as? String, ["system", "light", "dark"].contains(appearance.lowercased()) {
            theme.appearance = theme.isMidnight ? "dark" : appearance.lowercased()
        }
        if let fonts = dict["fonts"] as? [String: Any] {
            if let display = fonts["display"] as? String, !display.isEmpty { theme.displayFont = display }
            if let style = fonts["display_style"] as? String, !style.isEmpty { theme.displayStyle = style }
            if let body = fonts["body"] as? String, !body.isEmpty { theme.bodyFont = body }
            if let label = fonts["label"] as? String, !label.isEmpty { theme.labelFont = label }
        }
        if let crest = dict["crest"] as? String, !crest.trimmingCharacters(in: .whitespaces).isEmpty {
            theme.crest = crest.trimmingCharacters(in: .whitespaces)
        }
        theme.light = tokens(dict["light"])
        theme.dark = tokens(dict["dark"])
        return theme
    }

    private static func tokens(_ value: Any?) -> Tokens? {
        guard let dict = value as? [String: Any],
              let bg = hex(dict["bg"]), let ink = hex(dict["ink"]), let accent = hex(dict["accent"]) else { return nil }
        let card = hex(dict["card"]) ?? bg
        return Tokens(
            bg: bg,
            card: card,
            ink: ink,
            muted: hex(dict["muted"]) ?? mix(ink, bg, 0.4),
            accent: accent,
            accentText: hex(dict["accent_text"]) ?? accent,
            hairline: hex(dict["hairline"]) ?? mix(accent, bg, 0.62)
        )
    }

    static func hex(_ value: Any?) -> UInt32? {
        guard var text = value as? String else { return nil }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let number = UInt32(text, radix: 16) else { return nil }
        return number
    }

    static func hexString(_ value: UInt32) -> String { String(format: "#%06X", value) }

    /// A mix of two colours, `amount` of the way from `a` to `b`.
    static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ value: UInt32, _ shift: UInt32) -> Double { Double((value >> shift) & 0xFF) }
        func blend(_ shift: UInt32) -> UInt32 {
            UInt32((channel(a, shift) * (1 - amount) + channel(b, shift) * amount).rounded()) << shift
        }
        return blend(16) | blend(8) | blend(0)
    }

    /// The JSON written back to `weddings.theme` when a host picks a preset.
    var json: [String: Any] {
        var out: [String: Any] = [
            "preset": preset,
            "appearance": appearance,
            "fonts": ["display": displayFont, "display_style": displayStyle, "body": bodyFont, "label": labelFont]
        ]
        out["crest"] = crest ?? NSNull()
        func encode(_ t: Tokens) -> [String: String] {
            ["bg": Self.hexString(t.bg), "card": Self.hexString(t.card), "ink": Self.hexString(t.ink),
             "muted": Self.hexString(t.muted), "accent": Self.hexString(t.accent),
             "accent_text": Self.hexString(t.accentText), "hairline": Self.hexString(t.hairline)]
        }
        if let light { out["light"] = encode(light) }
        if let dark { out["dark"] = encode(dark) }
        return out
    }
}
