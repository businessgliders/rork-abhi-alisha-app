import AuthenticationServices
import SwiftUI

// MARK: - Sign in

/// Couples sign in with Apple first, so the wedding always has a real owner.
struct MilniCoupleSignInView: View {
    let back: () -> Void
    let signedIn: () -> Void

    private let session = ChatSession.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MilniBackButton(action: back).padding(.leading, -12)

            Spacer(minLength: 20)

            MilniRings(color: Milni.gold, lineWidth: 1, duration: 1.6, showsOuter: false, breathes: false)
                .frame(width: 64, height: 64)
                .padding(.leading, -8)
                .milniEntrance(0)

            MilniLabel("For the couple")
                .padding(.top, 26)
                .milniEntrance(1)
            MilniHeadline(first: "First, a quick", second: "sign in.", size: 44)
                .padding(.top, 12)
                .milniEntrance(2)
            MilniBody("Sign in with Apple to create a wedding. It keeps your wedding safe, and lets you invite family and manage guests from any device.")
                .padding(.top, 16)
                .milniEntrance(3)

            Spacer(minLength: 32)

            if let error = session.signInError {
                Text(error)
                    .font(Milni.inter(14))
                    .foregroundStyle(Color(hex: 0x9A3B2E))
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }

            SignInWithAppleButton(.continue) { request in
                session.prepare(request)
            } onCompletion: { result in
                Task { await session.complete(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 56)
            .clipShape(Capsule())
            .opacity(session.isSigningIn ? 0.5 : 1)
            .disabled(session.isSigningIn)
            .padding(.bottom, 8)
            .milniEntrance(4)
        }
        .milniSides()
        .background(Milni.ivory.ignoresSafeArea())
        .onChange(of: session.isSignedIn && !session.isAnonymous && !session.isSigningIn) { _, ready in
            if ready { signedIn() }
        }
        .onAppear {
            if session.isSignedIn && !session.isAnonymous { signedIn() }
        }
    }
}

// MARK: - Step one: names

struct MilniCoupleNamesView: View {
    @Binding var draft: CoupleDraft
    let back: () -> Void
    let next: () -> Void

    @FocusState private var field: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MilniBackButton(action: back).padding(.leading, -12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MilniLabel("Step one of four")
                        .padding(.top, 20)
                        .milniEntrance(0)
                    MilniHeadline(first: "Congratulations.", second: "Who's getting married?", size: 42)
                        .padding(.top, 12)
                        .milniEntrance(1)

                    MilniUnderlineField(label: "Partner one", text: $draft.partnerOne, placeholder: "Name") {
                        field = 2
                    }
                    .focused($field, equals: 1)
                    .padding(.top, 44)
                    .milniEntrance(2)

                    Text("&")
                        .font(Milni.cormorant(34, italic: true))
                        .foregroundStyle(Milni.gold)
                        .padding(.top, 18)
                        .milniEntrance(3)

                    MilniUnderlineField(label: "Partner two", text: $draft.partnerTwo, placeholder: "Name") {
                        if draft.namesReady { advance() }
                    }
                    .focused($field, equals: 2)
                    .padding(.top, 10)
                    .milniEntrance(4)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)

            Button("Continue", action: advance)
                .buttonStyle(.milniPrimary)
                .disabled(!draft.namesReady)
                .padding(.vertical, 8)
        }
        .milniSides()
        .background(Milni.ivory.ignoresSafeArea())
        .onAppear {
            if draft.partnerOne.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { field = 1 }
            }
        }
    }

    private func advance() {
        guard draft.namesReady else { return }
        BrandHaptics.tick()
        draft.partnerOne = draft.partnerOne.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.partnerTwo = draft.partnerTwo.trimmingCharacters(in: .whitespacesAndNewlines)
        field = nil
        next()
    }
}

// MARK: - Step two: dates

struct MilniCoupleDatesView: View {
    @Binding var draft: CoupleDraft
    let back: () -> Void
    let next: () -> Void

    @State private var editing: Edge = .start

    enum Edge { case start, end }

    private var today: Date { Calendar.current.startOfDay(for: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MilniBackButton(action: back).padding(.leading, -12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MilniLabel("Step one of four")
                        .padding(.top, 20)
                        .milniEntrance(0)
                    MilniHeadline(first: "When is", second: "the wedding week?", size: 42)
                        .padding(.top, 12)
                        .milniEntrance(1)
                    MilniBody("From the first welcome to the last goodbye. You can change this later.")
                        .padding(.top, 14)
                        .milniEntrance(2)

                    HStack(spacing: 18) {
                        dateTile("First day", date: draft.start, edge: .start)
                        dateTile("Last day", date: draft.end, edge: .end)
                    }
                    .padding(.top, 30)
                    .milniEntrance(3)

                    DatePicker(
                        editing == .start ? "First day" : "Last day",
                        selection: editing == .start ? startBinding : endBinding,
                        in: (editing == .start ? today : draft.start)...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(Milni.goldText)
                    .labelsHidden()
                    .padding(.top, 14)
                    .id(editing)
                    .milniEntrance(4)

                    Text("\(nights) · times shown in \(TimeZone.current.localizedName(for: .generic, locale: .current) ?? TimeZone.current.identifier)")
                        .font(Milni.inter(12))
                        .foregroundStyle(Milni.muted)
                        .padding(.top, 4)
                }
            }
            .scrollIndicators(.hidden)

            Button("Continue") {
                BrandHaptics.tick()
                next()
            }
            .buttonStyle(.milniPrimary)
            .padding(.vertical, 8)
        }
        .milniSides()
        .background(Milni.ivory.ignoresSafeArea())
    }

    private var startBinding: Binding<Date> {
        Binding {
            draft.start
        } set: { value in
            let day = Calendar.current.startOfDay(for: value)
            let length = draft.end.timeIntervalSince(draft.start)
            draft.start = day
            if draft.end < day { draft.end = day.addingTimeInterval(max(length, 0)) }
            withAnimation(.calm) { editing = .end }
        }
    }

    private var endBinding: Binding<Date> {
        Binding {
            draft.end
        } set: { value in
            draft.end = max(Calendar.current.startOfDay(for: value), draft.start)
        }
    }

    private var nights: String {
        let days = (Calendar.current.dateComponents([.day], from: draft.start, to: draft.end).day ?? 0) + 1
        return days == 1 ? "1 day" : "\(days) days"
    }

    private func dateTile(_ label: String, date: Date, edge: Edge) -> some View {
        Button {
            BrandHaptics.tick()
            withAnimation(.calm) { editing = edge }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                MilniLabel(label, color: editing == edge ? Milni.goldText : Milni.muted)
                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(Milni.cormorant(30, weight: 500))
                    .foregroundStyle(Milni.ink)
                Text(date.formatted(.dateTime.weekday(.wide).year()))
                    .font(Milni.inter(12))
                    .foregroundStyle(Milni.muted)
                Rectangle()
                    .fill(editing == edge ? Milni.ink : Milni.hairline)
                    .frame(height: 1.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MilniPressStyle())
        .accessibilityLabel("\(label), \(date.formatted(date: .long, time: .omitted))")
        .accessibilityAddTraits(editing == edge ? .isSelected : [])
    }
}

// MARK: - Step three: mood

struct MilniMoodView: View {
    @Binding var draft: CoupleDraft
    let back: () -> Void
    let next: () -> Void

    private let names = ["ivory": "Ivory", "blush": "Blush", "emerald": "Emerald", "midnight": "Midnight"]

    private var theme: BrandThemeColors { BrandTheme.colors(for: draft.preset) }
    private var background: Color { Color(hex: theme.background) }
    private var ink: Color { Color(hex: theme.ink) }
    private var accentText: Color { Color(hex: theme.accentText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MilniBackButton(color: ink, action: back).padding(.leading, -12)

            MilniLabel("Step three of four", color: accentText)
                .padding(.top, 12)
                .milniEntrance(0)
            MilniHeadline(first: "Set the", second: "mood.", size: 42, color: ink, accent: accentText)
                .padding(.top, 10)
                .milniEntrance(1)

            GeometryReader { proxy in
                MilniInvitationCard(
                    partnerOne: draft.partnerOne,
                    partnerTwo: draft.partnerTwo,
                    detail: detail,
                    preset: draft.preset,
                    drawsRings: false
                )
                .scaleEffect(min(0.78, (proxy.size.height - 12) / 420, (proxy.size.width - 20) / 300))
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .milniEntrance(2)

            HStack(spacing: 0) {
                ForEach(BrandTheme.presetIDs, id: \.self) { preset in
                    swatch(preset)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 18)
            .milniEntrance(3)

            Button {
                BrandHaptics.soft()
                next()
            } label: {
                Text("Looks beautiful")
            }
            .buttonStyle(MilniButtonStyle(kind: .primary, ink: ink, paper: background))
            .padding(.bottom, 8)
            .milniEntrance(4)
        }
        .milniSides()
        .background(background.ignoresSafeArea())
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .animation(.easeInOut(duration: 0.8), value: draft.preset)
    }

    private var detail: String {
        let summary = WeddingSummary(row: [
            "id": "",
            "start_date": Self.day(draft.start),
            "end_date": Self.day(draft.end),
            "timezone": TimeZone.current.identifier,
        ])
        let dates = summary.dateRange ?? ""
        guard let city = draft.venue?.city, !city.isEmpty else { return dates }
        return dates.isEmpty ? city : "\(dates) · \(city)"
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func swatch(_ preset: String) -> some View {
        let colors = BrandTheme.colors(for: preset)
        let selected = draft.preset == preset
        return Button {
            BrandHaptics.tick()
            withAnimation(.easeInOut(duration: 0.8)) { draft.preset = preset }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(hex: colors.background))
                    Circle()
                        .trim(from: 0.5, to: 1)
                        .fill(Color(hex: colors.accent))
                        .rotationEffect(.degrees(-45))
                    Circle()
                        .strokeBorder(Color(hex: colors.ink).opacity(0.18), lineWidth: 0.8)
                }
                .frame(width: 46, height: 46)
                .padding(5)
                .overlay {
                    Circle()
                        .strokeBorder(ink, lineWidth: selected ? 1.2 : 0)
                }
                .scaleEffect(selected ? 1.05 : 1)
                Text(names[preset] ?? preset.capitalized)
                    .font(Milni.inter(12, weight: selected ? 600 : 400))
                    .foregroundStyle(selected ? ink : ink.opacity(0.6))
            }
            .frame(minWidth: 60, minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(MilniPressStyle())
        .accessibilityLabel(names[preset] ?? preset)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Ready

struct MilniReadyView: View {
    let summary: WeddingSummary
    let done: () -> Void

    @State private var code: String?
    @State private var loading = true
    @State private var copied = false

    private var link: String? { code.map { "https://milniapp.com/j/\($0)" } }

    var body: some View {
        ZStack {
            Milni.midnight.ignoresSafeArea()
            RadialGradient(colors: [Color(hex: 0x2A3150), Milni.midnight], center: .top, startRadius: 20, endRadius: 520)
                .ignoresSafeArea()
            MilniSpecks(count: 16)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                MilniLabel("Your wedding is ready", color: Milni.champagneLight)
                    .multilineTextAlignment(.center)
                    .milniEntrance(0)

                VStack(spacing: -6) {
                    Text(summary.partnerOne)
                    Text("&").font(Milni.cormorant(32, italic: true))
                    Text(summary.partnerTwo)
                }
                .font(Milni.cormorant(50))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .milniFoil()
                .padding(.top, 20)
                .milniEntrance(1)

                Text("Share this code with your guests. It opens your wedding instantly, even before they install the app.")
                    .font(Milni.inter(15))
                    .lineSpacing(5)
                    .foregroundStyle(Color(hex: 0xF4EBDC).opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .milniEntrance(2)

                codeBox
                    .padding(.top, 30)
                    .milniEntrance(3)

                Spacer(minLength: 24)

                VStack(spacing: 10) {
                    if let link {
                        ShareLink(item: URL(string: link)!, message: Text("You're invited to our wedding week on Milni: \(link)")) {
                            Text("Share with guests")
                        }
                        .buttonStyle(MilniButtonStyle(kind: .primary, ink: Color(hex: 0xF4EBDC), paper: Milni.midnight))
                        .simultaneousGesture(TapGesture().onEnded { BrandHaptics.soft() })
                    }
                    Button(link == nil ? "Enter your wedding" : "I'll share it later") {
                        BrandHaptics.tick()
                        done()
                    }
                    .buttonStyle(MilniButtonStyle(kind: link == nil ? .primary : .tertiary, ink: Color(hex: 0xF4EBDC), paper: Milni.midnight, accent: Milni.champagneLight))
                }
                .padding(.bottom, 8)
                .milniEntrance(4)
            }
            .milniSides()
        }
        .task { await loadCode() }
    }

    private var codeBox: some View {
        VStack(spacing: 10) {
            ZStack {
                if let code {
                    Text(code)
                        .font(Milni.cormorant(38, weight: 500))
                        .tracking(6)
                        .foregroundStyle(Color(hex: 0xF4EBDC))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else if loading {
                    ProgressView().tint(Milni.champagne)
                } else {
                    Text("Your code will appear in Host settings.")
                        .font(Milni.inter(13))
                        .foregroundStyle(Milni.champagneLight)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .padding(.horizontal, 20)
            .overlay(Rectangle().strokeBorder(Milni.champagne.opacity(0.7), lineWidth: 0.8))
            .milniSheen(period: 3, intensity: 0.12)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { copy() }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Copies the code")

            if let code {
                Text(copied ? "Copied" : "milniapp.com/j/\(code)")
                    .font(Milni.inter(12, weight: 500))
                    .tracking(0.6)
                    .foregroundStyle(Milni.champagneLight)
                    .contentTransition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: code)
        .animation(.easeInOut(duration: 0.25), value: copied)
    }

    private func copy() {
        guard let link else { return }
        UIPasteboard.general.string = link
        BrandHaptics.soft()
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }

    private func loadCode() async {
        // The code is created alongside the wedding; give the server a moment if needed.
        for attempt in 0..<4 {
            if let found = try? await MilniAPI.shared.code(weddingID: summary.id), !found.isEmpty {
                code = found
                break
            }
            try? await Task.sleep(for: .milliseconds(600 * (attempt + 1)))
        }
        loading = false
    }
}
