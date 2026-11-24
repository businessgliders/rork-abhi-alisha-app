import SwiftUI

/// "My Experience": the guest's own week first (their looks, how the app keeps them posted,
/// and every answered question), then AVA Resort Cancún itself: photographs, both maps
/// and what's there.
struct ExperienceView: View {
    /// True while the My Experience tab is the one on screen.
    var isActive = true

    @Environment(ContentStore.self) private var content
    @Environment(DeepLinkRouter.self) private var router
    @Environment(ScheduleStore.self) private var schedule

    @State private var isShowingOutfits = false
    @State private var isShowingQuestions = false
    @State private var isShowingVenues = false
    @State private var isShowingToast = false
    @State private var isShowingPacking = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false

    private static let topAnchor = "experience.top"
    private static let resortAnchor = "experience.resort"

    var body: some View {
        ScrollViewReader { proxy in
            page
                .onChange(of: router.pendingResortSection) { _, _ in
                    openSectionIfAsked(proxy)
                }
                .onAppear { openSectionIfAsked(proxy) }
        }
        .fullScreenCover(isPresented: $isShowingOutfits) {
            MyOutfitsView()
        }
        .fullScreenCover(isPresented: $isShowingQuestions) {
            QuestionsView()
                .environment(content)
        }
        .fullScreenCover(isPresented: $isShowingVenues) {
            VenuesMapView()
                .environment(schedule)
        }
        .sheet(isPresented: $isShowingToast) {
            ToastWriterView()
                .environment(schedule)
                .environment(content)
        }
        .fullScreenCover(isPresented: $isShowingPacking) {
            PackingListView()
                .environment(schedule)
        }
        // The same confirmations behind Chat → … → Delete Account, reached from here.
        .chatAccountDialogs(isConfirmingSignOut: $isConfirmingSignOut, isConfirmingDelete: $isConfirmingDelete)
    }

    private var hasVenues: Bool { VenueMapPlot.hasAnyVenue(in: schedule.events) }

    private var venuesLink: some View {
        ExperienceRow(
            symbol: "map",
            title: String(localized: "The venues"),
            detail: String(localized: "Every celebration on one map, with directions.")
        ) {
            isShowingVenues = true
        }
    }

    private var toastLink: some View {
        ExperienceRow(
            symbol: "quote.opening",
            title: String(localized: "Write a toast"),
            detail: String(localized: "A few words for \(ActiveWedding.couple), drafted privately on your phone.")
        ) {
            isShowingToast = true
        }
    }

    private var packingLink: some View {
        ExperienceRow(
            symbol: "suitcase",
            title: String(localized: "Packing list"),
            detail: String(localized: "Made from your events, dress codes and the forecast.")
        ) {
            isShowingPacking = true
        }
    }

    /// Opens the same confirmation the Chat menu shows, then runs the same deletion.
    private var deleteAccountLink: some View {
        ExperienceRow(
            symbol: "person.crop.circle",
            title: String(localized: "Delete Account"),
            detail: String(localized: "Removes your name and every chat message, permanently.")
        ) {
            isConfirmingDelete = true
        }
    }

    /// An announcement asked for Travel & Stay (the resort half) or the FAQ.
    private func openSectionIfAsked(_ proxy: ScrollViewProxy) {
        guard let section = router.pendingResortSection else { return }
        router.pendingResortSection = nil
        Task {
            // Let the tab finish appearing before anything moves.
            try? await Task.sleep(for: .milliseconds(350))
            switch section {
            case .top:
                let anchor = showsResort ? Self.resortAnchor : Self.topAnchor
                withAnimation(.calm) { proxy.scrollTo(anchor, anchor: .top) }
            case .questions:
                isShowingQuestions = true
            }
        }
    }

    /// "Where we're staying" is AVA Resort Cancún: Abhi & Alisha's wedding only.
    private var showsResort: Bool { content.stay != nil }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .id(Self.topAnchor)

                SectionHeading(text: "Your week")
                    .padding(.horizontal, 22)
                    .padding(.top, 34)

                VStack(spacing: 12) {
                    MyOutfitsHomeCard { isShowingOutfits = true }
                    ExperienceUpdatesCard()
                    questionsLink
                    if hasVenues && !showsResort {
                        venuesLink
                    }
                    packingLink
                    toastLink
                    WalletPassButton()
                        .padding(.top, 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                SectionHeading(text: "Account")
                    .padding(.horizontal, 22)
                    .padding(.top, 42)

                VStack(spacing: 12) {
                    deleteAccountLink
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                if let stay = content.stay {
                    resortHeading
                        .padding(.horizontal, 22)
                        .padding(.top, 46)
                        .id(Self.resortAnchor)

                    if hasVenues {
                        venuesLink
                            .padding(.horizontal, 22)
                            .padding(.top, 18)
                    }

                    PhotosAndMaps(photos: content.resortPhotos, stay: stay)
                        .padding(.top, 18)

                    if !stay.amenities.isEmpty {
                        SectionHeading(text: "Amenities")
                            .padding(.horizontal, 22)
                            .padding(.top, 42)

                        AmenityRow(amenities: stay.resortAmenities)
                            .padding(.top, 18)
                    }
                }

                if !content.roomRates.isEmpty {
                    SectionHeading(text: "Room rates")
                        .padding(.horizontal, 22)
                        .padding(.top, 42)

                    RoomRatesList(rooms: content.roomRates)
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                }
            }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Your wedding week")

            Text("My Experience")
                .brandFont(.screenTitle)
                .foregroundStyle(BrandPalette.ink)

            GoldRule(width: 58, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resortHeading: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "Where we're staying")

            Text(ActiveWedding.place)
                .brandFont(.eventTitleSmall)
                .foregroundStyle(BrandPalette.ink)
                .padding(.top, 6)

            Text("Photographs, the resort map and the wing-by-wing guide.")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var questionsLink: some View {
        let count = content.faqs.count

        return ExperienceRow(
            symbol: "questionmark.bubble",
            title: "Questions & Answers",
            detail: count == 0
                ? "Travel, payments, transfers and more."
                : "\(count) answers from \(ActiveWedding.couple), all searchable."
        ) {
            isShowingQuestions = true
        }
    }
}

// MARK: - Rows

/// The shared matte row used across Experience's top half.
struct ExperienceRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    @ViewBuilder var trailing: Trailing

    init(
        symbol: String,
        title: String,
        detail: String,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
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
                            .brandFont(.bodyText)
                            .foregroundStyle(BrandPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detail)
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: 6)

                    trailing
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(PressableStyle())
    }
}

extension ExperienceRow where Trailing == ExperienceChevron {
    init(symbol: String, title: String, detail: String, action: @escaping () -> Void) {
        self.init(symbol: symbol, title: title, detail: detail, action: action) {
            ExperienceChevron()
        }
    }
}

struct ExperienceChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .light))
            .foregroundStyle(BrandPalette.gold)
    }
}

/// A small status pill: gold when on, quiet when off.
struct ExperienceStatusPill: View {
    let text: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(BrandLabel.font(size: 9.5, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
        }
        .foregroundStyle(isOn ? BrandPalette.goldDeep : BrandPalette.body.opacity(0.8))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(isOn ? BrandPalette.gold.opacity(0.14) : BrandPalette.hairline.opacity(0.6))
        )
        .fixedSize()
    }
}

/// How the app keeps this guest posted: wedding updates and Lock Screen follow-along.
struct ExperienceUpdatesCard: View {
    @Environment(PushRegistrar.self) private var push
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var areLiveActivitiesOn = EventActivityController.shared.areActivitiesEnabled

    var body: some View {
        VStack(spacing: 12) {
            ExperienceRow(
                symbol: "bell",
                title: "Wedding updates",
                detail: updatesDetail,
                action: tapUpdates
            ) {
                ExperienceStatusPill(text: push.isEnabled ? "On" : "Off", isOn: push.isEnabled)
            }

            ExperienceRow(
                symbol: "platter.filled.bottom.iphone",
                title: "Follow along on Lock Screen",
                detail: areLiveActivitiesOn
                    ? "Each celebration appears on your Lock Screen an hour before it begins."
                    : "Turn on Live Activities in Settings to follow each celebration.",
                action: openSettings
            ) {
                ExperienceStatusPill(text: areLiveActivitiesOn ? "On" : "Off", isOn: areLiveActivitiesOn)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            areLiveActivitiesOn = EventActivityController.shared.areActivitiesEnabled
        }
    }

    private var updatesDetail: String {
        if push.isEnabled { return "Schedule changes, shuttle times and moments not to miss." }
        if push.isDenied { return "Switched off for this app. Tap to turn them on in Settings." }
        return "Tap to hear about schedule changes and moments not to miss."
    }

    private func tapUpdates() {
        if push.isEnabled || push.isDenied {
            openSettings()
        } else {
            push.markOffered()
            push.isExplainerPresented = true
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}


// MARK: - Room rates

/// The couple's room types with their nightly rates, as guests see them.
struct RoomRatesList: View {
    let rooms: [WeddingContentItem]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rooms) { room in
                RoomRateCard(room: room)
            }
        }
        .animation(.calm, value: rooms)
    }
}

private struct RoomRateCard: View {
    let room: WeddingContentItem

    var body: some View {
        MatteCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(room.title ?? "Room")
                        .brandFont(.eventTitleSmall)
                        .foregroundStyle(BrandPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let adults = room.maxAdults, adults > 0 {
                        Text(Int(adults) == 1 ? "Up to 1 adult" : "Up to \(Int(adults)) adults")
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body)
                    }
                }

                HStack(alignment: .top, spacing: 0) {
                    rate("Sun – Wed", room.sunWedRate)
                    Rectangle()
                        .fill(BrandPalette.hairline)
                        .frame(width: 1)
                        .padding(.horizontal, 14)
                    rate("Thu – Sat", room.thuSatRate)
                }
                .fixedSize(horizontal: false, vertical: true)

                if let fee = room.extraAdultFee, fee > 0 {
                    Text("Extra adult \(money(fee)) a night")
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                }
                if let body = room.body, !body.isEmpty {
                    Text(body)
                        .brandFont(.bodyItalic)
                        .foregroundStyle(BrandPalette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func rate(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: label, size: 9.5)
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(money(value))
                        .font(Milni.cormorant(26, weight: 600))
                        .foregroundStyle(BrandPalette.ink)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("/ night")
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                }
            } else {
                Text("Ask the couple")
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func money(_ value: Double) -> String {
        let code = (room.currency?.uppercased()).flatMap { $0.count == 3 ? $0 : nil } ?? "USD"
        let whole = value.rounded() == value
        return value.formatted(.currency(code: code).precision(.fractionLength(whole ? 0 : 2)))
    }
}
