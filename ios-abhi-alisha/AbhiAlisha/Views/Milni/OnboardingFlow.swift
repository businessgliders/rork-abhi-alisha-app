import SwiftUI

/// Everything before a wedding opens: splash, intro, choosing a path, joining by code
/// and creating a wedding. Each step slides in from the side it belongs to.
struct OnboardingFlow: View {
    enum Step: Hashable {
        case splash
        case intro
        case choose
        case code(prefill: String?)
        case invitation(WeddingSummary, code: String)
        case name(WeddingSummary, code: String)
        case welcome(WeddingSummary, firstName: String)
        case coupleSignIn
        case coupleNames
        case coupleDates
        case coupleMood
        case coupleReady(WeddingSummary)

        /// Order used to decide which way a step slides.
        var depth: Int {
            switch self {
            case .splash: return 0
            case .intro: return 1
            case .choose: return 2
            case .code: return 3
            case .invitation: return 4
            case .name: return 5
            case .welcome: return 6
            case .coupleSignIn: return 3
            case .coupleNames: return 4
            case .coupleDates: return 5
            case .coupleMood: return 6
            case .coupleReady: return 7
            }
        }
    }

    /// Where to start; nil follows the context's onboarding entry.
    var entry: WeddingContext.OnboardingEntry? = nil
    /// Set when shown as a cover from inside a wedding: backing out or finishing closes it.
    var close: (() -> Void)? = nil

    private let context = WeddingContext.shared
    private let session = ChatSession.shared

    @State private var step: Step
    @State private var forward = true
    @State private var draft = CoupleDraft()
    /// The splash has dawned to ivory: the status bar turns dark to match.
    @State private var dawnLit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(entry: WeddingContext.OnboardingEntry? = nil, close: (() -> Void)? = nil) {
        self.entry = entry
        self.close = close
        // A cover opens straight on its own step, never flashing the splash first.
        switch entry {
        case .joinCode: _step = State(initialValue: .code(prefill: nil))
        case .choose: _step = State(initialValue: .choose)
        default: _step = State(initialValue: .splash)
        }
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            screen
                .id(step)
                .transition(transition)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.4) : .spring(response: 0.7, dampingFraction: 0.92), value: step)
        .preferredColorScheme(step.prefersDark && !(step == .splash && dawnLit) ? .dark : .light)
        .onAppear(perform: startStep)
        .onChange(of: context.pendingJoinCode) { _, code in
            guard let code else { return }
            context.pendingJoinCode = nil
            go(.code(prefill: code))
        }
    }

    private var background: Color {
        switch step {
        case .splash, .welcome, .coupleReady: return Milni.midnight
        case .invitation: return Milni.stone
        default: return Milni.ivory
        }
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        let insertion: AnyTransition = .opacity.combined(with: .offset(x: forward ? 40 : -40))
        let removal: AnyTransition = .opacity.combined(with: .offset(x: forward ? -40 : 40))
        return .asymmetric(insertion: insertion, removal: removal)
    }

    private func startStep() {
        if let code = context.pendingJoinCode {
            context.pendingJoinCode = nil
            step = .code(prefill: code)
            return
        }
        switch entry ?? context.onboardingEntry {
        case .splash: step = .splash
        case .choose: step = .choose
        case .joinCode: step = .code(prefill: nil)
        case .create: step = coupleStart
        }
    }

    private var coupleStart: Step {
        session.isSignedIn && !session.isAnonymous ? .coupleNames : .coupleSignIn
    }

    /// Back to the start: the choose screen, or out of the cover.
    private func backToStart() {
        if let close { close() } else { go(.choose) }
    }

    private func finish() {
        context.enterPending()
        close?()
    }

    private func go(_ next: Step) {
        forward = next.depth >= step.depth
        step = next
    }

    @ViewBuilder
    private var screen: some View {
        switch step {
        case .splash:
            if context.hasSeenIntro {
                MilniSplashView(advances: true) {
                    go(.choose)
                }
            } else {
                // First open: the midnight splash dawns into the intro in one scene.
                MilniDawnIntro(onLit: { dawnLit = $0 }) {
                    context.hasSeenIntro = true
                    go(.choose)
                }
            }
        case .intro:
            MilniIntroView {
                context.hasSeenIntro = true
                go(.choose)
            }
        case .choose:
            MilniChooseView(
                canGoBack: context.onboardingEntry != .splash,
                back: { context.returnToWedding() },
                join: { go(.code(prefill: nil)) },
                create: { go(coupleStart) },
                sample: { Task { await context.openSample() } }
            )
        case .code(let prefill):
            MilniCodeEntryView(prefill: prefill, back: backToStart) { summary, code in
                go(.invitation(summary, code: code))
            }
        case .invitation(let summary, let code):
            MilniInvitationView(summary: summary, back: { go(.code(prefill: code)) }) {
                accept(summary, code: code)
            }
        case .name(let summary, let code):
            MilniNameView(summary: summary, back: { go(.invitation(summary, code: code)) }) { name in
                try await joinAsGuest(name: name, summary: summary, code: code)
            }
        case .welcome(let summary, let firstName):
            MilniWelcomeView(summary: summary, firstName: firstName) {
                finish()
            }
        case .coupleSignIn:
            MilniCoupleSignInView(back: backToStart) {
                go(.coupleNames)
            }
        case .coupleNames:
            MilniCoupleNamesView(draft: $draft, back: backToStart) {
                go(.coupleDates)
            }
        case .coupleDates:
            MilniCoupleDatesView(draft: $draft, back: { go(.coupleNames) }) {
                go(.coupleMood)
            }
        case .coupleMood:
            MilniMoodView(draft: $draft, back: { go(.coupleDates) }) { summary in
                go(.coupleReady(summary))
            }
        case .coupleReady(let summary):
            MilniReadyView(summary: summary) {
                finish()
            }
        }
    }

    // MARK: - Joining

    private func accept(_ summary: WeddingSummary, code: String) {
        // Already a member: just open it.
        if let known = context.myWeddings.first(where: { $0.id.lowercased() == summary.id.lowercased() }) {
            context.switchTo(known)
            close?()
            return
        }
        if session.isSignedIn {
            Task {
                do {
                    try await context.join(code: code, preview: summary)
                    go(.welcome(context.pendingSummary ?? summary, firstName: firstName(session.me?.displayName)))
                } catch {
                    go(.name(summary, code: code))
                }
            }
        } else {
            go(.name(summary, code: code))
        }
    }

    private func joinAsGuest(name: String, summary: WeddingSummary, code: String) async throws {
        if !session.isSignedIn {
            guard await session.joinAsGuest(name: name) else { throw MilniError.failed }
        } else {
            _ = await session.saveName(name)
        }
        try await context.join(code: code, preview: summary)
        go(.welcome(context.pendingSummary ?? summary, firstName: firstName(name)))
    }

    private func firstName(_ name: String?) -> String {
        let clean = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.split(separator: " ").first.map(String.init) ?? "friend"
    }
}

private extension OnboardingFlow.Step {
    var prefersDark: Bool {
        switch self {
        case .splash, .welcome, .coupleReady: return true
        default: return false
        }
    }
}

/// The couple's answers while they create their wedding.
struct CoupleDraft: Equatable {
    var partnerOne = ""
    var partnerTwo = ""
    var start: Date = Calendar.current.startOfDay(for: Date().addingTimeInterval(60 * 60 * 24 * 180))
    var end: Date = Calendar.current.startOfDay(for: Date().addingTimeInterval(60 * 60 * 24 * 183))
    var preset = "ivory"

    var namesReady: Bool {
        !partnerOne.trimmingCharacters(in: .whitespaces).isEmpty
            && !partnerTwo.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Splash

struct MilniSplashView: View {
    var advances = false
    var done: () -> Void = {}

    @State private var showWord = false
    @State private var showTagline = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Milni.midnight.ignoresSafeArea()
            RadialGradient(
                colors: [Color(hex: 0x2A3150), Milni.midnight],
                center: .center,
                startRadius: 10,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                MilniRings(color: Milni.champagne, lineWidth: 1)
                    .frame(width: 150, height: 150)

                VStack(spacing: 14) {
                    Text("Milni")
                        .font(Milni.cormorant(58, weight: 400))
                        .milniFoil()
                        .opacity(showWord ? 1 : 0)
                        .blur(radius: showWord || reduceMotion ? 0 : 8)
                        .offset(y: showWord || reduceMotion ? 0 : 10)
                    Text("WHERE FAMILIES MEET")
                        .font(Milni.inter(11, weight: 600))
                        .tracking(3.2)
                        .foregroundStyle(Milni.champagneLight)
                        .opacity(showTagline ? 1 : 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Milni. Where families meet.")
            }
        }
        .task {
            withAnimation(.easeOut(duration: 1.1).delay(0.9)) { showWord = true }
            withAnimation(.easeOut(duration: 0.9).delay(1.6)) { showTagline = true }
            guard advances else { return }
            try? await Task.sleep(for: .seconds(3))
            // A cancelled sleep returns at once; never advance a splash that has left.
            guard !Task.isCancelled else { return }
            done()
        }
    }
}

// MARK: - Intro

struct MilniIntroView: View {
    let finish: () -> Void
    /// Arriving from the splash's dawn: the brand mark and the first chapter's rings are
    /// drawn by the dawn itself, and everything else waits for `revealed`.
    var isDawn = false
    var revealed = true
    var onChapter: (Int) -> Void = { _ in }

    private struct Chapter {
        let number: String
        let title: String
        let body: String
    }

    private let chapters = [
        Chapter(number: "ONE", title: "Every ceremony, gracefully in order.",
                body: "Mehndi to reception: times, places, directions and the weather, always one glance away."),
        Chapter(number: "TWO", title: "Dressed for every event.",
                body: "See each dress code and plan your outfits, jewellery and shoes, event by event."),
        Chapter(number: "THREE", title: "The whole family, together.",
                body: "Announcements, chat and Wedding Week photos, shared only with the people who belong."),
    ]

    @State private var index = 0
    @State private var cycle = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if isDawn {
                    // The splash's foil wordmark lands here.
                    Color.clear
                        .frame(width: 56, height: 28)
                        .anchorPreference(key: DawnAnchorKey.self, value: .bounds) { ["brand": $0] }
                        .accessibilityElement()
                        .accessibilityLabel("Milni")
                } else {
                    Text("MILNI")
                        .font(Milni.inter(12, weight: 600))
                        .tracking(3.4)
                        .foregroundStyle(Milni.ink)
                }
                Spacer()
                Button("Skip") {
                    BrandHaptics.tick()
                    finish()
                }
                .font(Milni.inter(14, weight: 500))
                .foregroundStyle(Milni.goldText)
                .frame(minWidth: 44, minHeight: 44)
                .opacity(revealed ? 1 : 0)
                .animation(.easeOut(duration: 0.7).delay(isDawn ? 1.8 : 0), value: revealed)
                .disabled(!revealed)
            }
            .milniSides()
            .padding(.top, 6)

            Spacer(minLength: 12)

            ZStack {
                if revealed {
                    IntroDrawing(chapter: index, isDawn: isDawn)
                        .id(index)
                        .transition(.opacity)
                }
            }
            .frame(width: 220, height: 220)
            .anchorPreference(key: DawnAnchorKey.self, value: .bounds) { ["drawing": $0] }

            Spacer(minLength: 12)

            ZStack(alignment: .topLeading) {
                if revealed {
                    VStack(alignment: .leading, spacing: 16) {
                        MilniLabel(chapters[index].number)
                            .milniEntrance(0, delay: textDelay)
                        Text(chapters[index].title)
                            .font(Milni.cormorant(40))
                            .foregroundStyle(Milni.ink)
                            .lineSpacing(-4)
                            .fixedSize(horizontal: false, vertical: true)
                            .milniEntrance(1, delay: textDelay)
                        MilniBody(chapters[index].body)
                            .milniEntrance(2, delay: textDelay)
                    }
                    .id("text-\(index)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .milniSides()
            .frame(minHeight: 230, alignment: .top)

            HStack {
                HStack(spacing: 6) {
                    ForEach(chapters.indices, id: \.self) { item in
                        Capsule()
                            .fill(item == index ? Milni.ink : Milni.hairline)
                            .frame(width: item == index ? 28 : 10, height: 2)
                    }
                }
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: index)
                .accessibilityElement()
                .accessibilityLabel("Page \(index + 1) of \(chapters.count)")

                Spacer()

                Button(action: advance) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Milni.ivory)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Milni.ink))
                }
                .buttonStyle(MilniPressStyle())
                .accessibilityLabel(index == chapters.count - 1 ? "Get started" : "Next")
            }
            .milniSides()
            .padding(.bottom, 20)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 18)
            .animation(Milni.entrance.delay(isDawn ? textDelay + 0.5 : 0), value: revealed)
            .allowsHitTesting(revealed)
        }
        .background((isDawn ? Color.clear : Milni.ivory).ignoresSafeArea())
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard revealed else { return }
                if value.translation.width < -40 { advance() }
                if value.translation.width > 40, index > 0 { move(to: index - 1) }
            }
        )
        .task(id: revealed ? cycle : -1) {
            guard revealed else { return }
            let firstDawn = isDawn && index == 0 && cycle == 0
            try? await Task.sleep(for: .seconds(firstDawn ? 5.6 : 4.2))
            guard !Task.isCancelled else { return }
            if index < chapters.count - 1 { move(to: index + 1) }
        }
        .onChange(of: index) { _, next in onChapter(next) }
    }

    /// After the dawn, the words wait for the mandap's arch to draw first.
    private var textDelay: Double {
        isDawn && index == 0 && cycle == 0 ? 1.3 : 0
    }

    private func advance() {
        BrandHaptics.tick()
        if index == chapters.count - 1 {
            finish()
        } else {
            move(to: index + 1)
        }
    }

    private func move(to next: Int) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.4) : .easeInOut(duration: 0.5)) { index = next }
        cycle += 1
    }
}

/// The chapter's line drawing, drawing itself in gold.
private struct IntroDrawing: View {
    let chapter: Int
    /// After the dawn the hairline circle stays away: the splash's rings sit in its place.
    var isDawn = false
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !(isDawn && chapter == 0) {
                Circle()
                    .stroke(Milni.hairline.opacity(0.6), lineWidth: 0.6)
            }
            shape
                .trim(from: 0, to: progress)
                .stroke(Milni.gold, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                .padding(34)
        }
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.4) : .easeInOut(duration: 2.4)) { progress = 1 }
        }
    }

    private var shape: AnyShape {
        switch chapter {
        case 0: return AnyShape(MandapShape())
        case 1: return AnyShape(DrapeShape())
        default: return AnyShape(FamilyCirclesShape())
        }
    }
}

/// Three arches on slender pillars under a domed canopy.
struct MandapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let x = rect.minX, y = rect.minY
        let base = y + h * 0.95
        let springY = y + h * 0.5
        let pillars: [CGFloat] = [0.06, 0.36, 0.64, 0.94]

        // Canopy dome and finial.
        path.move(to: CGPoint(x: x + w * 0.02, y: y + h * 0.32))
        path.addQuadCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.06), control: CGPoint(x: x + w * 0.18, y: y + h * 0.08))
        path.addQuadCurve(to: CGPoint(x: x + w * 0.98, y: y + h * 0.32), control: CGPoint(x: x + w * 0.82, y: y + h * 0.08))
        path.addLine(to: CGPoint(x: x + w * 0.02, y: y + h * 0.32))
        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.06))
        path.addLine(to: CGPoint(x: x + w * 0.5, y: y))

        // Pillars.
        for p in pillars {
            path.move(to: CGPoint(x: x + w * p, y: y + h * 0.32))
            path.addLine(to: CGPoint(x: x + w * p, y: base))
        }
        // Pointed arches between pillars.
        for i in 0..<3 {
            let left = x + w * pillars[i] , right = x + w * pillars[i + 1]
            let mid = (left + right) / 2
            path.move(to: CGPoint(x: left, y: springY))
            path.addQuadCurve(to: CGPoint(x: mid, y: y + h * 0.37), control: CGPoint(x: left, y: y + h * 0.38))
            path.addQuadCurve(to: CGPoint(x: right, y: springY), control: CGPoint(x: right, y: y + h * 0.38))
        }
        // Garland swag and floor.
        path.move(to: CGPoint(x: x + w * 0.06, y: y + h * 0.36))
        path.addQuadCurve(to: CGPoint(x: x + w * 0.94, y: y + h * 0.36), control: CGPoint(x: x + w * 0.5, y: y + h * 0.48))
        path.move(to: CGPoint(x: x - w * 0.02, y: base))
        path.addLine(to: CGPoint(x: x + w * 1.02, y: base))
        return path
    }
}

/// A draped lehenga silhouette: dupatta over one shoulder, a flared, pleated skirt.
struct DrapeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func p(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: rect.minX + w * px, y: rect.minY + h * py) }

        // Hanger hook and bar.
        path.move(to: p(0.5, 0.0))
        path.addQuadCurve(to: p(0.5, 0.08), control: p(0.58, 0.03))
        path.move(to: p(0.3, 0.12))
        path.addLine(to: p(0.5, 0.08))
        path.addLine(to: p(0.7, 0.12))

        // Bodice.
        path.move(to: p(0.36, 0.13))
        path.addQuadCurve(to: p(0.5, 0.21), control: p(0.42, 0.2))
        path.addQuadCurve(to: p(0.64, 0.13), control: p(0.58, 0.2))
        path.move(to: p(0.36, 0.13))
        path.addLine(to: p(0.38, 0.36))
        path.addLine(to: p(0.62, 0.36))
        path.addLine(to: p(0.64, 0.13))

        // Skirt.
        path.move(to: p(0.38, 0.36))
        path.addQuadCurve(to: p(0.08, 0.96), control: p(0.2, 0.62))
        path.addQuadCurve(to: p(0.92, 0.96), control: p(0.5, 1.02))
        path.addQuadCurve(to: p(0.62, 0.36), control: p(0.8, 0.62))
        // Pleats.
        for (top, bottom) in [(0.44, 0.3), (0.5, 0.5), (0.56, 0.7)] {
            path.move(to: p(top, 0.38))
            path.addQuadCurve(to: p(bottom, 0.97), control: p((top + bottom) / 2 + 0.02, 0.7))
        }
        // Dupatta falling from the shoulder.
        path.move(to: p(0.64, 0.13))
        path.addQuadCurve(to: p(0.86, 0.5), control: p(0.86, 0.22))
        path.addQuadCurve(to: p(0.78, 0.78), control: p(0.9, 0.66))
        // Border dots along the hem.
        path.move(to: p(0.12, 0.9))
        path.addQuadCurve(to: p(0.88, 0.9), control: p(0.5, 0.96))
        return path
    }
}

/// Three overlapping circles: families meeting.
struct FamilyCirclesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height) * 0.3
        let cx = rect.midX, cy = rect.midY
        let centres = [
            CGPoint(x: cx, y: cy - r * 0.62),
            CGPoint(x: cx - r * 0.66, y: cy + r * 0.48),
            CGPoint(x: cx + r * 0.66, y: cy + r * 0.48),
        ]
        for centre in centres {
            path.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
        }
        path.addEllipse(in: CGRect(x: cx - 3, y: cy - 3 + r * 0.1, width: 6, height: 6))
        return path
    }
}

// MARK: - Choose

struct MilniChooseView: View {
    var canGoBack = false
    var back: () -> Void = {}
    let join: () -> Void
    let create: () -> Void
    let sample: () -> Void

    @State private var openingSample = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if canGoBack {
                    MilniBackButton(action: back)
                        .padding(.leading, -12)
                }
                Spacer()
            }
            .frame(height: 44)

            Spacer(minLength: 20)

            MilniRings(color: Milni.gold, lineWidth: 1, duration: 1.6, showsOuter: false, breathes: false)
                .frame(width: 64, height: 64)
                .padding(.leading, -8)
                .milniEntrance(0)

            MilniHeadline(first: "Welcome", second: "to the wedding week.", size: 46)
                .padding(.top, 26)
                .milniEntrance(1)

            MilniBody("Every ceremony, outfit, photo and message, beautifully kept in one place.")
                .padding(.top, 18)
                .milniEntrance(2)

            Spacer(minLength: 32)

            VStack(spacing: 12) {
                Button("I'm a guest — join a wedding") {
                    BrandHaptics.tick()
                    join()
                }
                .buttonStyle(.milniPrimary)
                .milniEntrance(3)

                Button("We're getting married") {
                    BrandHaptics.tick()
                    create()
                }
                .buttonStyle(.milniSecondary)
                .milniEntrance(4)

                Button {
                    BrandHaptics.tick()
                    openingSample = true
                    sample()
                } label: {
                    if openingSample {
                        ProgressView().tint(Milni.goldText)
                    } else {
                        Text("Explore a sample wedding")
                    }
                }
                .buttonStyle(.milniTertiary)
                .disabled(openingSample)
                .milniEntrance(5)
            }
            .padding(.bottom, 12)
        }
        .milniSides()
        .background(Milni.ivory.ignoresSafeArea())
    }
}
