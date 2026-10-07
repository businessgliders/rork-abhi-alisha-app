import SwiftUI

/// "My Experience": the guest's own week first (their looks, how the app keeps them posted,
/// and every answered question), then AVA Resort Cancún itself: photographs, both maps
/// and what's there.
struct ExperienceView: View {
    /// True while the My Experience tab is the one on screen.
    var isActive = true

    @Environment(ContentStore.self) private var content
    @Environment(DeepLinkRouter.self) private var router

    @State private var isShowingOutfits = false
    @State private var isShowingQuestions = false

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
                withAnimation(.calm) { proxy.scrollTo(Self.resortAnchor, anchor: .top) }
            case .questions:
                isShowingQuestions = true
            }
        }
    }

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
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                resortHeading
                    .padding(.horizontal, 22)
                    .padding(.top, 46)
                    .id(Self.resortAnchor)

                PhotosAndMaps(photos: content.resortPhotos)
                    .padding(.top, 18)

                FullMapLink()
                    .padding(.horizontal, 22)
                    .padding(.top, 14)

                SectionHeading(text: "Amenities")
                    .padding(.horizontal, 22)
                    .padding(.top, 42)

                AmenityRow(amenities: ResortAmenity.all)
                    .padding(.top, 18)
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

            Text("AVA Resort Cancún")
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
                : "\(count) answers from Abhi & Alisha, all searchable."
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

/// Opens the resort's official map PDF, kept on the phone once it has loaded.
private struct FullMapLink: View {
    @State private var isShowingPDF = false

    var body: some View {
        Button {
            BrandHaptics.soft()
            isShowingPDF = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 12, weight: .light))
                Text("View full map (PDF)")
                    .font(BrandLabel.font(size: 11, weight: .semibold))
                    .tracking(1.3)
                    .textCase(.uppercase)
                Spacer(minLength: 6)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .regular))
            }
            .foregroundStyle(BrandPalette.goldDeep)
            .padding(.horizontal, 18)
            .frame(minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BrandPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BrandPalette.gold.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .fullScreenCover(isPresented: $isShowingPDF) {
            ResortPDFViewer()
        }
    }
}
