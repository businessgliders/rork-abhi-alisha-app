import SwiftUI

/// Home after the wedding: a short note from the couple and three ways back into the week.
struct ThankYouLinks: View {
    let onGallery: () -> Void
    let onOutfits: () -> Void
    let onChat: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Eyebrow(text: "With love")
                Text("Thank you for celebrating with us")
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The week was more beautiful because you were there. Here's where to find the memories.")
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)

            VStack(spacing: 12) {
                link(
                    symbol: "photo.on.rectangle",
                    title: "The Gallery",
                    detail: "Photographs from every celebration",
                    action: onGallery
                )
                link(
                    symbol: "hanger",
                    title: "My Outfits",
                    detail: "Your wedding week looks",
                    action: onOutfits
                )
                link(
                    symbol: "bubble.left.and.bubble.right",
                    title: "Chat",
                    detail: "Say thank you, share a moment",
                    action: onChat
                )
            }
        }
    }

    private func link(symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button {
            BrandHaptics.soft()
            action()
        } label: {
            MatteCard(cornerRadius: 22) {
                HStack(spacing: 16) {
                    Image(systemName: symbol)
                        .symbolVariant(.none)
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(BrandPalette.goldDeep)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(BrandPalette.gold.opacity(0.5), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .brandFont(.outfitRowTitle)
                            .foregroundStyle(BrandPalette.ink)
                        Text(detail)
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(BrandPalette.gold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(PressableStyle())
    }
}

/// Home's way into My Outfits before the wedding: progress across the week at a glance.
struct MyOutfitsHomeCard: View {
    let action: () -> Void

    @Environment(ScheduleStore.self) private var schedule
    @State private var outfits = OutfitStore.shared

    var body: some View {
        let events = schedule.events.filter { $0.isActive != false && !$0.isFarewell }
        let total = max(events.count * OutfitCategory.allCases.count, 1)
        let filled = events.reduce(0) { $0 + outfits.filledSlots(for: $1.id) }

        Button {
            BrandHaptics.soft()
            action()
        } label: {
            MatteCard(cornerRadius: 22) {
                HStack(spacing: 16) {
                    OutfitProgressRing(filled: filled, total: total, size: 44, showsCount: false)
                        .overlay {
                            Image(systemName: "hanger")
                                .font(.system(size: 14, weight: .light))
                                .foregroundStyle(BrandPalette.goldDeep)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("My Outfits")
                            .brandFont(.bodyText)
                            .foregroundStyle(BrandPalette.ink)
                        Text(filled == 0
                            ? "Plan your look for every celebration."
                            : "\(filled) of \(total) pieces planned for the week.")
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(BrandPalette.gold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(PressableStyle())
        .task {
            outfits.syncUser()
        }
    }
}
