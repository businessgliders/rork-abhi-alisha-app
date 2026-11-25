import SwiftUI
import UIKit

// MARK: - Colours

/// The Milni onboarding palette. Fixed colours: onboarding happens before any
/// wedding's theme applies.
enum Milni {
    static let ivory = Color(hex: 0xF7F3EC)
    static let ink = Color(hex: 0x17130F)
    static let gold = Color(hex: 0xB08D57)
    static let goldText = Color(hex: 0x7A5C2E)
    static let stone = Color(hex: 0xEFE9DF)
    static let midnight = Color(hex: 0x1B2033)
    static let champagne = Color(hex: 0xC9A96A)
    static let champagneLight = Color(hex: 0xC9B48D)
    static let body = Color(hex: 0x4A433B)
    static let muted = Color(hex: 0x5E554B)
    static let hairline = Color(hex: 0xCDBFA8)
    static let found = Color(hex: 0x3F6E5A)

    static let sidePadding: CGFloat = 28

    /// Shared entrance spring: slow and settled, no bounce.
    static let entrance = Animation.spring(response: 0.9, dampingFraction: 1)

    // MARK: Type

    static func cormorant(_ size: CGFloat, weight: CGFloat = 400, italic: Bool = false) -> Font {
        Font(BrandFont.uiFont(italic ? .cormorantItalic : .cormorant, size: size, weight: weight, textStyle: .largeTitle, maxSize: size * 1.25))
    }

    static func inter(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        Font(BrandFont.uiFont(.inter, size: size, weight: weight, textStyle: .body, maxSize: size * 1.4))
    }
}

// MARK: - Text pieces

/// Inter 11pt semibold caps with wide tracking.
struct MilniLabel: View {
    let text: String
    var color: Color = Milni.goldText

    init(_ text: String, color: Color = Milni.goldText) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Milni.inter(11, weight: 600))
            .tracking(2.4)
            .foregroundStyle(color)
    }
}

/// A Cormorant headline with an optional italic second line in gold.
struct MilniHeadline: View {
    let first: String
    var second: String?
    var size: CGFloat = 44
    var color: Color = Milni.ink
    var accent: Color = Milni.goldText
    var alignment: TextAlignment = .leading

    var body: some View {
        VStack(alignment: alignment == .center ? .center : .leading, spacing: -4) {
            Text(first)
                .font(Milni.cormorant(size))
                .foregroundStyle(color)
            if let second {
                Text(second)
                    .font(Milni.cormorant(size, italic: true))
                    .foregroundStyle(accent)
            }
        }
        .multilineTextAlignment(alignment)
        .lineSpacing(-6)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct MilniBody: View {
    let text: String
    var color: Color = Milni.body
    var alignment: TextAlignment = .leading

    init(_ text: String, color: Color = Milni.body, alignment: TextAlignment = .leading) {
        self.text = text
        self.color = color
        self.alignment = alignment
    }

    var body: some View {
        Text(text)
            .font(Milni.inter(15))
            .lineSpacing(5)
            .foregroundStyle(color)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Buttons

struct MilniButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, tertiary }
    var kind: Kind = .primary
    var ink: Color = Milni.ink
    var paper: Color = Milni.ivory
    var accent: Color = Milni.goldText

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Milni.inter(15, weight: kind == .tertiary ? 500 : 600))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, minHeight: kind == .tertiary ? 44 : 56)
            .padding(.horizontal, 20)
            .foregroundStyle(foreground)
            .background {
                switch kind {
                case .primary: Capsule().fill(ink)
                case .secondary: Capsule().strokeBorder(ink, lineWidth: 1)
                case .tertiary: Color.clear
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return paper
        case .secondary: return ink
        case .tertiary: return accent
        }
    }
}

extension ButtonStyle where Self == MilniButtonStyle {
    static var milniPrimary: MilniButtonStyle { MilniButtonStyle(kind: .primary) }
    static var milniSecondary: MilniButtonStyle { MilniButtonStyle(kind: .secondary) }
    static var milniTertiary: MilniButtonStyle { MilniButtonStyle(kind: .tertiary) }
}

/// Round back chevron for onboarding screens.
struct MilniBackButton: View {
    var color: Color = Milni.ink
    let action: () -> Void

    var body: some View {
        Button {
            BrandHaptics.tick()
            action()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(MilniPressStyle())
        .accessibilityLabel("Back")
    }
}

struct MilniPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Underline field

/// A value typed straight onto a 1.5pt ink line, no box.
struct MilniUnderlineField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var ink: Color = Milni.ink
    var accent: Color = Milni.goldText
    var size: CGFloat = 29
    var contentType: UITextContentType? = .givenName
    var submit: (() -> Void)?

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MilniLabel(label, color: accent)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(ink.opacity(0.25)))
                .font(Milni.cormorant(size, weight: 500))
                .foregroundStyle(ink)
                .tint(accent)
                .textContentType(contentType)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focused)
                .onSubmit { submit?() }
            Rectangle()
                .fill(ink.opacity(focused ? 1 : 0.7))
                .frame(height: 1.5)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Entrance

/// Fade, rise 22pt and un-blur, staggered by index. Reduce Motion cross-fades only.
struct MilniEntrance: ViewModifier {
    let index: Int
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 22)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .onAppear {
                let wait = delay + Double(index) * 0.16
                if reduceMotion {
                    withAnimation(.easeInOut(duration: 0.5).delay(wait)) { shown = true }
                } else {
                    withAnimation(Milni.entrance.delay(wait)) { shown = true }
                }
            }
    }
}

extension View {
    func milniEntrance(_ index: Int, delay: Double = 0) -> some View {
        modifier(MilniEntrance(index: index, delay: delay))
    }

    /// The milni horizontal rhythm.
    /// Side margins, and on wide screens a centred column about 640pt wide.
    func milniSides() -> some View {
        padding(.horizontal, Milni.sidePadding)
            .frame(maxWidth: 640 + Milni.sidePadding * 2)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Foil text

/// Gold foil: one layer only. The text sets the size and shape but is never drawn
/// itself; an animated champagne gradient, with a bright band crossing it, is masked to
/// the letters. No second copy of the text sits underneath, so nothing can ghost.
struct MilniFoil: ViewModifier {
    /// A card's own foil colours; `nil` uses the brand foil, which deepens on light.
    var base: [Color]? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// On ivory the pale champagne and a bright sweep would wash the letters out, so
    /// the light version is deeper gold with a softer band.
    private var isLight: Bool { base == nil && colorScheme == .light }

    private var colors: [Color] {
        if let base { return base }
        return isLight
            ? [Color(hex: 0x8E6C3A), Color(hex: 0xC9A96A), Color(hex: 0x9C7A47)]
            : [Color(hex: 0xA9864E), Color(hex: 0xE6CF9A), Color(hex: 0xB89360)]
    }

    func body(content: Content) -> some View {
        content
            .hidden()
            .overlay {
                GeometryReader { proxy in
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                        let t = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.5) / 4.5
                        let width = proxy.size.width
                        ZStack {
                            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0), location: 0),
                                    .init(color: .white.opacity(isLight ? 0.3 : 0.7), location: 0.5),
                                    .init(color: .white.opacity(0), location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: max(width * 0.3, 60), height: proxy.size.height * 2)
                            .rotationEffect(.degrees(18))
                            .offset(x: -width * 0.8 + width * 1.6 * t)
                            .blendMode(.plusLighter)
                        }
                        .frame(width: width, height: proxy.size.height)
                        .compositingGroup()
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func milniFoil() -> some View { modifier(MilniFoil()) }
}

// MARK: - Rings

/// Two interlocking rings that draw themselves; the brand mark.
struct MilniRings: View {
    var color: Color = Milni.champagne
    var lineWidth: CGFloat = 1
    var duration: Double = 2.2
    var showsOuter = true
    var breathes = true
    var delay: Double = 0
    /// The faint outer halo, faded out as the splash dawns into the intro.
    var haloOpacity: Double = 1

    @State private var first: CGFloat = 0
    @State private var second: CGFloat = 0
    @State private var outer: CGFloat = 0
    @State private var breath = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ring = size * 0.5
            ZStack {
                if showsOuter {
                    Circle()
                        .trim(from: 0, to: outer)
                        .stroke(color.opacity(0.35), lineWidth: lineWidth)
                        .frame(width: size * 0.96, height: size * 0.96)
                        .rotationEffect(.degrees(-90))
                        .opacity(haloOpacity)
                }
                Circle()
                    .trim(from: 0, to: first)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: ring, height: ring)
                    .rotationEffect(.degrees(-90))
                    .offset(x: -ring * 0.2)
                Circle()
                    .trim(from: 0, to: second)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: ring, height: ring)
                    .rotationEffect(.degrees(90))
                    .offset(x: ring * 0.2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(breath ? 1.04 : 1)
        }
        .accessibilityHidden(true)
        .onAppear(perform: start)
    }

    private func start() {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.6).delay(delay)) {
                first = 1; second = 1; outer = 1
            }
            return
        }
        withAnimation(.easeInOut(duration: duration).delay(delay)) { first = 1 }
        withAnimation(.easeInOut(duration: duration).delay(delay + 0.35)) { second = 1 }
        withAnimation(.easeInOut(duration: duration * 1.2).delay(delay + 0.2)) { outer = 1 }
        if breathes {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(delay + duration)) {
                breath = true
            }
        }
    }
}

// MARK: - Sheen

/// A soft diagonal light that sweeps across a surface every few seconds.
struct MilniSheen: ViewModifier {
    var period: Double = 3
    var intensity: Double = 0.22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { proxy in
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let raw = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                        // Sweep during the first 45% of each period, then rest.
                        let t = min(raw / 0.45, 1)
                        let width = proxy.size.width
                        LinearGradient(
                            colors: [.clear, .white.opacity(intensity), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.45, height: proxy.size.height * 2)
                        .rotationEffect(.degrees(22))
                        .offset(x: -width * 0.7 + width * 1.9 * t, y: -proxy.size.height * 0.5)
                    }
                }
                .allowsHitTesting(false)
                .blendMode(.plusLighter)
            }
        }
    }
}

extension View {
    func milniSheen(period: Double = 3, intensity: Double = 0.22) -> some View {
        modifier(MilniSheen(period: period, intensity: intensity))
    }
}

// MARK: - Specks

/// Gold specks drifting slowly upward, like dust in candlelight.
struct MilniSpecks: View {
    var count = 16
    var color: Color = Milni.champagne
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Speck {
        let x: Double
        let size: Double
        let period: Double
        let phase: Double
        let sway: Double
        let opacity: Double
    }

    private let specks: [Speck]

    init(count: Int = 16, color: Color = Milni.champagne) {
        self.count = count
        self.color = color
        var generator = SeededGenerator(seed: 7)
        specks = (0..<count).map { _ in
            Speck(
                x: Double.random(in: 0.04...0.96, using: &generator),
                size: Double.random(in: 1.5...3.5, using: &generator),
                period: Double.random(in: 7...12, using: &generator),
                phase: Double.random(in: 0...1, using: &generator),
                sway: Double.random(in: 6...18, using: &generator),
                opacity: Double.random(in: 0.35...0.9, using: &generator)
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            Canvas { canvas, size in
                let now = context.date.timeIntervalSinceReferenceDate
                for speck in specks {
                    let progress = (now / speck.period + speck.phase).truncatingRemainder(dividingBy: 1)
                    let y = size.height * (1.05 - progress * 1.1)
                    let x = size.width * speck.x + sin(progress * .pi * 2) * speck.sway
                    let fade = sin(progress * .pi)
                    let rect = CGRect(x: x, y: y, width: speck.size, height: speck.size)
                    canvas.opacity = speck.opacity * fade
                    canvas.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Small deterministic generator so the specks land in the same places every time.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Shake

struct MilniShake: GeometryEffect {
    var travel: CGFloat = 9
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes * 2), y: 0))
    }
}

// MARK: - Monogram

/// The couple's initials inside a thin double ring.
struct MilniMonogram: View {
    let initials: String
    var size: CGFloat = 32
    var ring: Color = Milni.gold
    var foil = false
    var textColor: Color = Milni.ink

    var body: some View {
        ZStack {
            Circle().strokeBorder(ring.opacity(0.9), lineWidth: 0.8)
            Circle().strokeBorder(ring.opacity(0.4), lineWidth: 0.6).padding(size * 0.07)
            Group {
                if foil {
                    Text(initials).milniFoil()
                } else {
                    Text(initials).foregroundStyle(textColor)
                }
            }
            .font(Milni.cormorant(size * 0.36, weight: 500, italic: true))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
