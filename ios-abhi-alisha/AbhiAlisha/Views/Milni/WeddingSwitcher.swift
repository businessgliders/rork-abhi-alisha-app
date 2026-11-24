import SwiftUI

// MARK: - Switcher capsule

/// Home's top-left capsule: the wedding's monogram and title. Opens the switcher.
struct WeddingSwitcherCapsule: View {
    private let context = WeddingContext.shared
    @State private var isPresented = false

    var body: some View {
        Button {
            BrandHaptics.tick()
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                MilniMonogram(
                    initials: context.snapshot.initials,
                    size: 26,
                    ring: Color(hex: 0xE6CF9A),
                    textColor: .white
                )
                Text(context.snapshot.coupleNames)
                    .font(Milni.inter(13, weight: 600))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .frame(height: 36)
            .background { glass }
            .contentShape(Capsule())
        }
        .buttonStyle(MilniPressStyle())
        .frame(minHeight: 44)
        .accessibilityLabel("\(context.snapshot.coupleNames). Switch wedding")
        .sheet(isPresented: $isPresented) {
            WeddingSwitcherSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

extension WeddingSwitcherCapsule {
    @ViewBuilder
    fileprivate var glass: some View {
        if #available(iOS 26.0, *) {
            Capsule().fill(Color.clear)
                .glassEffect(.regular.tint(Color.black.opacity(0.18)), in: .capsule)
        } else {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.black.opacity(0.2)))
        }
    }
}

// MARK: - Switcher sheet

struct WeddingSwitcherSheet: View {
    private let context = WeddingContext.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("YOUR WEDDINGS")
                    .font(Milni.inter(11, weight: 600))
                    .tracking(2.4)
                    .foregroundStyle(BrandPalette.goldDeep)
                    .padding(.top, 28)

                Text("Switch wedding")
                    .font(Milni.cormorant(36))
                    .foregroundStyle(BrandPalette.ink)
                    .padding(.top, 6)

                VStack(spacing: 0) {
                    if context.isSample {
                        row(
                            initials: context.snapshot.initials,
                            title: context.snapshot.coupleNames,
                            detail: "Sample wedding",
                            badge: nil,
                            selected: true
                        ) {}
                    }
                    ForEach(context.myWeddings) { wedding in
                        row(
                            initials: wedding.initials,
                            title: wedding.title,
                            detail: wedding.dateRange ?? "Dates to come",
                            badge: wedding.roleBadge,
                            selected: !context.isSample && wedding.id.lowercased() == context.weddingID.lowercased()
                        ) {
                            BrandHaptics.soft()
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                context.switchTo(wedding)
                            }
                        }
                    }
                    if context.myWeddings.isEmpty, !context.isSample {
                        row(
                            initials: context.snapshot.initials,
                            title: context.snapshot.coupleNames,
                            detail: context.snapshot.placeLine ?? "",
                            badge: nil,
                            selected: true
                        ) {}
                    }
                }
                .padding(.top, 20)

                VStack(spacing: 10) {
                    Button {
                        leave(.joinCode)
                    } label: {
                        Label("Join another wedding", systemImage: "envelope.open")
                    }
                    .buttonStyle(MilniButtonStyle(kind: .primary, ink: BrandPalette.ink, paper: BrandPalette.background))

                    Button {
                        leave(.create)
                    } label: {
                        Label("Create a wedding", systemImage: "plus")
                    }
                    .buttonStyle(MilniButtonStyle(kind: .secondary, ink: BrandPalette.ink, paper: BrandPalette.background))
                }
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .task { await context.refreshMyWeddings() }
    }

    private func leave(_ entry: WeddingContext.OnboardingEntry) {
        BrandHaptics.tick()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            context.goToOnboarding(entry)
        }
    }

    private func row(
        initials: String,
        title: String,
        detail: String,
        badge: String?,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                MilniMonogram(initials: initials, size: 44, ring: BrandPalette.gold, textColor: BrandPalette.ink)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(Milni.cormorant(22, weight: 500))
                            .foregroundStyle(BrandPalette.ink)
                            .lineLimit(1)
                        if let badge {
                            Text(badge.uppercased())
                                .font(Milni.inter(9, weight: 600))
                                .tracking(1.4)
                                .foregroundStyle(BrandPalette.goldDeep)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .overlay(Capsule().strokeBorder(BrandPalette.gold.opacity(0.6), lineWidth: 0.8))
                        }
                    }
                    if !detail.isEmpty {
                        Text(detail)
                            .font(Milni.inter(13))
                            .foregroundStyle(BrandPalette.body)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandPalette.goldDeep)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(BrandPalette.hairline).frame(height: 0.5)
            }
        }
        .buttonStyle(MilniPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Sample mode

/// A thin line across the top while browsing the sample wedding.
struct SampleWeddingBanner: View {
    var body: some View {
        Button {
            BrandHaptics.tick()
            WeddingContext.shared.goToOnboarding(.choose)
        } label: {
            HStack(spacing: 6) {
                Text("Sample wedding")
                    .foregroundStyle(Milni.champagneLight)
                Text("·").foregroundStyle(Milni.champagneLight.opacity(0.6))
                Text("Join yours")
                    .foregroundStyle(Color(hex: 0xF4EBDC))
                    .underline()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xF4EBDC))
            }
            .font(Milni.inter(12, weight: 500))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(Milni.midnight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("You're browsing a sample wedding. Join yours.")
    }
}

/// Shown in place of Chat and My Outfits while browsing the sample.
struct SampleJoinCard: View {
    var symbol = "bubble.left.and.bubble.right"

    var body: some View {
        VStack(spacing: 18) {
            MilniRings(color: BrandPalette.gold, lineWidth: 1, duration: 1.6, showsOuter: false, breathes: false)
                .frame(width: 64, height: 64)
            Text("Join a wedding to chat and plan outfits")
                .font(Milni.cormorant(32))
                .foregroundStyle(BrandPalette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("The sample shows how a wedding week looks. Conversations and outfits are for the guests of each wedding.")
                .font(Milni.inter(15))
                .lineSpacing(4)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Join a wedding") {
                BrandHaptics.tick()
                WeddingContext.shared.goToOnboarding(.choose)
            }
            .buttonStyle(MilniButtonStyle(kind: .primary, ink: BrandPalette.ink, paper: BrandPalette.background))
            .padding(.top, 8)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandPalette.background.ignoresSafeArea())
    }
}

// MARK: - Empty schedule

/// Before the couple adds events: their monogram and a quiet line.
struct WeddingEmptyState: View {
    var title = "Your schedule will appear here"
    var message = "Each ceremony, with its time, place and dress code, shows up as soon as it's added."

    var body: some View {
        VStack(spacing: 16) {
            MilniMonogram(initials: ActiveWedding.snapshot.initials, size: 72, ring: BrandPalette.gold, textColor: BrandPalette.ink)
            Text(title)
                .font(Milni.cormorant(28))
                .foregroundStyle(BrandPalette.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Milni.inter(14))
                .lineSpacing(4)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}
