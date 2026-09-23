import SwiftUI

/// Home: full-bleed dusk hero with the couple's names and live countdown,
/// then a content sheet that rises over the photograph.
struct HomeView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(ContentStore.self) private var content

    @State private var isShowingRSVP = false
    /// The party this guest last found, remembered between launches.
    @State private var rsvpMatch: RSVPRecord?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HeroHeader(
                    ceremonyDate: store.mainCeremony?.startsAt,
                    heroPhotos: content.heroPhotos
                )

                contentSheet
                    .offset(y: -HeroHeader.sheetOverlap)
            }
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $isShowingRSVP, onDismiss: syncMatch) {
            RSVPLookupSheet()
        }
        .onAppear(perform: syncMatch)
        .task {
            await store.refresh()
        }
    }

    private var contentSheet: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(BrandPalette.gold.opacity(0.35))
                .frame(width: 34, height: 2)
                .padding(.top, 20)

            rsvpBlock

            NotifyUpdatesCard()

            if let next = store.nextEvent {
                NextEventCard(event: next)
            }

            VStack(spacing: 12) {
                GoldRule(width: 30, opacity: 0.55)
                Text("AVA Resort Cancún · Mexico")
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body.opacity(0.85))
                    .tracking(0.4)
            }
            .padding(.top, 6)

            madeWithLove
                .padding(.top, 34)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, FloatingTabBar.contentReserve + 34)
        .readableWidth()
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 30,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 30,
                style: .continuous
            )
            .fill(BrandPalette.background)
        )
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
            rsvpBar
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

    private func forgetMatch() {
        RSVPService.shared.forgetLastMatch()
        withAnimation(.calm) {
            rsvpMatch = nil
        }
        PushRegistrar.shared.guestNameMayHaveChanged()
    }

    private var rsvpBar: some View {
        Button {
            BrandHaptics.soft()
            isShowingRSVP = true
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
                            colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(hex: 0xE0C982).opacity(0.5), lineWidth: 0.75)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Look up your reply by the name on your invitation")
    }
}

/// The hero: the couple's crossfading photographs, string of lights, their typed names,
/// and the countdown. The crest in the corner is the only mark above the names.
private struct HeroHeader: View {
    /// How far the content sheet rises over the photograph.
    static let sheetOverlap: CGFloat = 30

    let ceremonyDate: Date?
    let heroPhotos: [GalleryPhoto]

    var body: some View {
        // A shade shorter than full-bleed, so the RSVP bar and next event sit just above
        // the fold and only the signature waits below it.
        Color(BrandPalette.heroFallback)
            .containerRelativeFrame(.vertical) { length, _ in
                min(max(length * 0.61, 400), 646)
            }
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
            .clipped()
    }

    private var heroContent: some View {
        VStack(spacing: 0) {
            names

            GoldRule(width: 46, opacity: 0.7)
                .padding(.top, 18)
                .calmFadeIn(delay: 2.5)

            if let ceremonyDate {
                // The date types itself in once the countdown has settled into view.
                CountdownView(target: ceremonyDate, dateStartDelay: 3.15)
                    .padding(.top, 22)
                    .calmFadeIn(delay: 2.75)
            }
        }
    }

    // The names arrive letter by letter: Abhi, then the gold ampersand, then Alisha.
    private var names: some View {
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
        .accessibilityLabel("Abhi and Alisha")
    }

    private var firstName: some View {
        TypewriterText(
            text: "Abhi",
            spec: .heroNames,
            color: Color(hex: 0xFDFAF3),
            startDelay: 0.75,
            shadow: Color.black.opacity(0.35)
        )
    }

    private var secondName: some View {
        TypewriterText(
            text: "Alisha",
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
