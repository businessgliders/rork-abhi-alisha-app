import MapKit
import SwiftUI

// MARK: - Plotting

/// One spot on the venues map. Celebrations that share a venue share a pin ("4 · 5 · 6").
struct VenueMapPoint: Identifiable, Hashable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    /// Schedule numbers and events at this spot, in schedule order.
    let stops: [VenueStop]

    var numbersLabel: String { stops.map { String($0.number) }.joined(separator: " · ") }

    static func == (lhs: VenueMapPoint, rhs: VenueMapPoint) -> Bool { lhs.id == rhs.id && lhs.stops == rhs.stops }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct VenueStop: Identifiable, Hashable {
    let number: Int
    let event: ScheduleEvent
    var id: String { event.id }
}

@MainActor
enum VenueMapPlot {
    /// Where an event sits: its own coordinates, else the wedding's. Nil when the host
    /// hid the map for it or nothing is known — then no map UI shows at all.
    static func coordinate(for event: ScheduleEvent) -> CLLocationCoordinate2D? {
        guard event.hideMap != true else { return nil }
        if event.hasMapCoordinate, let lat = event.latitude, let lng = event.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return weddingCoordinate
    }

    static var weddingCoordinate: CLLocationCoordinate2D? {
        let wedding = ActiveWedding.snapshot
        guard let lat = wedding.latitude, let lng = wedding.longitude,
              abs(lat) > 0.0001 || abs(lng) > 0.0001 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// The number an event carries everywhere: its place in the schedule.
    static func number(of event: ScheduleEvent, in events: [ScheduleEvent]) -> Int? {
        events.firstIndex { $0.id == event.id }.map { $0 + 1 }
    }

    static func points(from events: [ScheduleEvent]) -> [VenueMapPoint] {
        var order: [String] = []
        var grouped: [String: (CLLocationCoordinate2D, [VenueStop])] = [:]
        for (index, event) in events.enumerated() {
            guard let coordinate = coordinate(for: event) else { continue }
            let key = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = (coordinate, [])
            }
            grouped[key]?.1.append(VenueStop(number: index + 1, event: event))
        }
        return order.compactMap { key in
            guard let (coordinate, stops) = grouped[key] else { return nil }
            return VenueMapPoint(id: key, coordinate: coordinate, stops: stops)
        }
    }

    static func hasAnyVenue(in events: [ScheduleEvent]) -> Bool {
        events.contains { coordinate(for: $0) != nil }
    }

    static func mapItem(at coordinate: CLLocationCoordinate2D, name: String?) -> MKMapItem {
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
        item.name = name
        return item
    }

    /// Hands off to Apple Maps with walking directions to the venue.
    static func openDirections(to coordinate: CLLocationCoordinate2D, name: String?) {
        mapItem(at: coordinate, name: name).openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    /// Walking minutes from the wedding's main address to this venue, when they're apart.
    static func walkingMinutes(to coordinate: CLLocationCoordinate2D) async -> Int? {
        guard let base = weddingCoordinate else { return nil }
        let from = CLLocation(latitude: base.latitude, longitude: base.longitude)
        let to = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard from.distance(from: to) > 40 else { return nil }
        let request = MKDirections.Request()
        request.source = mapItem(at: base, name: nil)
        request.destination = mapItem(at: coordinate, name: nil)
        request.transportType = .walking
        guard let eta = try? await MKDirections(request: request).calculateETA() else { return nil }
        let minutes = Int((eta.expectedTravelTime / 60).rounded(.up))
        return minutes <= 45 ? max(minutes, 1) : nil
    }
}

// MARK: - Pins

/// The event sheet's pin: a dot in the wedding's accent with a dark "3 · Sangeet" label.
struct EventMapPin: View {
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(BrandLabel.font(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(Color(hex: 0x1F1B16).opacity(0.88)))
            Circle()
                .fill(BrandPalette.gold)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
    }
}

/// The venues map's round numbered pin. Selected: gold with white numbers; others the reverse.
struct NumberedVenuePin: View {
    let label: String
    let isSelected: Bool

    var body: some View {
        Text(label)
            .font(Milni.cormorant(isSelected ? 18 : 16, weight: 700))
            .monospacedDigit()
            .foregroundStyle(isSelected ? Color.white : BrandPalette.goldDeep)
            .lineLimit(1)
            .padding(.horizontal, label.count > 2 ? 10 : 0)
            .frame(minWidth: isSelected ? 40 : 34, minHeight: isSelected ? 40 : 34)
            .background(Capsule(style: .continuous).fill(isSelected ? BrandPalette.gold : Color.white))
            .overlay(Capsule(style: .continuous).stroke(BrandPalette.gold, lineWidth: isSelected ? 0 : 1.5))
            .shadow(color: .black.opacity(isSelected ? 0.3 : 0.18), radius: isSelected ? 8 : 4, y: 2)
    }
}

// MARK: - Event sheet card

/// Where a celebration is: a rounded hairline map held on its pin, with walking directions
/// and Look Around when Apple has imagery for the spot.
struct EventMapCard: View {
    let event: ScheduleEvent
    let number: Int?
    let coordinate: CLLocationCoordinate2D

    @State private var lookAroundScene: MKLookAroundScene?
    @State private var isShowingLookAround = false
    @State private var walkMinutes: Int?

    private var pinLabel: String {
        if let number { return "\(number) · \(event.title)" }
        return event.title
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        VStack(spacing: 0) {
            Map(
                initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 650,
                    longitudinalMeters: 650
                )),
                interactionModes: []
            ) {
                Annotation(event.title, coordinate: coordinate, anchor: .bottom) {
                    EventMapPin(label: pinLabel)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(pinAccessibility)
                }
                .annotationTitles(.hidden)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 190)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Map of \(event.locationName ?? event.title)"))

            Rectangle().fill(BrandPalette.hairline).frame(height: 1)

            HStack(spacing: 0) {
                Button {
                    BrandHaptics.soft()
                    VenueMapPlot.openDirections(to: coordinate, name: event.locationName ?? event.title)
                } label: {
                    footerLabel(directionsText, symbol: "figure.walk")
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(directionsAccessibility)

                if lookAroundScene != nil {
                    Rectangle().fill(BrandPalette.hairline).frame(width: 1, height: 22)
                    Button {
                        BrandHaptics.soft()
                        isShowingLookAround = true
                    } label: {
                        footerLabel(String(localized: "Look Around"), symbol: "binoculars")
                    }
                    .buttonStyle(PressableStyle())
                    .transition(.opacity)
                }
            }
            .background(BrandPalette.card)
        }
        .clipShape(shape)
        .overlay(shape.stroke(BrandPalette.gold.opacity(0.3), lineWidth: 0.75))
        .animation(.softFade, value: lookAroundScene != nil)
        .lookAroundViewer(isPresented: $isShowingLookAround, initialScene: lookAroundScene)
        .task(id: event.id) {
            async let scene = try? MKLookAroundSceneRequest(coordinate: coordinate).scene
            async let minutes = VenueMapPlot.walkingMinutes(to: coordinate)
            let (foundScene, foundMinutes) = await (scene, minutes)
            lookAroundScene = foundScene ?? nil
            walkMinutes = foundMinutes
        }
    }

    private var directionsText: String {
        if let walkMinutes { return String(localized: "Directions · \(walkMinutes) min walk") }
        return String(localized: "Directions")
    }

    private var directionsAccessibility: String {
        if let walkMinutes {
            return String(localized: "Walking directions in Maps. About \(walkMinutes) minutes from \(ActiveWedding.place).")
        }
        return String(localized: "Walking directions in Maps")
    }

    private var pinAccessibility: String {
        var parts: [String] = []
        if let number { parts.append(String(localized: "Event \(number)")) }
        parts.append(event.title)
        if let venue = event.locationName { parts.append(venue) }
        return parts.joined(separator: ", ")
    }

    private func footerLabel(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .regular))
            Text(text)
                .font(BrandLabel.font(size: 11, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(BrandPalette.goldDeep)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

// MARK: - Venues map

/// Every venue of the week on one map, numbered as in the schedule. Tap a pin for the
/// celebrations there, directions, or the full event.
struct VenuesMapView: View {
    var focusEventID: String?

    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedPointID: String?
    @State private var selectedEventID: String?
    @State private var detailEvent: ScheduleEvent?

    private var points: [VenueMapPoint] { VenueMapPlot.points(from: store.events) }

    private var selectedPoint: VenueMapPoint? { points.first { $0.id == selectedPointID } }

    private var selectedStop: VenueStop? {
        guard let point = selectedPoint else { return nil }
        return point.stops.first { $0.id == selectedEventID } ?? point.stops.first
    }

    private var placeName: String {
        let wedding = ActiveWedding.snapshot
        return wedding.city?.nonEmpty ?? wedding.placeLine ?? String(localized: "The wedding")
    }

    var body: some View {
        Map(position: $position) {
            ForEach(points) { point in
                Annotation(point.stops.map(\.event.title).joined(separator: ", "), coordinate: point.coordinate, anchor: .center) {
                    Button {
                        select(point)
                    } label: {
                        NumberedVenuePin(label: point.numbersLabel, isSelected: point.id == selectedPointID)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibility(for: point))
                    .accessibilityAddTraits(point.id == selectedPointID ? .isSelected : [])
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .top) {
            titleCard
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }
        .safeAreaInset(edge: .bottom) {
            if let stop = selectedStop, let point = selectedPoint {
                stopCard(stop, in: point)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .softFade : .calm, value: selectedStop?.id)
        .sheet(item: $detailEvent) { event in
            EventDetailSheet(event: event)
        }
        .onAppear(perform: focusInitially)
    }

    // MARK: Pieces

    private var titleCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: String(localized: "The venues"), size: 10)
                Text(placeName)
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(BrandPalette.goldDeep)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(BrandPalette.gold.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close map")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(BrandPalette.card.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
    }

    private func stopCard(_ stop: VenueStop, in point: VenueMapPoint) -> some View {
        let event = stop.event
        let isNext = store.nextEvent?.id == event.id

        return VStack(alignment: .leading, spacing: 12) {
            if point.stops.count > 1 {
                HStack(spacing: 8) {
                    ForEach(point.stops) { other in
                        Button {
                            BrandHaptics.tick()
                            selectedEventID = other.id
                        } label: {
                            Text("\(other.number)")
                                .font(Milni.cormorant(16, weight: 700))
                                .foregroundStyle(other.id == stop.id ? Color.white : BrandPalette.goldDeep)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(other.id == stop.id ? BrandPalette.gold : Color.clear))
                                .overlay(Circle().stroke(BrandPalette.gold.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(Text("Event \(other.number), \(other.event.title)"))
                    }
                }
            }

            HStack(spacing: 8) {
                if let when = [event.displayDate, event.displayTime].compactMap({ $0 }).joined(separator: " · ").nonEmpty {
                    Eyebrow(text: when, size: 9.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if isNext {
                    Text("Next")
                        .font(BrandLabel.font(size: 9.5, weight: .bold))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: 0x3C8A5A)))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(stop.number) · \(event.title)")
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let venue = event.locationName {
                    Text(venue)
                        .brandFont(.bodyItalic)
                        .foregroundStyle(BrandPalette.body)
                }
                if let dress = event.dressCode {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(BrandPalette.gold).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(dress)
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.ink)
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                    .accessibilityLabel(Text("Dress code: \(dress)"))
                }
            }

            HStack(spacing: 10) {
                Button {
                    BrandHaptics.soft()
                    VenueMapPlot.openDirections(to: point.coordinate, name: event.locationName ?? event.title)
                } label: {
                    Text("Directions")
                        .font(BrandLabel.font(size: 12, weight: .semibold))
                        .tracking(1.3)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BrandPalette.gold))
                }
                .buttonStyle(PressableStyle())

                Button {
                    BrandHaptics.soft()
                    detailEvent = event
                } label: {
                    Text("Event details")
                        .font(BrandLabel.font(size: 12, weight: .semibold))
                        .tracking(1.3)
                        .textCase(.uppercase)
                        .foregroundStyle(BrandPalette.goldDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BrandPalette.gold.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: 520, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(BrandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: Behaviour

    private func select(_ point: VenueMapPoint) {
        BrandHaptics.tick()
        selectedPointID = point.id
        let upcoming = point.stops.first { ($0.event.startsAt ?? .distantFuture) > store.now }
        selectedEventID = (upcoming ?? point.stops.first)?.id
        let move = { position = .camera(MapCamera(centerCoordinate: point.coordinate, distance: 1400)) }
        if reduceMotion { move() } else { withAnimation(.calm, move) }
    }

    private func focusInitially() {
        let focusID = focusEventID ?? store.nextEvent?.id
        if let focusID, let point = points.first(where: { $0.stops.contains { $0.id == focusID } }) {
            selectedPointID = point.id
            selectedEventID = focusID
        }
        if points.count == 1, let only = points.first {
            position = .camera(MapCamera(centerCoordinate: only.coordinate, distance: 1400))
        }
    }

    private func accessibility(for point: VenueMapPoint) -> String {
        point.stops
            .map { stop in
                [String(localized: "Event \(stop.number)"), stop.event.title, stop.event.locationName]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            }
            .joined(separator: "; ")
    }
}
