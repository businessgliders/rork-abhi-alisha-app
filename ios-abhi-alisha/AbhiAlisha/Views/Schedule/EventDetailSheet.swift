import SwiftUI

/// Everything about one celebration that doesn't fit on the card: attire with
/// full-width outfit inspiration, questions, the venue, and adding it to your calendar.
/// The description is deliberately left out — it already reads on the card.
struct EventDetailSheet: View {
    let event: ScheduleEvent
    var weather: DayWeather?

    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var store

    @State private var expandedFAQID: String?
    @State private var lightboxPhoto: OutfitPhoto?
    @State private var calendarOutcome: CalendarService.Outcome?
    @State private var isSavingToCalendar = false
    @State private var followNotice: String?
    @State private var isShowingFullMap = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock

                    if !badges.isEmpty {
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(badges) { badge in
                                BrandPill(text: badge.text, tone: badge.tone)
                            }
                        }
                        .padding(.top, 22)
                    }

                    if let dressCode = event.dressCode {
                        attireSection(dressCode: dressCode)
                            .padding(.top, 34)
                    }

                    if let photos, event.dressCode == nil {
                        section(title: "Outfit Inspiration") {
                            outfitStrip(photos)
                        }
                        .padding(.top, 34)
                    }

                    if let faqs {
                        section(title: "Good to Know") {
                            VStack(spacing: 0) {
                                ForEach(faqs) { faq in
                                    faqRow(faq)
                                }
                            }
                        }
                        .padding(.top, 34)
                    }

                    section(title: "Where") {
                        venueBlock
                    }
                    .padding(.top, 34)

                    if canFollowLive {
                        followControl
                            .padding(.top, 34)
                    }

                    if canAddToCalendar {
                        calendarButton
                            .padding(.top, canFollowLive ? 14 : 34)
                    }

                    if let calendarOutcome {
                        Text(calendarOutcome.message)
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 44)
                .readableWidth()
            }
            .scrollIndicators(.hidden)
            .background(BrandPalette.background.ignoresSafeArea())
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
        .fullScreenCover(item: $lightboxPhoto) { photo in
            OutfitLightbox(photo: photo)
        }
        .fullScreenCover(isPresented: $isShowingFullMap) {
            ResortMapScreen(focusEventID: event.id, returnsToEventID: event.id)
        }
    }

    // MARK: - Blocks

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "The Celebrations")

            Text(event.title)
                .brandFont(.eventTitle)
                .foregroundStyle(BrandPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            if let timing {
                Text(timing)
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.body)
                    .padding(.top, 8)
            }

            GoldRule(width: 44, alignment: .leading)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            IconWatermark(key: event.iconKey, size: 84, opacity: 0.2)
                .offset(y: -4)
        }
    }

    private func attireSection(dressCode: String) -> some View {
        section(title: "Attire") {
            VStack(alignment: .leading, spacing: 20) {
                Text(dressCode)
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let photos {
                    outfitStrip(photos)
                }
            }
        }
    }

    /// Inspiration photographs run the full width of the sheet, stacked one under another.
    private func outfitStrip(_ photos: [OutfitPhoto]) -> some View {
        VStack(spacing: 18) {
            ForEach(photos) { photo in
                Button {
                    BrandHaptics.soft()
                    lightboxPhoto = photo
                } label: {
                    OutfitPlate(photo: photo)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(photo.caption ?? "Outfit inspiration")
            }
        }
    }

    /// Venue name, address, and this celebration's own corner of the resort map.
    private var venueBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            if event.locationName != nil || event.locationAddress != nil || event.resortMapLabel != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let name = event.locationName {
                        Text(name)
                            .brandFont(.bodyText)
                            .foregroundStyle(BrandPalette.ink)
                    }
                    if let address = event.locationAddress {
                        Text(address)
                            .brandFont(.bodyItalic)
                            .foregroundStyle(BrandPalette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let label = event.resortMapLabel {
                        Text(label)
                            .font(BrandLabel.font(size: 11, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(BrandPalette.goldDeep)
                            .padding(.top, 2)
                    }
                }
            }

            if let pin = mapPin {
                mapExcerpt(pin)
            }
        }
    }

    /// The resort map held on this celebration's own pin, with the way through to the
    /// whole thing. Left out entirely when the couple haven't placed this one.
    private func mapExcerpt(_ pin: ResortMapPin) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        return Button {
            BrandHaptics.soft()
            isShowingFullMap = true
        } label: {
            VStack(spacing: 0) {
                ResortMapCanvas(
                    pins: mapPins,
                    currentPinID: pin.id,
                    selectedPinID: pin.id,
                    focus: ResortMapFocus(pinID: pin.id, zoom: 3.6),
                    isInteractive: false
                )
                .frame(height: 186)

                HStack(spacing: 8) {
                    Text("View full map")
                        .font(BrandLabel.font(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .textCase(.uppercase)

                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(BrandPalette.goldDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(BrandPalette.card)
            }
            .clipShape(shape)
            .overlay(shape.stroke(BrandPalette.gold.opacity(0.3), lineWidth: 0.75))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("View the full resort map")
    }

    private func faqRow(_ faq: EventFAQ) -> some View {
        let isOpen = expandedFAQID == faq.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                BrandHaptics.tick()
                withAnimation(.calm) {
                    expandedFAQID = isOpen ? nil : faq.id
                }
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Text(faq.question ?? "")
                        .brandFont(.bodyText)
                        .foregroundStyle(BrandPalette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(BrandPalette.gold)
                        .rotationEffect(.degrees(isOpen ? 0 : -90))
                        .padding(.top, 5)
                }
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen, let answer = faq.answer {
                Text(answer)
                    .brandFont(.bodyItalic)
                    .lineSpacing(BrandFontSpec.bodyItalic.lineSpacing)
                    .foregroundStyle(BrandPalette.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Rectangle()
                .fill(BrandPalette.hairline)
                .frame(height: 1)
        }
    }

    /// Puts this celebration on the Lock Screen and in the Dynamic Island, counting down
    /// to it and then saying it is underway. It retires itself when the event ends.
    @ViewBuilder
    private var followControl: some View {
        let isFollowing = EventActivityController.shared.isFollowing(event)

        VStack(spacing: 10) {
            Button {
                toggleFollow(isFollowing: isFollowing)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isFollowing ? "checkmark" : "sparkles")
                        .font(.system(size: 13, weight: .light))
                    Text(isFollowing ? "Following This Event" : "Follow This Event")
                        .font(BrandLabel.font(size: 12, weight: .semibold))
                        .tracking(1.5)
                }
                .foregroundStyle(isFollowing ? Color(hex: 0xFFFBF1) : BrandPalette.goldDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            isFollowing
                                ? LinearGradient(
                                    colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(BrandPalette.gold.opacity(isFollowing ? 0.35 : 0.55), lineWidth: 1)
                )
            }
            .buttonStyle(PressableStyle())

            Text(followNotice ?? (isFollowing
                ? "On your Lock Screen until this celebration ends."
                : "Keep a countdown on your Lock Screen."))
                .brandFont(.bodySmall)
                .foregroundStyle(BrandPalette.body.opacity(0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    private func toggleFollow(isFollowing: Bool) {
        BrandHaptics.soft()
        if isFollowing {
            Task {
                await EventActivityController.shared.stopFollowing(event)
                withAnimation(.softFade) { followNotice = nil }
            }
            return
        }

        let started = EventActivityController.shared.follow(event)
        withAnimation(.softFade) {
            followNotice = started
                ? nil
                : "Turn on Live Activities for this app in Settings to follow along."
        }
    }

    private var calendarButton: some View {
        Button {
            saveToCalendar()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .light))
                Text("Add to Calendar")
                    .font(BrandLabel.font(size: 12, weight: .semibold))
                    .tracking(1.5)
            }
            .foregroundStyle(BrandPalette.goldDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(BrandPalette.gold.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(isSavingToCalendar)
        .opacity(isSavingToCalendar ? 0.55 : 1)
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: title, size: 10.5)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Derived

    private var timing: String? {
        let parts = [event.displayDate, event.displayTime].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "  ·  ")
    }

    private var photos: [OutfitPhoto]? {
        let valid = (event.outfitPhotos ?? []).filter { $0.imageURL != nil || $0.lightboxURL != nil }
        return valid.isEmpty ? nil : valid
    }

    /// Every plotted celebration, so the number on this pin matches the legend's.
    private var mapPins: [ResortMapPin] {
        ResortMapPlot.pins(from: store.events)
    }

    private var mapPin: ResortMapPin? {
        mapPins.first { $0.id == event.id }
    }

    private var faqs: [EventFAQ]? {
        let valid = (event.faqs ?? []).filter { ($0.question?.isEmpty == false) && ($0.answer?.isEmpty == false) }
        return valid.isEmpty ? nil : valid
    }

    /// Hidden entirely when there is no confirmed start time to save.
    private var canAddToCalendar: Bool {
        event.startsAt != nil && !event.isTimeToBeAnnounced
    }

    /// Offered only while there is still something to count down to.
    private var canFollowLive: Bool {
        guard let startsAt = event.startsAt, !event.isTimeToBeAnnounced else { return false }
        let end = event.endsAt ?? startsAt.addingTimeInterval(2 * 3600)
        return end > Date()
    }

    private struct Badge: Identifiable {
        let id = UUID()
        let text: String
        let tone: PillTone
    }

    private var badges: [Badge] {
        var result: [Badge] = []
        if let weather {
            result.append(Badge(text: weather.pillText, tone: .neutral))
        }
        switch event.ceremonyType {
        case .sikh:
            result.append(Badge(text: "Sikh Ceremony", tone: .sikh))
        case .hindu:
            result.append(Badge(text: "Hindu Ceremony", tone: .hindu))
        case .none:
            break
        }
        return result
    }

    private func saveToCalendar() {
        guard !isSavingToCalendar else { return }
        isSavingToCalendar = true
        BrandHaptics.soft()
        Task {
            let outcome = await CalendarService.shared.add(event)
            withAnimation(.softFade) {
                calendarOutcome = outcome
            }
            isSavingToCalendar = false
        }
    }
}

/// A full-width inspiration photograph in its natural proportions, with a hairline frame.
private struct OutfitPlate: View {
    let photo: OutfitPhoto

    private var url: URL? {
        URL(string: photo.imageURL ?? photo.lightboxURL ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RemoteImage(url: url, contentMode: .fit, aspectRatio: 16.0 / 9.0)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(BrandPalette.gold.opacity(0.3), lineWidth: 0.75)
                )

            if let caption = photo.caption {
                Text(caption)
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Full-screen look at one outfit photograph.
private struct OutfitLightbox: View {
    let photo: OutfitPhoto

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = URL(string: photo.lightboxURL ?? photo.imageURL ?? "") {
                RemoteImage(url: url, contentMode: .fit) {
                    ProgressView().tint(BrandPalette.goldPale)
                }
                .padding(.horizontal, 8)
            }

            if let caption = photo.caption {
                VStack {
                    Spacer()
                    Text(caption)
                        .brandFont(.bodyItalic)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 44)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(PressableStyle())
            .padding(.trailing, 18)
            .padding(.top, 12)
            .accessibilityLabel("Close photograph")
        }
    }
}
