import Foundation

/// A celebration as the couple edits it: the raw record, verbatim, so what they see in
/// the editor is exactly what's stored — not the tidied copy guests read.
nonisolated struct TimelineEntry: Identifiable, Hashable, Sendable {
    let id: String
    var fields: [String: JSONValue]

    init?(raw: [String: JSONValue]) {
        guard let id = raw["id"]?.stringValue else { return nil }
        self.id = id
        self.fields = raw
    }

    var title: String? { fields["title"]?.stringValue }
    var locationName: String? { fields["location_name"]?.stringValue }
    var sortOrder: Double { fields["sort_order"]?.doubleValue ?? .greatestFiniteMagnitude }
    var isActive: Bool { fields["is_active"]?.boolValue ?? true }

    var summary: String? {
        let parts = [fields["date"]?.stringValue?.squeezingSpaces, fields["time"]?.stringValue?.squeezingSpaces]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    var iconKey: EventIconKey {
        if let stored = fields["icon_key"]?.stringValue?.lowercased(),
           let key = EventIconKey(rawValue: stored) {
            return key
        }
        return EventIconKey.inferred(fromTitle: title ?? "")
    }

    static func entries(from rows: [JSONValue]) -> [TimelineEntry] {
        rows.compactMap { $0.objectValue.flatMap(TimelineEntry.init(raw:)) }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return (lhs.title ?? "") < (rhs.title ?? "")
            }
    }
}

/// The eight fields the couple may change — and nothing else.
nonisolated struct EventDraft: Equatable, Sendable {
    var title: String
    var date: String
    var time: String
    var startsAt: Date?
    var endsAt: Date?
    var locationName: String
    var description: String
    var dressCode: String

    init(entry: TimelineEntry) {
        let fields = entry.fields
        title = fields["title"]?.rawString ?? ""
        date = fields["date"]?.rawString ?? ""
        time = fields["time"]?.rawString ?? ""
        startsAt = ScheduleEvent.date(from: fields["starts_at"]?.rawString)
        endsAt = ScheduleEvent.date(from: fields["ends_at"]?.rawString)
        locationName = fields["location_name"]?.rawString ?? ""
        description = fields["description"]?.rawString ?? ""
        dressCode = fields["dress_code"]?.rawString ?? ""
    }

    var isValid: Bool { !title.trimmed.isEmpty }

    /// Only what actually changed, keyed by the entity's own field names.
    func changes(from original: EventDraft) -> [String: JSONValue] {
        var changes: [String: JSONValue] = [:]

        func text(_ key: String, _ new: String, _ old: String) {
            if new.trimmed != old.trimmed { changes[key] = .string(new.trimmed) }
        }

        text("title", title, original.title)
        text("date", date, original.date)
        text("time", time, original.time)
        text("location_name", locationName, original.locationName)
        text("description", description, original.description)
        text("dress_code", dressCode, original.dressCode)

        if !Self.same(startsAt, original.startsAt) {
            changes["starts_at"] = startsAt.map { .string(EventTime.string(from: $0)) } ?? .null
        }
        if !Self.same(endsAt, original.endsAt) {
            changes["ends_at"] = endsAt.map { .string(EventTime.string(from: $0)) } ?? .null
        }
        return changes
    }

    private static func same(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (left?, right?): return abs(left.timeIntervalSince(right)) < 1
        default: return false
        }
    }
}

/// Celebration times are Cancún local, written with their offset ("…T19:00:00-05:00").
nonisolated enum EventTime {
    static let zone: TimeZone = TimeZone(identifier: "America/Cancun") ?? .current

    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = zone
        return formatter.string(from: date)
    }
}
