import AuthenticationServices
import SwiftUI

// MARK: - Save your spot

/// A quiet offer for name-only guests: sign in with Apple and this week follows them
/// to every device — outfits, chats, their RSVP match. Never pushy: a small card with
/// a close button, and when it's dismissed it stays away for fourteen days.
struct SaveYourSpotCard: View {
    @State private var session = ChatSession.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let dismissKey = "milni.saveSpot.hiddenUntil"

    /// True while the dismissal is still running its fourteen days.
    static var isHidden: Bool {
        guard let until = UserDefaults.standard.object(forKey: dismissKey) as? Date else { return false }
        return until > Date()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text("Save your spot")
                    .font(BrandLabel.font(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Milni.gold)

                Spacer(minLength: 8)

                Button {
                    BrandHaptics.tick()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Milni.ivory.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(Text("Dismiss. Won't show again for two weeks."))
            }

            Text("Keep your week, wherever you are.")
                .font(Milni.cormorant(26, weight: 600))
                .foregroundStyle(Milni.ivory)
                .fixedSize(horizontal: false, vertical: true)

            Text("Sign in with Apple and your schedule, outfits and chats come with you to every device.")
                .font(Milni.inter(13))
                .foregroundStyle(Milni.ivory.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            if let error = session.signInError {
                Text(error)
                    .font(Milni.inter(13))
                    .foregroundStyle(Milni.ivory.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                SignInWithAppleButton(.signIn) { request in
                    session.prepare(request)
                } onCompletion: { result in
                    Task { await session.complete(result) }
                }
                .signInWithAppleButtonStyle(.whiteOutline)
                .frame(height: 42)
                .frame(maxWidth: 190)
                .clipShape(Capsule())
                .opacity(session.isSigningIn ? 0.5 : 1)
                .disabled(session.isSigningIn)
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Milni.midnight))
        .overlay(shape.stroke(Milni.gold.opacity(0.35), lineWidth: 0.75))
    }

    private func dismiss() {
        UserDefaults.standard.set(Date().addingTimeInterval(14 * 24 * 60 * 60), forKey: Self.dismissKey)
    }
}

// MARK: - Feature tiles

/// The guest's week as a two-by-two of small living cards — outfits, questions,
/// packing, a toast. Each icon carries a slow, gentle loop that stops the moment
/// Reduce Motion is on.
struct ExperienceTiles: View {
    var onOutfits: () -> Void
    var onQuestions: () -> Void
    var onPacking: () -> Void
    var onToast: () -> Void

    @Environment(ContentStore.self) private var content
    @Environment(ScheduleStore.self) private var schedule
    @State private var outfits = OutfitStore.shared

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ExperienceTile(
                title: "My Outfits",
                subtitle: outfitsSubtitle,
                icon: { TileIcon(kind: .outfits) },
                action: onOutfits
            )
            ExperienceTile(
                title: "Questions",
                subtitle: questionsSubtitle,
                icon: { TileIcon(kind: .questions) },
                action: onQuestions
            )
            ExperienceTile(
                title: "Packing list",
                subtitle: "Made from your events, dress codes and the forecast.",
                icon: { TileIcon(kind: .packing) },
                action: onPacking
            )
            ExperienceTile(
                title: "A toast",
                subtitle: "A few words for the day, drafted privately on your phone.",
                icon: { TileIcon(kind: .toast) },
                action: onToast
            )
        }
        .task {
            outfits.syncUser()
        }
    }

    private var outfitsSubtitle: String {
        let events = schedule.events.filter { $0.isActive != false && !$0.isFarewell }
        let total = max(events.count * OutfitCategory.allCases.count, 1)
        let filled = events.reduce(0) { $0 + outfits.filledSlots(for: $1.id) }
        return filled == 0
            ? "Plan your look for every celebration."
            : "\(filled) of \(total) pieces planned."
    }

    private var questionsSubtitle: String {
        let count = content.faqs.count
        return count == 0
            ? "Travel, payments and more."
            : "\(count) answers, all searchable."
    }
}

private struct ExperienceTile<Icon: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button {
            BrandHaptics.soft()
            action()
        } label: {
            MatteCard(cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    icon()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .brandFont(.bodyText)
                            .foregroundStyle(BrandPalette.ink)
                        Text(subtitle)
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.leading)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 132, alignment: .topLeading)
            }
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Tile icons

/// A gold coin with a symbol that breathes: the hanger sways, the bubble bobs, the
/// packing ring fills, the glasses clink. Loops run 2.5–3.5 seconds and never run at
/// all under Reduce Motion.
struct TileIcon: View {
    enum Kind { case outfits, questions, packing, toast }

    let kind: Kind

    @State private var moving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(BrandPalette.gold.opacity(0.1))
            icon
        }
        .frame(width: 46, height: 46)
        .onAppear(perform: start)
        .accessibilityHidden(true)
    }

    private func start() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { moving = true }
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .outfits:
            Image(systemName: "tshirt")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(BrandPalette.goldDeep)
                .rotationEffect(.degrees(moving ? 7 : -7), anchor: .top)

        case .questions:
            Image(systemName: "questionmark.bubble")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(BrandPalette.goldDeep)
                .offset(y: moving ? -3 : 3)

        case .packing:
            ZStack {
                Circle()
                    .stroke(BrandPalette.hairline, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: moving ? 0.85 : 0.12)
                    .stroke(BrandPalette.gold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "suitcase")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(BrandPalette.goldDeep)
            }
            .frame(width: 24, height: 24)

        case .toast:
            ZStack {
                Image(systemName: "wineglass")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(BrandPalette.goldDeep)
                    .rotationEffect(.degrees(moving ? 9 : -9), anchor: .bottom)
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BrandPalette.gold)
                    .offset(x: 12, y: -12)
                    .opacity(moving ? 1 : 0.25)
            }
        }
    }
}
