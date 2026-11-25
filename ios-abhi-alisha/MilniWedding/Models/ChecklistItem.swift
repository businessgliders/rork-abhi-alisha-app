import Foundation

/// One task on the wedding-day checklist.
///
/// The record is kept whole, as the backend sent it, so saving a change never drops a
/// field this build doesn't know about. Field names that vary (done, due date) are read
/// from whichever key the record actually uses, and written back to that same key.
nonisolated struct ChecklistItem: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var fields: [String: JSONValue]

    /// Items made offline carry this until the backend gives them a real id.
    static let localPrefix = "local-"

    static let doneKeys = ["is_done", "done", "completed", "is_completed", "is_complete"]
    static let dueKeys = ["due_date", "due_at", "due"]

    init(id: String, fields: [String: JSONValue]) {
        self.id = id
        self.fields = fields
    }

    init?(raw: [String: JSONValue]) {
        guard let id = raw["id"]?.stringValue else { return nil }
        self.init(id: id, fields: raw)
    }

    var isLocalOnly: Bool { id.hasPrefix(Self.localPrefix) }

    var title: String? { fields["title"]?.stringValue }
    var notes: String? { (fields["notes"] ?? fields["description"])?.stringValue }
    var category: String? { fields["category"]?.stringValue }
    var sortOrder: Double { fields["sort_order"]?.doubleValue ?? .greatestFiniteMagnitude }
    var isActive: Bool { fields["is_active"]?.boolValue ?? true }

    var doneKey: String { Self.doneKeys.first { fields[$0] != nil } ?? "is_done" }
    var dueKey: String { Self.dueKeys.first { fields[$0] != nil } ?? "due_date" }

    var isDone: Bool { fields[doneKey]?.boolValue ?? false }
    var dueDate: Date? { fields[dueKey]?.rawString.flatMap(ChecklistDates.parse) }

    /// Past its day and still not done.
    func isOverdue(now: Date = Date()) -> Bool {
        guard !isDone, let dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: now)
    }
}

/// A category's worth of tasks, in the couple's order.
nonisolated struct ChecklistSection: Identifiable, Sendable {
    let name: String
    let items: [ChecklistItem]

    var id: String { name }
    var doneCount: Int { items.filter(\.isDone).count }
}

/// Due dates are calendar days ("2027-01-30"); full timestamps are read too.
nonisolated enum ChecklistDates {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        let value = string.trimmed
        guard !value.isEmpty else { return nil }
        if value.count == 10, let day = dayFormatter.date(from: value) { return day }
        return ScheduleEvent.date(from: value) ?? dayFormatter.date(from: String(value.prefix(10)))
    }

    static func string(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func display(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }
}
