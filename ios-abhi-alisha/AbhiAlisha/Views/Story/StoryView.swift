import SwiftUI

/// "Story" holds two halves of the same thing: the couple's own invitation, written in
/// their words, and the families standing beside them. A segmented control moves between
/// them and the screen cross-fades — nothing reloads.
struct StoryView: View {
    @Environment(ContentStore.self) private var content

    @State private var section: StorySection = .story

    private enum StorySection: String, CaseIterable, Identifiable {
        case story
        case family

        var id: String { rawValue }

        var title: String {
            switch self {
            case .story: return "Our Story"
            case .family: return "Our Family"
            }
        }

        var eyebrow: String {
            switch self {
            case .story: return "Invitation"
            case .family: return "Side by side"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                picker
                    .padding(.top, 22)

                ZStack(alignment: .top) {
                    if section == .story {
                        invitation
                            .transition(.opacity)
                    } else {
                        FamilyRoster(members: content.familyMembers)
                            .transition(.opacity)
                    }
                }
                .animation(.softFade, value: section)
                .padding(.top, 26)
            }
            .padding(.horizontal, 22)
            .padding(.top, ScreenChrome.contentReserve)
            .padding(.bottom, FloatingTabBar.contentReserve + 24)
            .readableWidth()
            .crestCorner()
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .task {
            await content.refreshIfNeeded()
        }
    }

    /// The couple's letter, standing in for the story itself.
    @ViewBuilder
    private var invitation: some View {
        if let letter = content.loveLetter {
            LoveLetterView(letter: letter)
        } else {
            VStack(spacing: 18) {
                IconWatermark(key: .paisley, size: 92, opacity: 0.3)

                Text("Abhi & Alisha are still writing this chapter.")
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 70)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: section.eyebrow)
                .animation(.softFade, value: section)

            Text("Story")
                .brandFont(.screenTitle)
                .foregroundStyle(BrandPalette.ink)

            GoldRule(width: 58, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A slim gold-lined segmented control, drawn in the app's own hand.
    private var picker: some View {
        HStack(spacing: 0) {
            ForEach(StorySection.allCases) { option in
                let isSelected = option == section

                Button {
                    guard !isSelected else { return }
                    BrandHaptics.tick()
                    withAnimation(.calm) { section = option }
                } label: {
                    Text(option.title.uppercased())
                        .font(BrandLabel.font(size: 10.5, weight: isSelected ? .semibold : .medium))
                        .tracking(1.9)
                        .foregroundStyle(isSelected ? BrandPalette.goldDeep : BrandPalette.tabInactive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(BrandPalette.card)
                                    .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(BrandPalette.hairline.opacity(0.55))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(BrandPalette.gold.opacity(0.28), lineWidth: 0.75)
        )
    }
}
