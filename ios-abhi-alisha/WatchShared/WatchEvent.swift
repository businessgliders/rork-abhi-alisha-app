import Foundation

/// The six line-art motifs, shared with the iPhone app. Keyword inference fills an
/// empty `icon_key` exactly the way the phone decides.
nonisolated enum WatchIconKey: String, CaseIterable, Sendable {
    case flutes
    case paisley
    case arch
    case mandap
    case sparkle
    case sun

    /// Keyword inference used only when `icon_key` is empty.
    static func inferred(fromTitle title: String) -> WatchIconKey {
        let text = title.lowercased()
        let rules: [(keywords: [String], key: WatchIconKey)] = [
            (["mehndi", "sangeet", "haldi"], .paisley),
            (["anand karaj", "sikh", "gurdwara"], .arch),
            (["phera", "mandap", "hindu", "baraat"], .mandap),
            (["reception"], .sparkle),
            (["welcome", "cocktail", "party"], .flutes),
            (["brunch", "farewell", "thank you", "rest"], .sun)
        ]
        for rule in rules where rule.keywords.contains(where: text.contains) {
            return rule.key
        }
        return .sparkle
    }
}

/// A celebration, as the watch sees it: the same fields the phone reads, decoded just
/// as defensively. Anything missing stays missing and the UI simply leaves it out.
nonisolated struct WatchEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let dateText: String?
    let timeText: String?
    let startsAt: Date?
    let endsAt: Date?
    let storedIconKey: String?
    let sortOrder: Double?
    let locationName: String?
    let dressCode: String?
    let description: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case dateText = "date"
        case timeText = "time"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case storedIconKey = "icon_key"
        case sortOrder = "sort_order"
        case locationName = "location_name"
        case dressCode = "dress_code"
        case description
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = (try container.decodeIfPresent(String.self, forKey: .title) ?? "").trimmed
        dateText = try container.decodeIfPresent(String.self, forKey: .dateText)?.nonEmpty
        timeText = try container.decodeIfPresent(String.self, forKey: .timeText)?.nonEmpty
        startsAt = WatchEvent.date(from: try container.decodeIfPresent(String.self, forKey: .startsAt))
        endsAt = WatchEvent.date(from: try container.decodeIfPresent(String.self, forKey: .endsAt))
        storedIconKey = try container.decodeIfPresent(String.self, forKey: .storedIconKey)?.nonEmpty
        sortOrder = try container.decodeIfPresent(Double.self, forKey: .sortOrder)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)?.nonEmpty
        dressCode = try container.decodeIfPresent(String.self, forKey: .dressCode)?.nonEmpty
        description = try container.decodeIfPresent(String.self, forKey: .description)?.nonEmpty
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive)
    }

    // MARK: - Derived values

    /// Stored value always wins; keyword inference only fills an empty field.
    var iconKey: WatchIconKey {
        if let storedIconKey, let key = WatchIconKey(rawValue: storedIconKey.lowercased()) {
            return key
        }
        return WatchIconKey.inferred(fromTitle: title)
    }

    /// The first religious ceremony drives the countdown, same as on the phone.
    var ceremonyKind: WatchCeremonyKind? {
        let text = title.lowercased()
        if ["anand karaj", "gurdwara", "sikh"].contains(where: text.contains) { return .sikh }
        if ["phera", "mandap", "hindu", "baraat"].contains(where: text.contains) { return .hindu }
        return nil
    }

    /// The `date` string verbatim when present, otherwise formatted from `starts_at`.
    var displayDate: String? {
        if let dateText { return dateText.squeezingSpaces }
        guard let startsAt else { return nil }
        return Self.dateDisplayFormatter.string(from: startsAt)
    }

    /// The `time` string verbatim when present (it may read "PM (TBA)"), otherwise
    /// formatted from `starts_at`.
    var displayTime: String? {
        if let timeText { return timeText.squeezingSpaces }
        guard let startsAt else { return nil }
        return Self.timeDisplayFormatter.string(from: startsAt)
    }

    /// An unpublished end runs two hours, exactly as the phone assumes.
    var end: Date {
        endsAt ?? startsAt?.addingTimeInterval(2 * 3600) ?? .distantPast
    }

    func isHappening(at now: Date) -> Bool {
        guard let startsAt else { return false }
        return now >= startsAt && now <= end
    }

    // MARK: - Formatters

    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()

    private static let timeDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func date(from string: String?) -> Date? {
        guard let string = string?.trimmed, !string.isEmpty else { return nil }
        if let date = isoFormatter.date(from: string) { return date }
        if let date = isoFractionalFormatter.date(from: string) { return date }
        // Timestamps without an offset (base44 audit fields) are treated as UTC.
        if let date = isoFormatter.date(from: string + "Z") { return date }
        return isoFractionalFormatter.date(from: string + "Z")
    }
}

nonisolated enum WatchCeremonyKind: Sendable {
    case sikh
    case hindu
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nonEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    /// Collapses the double spaces that creep into hand-entered date strings.
    var squeezingSpaces: String {
        trimmed
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
