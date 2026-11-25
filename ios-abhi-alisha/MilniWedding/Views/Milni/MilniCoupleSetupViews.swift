import MapKit
import SwiftUI

/// Where the couple will celebrate, chosen from Apple Maps.
struct CoupleVenue: Equatable, Hashable {
    var name: String
    var address: String
    var city: String
    var country: String
    var latitude: Double
    var longitude: Double
    var timeZoneID: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone? { timeZoneID.flatMap(TimeZone.init(identifier:)) }

    var subtitle: String {
        [address, city, country].filter { !$0.isEmpty }.reduce(into: [String]()) { out, part in
            if !out.contains(where: { $0.localizedCaseInsensitiveContains(part) }) { out.append(part) }
        }
        .joined(separator: ", ")
    }

    init(name: String, address: String, city: String, country: String, latitude: Double, longitude: Double, timeZoneID: String?) {
        self.name = name
        self.address = address
        self.city = city
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneID = timeZoneID
    }

    init(item: MKMapItem) {
        let placemark = item.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        self.init(
            name: item.name ?? placemark.locality ?? "Our venue",
            address: street,
            city: placemark.locality ?? placemark.administrativeArea ?? "",
            country: placemark.country ?? "",
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude,
            timeZoneID: item.timeZone?.identifier
        )
    }
}

// MARK: - Step two: where

struct MilniWhereView: View {
    @Binding var draft: CoupleDraft
    let back: () -> Void
    let next: () -> Void

    @State private var query = ""
    @State private var results: [CoupleVenue] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var camera: MapCameraPosition = .automatic
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MilniBackButton(action: back).padding(.leading, -12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MilniLabel("Step two of four")
                        .padding(.top, 20)
                        .milniEntrance(0)
                    MilniHeadline(first: "Where will you", second: "celebrate?", size: 42)
                        .padding(.top, 12)
                        .milniEntrance(1)

                    searchField
                        .padding(.top, 34)
                        .milniEntrance(2)

                    VStack(spacing: 0) {
                        ForEach(rows, id: \.self) { venue in
                            row(venue)
                        }
                    }
                    .padding(.top, 10)
                    .animation(.easeInOut(duration: 0.3), value: rows)

                    if let venue = draft.venue {
                        mapPreview(venue)
                            .padding(.top, 22)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)

            VStack(spacing: 2) {
                Button("Continue") {
                    BrandHaptics.tick()
                    focused = false
                    next()
                }
                .buttonStyle(.milniPrimary)
                .disabled(draft.venue == nil)

                Button("We haven't chosen yet") {
                    BrandHaptics.tick()
                    focused = false
                    draft.venue = nil
                    next()
                }
                .buttonStyle(.milniTertiary)
            }
            .padding(.vertical, 8)
        }
        .milniSides()
        .background(Milni.ivory.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.4), value: draft.venue)
        .onAppear {
            if let venue = draft.venue {
                query = venue.name
                camera = Self.camera(for: venue)
            }
        }
    }

    /// The selected place stays listed, at the top, while the search changes.
    private var rows: [CoupleVenue] {
        var list = results
        if let venue = draft.venue {
            list.removeAll { $0 == venue }
            list.insert(venue, at: 0)
        }
        return Array(list.prefix(6))
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            MilniLabel("Venue or city", color: Milni.goldText)
            HStack(spacing: 10) {
                TextField("", text: $query, prompt: Text("Search Apple Maps").foregroundStyle(Milni.ink.opacity(0.25)))
                    .font(Milni.cormorant(27, weight: 500))
                    .foregroundStyle(Milni.ink)
                    .tint(Milni.goldText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                    .onChange(of: query) { _, text in schedule(text) }
                if searching {
                    ProgressView().controlSize(.small).tint(Milni.goldText)
                }
            }
            Rectangle()
                .fill(Milni.ink.opacity(focused ? 1 : 0.7))
                .frame(height: 1.5)
        }
    }

    private func row(_ venue: CoupleVenue) -> some View {
        let selected = draft.venue == venue
        return Button {
            BrandHaptics.soft()
            focused = false
            withAnimation(.easeInOut(duration: 0.4)) {
                draft.venue = venue
                camera = Self.camera(for: venue)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(selected ? Milni.ink : Color.clear)
                    Circle()
                        .strokeBorder(Milni.ink.opacity(selected ? 0 : 0.25), lineWidth: 1)
                    Image(systemName: "mappin")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(selected ? Milni.ivory : Milni.ink.opacity(0.6))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(venue.name)
                        .font(Milni.cormorant(21, weight: 500))
                        .foregroundStyle(Milni.ink)
                        .lineLimit(1)
                    if !venue.subtitle.isEmpty {
                        Text(venue.subtitle)
                            .font(Milni.inter(12.5))
                            .foregroundStyle(Milni.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Milni.goldText)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(Milni.hairline.opacity(0.6)).frame(height: 0.5)
            }
        }
        .buttonStyle(MilniPressStyle())
        .accessibilityLabel("\(venue.name), \(venue.subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func mapPreview(_ venue: CoupleVenue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Map(position: $camera, interactionModes: []) {
                Annotation(venue.name, coordinate: venue.coordinate, anchor: .bottom) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Milni.ink)
                            .frame(width: 30, height: 30)
                            .overlay(Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(Milni.champagne))
                        Rectangle().fill(Milni.ink).frame(width: 1.5, height: 10)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Milni.gold.opacity(0.7), lineWidth: 0.6)
            )
            .accessibilityLabel("Map of \(venue.name)")

            Text("WEATHER & MAP FOLLOW THIS PLACE")
                .font(Milni.inter(10.5, weight: 600))
                .tracking(1.8)
                .foregroundStyle(Milni.goldText)
        }
    }

    private static func camera(for venue: CoupleVenue) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: venue.coordinate, latitudinalMeters: 1800, longitudinalMeters: 1800))
    }

    private func schedule(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            searching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            searching = true
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.resultTypes = [.pointOfInterest, .address]
            let found = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
            guard !Task.isCancelled else { return }
            results = found.prefix(6).map(CoupleVenue.init(item:))
            searching = false
        }
    }
}

// MARK: - Step four: wedding week

struct MilniWeekView: View {
    @Binding var draft: CoupleDraft
    let back: () -> Void
    let created: (WeddingSummary) -> Void

    @State private var working = false
    @State private var error: String?
    @State private var isAdding = false
    @State private var newEvent = ""
    @FocusState private var addFocused: Bool

    static let suggestions: [(title: String, kind: String)] = [
        ("Welcome party", "welcome"),
        ("Mehndi", "mehndi"),
        ("Haldi", "haldi"),
        ("Sangeet", "sangeet"),
        ("Ceremony", "ceremony"),
        ("Reception", "reception"),
        ("Farewell brunch", "brunch")
    ]

    private var allTitles: [String] { Self.suggestions.map(\.title) + draft.customEvents }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MilniBackButton(action: back).padding(.leading, -12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MilniLabel("Step four of four")
                        .padding(.top, 20)
                        .milniEntrance(0)
                    MilniHeadline(first: "Your", second: "wedding week.", size: 42)
                        .padding(.top, 12)
                        .milniEntrance(1)
                    MilniBody("Choose what you're celebrating. Times and places can be added later.")
                        .padding(.top, 14)
                        .milniEntrance(2)

                    VStack(spacing: 0) {
                        ForEach(Array(allTitles.enumerated()), id: \.element) { index, title in
                            toggleRow(title)
                                .milniEntrance(3 + min(index, 7), delay: 0)
                        }
                        addRow
                    }
                    .padding(.top, 24)

                    if let error {
                        Text(error)
                            .font(Milni.inter(14))
                            .foregroundStyle(Color(hex: 0x9A3B2E))
                            .padding(.top, 14)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)

            Button {
                create()
            } label: {
                if working {
                    ProgressView().tint(Milni.ivory)
                } else {
                    Text(buttonTitle)
                        .contentTransition(.numericText())
                }
            }
            .buttonStyle(.milniPrimary)
            .disabled(working)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.25), value: draft.selectedEvents.count)
        }
        .milniSides()
        .background(Milni.ivory.ignoresSafeArea())
    }

    private var buttonTitle: String {
        let count = draft.selectedEvents.count
        return count == 0 ? "Create our wedding" : "Create our wedding · \(count) \(count == 1 ? "event" : "events")"
    }

    private func toggleRow(_ title: String) -> some View {
        let on = draft.selectedEvents.contains(title)
        return Button {
            BrandHaptics.tick()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                if on { draft.selectedEvents.removeAll { $0 == title } } else { draft.selectedEvents.append(title) }
            }
        } label: {
            HStack {
                Text(title)
                    .font(Milni.cormorant(24, weight: on ? 500 : 400))
                    .foregroundStyle(on ? Milni.ink : Milni.ink.opacity(0.55))
                Spacer()
                ZStack {
                    Circle()
                        .strokeBorder(Milni.ink.opacity(on ? 0 : 0.3), lineWidth: 1)
                    Circle()
                        .fill(Milni.ink)
                        .scaleEffect(on ? 1 : 0.2)
                        .opacity(on ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Milni.ivory)
                        .scaleEffect(on ? 1 : 0.4)
                        .opacity(on ? 1 : 0)
                }
                .frame(width: 26, height: 26)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(Milni.hairline.opacity(0.6)).frame(height: 0.5)
            }
        }
        .buttonStyle(MilniPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var addRow: some View {
        if isAdding {
            HStack(spacing: 12) {
                TextField("", text: $newEvent, prompt: Text("Name your event").foregroundStyle(Milni.ink.opacity(0.25)))
                    .font(Milni.cormorant(24, weight: 500))
                    .foregroundStyle(Milni.ink)
                    .tint(Milni.goldText)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($addFocused)
                    .onSubmit(commitNew)
                Button("Add", action: commitNew)
                    .font(Milni.inter(14, weight: 600))
                    .foregroundStyle(Milni.goldText)
                    .disabled(newEvent.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.vertical, 13)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Milni.ink).frame(height: 1.5)
            }
            .onAppear { addFocused = true }
        } else {
            Button {
                BrandHaptics.tick()
                withAnimation(.easeInOut(duration: 0.3)) { isAdding = true }
            } label: {
                Text("+ Add your own event")
                    .font(Milni.inter(14, weight: 600))
                    .foregroundStyle(Milni.goldText)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MilniPressStyle())
        }
    }

    private func commitNew() {
        let title = newEvent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        BrandHaptics.soft()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            if !allTitles.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) {
                draft.customEvents.append(title)
            }
            if !draft.selectedEvents.contains(title) { draft.selectedEvents.append(title) }
            newEvent = ""
            isAdding = false
        }
    }

    private func create() {
        guard !working else { return }
        guard ChatSession.shared.isSignedIn, !ChatSession.shared.isAnonymous else {
            error = "Sign in with Apple to create a wedding."
            return
        }
        BrandHaptics.soft()
        working = true
        error = nil
        // In the order shown, so the schedule starts in a sensible order.
        let events: [(title: String, kind: String)] = allTitles
            .filter { draft.selectedEvents.contains($0) }
            .map { title in (title, Self.suggestions.first { $0.title == title }?.kind ?? "custom") }
        Task {
            do {
                let summary = try await WeddingContext.shared.create(
                    partnerOne: draft.partnerOne,
                    partnerTwo: draft.partnerTwo,
                    start: draft.start,
                    end: draft.end,
                    preset: draft.preset,
                    venue: draft.venue,
                    events: events
                )
                created(summary)
            } catch {
                print("[Milni] create wedding failed: \(error)")
                self.error = "We couldn't create your wedding just now. Please try again."
            }
            working = false
        }
    }
}
