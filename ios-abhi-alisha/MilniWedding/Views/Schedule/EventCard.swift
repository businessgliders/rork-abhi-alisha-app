import SwiftUI

/// The matte event card. Every element is omitted when its field is empty —
/// nothing renders as null, zero, or an empty row.
///
/// In `fillsHeight` mode the card takes the space the schedule screen gives it and
/// long descriptions scroll inside; the title, chips and location never move.
///
/// With `showsAttirePreview` (iPad portrait, where the card is tall), the description
/// takes only the room it needs and the couple's attire photos fill the rest.
struct EventCard: View {
    let event: ScheduleEvent
    var weather: DayWeather?
    var fillsHeight = false
    var showsAttirePreview = false
    var onOpenDetails: (() -> Void)?

    @State private var descriptionHeight: CGFloat = 0

    var body: some View {
        EmbossedPaperCard(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .brandFont(.eventTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, weather == nil ? 0 : 84)

                GoldRule(width: 44, alignment: .leading)
                    .debossed()
                    .padding(.top, 14)

                description
                    .padding(.top, 14)

                chips
                    .padding(.top, 16)

                if showsAttirePreview {
                    CardAttirePreview(event: event, onTap: openDetails)
                        .padding(.top, 22)
                }

                if event.locationName != nil || event.displayTime != nil {
                    whereAndWhen
                        .padding(.top, 18)
                }

                if let date = event.displayDate {
                    dateLine(date)
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 26)
            .padding(.bottom, 22)
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsHeight ? .infinity : nil,
                alignment: .topLeading
            )
            // Faint, behind the title, tucked under the weather chip and well clear of
            // the location row.
            .background(alignment: .topTrailing) {
                IconWatermark(key: event.iconKey, size: 96, opacity: 0.14)
                    .debossed()
                    .padding(.top, weather == nil ? 18 : 58)
                    .padding(.trailing, 16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                if let weather {
                    WeatherChip(weather: weather, onTap: openDetails)
                        .padding(.top, 20)
                        .padding(.trailing, 20)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture {
            openDetails()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open event details") {
            openDetails()
        }
    }

    // MARK: - Pieces

    /// Scrolls inside the card when the copy is longer than the space available.
    @ViewBuilder
    private var description: some View {
        if let description = event.description {
            let text = Text(description)
                .brandFont(.bodyItalic)
                .lineSpacing(BrandFontSpec.bodyItalic.lineSpacing)
                .foregroundStyle(BrandPalette.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if fillsHeight && showsAttirePreview {
                // Only as tall as the copy, and first to claim space; it still scrolls if
                // the copy outgrows the card.
                ScrollView(.vertical) {
                    text
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { descriptionHeight = $0 }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(minHeight: 0, maxHeight: max(descriptionHeight, 1), alignment: .top)
                .layoutPriority(1)
            } else if fillsHeight {
                ScrollView(.vertical) {
                    text
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                text
            }
        }
    }

    /// The dress code's colour, and the invitation to open the full details.
    /// They wrap onto a second line rather than squeeze when the type is large.
    @ViewBuilder
    private var chips: some View {
        if event.dressCode != nil || onOpenDetails != nil {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                if let dressCode = event.dressCode {
                    AttireChip(dressCode: dressCode, onTap: openDetails)
                }

                if onOpenDetails != nil {
                    DetailsInvitation(action: openDetails)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The start time reads as prominently as the venue, on one centred line.
    /// Its label is deliberately faint — the venue and time carry the weight.
    private var whereAndWhen: some View {
        VStack(spacing: 8) {
            Eyebrow(
                text: "Location & Time",
                color: BrandPalette.gold.opacity(0.55),
                size: 8.5
            )

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                timeText
                separatorDot
                locationText
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var timeText: some View {
        if let time = event.displayTime {
            Text(time)
                .brandFont(.eventTitleSmall)
                .foregroundStyle(BrandPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    @ViewBuilder
    private var locationText: some View {
        if let locationName = event.locationName {
            Text(locationName)
                .brandFont(.bodyText)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var separatorDot: some View {
        if event.displayTime != nil && event.locationName != nil {
            Circle()
                .fill(BrandPalette.gold.opacity(0.6))
                .frame(width: 3, height: 3)
                .offset(y: -5)
                .accessibilityHidden(true)
        }
    }

    /// The date closes the card, in small gold caps.
    private func dateLine(_ date: String) -> some View {
        Text(date.uppercased())
            .font(BrandLabel.font(size: 9.5, weight: .semibold))
            .tracking(2.4)
            .foregroundStyle(BrandPalette.gold.opacity(0.75))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func openDetails() {
        guard let onOpenDetails else { return }
        BrandHaptics.soft()
        onOpenDetails()
    }
}

// MARK: - Attire preview

extension ScheduleEvent {
    /// The couple's outfit suggestion photographs that can actually be shown.
    var attirePhotos: [OutfitPhoto] {
        (outfitPhotos ?? []).filter { $0.imageURL != nil || $0.lightboxURL != nil }
    }
}

/// On a tall card: up to four of the couple's attire photographs in a row, with the
/// guest's own look progress beside the heading. Either opens the details.
private struct CardAttirePreview: View {
    let event: ScheduleEvent
    let onTap: () -> Void

    @State private var outfits = OutfitStore.shared

    private var photos: [OutfitPhoto] { Array(event.attirePhotos.prefix(4)) }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Eyebrow(text: "Attire inspiration", color: BrandPalette.gold.opacity(0.8), size: 9.5)
                    Spacer(minLength: 8)
                    if !event.isFarewell {
                        progress
                    }
                }

                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        BrandPalette.hairline.opacity(0.7)
                            .aspectRatio(0.78, contentMode: .fit)
                            .overlay {
                                RemoteImage(url: URL(string: photo.imageURL ?? photo.lightboxURL ?? ""), contentMode: .fill)
                                    .allowsHitTesting(false)
                            }
                            .clipShape(.rect(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(BrandPalette.gold.opacity(0.25), lineWidth: 0.75)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Attire inspiration and my outfit")
        .accessibilityHint("Opens the event details")
    }

    private var progress: some View {
        let filled = outfits.filledSlots(for: event.id)
        return HStack(spacing: 7) {
            OutfitProgressRing(filled: filled, size: 22, lineWidth: 2, showsCount: false)
            Text(filled == 0 ? "Plan my outfit" : "My outfit · \(filled) of 4 added")
                .font(BrandLabel.font(size: 10.5, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(BrandPalette.body)
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 11)
        .padding(.vertical, 5)
        .background(Capsule(style: .continuous).fill(BrandPalette.background.opacity(0.55)))
        .overlay(Capsule(style: .continuous).stroke(BrandPalette.hairline, lineWidth: 0.75))
    }
}

// MARK: - Compact chips

/// The day's forecast as a glyph and a temperature, in the card's top corner.
private struct WeatherChip: View {
    let weather: DayWeather
    let onTap: () -> Void

    var body: some View {
        ChipShell(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: weather.symbolName)
                    .symbolVariant(.none)
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(BrandPalette.goldDeep)

                Text(weather.chipText)
                    .font(BrandLabel.font(size: 11.5, weight: .medium))
                    .foregroundStyle(BrandPalette.body)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("Weather: \(weather.accessibilityText)")
    }
}

/// The dress code as its colour, beside a garment glyph. Tapping opens the detail pane.
private struct AttireChip: View {
    let dressCode: String
    let onTap: () -> Void

    private var swatch: AttireSwatch { AttireSwatch.infer(from: dressCode) }

    var body: some View {
        ChipShell(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(swatch.gradient)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(swatch.ringColor, lineWidth: 0.5))

                Image(systemName: "tshirt")
                    .symbolVariant(.none)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(BrandPalette.goldDeep)

                Text(swatch.label)
                    .font(BrandLabel.font(size: 11, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(BrandPalette.body)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("Attire: \(dressCode)")
    }
}

/// The spoken invitation beside the attire chip, in place of a bare arrow.
private struct DetailsInvitation: View {
    let action: () -> Void

    var body: some View {
        ChipShell(action: action) {
            HStack(spacing: 7) {
                Text("Tap to view all details")
                    .font(BrandLabel.font(size: 11, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(BrandPalette.body)
                    .lineLimit(1)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(BrandPalette.goldDeep)
            }
        }
        .accessibilityLabel("Open event details")
    }
}

/// Shared rounded chip surface — matte, hairline, and no larger than it needs to be.
private struct ChipShell<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(BrandPalette.background.opacity(0.55))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(BrandPalette.hairline, lineWidth: 0.75)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(.isButton)
    }
}

/// Minimal wrapping layout for pill badges.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                widestRow = max(widestRow, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        widestRow = max(widestRow, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: min(widestRow, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
