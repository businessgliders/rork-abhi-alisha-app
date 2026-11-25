import SwiftUI

/// Reads the colour the couple asked for out of a dress code line — they write it in
/// brackets, e.g. "Formal Indian Attire (Any Colour Attire)" — and turns it into a
/// small swatch plus a two-word label.
struct AttireSwatch {
    let colors: [Color]
    let label: String

    var gradient: LinearGradient {
        LinearGradient(
            colors: colors.count == 1 ? [colors[0], colors[0]] : colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The swatch reads as a real fabric colour, so it keeps a hairline ring
    /// to stay visible against both the cream and the near-black card.
    var ringColor: Color { BrandPalette.ink.opacity(0.22) }

    static func infer(from dressCode: String) -> AttireSwatch {
        let text = dressCode.lowercased()

        if text.contains("black") {
            return AttireSwatch(colors: [Color(hex: 0x2A2A2C), Color(hex: 0x0E0E10)], label: "All Black")
        }
        if text.contains("pastel") {
            return AttireSwatch(
                colors: [Color(hex: 0xF6D9DE), Color(hex: 0xD8E7DA), Color(hex: 0xD5E2EF)],
                label: "Pastels"
            )
        }
        if text.contains("any colour") || text.contains("any color") || text.contains("colourful") {
            return AttireSwatch(
                colors: [Color(hex: 0xC8384C), Color(hex: 0xE0A32C), Color(hex: 0x2E7C74)],
                label: "Any Colour"
            )
        }
        if text.contains("white") || text.contains("ivory") || text.contains("cream") {
            return AttireSwatch(colors: [Color(hex: 0xFBF6EA), Color(hex: 0xEADFC6)], label: "Ivory")
        }
        if text.contains("maroon") || text.contains("red") {
            return AttireSwatch(colors: [Color(hex: 0xA32234), Color(hex: 0x6E1522)], label: "Reds")
        }
        if text.contains("pink") || text.contains("rose") {
            return AttireSwatch(colors: [Color(hex: 0xE79BAC), Color(hex: 0xC96A81)], label: "Rose")
        }
        if text.contains("blue") || text.contains("navy") {
            return AttireSwatch(colors: [Color(hex: 0x35597F), Color(hex: 0x1D3550)], label: "Blues")
        }
        if text.contains("green") || text.contains("emerald") {
            return AttireSwatch(colors: [Color(hex: 0x2E7C56), Color(hex: 0x1B4B35)], label: "Greens")
        }
        return AttireSwatch(
            colors: [Color(hex: 0xD8BE72), Color(hex: 0xA9873C)],
            label: text.contains("formal") ? "Formal" : "Attire"
        )
    }
}
