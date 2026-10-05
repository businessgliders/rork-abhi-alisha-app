import SwiftUI

/// Look up your own reply by the name on your invitation. Only the matching party is
/// ever shown, and the last match is remembered so it reads offline too.
struct RSVPLookupSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var match: RSVPRecord?
    @State private var message: String?
    @State private var isSearching = false
    @State private var isCheckDrawn = false
    @FocusState private var isNameFocused: Bool

    private static let resultAnchor = "rsvp.result"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock

                    nameField
                        .padding(.top, 26)

                    lookupButton
                        .padding(.top, 14)

                    if let message {
                        Text(message)
                            .brandFont(.bodyItalic)
                            .foregroundStyle(BrandPalette.body)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 26)
                            .transition(.opacity)
                    }

                    if let match {
                        RSVPResultCard(record: match, isCheckDrawn: isCheckDrawn)
                            .padding(.top, 30)
                            .id(Self.resultAnchor)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 44)
                .readableWidth()
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(BrandPalette.background.ignoresSafeArea())
            .animation(.calm, value: match)
            .animation(.softFade, value: message)
            .onChange(of: match?.id) { _, newID in
                guard newID != nil else { return }
                revealResult(proxy)
            }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(BrandLabel.font(size: 13, weight: .medium))
                        .foregroundStyle(BrandPalette.goldDeep)
                }
            }
        }
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
        .onAppear(perform: restoreLastMatch)
    }

    // MARK: - Pieces

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Your reply")

            Text("RSVP Lookup")
                .brandFont(.eventTitle)
                .foregroundStyle(BrandPalette.ink)

            GoldRule(width: 44, alignment: .leading)
                .padding(.top, 6)

            Text("Enter your first name, or your full name as it appears on your invitation, and we'll find your reply.")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameField: some View {
        HStack(spacing: 10) {
            Image(systemName: "person")
                .symbolVariant(.none)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(BrandPalette.gold)

            TextField("First name or full name", text: $name)
                .textContentType(.name)
                .brandFont(.bodyText)
                .foregroundStyle(BrandPalette.ink)
                .tint(BrandPalette.goldDeep)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isNameFocused)
                .onSubmit(search)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BrandPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BrandPalette.gold.opacity(0.3), lineWidth: 1)
        )
    }

    private var lookupButton: some View {
        Button(action: search) {
            HStack(spacing: 10) {
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(hex: 0xFFFBF1))
                }

                Text(isSearching ? "Looking" : "Find my details")
                    .font(BrandLabel.font(size: 12.5, weight: .semibold))
                    .tracking(1.5)
            }
            .foregroundStyle(Color(hex: 0xFFFBF1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(isSearching || name.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
    }

    // MARK: - Behaviour

    private func restoreLastMatch() {
        guard match == nil, let cached = RSVPService.shared.lastMatch else { return }
        isCheckDrawn = true
        match = cached
        if let guestName = cached.guestName { name = guestName }
    }

    /// Keyboard away, then the result glides into view and its check mark draws itself.
    private func revealResult(_ proxy: ScrollViewProxy) {
        isNameFocused = false
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.calm) {
                proxy.scrollTo(Self.resultAnchor, anchor: .top)
            }
            try? await Task.sleep(for: .milliseconds(380))
            guard !isCheckDrawn else { return }
            withAnimation(.easeOut(duration: 0.6)) { isCheckDrawn = true }
            BrandHaptics.tick()
        }
    }

    private func search() {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSearching else { return }

        isSearching = true
        message = nil
        BrandHaptics.soft()

        Task {
            let outcome = await RSVPService.shared.lookup(name: query)
            isSearching = false

            switch outcome {
            case let .found(record):
                isNameFocused = false
                if record.id != match?.id { isCheckDrawn = false }
                match = record
                message = nil
                if isCheckDrawn { BrandHaptics.tick() }
            case .ambiguous:
                isCheckDrawn = false
                match = nil
                message = "A few of our guests share that name. Add your last name so we find the right reply."
            case .notFound:
                match = nil
                message = "We couldn't find that name just yet. Try the spelling exactly as it appears on your invitation, or send Abhi & Alisha a note and they'll gladly sort it out."
            case .offline:
                match = nil
                message = "We couldn't reach the guest list just now. Try again in a moment, once you're back online."
            }
        }
    }
}

/// A gold ring with a check that strokes itself in once the reply is found.
private struct DrawnCheckMark: View {
    let isDrawn: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(BrandPalette.gold.opacity(isDrawn ? 0.14 : 0))
            Circle()
                .trim(from: 0, to: isDrawn ? 1 : 0)
                .stroke(BrandPalette.gold, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CheckShape()
                .trim(from: 0, to: isDrawn ? 1 : 0)
                .stroke(BrandPalette.goldDeep, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .padding(11)
        }
        .scaleEffect(isDrawn ? 1 : 0.8)
        .opacity(isDrawn ? 1 : 0.001)
        .accessibilityLabel("Reply found")
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

/// The matched party's own details — never anybody else's.
private struct RSVPResultCard: View {
    let record: RSVPRecord
    let isCheckDrawn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                if let firstName = record.firstName {
                    Text("Welcome, \(firstName)")
                        .brandFont(.eventTitle)
                        .foregroundStyle(BrandPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("We found you")
                        .brandFont(.eventTitle)
                        .foregroundStyle(BrandPalette.ink)
                }

                Spacer(minLength: 0)

                DrawnCheckMark(isDrawn: isCheckDrawn)
                    .frame(width: 38, height: 38)
            }

            if let isAttending = record.isAttending {
                BrandPill(
                    text: isAttending ? "Attending" : "Unable to attend",
                    tone: isAttending ? .gold : .neutral
                )
                .padding(.top, 14)
            }

            GoldRule(width: 40, alignment: .leading)
                .padding(.top, 20)

            if let partyLine = record.partyLine {
                detailRow(label: "Party", value: partyLine)
                    .padding(.top, 20)
            }

            if !record.partyMembers.isEmpty {
                labelled("Travelling with") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(record.partyMembers, id: \.self) { person in
                            Text(person)
                                .brandFont(.bodyText)
                                .foregroundStyle(BrandPalette.ink)
                        }
                    }
                }
                .padding(.top, 18)
            }

            if let dietary = record.dietaryRestrictions {
                labelled("Dietary notes") {
                    Text(dietary)
                        .brandFont(.bodyItalic)
                        .foregroundStyle(BrandPalette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 18)
            }

            if let note = record.message {
                labelled("Your note to the couple") {
                    Text(note)
                        .brandFont(.bodyItalic)
                        .foregroundStyle(BrandPalette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 18)
            }

            if let events = record.events, !events.isEmpty {
                labelled("Your events") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(events, id: \.self) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle()
                                    .fill(BrandPalette.gold)
                                    .frame(width: 4, height: 4)
                                    .offset(y: -4)

                                Text(event)
                                    .brandFont(.bodyText)
                                    .foregroundStyle(BrandPalette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, 18)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(BrandPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrandPalette.hairline, lineWidth: 1)
        )
    }

    private func detailRow(label: String, value: String) -> some View {
        labelled(label) {
            Text(value)
                .brandFont(.bodyText)
                .foregroundStyle(BrandPalette.ink)
        }
    }

    private func labelled<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(text: label, size: 9.5)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
