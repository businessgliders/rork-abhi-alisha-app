import CoreText
import SwiftUI
import UIKit

/// The three brand typefaces. Playfair Display Italic for display, Cormorant Garamond
/// for body copy, Great Vibes for the couple's script wordmark. SF Pro stays for UI labels.
enum BrandTypeface {
    case playfairItalic
    case playfair
    case cormorant
    case cormorantItalic
    case script

    var postScriptName: String {
        switch self {
        case .playfairItalic: return "PlayfairDisplay-Italic"
        case .playfair: return "PlayfairDisplay-Regular"
        case .cormorant: return "CormorantGaramond-Light"
        case .cormorantItalic: return "CormorantGaramond-LightItalic"
        case .script: return "GreatVibes-Regular"
        }
    }
}

/// Registers the bundled variable fonts and resolves Dynamic Type aware instances.
enum BrandFont {
    private static var didRegister = false

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        let names = [
            "PlayfairDisplay-Italic",
            "PlayfairDisplay",
            "CormorantGaramond",
            "CormorantGaramond-Italic",
            "GreatVibes-Regular"
        ]
        let urls = names.compactMap { Bundle.main.url(forResource: $0, withExtension: "ttf") }
        guard !urls.isEmpty else {
            print("[BrandFont] no bundled font files found")
            return
        }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { errors, _ in
            if CFArrayGetCount(errors) > 0 {
                print("[BrandFont] font registration reported \(CFArrayGetCount(errors)) issue(s)")
            }
            return true
        }
    }

    /// Weight axis tag for variable fonts ('wght').
    private static let weightAxis = 2_003_265_652

    static func uiFont(
        _ face: BrandTypeface,
        size: CGFloat,
        weight: CGFloat? = nil,
        textStyle: UIFont.TextStyle = .body,
        maxSize: CGFloat? = nil
    ) -> UIFont {
        registerIfNeeded()
        var descriptor = UIFontDescriptor(fontAttributes: [.name: face.postScriptName])
        if let weight {
            let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
            descriptor = descriptor.addingAttributes([variation: [weightAxis: weight]])
        }
        let base = UIFont(descriptor: descriptor, size: size)
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        if let maxSize {
            return metrics.scaledFont(for: base, maximumPointSize: maxSize)
        }
        return metrics.scaledFont(for: base)
    }
}

struct BrandFontSpec {
    let face: BrandTypeface
    let size: CGFloat
    let weight: CGFloat?
    let textStyle: UIFont.TextStyle
    let maxSize: CGFloat?

    init(
        _ face: BrandTypeface,
        size: CGFloat,
        weight: CGFloat? = nil,
        textStyle: UIFont.TextStyle = .body,
        maxSize: CGFloat? = nil
    ) {
        self.face = face
        self.size = size
        self.weight = weight
        self.textStyle = textStyle
        self.maxSize = maxSize
    }

    var resolved: Font {
        Font(BrandFont.uiFont(face, size: size, weight: weight, textStyle: textStyle, maxSize: maxSize))
    }

    var lineSpacing: CGFloat { size * 0.32 }
}

private struct BrandFontModifier: ViewModifier {
    let spec: BrandFontSpec
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(spec.resolved)
    }
}

extension View {
    /// Applies a brand typeface that re-resolves whenever Dynamic Type changes.
    func brandFont(_ spec: BrandFontSpec) -> some View {
        modifier(BrandFontModifier(spec: spec))
    }
}

// MARK: - Type scale

extension BrandFontSpec {
    /// Couple's names on the hero.
    static let heroNames = BrandFontSpec(.playfairItalic, size: 46, weight: 500, textStyle: .largeTitle, maxSize: 68)
    static let scriptLogo = BrandFontSpec(.script, size: 27, textStyle: .title3, maxSize: 40)
    static let countdown = BrandFontSpec(.playfairItalic, size: 34, weight: 500, textStyle: .title1, maxSize: 46)
    static let screenTitle = BrandFontSpec(.playfairItalic, size: 40, weight: 500, textStyle: .largeTitle, maxSize: 56)
    static let eventTitle = BrandFontSpec(.playfairItalic, size: 30, weight: 500, textStyle: .title1, maxSize: 44)
    static let eventTitleSmall = BrandFontSpec(.playfairItalic, size: 24, weight: 500, textStyle: .title2, maxSize: 36)
    /// The opening line of the couple's letter.
    static let letterSalutation = BrandFontSpec(.playfairItalic, size: 27, weight: 500, textStyle: .title2, maxSize: 40)
    static let bodyText = BrandFontSpec(.cormorant, size: 19, weight: 450, textStyle: .body, maxSize: 30)
    static let bodyItalic = BrandFontSpec(.cormorantItalic, size: 19, weight: 450, textStyle: .body, maxSize: 30)
    static let bodySmall = BrandFontSpec(.cormorant, size: 17, weight: 500, textStyle: .callout, maxSize: 26)
}

/// Small letterspaced SF Pro caps used for labels and eyebrows.
enum BrandLabel {
    static func font(size: CGFloat = 11, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}
