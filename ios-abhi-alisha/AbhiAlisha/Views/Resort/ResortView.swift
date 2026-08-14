import SwiftUI

/// "Resort" — AVA Resort Cancún: the photography gathered into a single swipeable stack
/// with both maps standing beside it, then what's there, then every question the couple
/// has answered, searchable. Published data only.
struct ResortView: View {
    @Environment(ContentStore.self) private var content

    @State private var expandedFaqID: String?
    @State private var expandedSections: Set<String> = []
    @State private var didPrimeSections = false
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 22)

                SectionHeading(text: "Photos & Maps")
                    .padding(.horizontal, 22)
                    .padding(.top, 34)

                PhotosAndMaps(
                    photos: content.resortPhotos,
                    scheduleMapURL: content.resortMap?.url
                )
                .padding(.top, 18)

                SectionHeading(text: "Amenities")
                    .padding(.horizontal, 22)
                    .padding(.top, 42)

                AmenityRow(amenities: ResortAmenity.all)
                    .padding(.top, 18)

                questions
                    .padding(.top, 46)
            }
            .padding(.top, ScreenChrome.contentReserve)
            .padding(.bottom, FloatingTabBar.contentReserve + 24)
            .readableWidth()
            .crestCorner()
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(BrandPalette.background.ignoresSafeArea())
        .animation(.softFade, value: query)
        .task {
            await content.refreshIfNeeded()
        }
        .onChange(of: content.faqs.count) { _, _ in
            primeSectionsIfNeeded()
        }
        .onAppear(perform: primeSectionsIfNeeded)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Where we're staying")

            Text("Resort")
                .brandFont(.screenTitle)
                .foregroundStyle(BrandPalette.ink)

            GoldRule(width: 58, alignment: .leading)
                .padding(.top, 2)

            Text("AVA Resort Cancún · Mexico")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Questions

    /// Every answered question, grouped and collapsed. The first group opens on arrival;
    /// searching opens whichever groups still have a match.
    private var questions: some View {
        let groups = matchingGroups

        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "Questions")

            QuestionSearchField(text: $query)
                .padding(.top, 18)

            if isSearching {
                Text(resultCount == 1 ? "1 answer" : "\(resultCount) answers")
                    .font(BrandLabel.font(size: 10, weight: .medium))
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(BrandPalette.body.opacity(0.75))
                    .padding(.top, 14)
            }

            if groups.isEmpty {
                emptyQuestions
            } else {
                VStack(spacing: 10) {
                    ForEach(groups, id: \.section.id) { group in
                        QuestionGroup(
                            section: group.section,
                            items: group.items,
                            isExpanded: isExpanded(group.section),
                            expandedFaqID: $expandedFaqID,
                            onToggle: { toggle(group.section) }
                        )
                    }
                }
                .padding(.top, 20)
            }
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyQuestions: some View {
        VStack(spacing: 14) {
            IconWatermark(key: .sparkle, size: 70, opacity: 0.3)

            Text(
                isSearching
                    ? "Nothing matches “\(query)”. Try a different word."
                    : "The couple's answers will appear here soon."
            )
            .brandFont(.bodyItalic)
            .foregroundStyle(BrandPalette.body)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 46)
    }

    // MARK: - Question state

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var resultCount: Int {
        matchingGroups.reduce(0) { $0 + $1.items.count }
    }

    /// Groups with at least one question left after the search text is applied.
    private var matchingGroups: [(section: FaqSection, items: [Faq])] {
        content.allSectionsInReadingOrder().compactMap { section in
            let items = matching(content.faqs(in: section))
            return items.isEmpty ? nil : (section, items)
        }
    }

    private func matching(_ items: [Faq]) -> [Faq] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return items }
        return items.filter { faq in
            let haystack = [faq.question, faq.answer].compactMap { $0 }.joined(separator: " ")
            return haystack.localizedStandardContains(needle)
        }
    }

    /// While searching every surviving group is open, so no match ever hides.
    private func isExpanded(_ section: FaqSection) -> Bool {
        isSearching || expandedSections.contains(section.id)
    }

    private func toggle(_ section: FaqSection) {
        BrandHaptics.tick()
        withAnimation(.calm) {
            if expandedSections.contains(section.id) {
                expandedSections.remove(section.id)
            } else {
                expandedSections.insert(section.id)
            }
        }
    }

    /// Only the first group starts open; the rest wait to be asked for.
    private func primeSectionsIfNeeded() {
        guard !didPrimeSections,
              let first = content.allSectionsInReadingOrder().first else { return }
        didPrimeSections = true
        expandedSections = [first.id]
    }
}

// MARK: - Photography & maps

/// One resort photograph in the deck.
private struct ResortSlide: Identifiable, Hashable {
    let id: String
    let url: URL
}

/// The whole resort library gathered into a single swipeable stack — the way Messages
/// collates a run of photos — which leaves room for both maps to stand beside it.
private struct PhotosAndMaps: View {
    let photos: [GalleryPhoto]
    let scheduleMapURL: URL?

    @State private var lightbox: LightboxContext?
    @State private var isShowingResortMap = false

    private static let rowHeight: CGFloat = 320
    private static let mapsWidth: CGFloat = 132

    /// The couple's published photography first, then anything filed under a resort
    /// category, with duplicates dropped.
    private var slides: [ResortSlide] {
        var seen = Set<String>()
        var result: [ResortSlide] = []

        for url in ResortMedia.photos where seen.insert(url.absoluteString).inserted {
            result.append(ResortSlide(id: url.absoluteString, url: url))
        }
        for photo in photos {
            guard let url = photo.url, seen.insert(url.absoluteString).inserted else { continue }
            result.append(ResortSlide(id: photo.id, url: url))
        }
        return result
    }

    var body: some View {
        let deck = slides

        return HStack(alignment: .top, spacing: 12) {
            PhotoDeck(slides: deck) { position in
                lightbox = LightboxContext(
                    title: "AVA Resort Cancún",
                    items: deck.map(\.url),
                    startIndex: position
                )
            }

            VStack(spacing: 12) {
                MapPlate(
                    title: "Resort Map",
                    localImageName: ResortMapArtwork.imageName,
                    remoteURL: nil,
                    imageAlignment: .center,
                    action: { isShowingResortMap = true }
                )

                if let scheduleMapURL {
                    MapPlate(
                        title: "Schedule Map",
                        localImageName: nil,
                        remoteURL: scheduleMapURL,
                        action: {
                            lightbox = LightboxContext(
                                title: "Schedule Map",
                                items: [scheduleMapURL],
                                startIndex: 0
                            )
                        }
                    )
                }
            }
            .frame(width: Self.mapsWidth)
        }
        .frame(height: Self.rowHeight)
        .padding(.horizontal, 22)
        .fullScreenCover(item: $lightbox) { context in
            Lightbox(context: context)
        }
        .fullScreenCover(isPresented: $isShowingResortMap) {
            ResortMapScreen()
        }
    }
}

/// The photographs as a fanned pile: the top one is thrown aside to reveal the next.
/// Cards behind sit a little lower and smaller, so the depth of the stack reads at a glance.
///
/// The pile keeps its own running order rather than an index into the source, so a thrown
/// photograph never reappears — it leaves the screen and is quietly filed at the back while
/// it is out of sight, and the cards behind rise into its place during the throw itself.
private struct PhotoDeck: View {
    let slides: [ResortSlide]
    /// Reports the position of the top photograph within the original run.
    let onOpen: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var order: [ResortSlide] = []
    @State private var position = 0
    @State private var drag: CGSize = .zero
    @State private var isThrowing = false

    /// Three read as a pile; a fourth is kept loaded just off the back so it can rise
    /// into view mid-throw instead of appearing afterwards.
    private static let depthShown = 3
    private static let throwDistance: CGFloat = 72

    var body: some View {
        ZStack {
            if order.isEmpty {
                emptyPlate
            } else {
                ForEach(visible.reversed(), id: \.slide.id) { entry in
                    card(entry.slide, depth: entry.depth)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            syncOrder(slides)
            warmUpcoming()
        }
        .onChange(of: slides) { _, incoming in syncOrder(incoming) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Swipe the photograph aside for the next one")
        .accessibilityAdjustableAction { _ in
            withAnimation(.softFade) { advance() }
        }
    }

    // MARK: - Cards

    /// The running order, keyed by identity so each card keeps its view — and its
    /// in-flight offset — as the pile turns.
    private var visible: [(depth: Int, slide: ResortSlide)] {
        guard !order.isEmpty else { return [] }
        let count = min(Self.depthShown + 1, order.count)
        return (0..<count).map { ($0, order[$0]) }
    }

    @ViewBuilder
    private func card(_ slide: ResortSlide, depth: Int) -> some View {
        let isTop = depth == 0

        if isTop {
            plate(slide, depth: depth, isTop: true)
                .gesture(throwGesture)
                .onTapGesture { open() }
                .overlay(alignment: .topTrailing) { expandButton }
                .overlay(alignment: .bottomLeading) { counter }
                .zIndex(10)
        } else {
            plate(slide, depth: depth, isTop: false)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(Double(10 - depth))
        }
    }

    /// The photograph rides in an overlay on a sized colour, so a filled crop
    /// never widens the stack it sits in.
    private func plate(_ slide: ResortSlide, depth: Int, isTop: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        // Mid-throw every card behind is already climbing one place forward.
        let settle = max(CGFloat(depth) - (isThrowing ? 1 : 0), 0)
        let isSpare = settle >= CGFloat(Self.depthShown)

        return BrandPalette.hairline.opacity(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                // No mark of any kind while it loads: the next photographs are warmed
                // in advance, so anything drawn here would only read as a flicker.
                RemoteImage(url: slide.url, contentMode: .fill, transitionDuration: 0.25) {
                    QuietPhotoPlaceholder()
                }
                .allowsHitTesting(false)
            }
            .clipShape(shape)
            .overlay(shape.stroke(BrandPalette.gold.opacity(isTop ? 0.3 : 0.16), lineWidth: 0.75))
            .shadow(
                color: Color.black.opacity(isTop ? 0.18 : 0.08),
                radius: isTop ? 18 : 9,
                y: isTop ? 10 : 5
            )
            .scaleEffect(1 - settle * 0.05, anchor: .bottom)
            .offset(
                x: isTop ? drag.width : 0,
                y: settle * 11 + (isTop ? drag.height * 0.28 : 0)
            )
            .rotationEffect(.degrees(isTop ? Double(drag.width) / 24 : 0), anchor: .bottom)
            .opacity(isSpare ? 0 : 1)
    }

    private var emptyPlate: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(BrandPalette.card)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(BrandPalette.hairline, lineWidth: 1)
            )
            .overlay {
                IconWatermark(key: .sparkle, size: 54, opacity: 0.3)
            }
    }

    /// A dark pill in the corner, exactly as the map cards wear their titles.
    private var counter: some View {
        Text("\(currentNumber) / \(order.count)")
            .font(BrandLabel.font(size: 9, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Color(hex: 0xFDFAF3))
            .monospacedDigit()
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(Color.black.opacity(0.45)))
            .padding(14)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var expandButton: some View {
        Button(action: open) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFDFAF3))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.42)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .padding(12)
        .accessibilityLabel("Open photograph full screen")
    }

    private func open() {
        BrandHaptics.soft()
        onOpen(position)
    }

    // MARK: - Throwing

    private var throwGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !isThrowing else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard !isThrowing else { return }
                if abs(value.translation.width) > Self.throwDistance {
                    throwAway(towards: value.translation.width < 0 ? -1 : 1)
                } else {
                    withAnimation(.calm) { drag = .zero }
                }
            }
    }

    /// Either direction reveals the next photograph. The card carries on past the edge,
    /// and only once it is gone is it moved to the back — without animation, so nothing
    /// snaps home or fades in the middle of the stack.
    private func throwAway(towards direction: CGFloat) {
        guard order.count > 1 else {
            withAnimation(.calm) { drag = .zero }
            return
        }

        BrandHaptics.soft()

        guard !reduceMotion else {
            drag = .zero
            withAnimation(.softFade) { advance() }
            return
        }

        withAnimation(.easeOut(duration: 0.3), completionCriteria: .logicallyComplete) {
            isThrowing = true
            drag = CGSize(
                width: direction * 900,
                height: drag.height + 40
            )
        } completion: {
            var silent = Transaction()
            silent.disablesAnimations = true
            withTransaction(silent) {
                advance()
                drag = .zero
                isThrowing = false
            }
        }
    }

    /// The top photograph goes to the bottom of the pile, so the run never ends.
    private func advance() {
        guard order.count > 1 else { return }
        order.append(order.removeFirst())
        position = (position + 1) % order.count
        warmUpcoming()
    }

    /// Loads the next few photographs before they are asked for, so a card is already
    /// holding its picture by the time it rises to the top of the pile.
    private func warmUpcoming() {
        guard !order.isEmpty else { return }
        let reach = min(6, order.count)
        ImageCache.shared.prefetch(order.prefix(reach).map(\.url))
    }

    private func syncOrder(_ incoming: [ResortSlide]) {
        guard Set(incoming.map(\.id)) != Set(order.map(\.id)) else { return }
        order = incoming
        position = 0
        drag = .zero
        isThrowing = false
        warmUpcoming()
    }

    private var currentNumber: Int {
        order.isEmpty ? 0 : position % order.count + 1
    }

    private var accessibilityLabel: String {
        guard !order.isEmpty else { return "Resort photographs" }
        return "Resort photograph \(currentNumber) of \(order.count)"
    }
}

/// One map card, standing beside the photo stack. Each opens full size.
private struct MapPlate: View {
    let title: String
    let localImageName: String?
    let remoteURL: URL?
    var imageAlignment: Alignment = .leading
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        Button {
            BrandHaptics.soft()
            action()
        } label: {
            BrandPalette.hairline.opacity(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: imageAlignment) {
                    if let localImageName {
                        Image(localImageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    } else if let remoteURL {
                        RemoteImage(url: remoteURL, contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(shape)
                .overlay(shape.stroke(BrandPalette.gold.opacity(0.25), lineWidth: 0.75))
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 6) {
                        Text(title.uppercased())
                            .font(BrandLabel.font(size: 8.5, weight: .semibold))
                            .tracking(1.5)

                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 7, weight: .semibold))
                            .opacity(0.85)
                    }
                    .foregroundStyle(Color(hex: 0xFDFAF3))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                    )
                    .padding(10)
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
        .accessibilityHint("Opens full screen")
    }
}

/// A run of images to show full size, opened at one of them.
private struct LightboxContext: Identifiable {
    let title: String
    let items: [URL]
    let startIndex: Int

    var id: String {
        "\(items.first?.absoluteString ?? "empty")#\(startIndex)"
    }
}

/// The images at full definition, paged left and right the way Photos does it, each
/// one pinchable and pannable.
private struct Lightbox: View {
    let context: LightboxContext

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(context: LightboxContext) {
        self.context = context
        _index = State(initialValue: context.startIndex)
    }

    private var isRun: Bool { context.items.count > 1 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(context.items.enumerated()), id: \.offset) { entry in
                    ZoomablePhoto(url: entry.element, maximumScale: 6)
                        .tag(entry.offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .onChange(of: index) { _, _ in
            BrandHaptics.tick()
            warmNeighbours()
        }
        .onAppear(perform: warmNeighbours)
        .overlay(alignment: .topTrailing) {
            Button {
                BrandHaptics.tick()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.16)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .padding(.trailing, 18)
            .padding(.top, 14)
            .accessibilityLabel("Close")
        }
        .overlay(alignment: .top) {
            VStack(spacing: 7) {
                Text(context.title.uppercased())
                    .font(BrandLabel.font(size: 10, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Color.white.opacity(0.7))

                if isRun {
                    Text("\(index + 1) / \(context.items.count)")
                        .font(BrandLabel.font(size: 9, weight: .medium))
                        .tracking(1.4)
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.5))
                        .contentTransition(.numericText())
                }
            }
            .padding(.top, 24)
            .allowsHitTesting(false)
        }
        .statusBarHidden()
    }

    /// Keeps the images on either side ready, so paging never waits on the network.
    private func warmNeighbours() {
        let urls = (index - 2...index + 2)
            .filter { context.items.indices.contains($0) }
            .map { context.items[$0] }
        ImageCache.shared.prefetch(urls)
    }
}

// MARK: - Amenities

/// What's waiting at the resort, drawn with the app's own line icons.
struct ResortAmenity: Identifiable, Hashable {
    let id: String
    let name: String
    let note: String
    let symbolName: String

    static let all: [ResortAmenity] = [
        ResortAmenity(
            id: "restaurants",
            name: "Restaurants",
            note: "À la carte and buffet dining",
            symbolName: "fork.knife"
        ),
        ResortAmenity(
            id: "pools",
            name: "Pools",
            note: "Oceanfront and quiet pools",
            symbolName: "figure.pool.swim"
        ),
        ResortAmenity(
            id: "spa",
            name: "Spa",
            note: "Treatments and hydrotherapy",
            symbolName: "leaf"
        ),
        ResortAmenity(
            id: "beach",
            name: "Beach",
            note: "Caribbean shoreline",
            symbolName: "beach.umbrella"
        ),
        ResortAmenity(
            id: "bars",
            name: "Bars",
            note: "Lounges and swim-up bars",
            symbolName: "wineglass"
        ),
        ResortAmenity(
            id: "activities",
            name: "Activities",
            note: "Fitness, watersports, evenings out",
            symbolName: "sparkles"
        )
    ]
}

/// Amenities as a horizontal run of cards, swiped like the photography.
private struct AmenityRow: View {
    let amenities: [ResortAmenity]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(amenities) { amenity in
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: amenity.symbolName)
                            .symbolVariant(.none)
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 19, weight: .ultraLight))
                            .foregroundStyle(BrandPalette.goldDeep)

                        Spacer(minLength: 6)

                        Text(amenity.name)
                            .brandFont(.eventTitleSmall)
                            .foregroundStyle(BrandPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(amenity.note)
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                    .frame(width: 186, height: 168, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(BrandPalette.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(BrandPalette.hairline, lineWidth: 1)
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 22, for: .scrollContent)
    }
}

// MARK: - Questions

/// A gold-lined search field in the app's own hand, not the system's.
private struct QuestionSearchField: View {
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(BrandPalette.gold)

            TextField("Search the answers", text: $text)
                .brandFont(.bodyText)
                .foregroundStyle(BrandPalette.ink)
                .tint(BrandPalette.goldDeep)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    BrandHaptics.tick()
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(BrandPalette.body.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BrandPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BrandPalette.gold.opacity(isFocused ? 0.6 : 0.28), lineWidth: 1)
        )
        .animation(.softFade, value: isFocused)
    }
}

/// One collapsible category of questions: a gold heading row with a count, and the
/// questions themselves once it is open.
private struct QuestionGroup: View {
    let section: FaqSection
    let items: [Faq]
    let isExpanded: Bool
    @Binding var expandedFaqID: String?
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Eyebrow(text: section.heading, size: 10)

                    Text("\(items.count)")
                        .font(BrandLabel.font(size: 9.5, weight: .medium))
                        .foregroundStyle(BrandPalette.body.opacity(0.7))
                        .monospacedDigit()

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(BrandPalette.gold)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                AccordionList(items: items, expandedID: $expandedFaqID)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BrandPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BrandPalette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Shared pieces

/// A gold caps heading with a hairline beneath, used to open each section.
struct SectionHeading: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: text)

            Rectangle()
                .fill(BrandPalette.hairline)
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Expandable question rows separated by gold-tinted hairlines.
struct AccordionList: View {
    let items: [Faq]
    @Binding var expandedID: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                row(item)
            }
        }
    }

    private func row(_ item: Faq) -> some View {
        let isOpen = expandedID == item.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                BrandHaptics.tick()
                withAnimation(.calm) {
                    expandedID = isOpen ? nil : item.id
                }
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Text(item.question ?? "")
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

            if isOpen, let answer = item.answer {
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
}
