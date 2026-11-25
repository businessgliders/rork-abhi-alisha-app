import SwiftUI

/// Home: full-bleed dusk hero with the couple's names and live countdown, held still,
/// while the content sheet glides up over it like a layer laid on top.
struct HomeView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(ContentStore.self) private var content
    @Environment(DeepLinkRouter.self) private var router
    @Environment(\.openURL) private var openURL

    @State private var isShowingRSVP = false
    /// The party this guest last found, remembered between launches.
    @State private var rsvpMatch: RSVPRecord?
    /// How far the sheet has risen, 0 at rest to 1 once it covers the hero.
    @State private var coverage: CGFloat = 0
    @State private var isShowingOutfits = false
    @State private var phase = WeddingPhase.shared
    @State private var isShowingVenues = false
    /// The wedding week's weather at the main venue, from Apple Weather.
    @State private var weddingWeather: DayWeather?

    /// From noon on the day after the reception, Home becomes a thank-you.
    private var isThankYou: Bool { phase.isThankYou(at: store.now) }

    /// Still waiting for the couple to approve this phone's request.
    private var isPendingGuest: Bool {
        !ActiveWedding.snapshot.isSampleWedding
            && WeddingContext.shared.status?.lowercased() == "pending"
    }

    var body: some View {
        GeometryReader { proxy in
            let heroHeight = HeroHeader.height(for: proxy.size.height + proxy.safeAreaInsets.top)

            ZStack(alignment: .top) {
                // The photograph stays exactly where it is; only the sheet moves.
                HeroHeader(
                    ceremonyDate: store.mainCeremony?.startsAt,
                    heroPhotos: content.heroPhotos,
                    isThankYou: isThankYou
                )
                .frame(height: heroHeight)
                .overlay {
                    Color.black
                        .opacity(Double(coverage) * 0.45)
                        .allowsHitTesting(false)
                        .ignoresSafeArea(edges: .horizontal)
                }
                .accessibilityElement(children: .contain)

                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: heroHeight - HeroHeader.sheetOverlap)
                            .accessibilityHidden(true)

                        contentSheet
                    }
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in
                    let travel = max(heroHeight - HeroHeader.sheetOverlap, 1)
                    let next = min(max(offset / travel, 0), 1)
                    // Coarse steps keep the dimming smooth without redrawing every point.
                    let stepped = (next * 40).rounded() / 40
                    if stepped != coverage { coverage = stepped }
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(BrandPalette.heroFallback.ignoresSafeArea())
        .sheet(isPresented: $isShowingRSVP, onDismiss: syncMatch) {
            RSVPLookupSheet()
        }
        .fullScreenCover(isPresented: $isShowingOutfits) {
            MyOutfitsView()
        }
        .fullScreenCover(isPresented: $isShowingVenues) {
            VenuesMapView()
                .environment(store)
        }
        .animation(.calm, value: isThankYou)
        .onAppear {
            syncMatch()
            openRSVPIfAsked()
            // Back on Home (after the couple's area, say): bring the wedding row up to
            // date, keeping the last good names if the load fails.
            Task { await WeddingContext.shared.refreshCurrent() }
        }
        .onChange(of: router.pendingRSVP) { _, _ in
            openRSVPIfAsked()
        }
        .task {
            await store.refresh()
        }
        .task(id: ActiveWedding.snapshot.id) {
            await loadWeddingWeather()
        }
    }

    /// The place line; a button to the venues map whenever any venue can be placed.
    @ViewBuilder
    private var placeLine: some View {
        let place = Text(ActiveWedding.snapshot.placeWithCountry ?? "")
            .brandFont(.bodySmall)
            .tracking(0.4)
        if VenueMapPlot.hasAnyVenue(in: store.events) {
            Button {
                BrandHaptics.tick()
                isShowingVenues = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(BrandPalette.gold)
                    place
                        .foregroundStyle(BrandPalette.body.opacity(0.85))
                        .underline(color: BrandPalette.gold.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Opens a map of the venues")
        } else {
            place.foregroundStyle(BrandPalette.body.opacity(0.85))
        }
    }

    private func loadWeddingWeather() async {
        guard let place = WeatherPlace.forWedding(),
              let date = store.mainCeremony?.startsAt ?? ActiveWedding.snapshot.start
        else {
            weddingWeather = nil
            return
        }
        let fetched = await WeddingWeather.shared.weather(key: "wedding-" + ActiveWedding.snapshot.id, for: date, at: place)
        withAnimation(.softFade) { weddingWeather = fetched }
    }

    private var contentSheet: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(BrandPalette.gold.opacity(0.35))
                .frame(width: 34, height: 2)
                .padding(.top, 20)

            if isThankYou {
                ThankYouLinks(
                    onGallery: openGallery,
                    onOutfits: { isShowingOutfits = true },
                    onChat: { DeepLinkRouter.shared.open(.tab(.chat)) }
                )
                .transition(.opacity)
            } else {
                if isPendingGuest {
                    PendingInvitationCard()
                        .transition(.opacity)
                }

                HappeningNowBanner(events: store.events)

                if ActiveWedding.snapshot.isMilniWedding {
                    rsvpBlock
                } else if let link = rsvpLink {
                    rsvpBar(hint: "Opens the couple's RSVP page in Safari") {
                        openURL(link)
                    }
                }

                if let next = store.nextEvent {
                    NextEventCard(event: next)
                } else if store.events.isEmpty && !store.isRefreshing {
                    WeddingEmptyState()
                }

                NotifyUpdatesCard()

                MyOutfitsHomeCard {
                    isShowingOutfits = true
                }
            }

            VStack(spacing: 12) {
                GoldRule(width: 30, opacity: 0.55)
                placeLine

                if let weddingWeather, !isThankYou {
                    Label {
                        Text(weddingWeather.pillText)
                    } icon: {
                        Image(systemName: weddingWeather.symbolName)
                            .symbolRenderingMode(.multicolor)
                    }
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body.opacity(0.85))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Weather for the wedding: \(weddingWeather.accessibilityText)"))
                    .transition(.opacity)

                    WeatherAttributionFooter()
                        .frame(maxWidth: 220)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.top, 6)

            madeWithLove
                .padding(.top, 34)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, FloatingTabBar.contentReserve + 34)
        .readableWidth()
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            // The sheet carries the page colour well past its end, so pulling up past the
            // bottom never shows the photograph behind it.
            UnevenRoundedRectangle(
                topLeadingRadius: 30,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 30,
                style: .continuous
            )
            .fill(BrandPalette.background)
            .padding(.bottom, -600)
            .shadow(color: Color.black.opacity(0.18), radius: 18, y: -4)
            .ignoresSafeArea(edges: .horizontal)
        }
    }

    /// The quiet signature at the very bottom of the screen.
    private var madeWithLove: some View {
        Text("Made with ❤️ by JG in 🇨🇦")
            .font(BrandLabel.font(size: 9.5, weight: .medium))
            .tracking(1.6)
            .foregroundStyle(BrandPalette.body.opacity(0.5))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// A greeting once we know who's holding the phone, the invitation to look up
    /// otherwise.
    @ViewBuilder
    private var rsvpBlock: some View {
        if let rsvpMatch {
            RSVPWelcomeCard(
                record: rsvpMatch,
                onOpenDetails: { isShowingRSVP = true },
                onReset: forgetMatch
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            rsvpBar(hint: "Look up your reply by the name on your invitation") {
                isShowingRSVP = true
            }
            .transition(.opacity)
        }
    }

    private func syncMatch() {
        let latest = RSVPService.shared.lastMatch
        let changed = latest?.id != rsvpMatch?.id
        withAnimation(.calm) {
            rsvpMatch = latest
        }
        if changed {
            // So the couple's list knows whose phone this is.
            PushRegistrar.shared.guestNameMayHaveChanged()
        }
    }

    private func openGallery() {
        router.pendingStoryGallery = true
        router.open(.tab(.story))
    }

    /// An announcement asked for the RSVP: open the lookup straight away, unless the
    /// wedding is over and the RSVP has nothing left to say.
    private func openRSVPIfAsked() {
        guard router.pendingRSVP else { return }
        guard !isThankYou else {
            router.pendingRSVP = false
            return
        }
        router.pendingRSVP = false
        isShowingRSVP = true
    }

    private func forgetMatch() {
        RSVPService.shared.forgetLastMatch()
        withAnimation(.calm) {
            rsvpMatch = nil
        }
        PushRegistrar.shared.guestNameMayHaveChanged()
    }

    /// The couple's own RSVP page, when they set one.
    private var rsvpLink: URL? {
        guard let text = ActiveWedding.snapshot.rsvpURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        let full = text.lowercased().hasPrefix("http") ? text : "https://" + text
        return URL(string: full)
    }

    private func rsvpBar(hint: String, action: @escaping () -> Void) -> some View {
        Button {
            BrandHaptics.soft()
            action()
        } label: {
            HStack(spacing: 12) {
                Text("Find your RSVP details")
                    .font(BrandLabel.font(size: 12.5, weight: .semibold))
                    .tracking(1.5)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color(hex: 0xFFFBF1))
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [BrandPalette.gold, BrandPalette.goldDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BrandPalette.goldPale.opacity(0.5), lineWidth: 0.75)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint(hint)
    }
}

/// The hero: the couple's crossfading photographs, string of lights, their typed names,
/// and the countdown. The crest in the corner is the only mark above the names.
private struct HeroHeader: View {
    /// How far the content sheet rises over the photograph.
    static let sheetOverlap: CGFloat = 30

    /// A shade shorter than full-bleed, so the RSVP bar and next event sit just above
    /// the fold and only the signature waits below it.
    static func height(for screenHeight: CGFloat) -> CGFloat {
        min(max(screenHeight * 0.61, 400), 646)
    }

    let ceremonyDate: Date?
    let heroPhotos: [GalleryPhoto]
    var isThankYou = false

    /// Always the current wedding row (`partner_one` / `partner_two`), observed so the
    /// names redraw the moment it changes.
    private var wedding: WeddingSnapshot { WeddingContext.shared.snapshot }

    var body: some View {
        // Only the photograph runs under the side safe areas (the status strip on a
        // wide screen); the names and countdown stay inside them.
        Color.clear
            .background {
                photograph
                    .ignoresSafeArea(edges: .horizontal)
            }
            .overlay(alignment: .top) {
                DecorativeLightString()
                    .padding(.top, 38)
            }
            .overlay(alignment: .bottom) {
                heroContent
                    .padding(.horizontal, 26)
                    .padding(.bottom, 58)
                    .readableWidth(560)
            }
    }

    private var photograph: some View {
        Color(BrandPalette.heroFallback)
            .overlay {
                HeroSlideshow(photos: heroPhotos)
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.34), location: 0),
                        .init(color: Color.black.opacity(0.06), location: 0.32),
                        .init(color: Color.black.opacity(0.5), location: 0.66),
                        .init(color: Color.black.opacity(0.82), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .clipped()
    }

    private var heroContent: some View {
        VStack(spacing: 0) {
            names

            GoldRule(width: 46, opacity: 0.7)
                .padding(.top, 18)
                .calmFadeIn(delay: 2.5)

            if isThankYou {
                Text("Thank you for celebrating with us")
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(Color(hex: 0xFDFAF3))
                    .multilineTextAlignment(.center)
                    .shadow(color: Color.black.opacity(0.35), radius: 10, y: 3)
                    .padding(.top, 22)
                    .calmFadeIn(delay: 2.75)
            } else if let ceremonyDate {
                // The date types itself in once the countdown has settled into view.
                CountdownView(target: ceremonyDate, dateStartDelay: 3.15)
                    .padding(.top, 22)
                    .calmFadeIn(delay: 2.75)
            }
        }
    }

    // The names arrive letter by letter: Abhi, then the gold ampersand, then Alisha.
    // A name that hasn't loaded never leaves a lone "&" on the hero: the wedding's
    // title stands in until the row arrives.
    @ViewBuilder
    private var names: some View {
        if wedding.partnerOne.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || wedding.partnerTwo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            TypewriterText(
                text: wedding.coupleNames,
                spec: .heroNames,
                color: Color(hex: 0xFDFAF3),
                startDelay: 0.75,
                shadow: Color.black.opacity(0.35)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(wedding.coupleNamesSpoken)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    firstName
                    ampersand
                    secondName
                }

                VStack(spacing: 0) {
                    firstName
                    ampersand
                    secondName
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(wedding.coupleNamesSpoken)
        }
    }

    private var firstName: some View {
        TypewriterText(
            text: wedding.partnerOne,
            spec: .heroNames,
            color: Color(hex: 0xFDFAF3),
            startDelay: 0.75,
            shadow: Color.black.opacity(0.35)
        )
    }

    private var secondName: some View {
        TypewriterText(
            text: wedding.partnerTwo,
            spec: .heroNames,
            color: Color(hex: 0xFDFAF3),
            startDelay: 1.85,
            shadow: Color.black.opacity(0.35)
        )
    }

    private var ampersand: some View {
        Text("&")
            .brandFont(.heroNames)
            .foregroundStyle(Color(hex: 0xD9BE74))
            .shadow(color: Color.black.opacity(0.3), radius: 10, y: 3)
            .accessibilityHidden(true)
            .calmFadeIn(delay: 1.4, duration: 0.85)
    }
}

/// A guest whose request is still waiting: the wedding's names and a gentle note
/// that the couple has yet to let them in.
private struct PendingInvitationCard: View {
    private var snapshot: WeddingSnapshot { ActiveWedding.snapshot }

    var body: some View {
        MatteCard(cornerRadius: 24) {
            HStack(spacing: 18) {
                MilniRings(color: BrandPalette.gold, lineWidth: 0.9, duration: 3.2, showsOuter: false, breathes: true, delay: 0.4)
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow(text: "You're invited")

                    Text(snapshot.coupleNames)
                        .brandFont(.eventTitleSmall)
                        .foregroundStyle(BrandPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Waiting for the couple to let you in")
                        .brandFont(.bodyText)
                        .foregroundStyle(BrandPalette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The next celebration still to come.
private struct NextEventCard: View {
    let event: ScheduleEvent

    var body: some View {
        MatteCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: "Next")

                Text(event.title)
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.trailing, 48)

                if !details.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(details, id: \.self) { line in
                            Text(line)
                                .brandFont(.bodyText)
                                .foregroundStyle(BrandPalette.body)
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                IconWatermark(key: event.iconKey, size: 80, opacity: 0.15)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
        }
    }

    private var details: [String] {
        var lines: [String] = []
        let timing = [event.displayDate, event.displayTime].compactMap { $0 }
        if !timing.isEmpty {
            lines.append(timing.joined(separator: "  ·  "))
        }
        if let locationName = event.locationName {
            lines.append(locationName)
        }
        return lines
    }
}

/// Calm press feedback — a slight settle, never a bounce.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.22), value: configuration.isPressed)
    }
}
