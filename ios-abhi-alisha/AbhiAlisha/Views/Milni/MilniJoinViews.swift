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
    let back: () -> Void
    let accept: () -> Void

    @State private var risen = false
    @State private var accepting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MilniBackButton(action: back).padding(.leading, -12)
                Spacer()
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

// MARK: - Your name

struct MilniNameView: View {
    let summary: WeddingSummary
    let back: () -> Void
    let submit: (String) async throws -> Void

    @State private var name = ChatSession.shared.suggestedName
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MilniBackButton(action: back).padding(.leading, -12)

            MilniLabel(summary.coupleNames)
                .padding(.top, 24)
                .milniEntrance(0)
            MilniHeadline(first: "How should the", second: "family know you?", size: 42)
                .padding(.top, 12)
                .milniEntrance(1)

            MilniUnderlineField(label: "Your name", text: $name, placeholder: "First and last name", contentType: .name) {
                go()
            }
            .padding(.top, 44)
            .milniEntrance(2)

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
            .padding(.top, 18)
            .milniEntrance(3)

            if let error {
                Text(error)
                    .font(Milni.inter(14))
                    .foregroundStyle(Color(hex: 0x9A3B2E))
                    .padding(.top, 16)
                    .transition(.opacity)
            }

            Spacer()

            Button {
                go()
            } label: {
                if working {
                    ProgressView().tint(Milni.ivory)
                } else {
                    Text("Join the wedding")
                }
            }
            .buttonStyle(.milniPrimary)
            .disabled(name.trimmingCharacters(in: .whitespaces).count < 2 || working)
            .padding(.bottom, 8)
        }
        .milniSides()
        .background(Milni.ivory.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: error)
    }

    private func go() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2, !working else { return }
        BrandHaptics.soft()
        working = true
        error = nil
        Task {
            do {
                try await submit(clean)
            } catch {
                self.error = (error as? MilniError) == .notFound
                    ? "We couldn't find that code."
                    : "We couldn't join you just now. Please try again."
            }
            working = false
        }
    }
}

// MARK: - Welcome

struct MilniWelcomeView: View {
    let summary: WeddingSummary
    let firstName: String
    let enter: () -> Void

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

                    Button("Enter the wedding") {
                        BrandHaptics.soft()
                        enter()
                    }
                    .buttonStyle(.milniPrimary)
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
