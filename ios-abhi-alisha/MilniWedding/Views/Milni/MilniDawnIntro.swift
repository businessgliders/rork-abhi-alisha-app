import SwiftUI

/// Where the splash's marks sit, and where the intro wants them: read by the dawn so the
/// rings and the wordmark travel between the two real layouts rather than guessed points.
struct DawnAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The first open, as one continuous scene.
///
/// 0–3.0s: the midnight splash (rings draw, foil "Milni", "WHERE FAMILIES MEET").
/// 3.0s: a champagne glow blooms from the rings' centre while an ivory, soft-edged circle
/// grows behind it to fill the screen; the midnight is never cut. The rings shrink, float
/// up and deepen to gold, their halo fading; the wordmark glides to the top-left and
/// becomes the intro's brand mark, still in foil, and the tagline fades.
/// 4.5s: the mandap's arch draws over the rings, then its ground line, then the first
/// chapter's words, the progress dashes and the arrow rise in, and "Skip" appears.
/// Reduce Motion: a simple cross-fade from the splash to the intro.
struct MilniDawnIntro: View {
    /// The ivory has taken the screen (true), so the status bar can turn dark.
    var onLit: (Bool) -> Void = { _ in }
    let finish: () -> Void

    @State private var showWord = false
    @State private var showTagline = false
    @State private var dawn = false
    @State private var glow = false
    @State private var glowFade = false
    @State private var revealed = false
    @State private var chapter = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// cubic-bezier(.7, 0, .2, 1) over 1.7s.
    private static let dawnCurve = Animation.timingCurve(0.7, 0, 0.2, 1, duration: 1.7)
    private static let glowColor = Color(hex: 0xE9C98F)
    /// The wordmark's size as the intro's brand mark (58pt → about 23pt).
    private static let brandScale: CGFloat = 0.4

    var body: some View {
        if reduceMotion {
            reduced
        } else {
            scene
        }
    }

    // MARK: - Reduce Motion

    private var reduced: some View {
        ZStack {
            if revealed {
                MilniIntroView(finish: finish)
                    .transition(.opacity)
            } else {
                MilniSplashView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            onLit(true)
            withAnimation(.easeInOut(duration: 0.6)) { revealed = true }
        }
    }

    // MARK: - The dawn

    private var scene: some View {
        ZStack {
            splashLayout
            MilniIntroView(
                finish: finish,
                isDawn: true,
                revealed: revealed,
                onChapter: { next in
                    withAnimation(.easeInOut(duration: 0.5)) { chapter = next }
                }
            )
        }
        // Light and marks sit under the intro, so the mandap draws over the rings.
        .backgroundPreferenceValue(DawnAnchorKey.self) { anchors in
            GeometryReader { proxy in
                light(anchors, in: proxy)
                marks(anchors, in: proxy)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .background {
            ZStack {
                Milni.midnight
                RadialGradient(
                    colors: [Color(hex: 0x2A3150), Milni.midnight],
                    center: .center,
                    startRadius: 10,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        }
        .task { await run() }
    }

    /// Mirrors the splash: only the tagline is drawn here; the rings and wordmark are
    /// placeholders the travelling marks start from.
    private var splashLayout: some View {
        VStack(spacing: 28) {
            Color.clear
                .frame(width: 150, height: 150)
                .anchorPreference(key: DawnAnchorKey.self, value: .bounds) { ["rings": $0] }

            VStack(spacing: 14) {
                Text("Milni")
                    .font(Milni.cormorant(58, weight: 400))
                    .hidden()
                    .anchorPreference(key: DawnAnchorKey.self, value: .bounds) { ["word": $0] }
                Text("WHERE FAMILIES MEET")
                    .font(Milni.inter(11, weight: 600))
                    .tracking(3.2)
                    .foregroundStyle(Milni.champagneLight)
                    .opacity(showTagline && !dawn ? 1 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Milni. Where families meet.")
        .accessibilityHidden(revealed)
        .allowsHitTesting(false)
    }

    /// The ivory circle, and the champagne glow blooming in front of it.
    @ViewBuilder
    private func light(_ anchors: [String: Anchor<CGRect>], in proxy: GeometryProxy) -> some View {
        let rings = anchors["rings"].map { proxy[$0] } ?? CGRect(origin: .zero, size: proxy.size)
        let centre = CGPoint(x: rings.midX, y: rings.midY)
        let reach = hypot(
            max(centre.x, proxy.size.width - centre.x),
            max(centre.y, proxy.size.height - centre.y)
        )
        let diameter = reach * 2 + 160

        Circle()
            .fill(Milni.ivory)
            .frame(width: diameter, height: diameter)
            .blur(radius: 36)
            .scaleEffect(dawn ? 1 : 0.001)
            .position(centre)

        Circle()
            .fill(
                RadialGradient(
                    colors: [Self.glowColor, Self.glowColor.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 230
                )
            )
            .frame(width: 460, height: 460)
            .scaleEffect(glow ? 1.7 : 0.15)
            .opacity(glowFade ? 0 : (glow ? 0.95 : 0))
            .position(centre)
    }

    /// The rings and the wordmark, travelling from the splash to the intro.
    @ViewBuilder
    private func marks(_ anchors: [String: Anchor<CGRect>], in proxy: GeometryProxy) -> some View {
        let rings = anchors["rings"].map { proxy[$0] } ?? .zero
        let drawing = anchors["drawing"].map { proxy[$0] } ?? rings
        let word = anchors["word"].map { proxy[$0] } ?? .zero
        let brand = anchors["brand"].map { proxy[$0] } ?? word

        // Under the mandap's canopy, between its arches and its ground line.
        let ringsTarget = CGPoint(x: drawing.midX, y: drawing.midY + 14)
        let wordTarget = CGPoint(x: brand.minX + word.width * Self.brandScale / 2, y: brand.midY)

        MilniRings(
            color: dawn ? Milni.gold : Milni.champagne,
            lineWidth: 1,
            haloOpacity: dawn ? 0 : 1
        )
        .frame(width: max(rings.width, 1), height: max(rings.height, 1))
        .scaleEffect(dawn ? 0.62 : 1)
        .position(dawn ? ringsTarget : CGPoint(x: rings.midX, y: rings.midY))
        .opacity(chapter == 0 ? 1 : 0)

        Text("Milni")
            .font(Milni.cormorant(58, weight: 400))
            .fixedSize()
            .milniFoil()
            .opacity(showWord ? 1 : 0)
            .blur(radius: showWord ? 0 : 8)
            .scaleEffect(dawn ? Self.brandScale : 1)
            .position(dawn ? wordTarget : CGPoint(x: word.midX, y: word.midY + (showWord ? 0 : 10)))
    }

    private func run() async {
        withAnimation(.easeOut(duration: 1.1).delay(0.9)) { showWord = true }
        withAnimation(.easeOut(duration: 0.9).delay(1.6)) { showTagline = true }

        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 1.1)) { glow = true }
        withAnimation(Self.dawnCurve) { dawn = true }

        try? await Task.sleep(for: .seconds(0.8))
        guard !Task.isCancelled else { return }
        onLit(true)
        withAnimation(.easeIn(duration: 0.9)) { glowFade = true }

        try? await Task.sleep(for: .seconds(0.7))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.4)) { revealed = true }
    }
}
