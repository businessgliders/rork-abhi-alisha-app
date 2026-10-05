import SwiftUI

/// Every celebration in order, each with a ring showing how many of the four pieces
/// are photographed and a glimpse of the guest's own outfit.
struct MyOutfitsView: View {
    @Environment(ScheduleStore.self) private var schedule
    @Environment(\.dismiss) private var dismiss
    @State private var outfits = OutfitStore.shared
    @State private var session = ChatSession.shared

    private var events: [ScheduleEvent] {
        schedule.events.filter { $0.isActive != false && !$0.isFarewell }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    summaryCard
                        .padding(.top, 24)

                    VStack(spacing: 12) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            NavigationLink(value: OutfitLookRoute(eventID: event.id)) {
                                OutfitEventRow(
                                    event: event,
                                    filled: outfits.filledSlots(for: event.id),
                                    cover: outfits.coverItem(for: event.id)
                                )
                            }
                            .buttonStyle(PressableStyle())
                            .calmFadeIn(delay: 0.05 * Double(index), duration: 0.5)
                        }
                    }
                    .padding(.top, 24)

                    if events.isEmpty {
                        AdminNote(text: "The celebrations will appear here soon.", symbol: "sparkles")
                    }

                    OutfitPrivacyLine()
                        .padding(.top, 34)
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 44)
                .readableWidth()
            }
            .scrollIndicators(.hidden)
            .background(BrandPalette.background.ignoresSafeArea())
            .navigationDestination(for: OutfitLookRoute.self) { route in
                OutfitLookView(eventID: route.eventID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(BrandLabel.font(size: 13, weight: .medium))
                        .foregroundStyle(BrandPalette.goldDeep)
                }
            }
        }
        .tint(BrandPalette.goldDeep)
        .task(id: session.userID) {
            outfits.syncUser()
            await outfits.refreshAll()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Your wedding week looks")

            Text("My Outfits")
                .brandFont(.screenTitle)
                .foregroundStyle(BrandPalette.ink)

            GoldRule(width: 58, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCard: some View {
        let total = events.count * OutfitCategory.allCases.count
        let filled = events.reduce(0) { $0 + outfits.filledSlots(for: $1.id) }
        let readyLooks = events.filter { outfits.filledSlots(for: $0.id) == OutfitCategory.allCases.count }.count

        return MatteCard(cornerRadius: 22) {
            HStack(spacing: 18) {
                OutfitProgressRing(filled: filled, total: max(total, 1), size: 62, lineWidth: 3, showsCount: false)
                    .overlay {
                        Text("\(readyLooks)")
                            .brandFont(.eventTitleSmall)
                            .foregroundStyle(BrandPalette.goldDeep)
                            .contentTransition(.numericText())
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(readyLooks == 1 ? "1 look ready" : "\(readyLooks) looks ready")
                        .brandFont(.outfitRowTitle)
                        .foregroundStyle(BrandPalette.ink)
                    Text(filled == 0
                        ? "Photograph your outfit, jewellery, shoes and accessories for each celebration."
                        : "\(filled) of \(total) pieces planned across the week.")
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}

/// One celebration in My Outfits.
private struct OutfitEventRow: View {
    let event: ScheduleEvent
    let filled: Int
    let cover: OutfitItem?

    var body: some View {
        HStack(spacing: 16) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .brandFont(.outfitRowTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = event.displayDate {
                    Text(date)
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                }
                if let dressCode = event.dressCode {
                    Text(dressCode)
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.goldDeep)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            OutfitProgressRing(filled: filled, size: 44)
        }
        .padding(12)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BrandPalette.card))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(filled == 4 ? BrandPalette.gold.opacity(0.5) : BrandPalette.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if let cover {
            OutfitThumbnail(path: cover.photoPath, iconSize: 20)
                .frame(width: 64, height: 80)
                .clipShape(shape)
        } else {
            shape
                .fill(BrandPalette.gold.opacity(0.05))
                .overlay(shape.strokeBorder(BrandPalette.gold.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                .overlay {
                    LineArtIcon(key: event.iconKey)
                        .stroke(BrandPalette.gold.opacity(0.75), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                        .frame(width: 28, height: 28)
                }
                .frame(width: 64, height: 80)
        }
    }
}
