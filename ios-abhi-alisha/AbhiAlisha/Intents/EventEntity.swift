import AppIntents
import CoreSpotlight
import Foundation

/// One celebration of the open wedding, as Siri, Shortcuts and Spotlight see it.
struct EventEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Wedding event"),
        numericFormat: "\(placeholder: .int) wedding events"
    )
    static let defaultQuery = EventQuery()

    let id: String
    let title: String
    let startsAt: Date?
    let venue: String?
    let dressCode: String?

    init(event: ScheduleEvent) {
        id = event.id
        title = event.title
        startsAt = event.startsAt
        venue = event.locationName
        dressCode = event.dressCode?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(IntentSchedule.whenLine(startsAt) ?? venue ?? "")",
            image: .init(systemName: "sparkles")
        )
    }
}

struct EventQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [EventEntity] {
        let events = await IntentSchedule.events()
        return identifiers.compactMap { id in events.first { $0.id == id }.map(EventEntity.init) }
    }

    func entities(matching string: String) async throws -> [EventEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let events = await IntentSchedule.events()
        guard !needle.isEmpty else { return events.map(EventEntity.init) }
        return events
            .filter { $0.title.lowercased().contains(needle) || ($0.ceremonyType?.rawValue.lowercased().contains(needle) ?? false) }
            .map(EventEntity.init)
    }

    func suggestedEntities() async throws -> [EventEntity] {
        await IntentSchedule.events().map(EventEntity.init)
    }
}

/// Reads the open wedding's schedule the way the widgets do: from the shared cache only.
enum IntentSchedule {
    @MainActor
    static func events() -> [ScheduleEvent] {
        ActiveWedding.reload()
        if let cached = ScheduleCache.shared.load(), !cached.isEmpty {
            return cached.filter { $0.isActive != false }
        }
        // Abhi & Alisha ship a bundled copy; other weddings simply have nothing yet.
        return ActiveWedding.snapshot.isAbhiAlisha ? WeddingTimeline.load().events : []
    }

    /// What's underway, else what's next.
    @MainActor
    static func focus(at now: Date = .now) -> ScheduleEvent? {
        WeddingTimeline(events: events()).focus(at: now)
    }

    /// The celebration that matters "today": underway, else the next one today in the
    /// wedding's time zone, else simply the next one.
    @MainActor
    static func today(at now: Date = .now) -> ScheduleEvent? {
        let timeline = WeddingTimeline(events: events())
        if let happening = timeline.happening(at: now) { return happening }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ActiveWedding.snapshot.timeZone
        let laterToday = timeline.timedEvents.filter {
            guard let start = $0.startsAt else { return false }
            return start > now && calendar.isDate(start, inSameDayAs: now)
        }
        let withCode = laterToday.first { ($0.dressCode?.isEmpty == false) }
        return withCode ?? laterToday.first ?? timeline.upcoming(at: now)
    }

    /// "Sat 31 Jan · 7:30 PM" in the wedding's own time zone.
    static func whenLine(_ date: Date?) -> String? {
        guard let date else { return nil }
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = ActiveWedding.snapshot.timeZone
        return date.formatted(style)
    }

    static func timeOnly(_ date: Date?) -> String? {
        guard let date else { return nil }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = ActiveWedding.snapshot.timeZone
        return date.formatted(style)
    }
}
