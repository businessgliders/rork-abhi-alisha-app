import AuthenticationServices
import SwiftUI
import UIKit

// MARK: - Enter code

struct MilniCodeEntryView: View {
    var prefill: String?
    let back: () -> Void
    let found: (WeddingSummary, String) -> Void

    @State private var code = ""
    @State private var error: String?
    @State private var searching = false
    @State private var shake: CGFloat = 0
    @State private var scanning = false
    @State private var explicit = false
    @State private var pulse = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var slotCount: Int { min(10, max(6, code.count + (code.count >= 6 ? 1 : 0))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MilniBackButton(action: back)
                .padding(.leading, -12)

            MilniLabel("Your invitation")
                .padding(.top, 24)
                .milniEntrance(0)
            MilniHeadline(first: "Enter your", second: "wedding code", size: 42)
                .padding(.top, 12)
                .milniEntrance(1)

            slots
                .padding(.top, 40)
                .modifier(MilniShake(animatableData: shake))
                .milniEntrance(2)

            ZStack(alignment: .leading) {
                if searching {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(Milni.goldText)
                        Text("Finding your wedding…")
                    }
                    .transition(.opacity)
                } else if let error {
                    Text(error)
                        .foregroundStyle(Color(hex: 0x9A3B2E))
                        .transition(.opacity)
                }
            }
            .font(Milni.inter(14))
            .foregroundStyle(Milni.muted)
            .frame(height: 24, alignment: .leading)
            .padding(.top, 18)
            .animation(.easeInOut(duration: 0.25), value: searching)
            .animation(.easeInOut(duration: 0.25), value: error)
            .accessibilityElement(children: .combine)

            HStack(spacing: 22) {
                Button {
                    paste()
                } label: {
                    Label("Paste code from invite", systemImage: "doc.on.clipboard")
                }
                Button {
                    BrandHaptics.tick()
                    focused = false
                    scanning = true
                } label: {
                    Label("Scan QR code", systemImage: "qrcode.viewfinder")
                }
            }
            .labelStyle(MilniSmallLabelStyle())
            .font(Milni.inter(13, weight: 500))
            .foregroundStyle(Milni.goldText)
            .padding(.top, 14)
            .milniEntrance(3)

            Spacer()
        }
        .milniSides()
        .background(Milni.ivory.ignoresSafeArea())
        .overlay {
            // The real keyboard types into this hidden field.
            TextField("", text: $code)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit {
                    explicit = true
                    lookupNow()
                }
                .opacity(0.011)
                .frame(width: 1, height: 1)
                .accessibilityLabel("Wedding code")
                .accessibilityValue(code)
        }
        .onChange(of: code) { old, new in
            let clean = WeddingContext.normalize(new)
            if clean != new { code = clean; return }
            if clean.count > old.count { BrandHaptics.tick() }
            error = nil
        }
        .task(id: code) {
            guard code.count >= 6 else { searching = false; return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await lookup(code)
        }
        .onAppear {
            if let prefill, !prefill.isEmpty {
                explicit = true
                code = WeddingContext.normalize(prefill)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { focused = true }
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .sheet(isPresented: $scanning) {
            MilniQRScannerSheet { scanned in
                scanning = false
                explicit = true
                code = scanned
            }
        }
    }

    private var slots: some View {
        HStack(spacing: 8) {
            ForEach(0..<slotCount, id: \.self) { index in
                let chars = Array(code)
                let letter = index < chars.count ? String(chars[index]) : ""
                let isNext = index == chars.count && focused
                VStack(spacing: 6) {
                    ZStack {
                        if !letter.isEmpty {
                            Text(letter)
                                .font(Milni.cormorant(32, weight: 500))
                                .foregroundStyle(Milni.ink)
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
                        }
                    }
                    .frame(height: 40)
                    Rectangle()
                        .fill(isNext ? Milni.gold.opacity(pulse ? 1 : 0.35) : (letter.isEmpty ? Milni.hairline : Milni.ink))
                        .frame(height: isNext ? 2 : 1.5)
                }
                .frame(maxWidth: 34)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: letter)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: slotCount)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .accessibilityHidden(true)
    }

    private func paste() {
        BrandHaptics.tick()
        guard let text = UIPasteboard.general.string else {
            error = "There's no code on your clipboard."
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromLink = URL(string: trimmed).flatMap(WeddingContext.joinCode(from:))
        let fromText = trimmed
            .components(separatedBy: CharacterSet(charactersIn: " /\n"))
            .compactMap { URL(string: $0) }
            .compactMap(WeddingContext.joinCode(from:))
            .first
        explicit = true
        code = fromLink ?? fromText ?? WeddingContext.normalize(trimmed)
    }

    private func lookupNow() {
        guard code.count >= 6 else {
            fail("Wedding codes are at least 6 letters.")
            return
        }
        Task { await lookup(code) }
    }

    private func lookup(_ value: String) async {
        searching = true
        do {
            let summary = try await MilniAPI.shared.preview(code: value)
            guard value == code else { return }
            searching = false
            focused = false
            BrandHaptics.soft()
            found(summary, value)
        } catch {
            guard value == code else { return }
            searching = false
            let isMissing = (error as? MilniError) == .notFound || !(error is URLError)
            // While someone is still typing a longer code, wait before complaining.
            if !explicit && value.count < 10 {
                try? await Task.sleep(for: .milliseconds(1200))
                guard value == code, !Task.isCancelled else { return }
            }
            fail(isMissing ? "We couldn't find that code." : "We couldn't reach Milni. Check your connection and try again.")
        }
        explicit = false
    }

    private func fail(_ message: String) {
        error = message
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        if reduceMotion { return }
        shake = 0
        withAnimation(.linear(duration: 0.45)) { shake = 1 }
    }
}

private struct MilniSmallLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 13, weight: .regular))
            configuration.title
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Invitation found

struct MilniInvitationView: View {
    let summary: WeddingSummary
    var progress: Int = 0
    let back: () -> Void
    let accept: () -> Void

    @State private var risen = false
    @State private var accepting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MilniBackButton(action: back).padding(.leading, -12)
                Spacer(minLength: 0)
                MilniProgressTrack(index: progress)
                    .frame(width: 88)
                    .padding(.trailing, 4)
            }
            .milniSides()

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                MilniLabel("Invitation found", color: Milni.found)
            }
            .foregroundStyle(Milni.found)
            .padding(.top, 4)
            .milniEntrance(0)

            GeometryReader { proxy in
                MilniInvitationCard(
                    partnerOne: summary.partnerOne,
                    partnerTwo: summary.partnerTwo,
                    detail: summary.cityAndDates,
                    preset: summary.preset
                )
                .rotation3DEffect(.degrees(risen || reduceMotion ? 0 : 24), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .scaleEffect(risen || reduceMotion ? 1 : 0.92)
                .offset(y: risen || reduceMotion ? 0 : 160)
                .opacity(risen ? 1 : 0)
                // Shrinks on short screens so the buttons always fit.
                .scaleEffect(min(1, (proxy.size.height - 24) / 420, (proxy.size.width - 40) / 300))
                .frame(width: proxy.size.width, height: proxy.size.height)
            }

            VStack(spacing: 10) {
                Button {
                    BrandHaptics.soft()
                    accepting = true
                    accept()
                } label: {
                    if accepting {
                        ProgressView().tint(Milni.ivory)
                    } else {
                        Text("Accept invitation")
                    }
                }
                .buttonStyle(.milniPrimary)
                .disabled(accepting)
                Button("Not your wedding?", action: back)
                    .buttonStyle(.milniTertiary)
            }
            .milniSides()
            .padding(.bottom, 8)
            .milniEntrance(2, delay: 0.6)
        }
        .background(Milni.stone.ignoresSafeArea())
        .onAppear {
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.6)) { risen = true }
            } else {
                withAnimation(.spring(response: 1.3, dampingFraction: 0.82).delay(0.15)) { risen = true }
            }
        }
    }

}

// MARK: - Who's joining

/// The four steps a guest walks, from the invitation to the welcome: a thin gold
/// track under the back link so it's always clear where they are.
struct MilniProgressTrack: View {
    /// Zero-based step; the last of four is the welcome.
    var index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { item in
                Capsule()
                    .fill(item <= index ? Milni.gold : Milni.hairline)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.5, dampingFraction: 0.9),
            value: index
        )
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(index + 1) of 4"))
    }
}

/// Step two of four: who's joining. Guests type their name; family and wedding party
/// sign in with Apple instead — an offer, never a wall.
struct MilniWhoView: View {
    let summary: WeddingSummary
    var progress: Int
    let back: () -> Void
    let submit: (String) async throws -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var working = false
    @State private var error: String?
    @State private var appleSignedIn = false

    private let session = ChatSession.shared

    private var fullName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var isReady: Bool { fullName.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MilniBackButton(action: back).padding(.leading, -12)
                Spacer(minLength: 0)
                MilniProgressTrack(index: progress)
                    .frame(width: 88)
                    .padding(.trailing, 4)
            }

            MilniLabel(summary.coupleNames)
                .padding(.top, 20)
                .milniEntrance(0)
            MilniHeadline(first: "Who's", second: "joining?", size: 42)
                .padding(.top, 12)
                .milniEntrance(1)

            if appleSignedIn {
                signedInChip
                    .padding(.top, 30)
                    .milniEntrance(2)
            } else {
                nameFields
                    .padding(.top, 34)
                    .milniEntrance(2)
            }

            if let error {
                Text(error)
                    .font(Milni.inter(14))
                    .foregroundStyle(Color(hex: 0x9A3B2E))
                    .padding(.top, 16)
                    .transition(.opacity)
            }
            if let notice = session.linkNotice {
                Text(notice)
                    .font(Milni.inter(14))
                    .foregroundStyle(Milni.found)
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            Spacer()

            Button {
                go()
            } label: {
                if working {
                    ProgressView().tint(Milni.ivory)
                } else {
                    Text(appleSignedIn ? "Continue" : "Join as a guest")
                }
            }
            .buttonStyle(.milniPrimary)
            .disabled(!isReady || working)
            .padding(.bottom, 10)

            if !appleSignedIn {
                familyCard
                    .padding(.bottom, 8)
            }
        }
        .milniSides()
        .background(Milni.ivory.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: error)
        .animation(.easeInOut(duration: 0.3), value: appleSignedIn)
        .onAppear(perform: fillFromSession)
        .onChange(of: session.isSignedIn && !session.isAnonymous) { _, signedIn in
            if signedIn {
                appleSignedIn = true
                fillFromSession()
            }
        }
        .onChange(of: session.linkNotice) { _, notice in
            // The Apple ID already had an account and the guest history moved: say so,
            // then carry on as the signed-in person.
            if notice != nil, session.isSignedIn {
                appleSignedIn = true
            }
        }
    }

    private var nameFields: some View {
        VStack(spacing: 26) {
            MilniUnderlineField(label: "First name", text: $firstName, placeholder: "Your first name", contentType: .givenName) {
                go()
            }
            MilniUnderlineField(label: "Last name", text: $lastName, placeholder: "Optional", contentType: .familyName) {
                go()
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 12))
                    .foregroundStyle(Milni.goldText)
                    .padding(.top, 2)
                Text("The couple approves guests before the family chat opens.")
                    .font(Milni.inter(13))
                    .foregroundStyle(Milni.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Family and wedding party sign in with Apple: their week follows them across
    /// devices. A quiet card on midnight, with the compact white-outline control.
    private var familyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Family or wedding party?")
                .font(Milni.cormorant(24, weight: 600))
                .foregroundStyle(Milni.ivory)
            Text("Sign in with Apple and your week follows you to every device.")
                .font(Milni.inter(13))
                .foregroundStyle(Milni.ivory.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            SignInWithAppleButton(.signIn) { request in
                session.prepare(request)
            } onCompletion: { result in
                Task { await session.complete(result) }
            }
            .signInWithAppleButtonStyle(.whiteOutline)
            .frame(height: 44)
            .clipShape(Capsule())
            .opacity(session.isSigningIn ? 0.5 : 1)
            .disabled(session.isSigningIn)
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Milni.midnight))
        .accessibilityElement(children: .contain)
    }

    private var signedInChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
            Text("Signed in with Apple")
                .font(Milni.inter(14, weight: 500))
        }
        .foregroundStyle(Milni.found)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Milni.found.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }

    private func fillFromSession() {
        if firstName.isEmpty, let suggested = ChatJSON.clean(session.suggestedName) {
            let parts = suggested.split(separator: " ").map(String.init)
            firstName = parts.first ?? ""
            if parts.count > 1 { lastName = parts.dropFirst().joined(separator: " ") }
        }
        if session.isSignedIn && !session.isAnonymous {
            appleSignedIn = true
        }
    }

    private func go() {
        guard isReady, !working else { return }
        BrandHaptics.soft()
        working = true
        error = nil
        Task {
            do {
                try await submit(fullName)
            } catch {
                self.error = (error as? MilniError) == .notFound
                    ? "We couldn't find that code."
                    : "We couldn't join you just now. Please try again."
            }
            working = false
        }
    }
}

// MARK: - RSVP match

/// Step three of four: the party found for the name typed. Offered only when the
/// lookup answered; a quiet skip otherwise.
struct MilniRSVPView: View {
    let summary: WeddingSummary
    let firstName: String
    let matches: [RSVPRecord]
    var progress: Int
    let back: () -> Void
    let skip: () -> Void
    let confirm: (RSVPRecord) async -> Void

    @State private var picked: RSVPRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MilniBackButton(action: back).padding(.leading, -12)
                Spacer(minLength: 0)
                MilniProgressTrack(index: progress)
                    .frame(width: 88)
                    .padding(.trailing, 4)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    MilniLabel(summary.coupleNames)
                        .padding(.top, 20)
                        .milniEntrance(0)
                    MilniHeadline(first: "Is this", second: "you, \(firstName)?", size: 42)
                        .padding(.top, 12)
                        .milniEntrance(1)
                    MilniBody("Found on \(summary.coupleNames)'s guest list. Pick your reply so the week can greet you by name.")
                        .padding(.top, 14)
                        .milniEntrance(2)

                    VStack(spacing: 12) {
                        ForEach(matches) { record in
                            matchCard(record)
                        }
                    }
                    .padding(.top, 26)
                    .milniEntrance(3)
                }
                .padding(.bottom, 24)
            }

            Button("None of these", action: skip)
                .buttonStyle(.milniTertiary)
                .padding(.bottom, 8)
        }
        .milniSides()
        .background(Milni.ivory.ignoresSafeArea())
    }

    private func matchCard(_ record: RSVPRecord) -> some View {
        Button {
            guard picked == nil else { return }
            BrandHaptics.soft()
            picked = record
            Task { await confirm(record) }
        } label: {
            MatteCard(cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(record.displayName ?? "")
                            .font(Milni.cormorant(24, weight: 600))
                            .foregroundStyle(Milni.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        if let attending = record.isAttending {
                            Text(attending ? "Coming" : "Can't come")
                                .font(Milni.inter(11, weight: 600))
                                .tracking(0.8)
                                .textCase(.uppercase)
                                .foregroundStyle(attending ? Milni.found : Milni.muted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill((attending ? Milni.found : Milni.muted).opacity(0.1)))
                        }
                    }

                    if let party = record.partyLine {
                        Text(party)
                            .font(Milni.inter(13))
                            .foregroundStyle(Milni.muted)
                    }

                    if let events = record.events?.filter({ !$0.isEmpty }), !events.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(events.prefix(3), id: \.self) { event in
                                Text(event)
                                    .font(Milni.inter(11, weight: 500))
                                    .foregroundStyle(Milni.goldText)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Capsule().stroke(Milni.gold.opacity(0.5), lineWidth: 0.8))
                                    .lineLimit(1)
                            }
                            if events.count > 3 {
                                Text("+\(events.count - 3)")
                                    .font(Milni.inter(11, weight: 500))
                                    .foregroundStyle(Milni.muted)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(PressableStyle())
        .opacity(picked == nil || picked?.id == record.id ? 1 : 0.5)
        .accessibilityLabel(Text("\(record.displayName ?? "A party") on the guest list"))
        .accessibilityHint(attendingHint(for: record))
    }

    private func attendingHint(for record: RSVPRecord) -> String {
        if let attending = record.isAttending {
            return attending ? "Confirms this is you" : "This reply says you can't come"
        }
        return "Confirms this is you"
    }
}

// MARK: - Welcome

struct MilniWelcomeView: View {
    let summary: WeddingSummary
    let firstName: String
    let enter: () -> Void

    @State private var push = PushRegistrar.shared
    @State private var open = false
    @State private var showText = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Milni.ivory.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()
                    ZStack {
                        Circle().fill(Milni.midnight)
                        Circle().strokeBorder(Milni.champagne.opacity(0.8), lineWidth: 0.8).padding(8)
                        Circle().strokeBorder(Milni.champagne.opacity(0.4), lineWidth: 0.6).padding(13)
                        Text(summary.initials.count == 2 ? "\(summary.initials.prefix(1)) & \(summary.initials.suffix(1))" : summary.initials)
                            .font(Milni.cormorant(40, weight: 500, italic: true))
                            .milniFoil()
                    }
                    .frame(width: 132, height: 132)
                    .scaleEffect(showText || reduceMotion ? 1 : 0.9)
                    .opacity(showText ? 1 : 0)

                    VStack(spacing: 14) {
                        MilniLabel("You're on the list")
                            .padding(.top, 36)
                        VStack(spacing: -4) {
                            Text("Welcome,")
                                .font(Milni.cormorant(46))
                                .foregroundStyle(Milni.ink)
                            Text(firstName)
                                .font(Milni.cormorant(46, italic: true))
                                .foregroundStyle(Milni.goldText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .accessibilityElement(children: .combine)
                        MilniBody("\(summary.coupleNames) can't wait to celebrate with you.", alignment: .center)
                            .padding(.top, 4)
                        WalletPassButton(weddingID: summary.id)
                            .padding(.top, 10)
                    }
                    .milniSides()
                    .opacity(showText ? 1 : 0)
                    .offset(y: showText || reduceMotion ? 0 : 16)

                    Spacer()

                    VStack(spacing: 10) {
                        if push.isEnabled {
                            Button("Enter the wedding") {
                                BrandHaptics.soft()
                                enter()
                            }
                            .buttonStyle(.milniPrimary)
                        } else {
                            Button {
                                BrandHaptics.soft()
                                push.markOffered()
                                push.isExplainerPresented = true
                            } label: {
                                Label("Turn on updates", systemImage: "bell")
                            }
                            .buttonStyle(.milniPrimary)

                            Button("Not now", action: enter)
                                .buttonStyle(.milniTertiary)
                        }
                    }
                    .milniSides()
                    .padding(.bottom, 8)
                    .opacity(showText ? 1 : 0)
                }

                // Curtains.
                HStack(spacing: 0) {
                    curtain(leading: true)
                        .offset(x: open ? -proxy.size.width / 2 - 20 : 0)
                    curtain(leading: false)
                        .offset(x: open ? proxy.size.width / 2 + 20 : 0)
                }
                .ignoresSafeArea()
                .allowsHitTesting(!open)
                .opacity(reduceMotion && open ? 0 : 1)
            }
        }
        .onAppear {
            BrandHaptics.soft()
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.6).delay(0.3)) { open = true; showText = true }
                return
            }
            withAnimation(.easeInOut(duration: 1.4).delay(0.35)) { open = true }
            withAnimation(Milni.entrance.delay(1.2)) { showText = true }
        }
    }

    private func curtain(leading: Bool) -> some View {
        ZStack(alignment: leading ? .trailing : .leading) {
            LinearGradient(
                colors: leading
                    ? [Milni.midnight, Color(hex: 0x232A42), Milni.midnight, Color(hex: 0x161A2A)]
                    : [Color(hex: 0x161A2A), Milni.midnight, Color(hex: 0x232A42), Milni.midnight],
                startPoint: .leading,
                endPoint: .trailing
            )
            Rectangle()
                .fill(Milni.champagne.opacity(0.7))
                .frame(width: 1)
        }
    }
}
