import Foundation

nonisolated struct OutfitPhoto: Codable, Hashable, Identifiable, Sendable {
    let imageURL: String?
    let lightboxURL: String?
    let caption: String?

    var id: String { imageURL ?? lightboxURL ?? caption ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
        case lightboxURL = "lightbox_url"
        case caption
    }
}

nonisolated struct EventFAQ: Codable, Hashable, Identifiable, Sendable {
    let question: String?
    let answer: String?

    var id: String { (question ?? "") + (answer ?? "") }
}

nonisolated enum CeremonyType: String, Codable, Sendable {
    case sikh
    case hindu
}

/// A single celebration in the wedding weekend, as returned by the base44 `ScheduleEvent` entity.
/// Optional fields stay optional: the UI omits anything missing rather than rendering a placeholder.
nonisolated struct ScheduleEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let dateText: String?
    let timeText: String?
    let startsAt: Date?
    let endsAt: Date?
    let storedCeremonyType: String?
    let storedIconKey: String?
    let sortOrder: Double?
    let locationName: String?
    let locationAddress: String?
    let latitude: Double?
    let longitude: Double?
    let hideMap: Bool?
    let resortMapX: Double?
    let resortMapY: Double?
    let resortMapLabel: String?
    let description: String?
    let dressCode: String?
    let outfitPhotos: [OutfitPhoto]?
    let faqs: [EventFAQ]?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case dateText = "date"
        case timeText = "time"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case storedCeremonyType = "ceremony_type"
        case storedIconKey = "icon_key"
        case sortOrder = "sort_order"
        case locationName = "location_name"
        case locationAddress = "location_address"
        case latitude
        case longitude
        case hideMap = "hide_map"
        case resortMapX = "resort_map_x"
        case resortMapY = "resort_map_y"
        case resortMapLabel = "resort_map_label"
        case description
        case dressCode = "dress_code"
        case outfitPhotos = "outfit_photos"
        case faqs
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = (try container.decodeIfPresent(String.self, forKey: .title) ?? "").trimmed
        dateText = try container.decodeIfPresent(String.self, forKey: .dateText)?.nonEmpty
        timeText = try container.decodeIfPresent(String.self, forKey: .timeText)?.nonEmpty
        startsAt = ScheduleEvent.date(from: try container.decodeIfPresent(String.self, forKey: .startsAt))
        endsAt = ScheduleEvent.date(from: try container.decodeIfPresent(String.self, forKey: .endsAt))
        storedCeremonyType = try container.decodeIfPresent(String.self, forKey: .storedCeremonyType)?.nonEmpty
        storedIconKey = try container.decodeIfPresent(String.self, forKey: .storedIconKey)?.nonEmpty
        sortOrder = try container.decodeIfPresent(Double.self, forKey: .sortOrder)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)?.nonEmpty
        locationAddress = try container.decodeIfPresent(String.self, forKey: .locationAddress)?.nonEmpty
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        hideMap = try container.decodeIfPresent(Bool.self, forKey: .hideMap)
        resortMapX = try container.decodeIfPresent(Double.self, forKey: .resortMapX)
        resortMapY = try container.decodeIfPresent(Double.self, forKey: .resortMapY)
        resortMapLabel = try container.decodeIfPresent(String.self, forKey: .resortMapLabel)?.nonEmpty
        description = try container.decodeIfPresent(String.self, forKey: .description)?.nonEmpty?.withoutDashes
        dressCode = try container.decodeIfPresent(String.self, forKey: .dressCode)?.nonEmpty
        outfitPhotos = try container.decodeIfPresent([OutfitPhoto].self, forKey: .outfitPhotos)
        faqs = try container.decodeIfPresent([EventFAQ].self, forKey: .faqs)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(dateText, forKey: .dateText)
        try container.encodeIfPresent(timeText, forKey: .timeText)
        try container.encodeIfPresent(startsAt.map(ScheduleEvent.isoFormatter.string(from:)), forKey: .startsAt)
        try container.encodeIfPresent(endsAt.map(ScheduleEvent.isoFormatter.string(from:)), forKey: .endsAt)
        try container.encodeIfPresent(storedCeremonyType, forKey: .storedCeremonyType)
        try container.encodeIfPresent(storedIconKey, forKey: .storedIconKey)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(locationName, forKey: .locationName)
        try container.encodeIfPresent(locationAddress, forKey: .locationAddress)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(hideMap, forKey: .hideMap)
        try container.encodeIfPresent(resortMapX, forKey: .resortMapX)
        try container.encodeIfPresent(resortMapY, forKey: .resortMapY)
        try container.encodeIfPresent(resortMapLabel, forKey: .resortMapLabel)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(dressCode, forKey: .dressCode)
        try container.encodeIfPresent(outfitPhotos, forKey: .outfitPhotos)
        try container.encodeIfPresent(faqs, forKey: .faqs)
        try container.encodeIfPresent(isActive, forKey: .isActive)
    }

    // MARK: - Derived values

    /// Stored value always wins; keyword inference only fills an empty field.
    var iconKey: EventIconKey {
        if let storedIconKey, let key = EventIconKey(rawValue: storedIconKey.lowercased()) {
            return key
        }
        return EventIconKey.inferred(fromTitle: title)
    }

    /// Stored value always wins; a badge is never shown unless the title clearly names a religious ceremony.
    var ceremonyType: CeremonyType? {
        if let storedCeremonyType, let type = CeremonyType(rawValue: storedCeremonyType.lowercased()) {
            return type
        }
        return ScheduleEvent.inferCeremonyType(fromTitle: title)
    }

    /// The `date` string verbatim when present, otherwise formatted from `starts_at`.
    var displayDate: String? {
        if let dateText { return dateText.squeezingSpaces }
        guard let startsAt else { return nil }
        return ScheduleEvent.dateDisplayFormatter.string(from: startsAt)
    }

    /// The `time` string verbatim when present (it may read "PM (TBA)"), otherwise formatted from `starts_at`.
    var displayTime: String? {
        if let timeText { return timeText.squeezingSpaces }
        guard let startsAt else { return nil }
        return ScheduleEvent.timeDisplayFormatter.string(from: startsAt)
    }

    /// True when the published time is still to be announced.
    var isTimeToBeAnnounced: Bool {
        guard let timeText = timeText?.uppercased() else { return false }
        return timeText.contains("TBA") || timeText.contains("TBD")
    }

    var hasMapCoordinate: Bool {
        guard hideMap != true, let latitude, let longitude else { return false }
        return abs(latitude) > 0.0001 && abs(longitude) > 0.0001
    }

    func isHappening(at now: Date) -> Bool {
        guard let startsAt else { return false }
        let end = endsAt ?? startsAt.addingTimeInterval(2 * 3600)
        return now >= startsAt && now <= end
    }

    // MARK: - Fallback inference

    static func inferCeremonyType(fromTitle title: String) -> CeremonyType? {
        let text = title.lowercased()
        let sikhKeywords = ["anand karaj", "gurdwara", "sikh"]
        let hinduKeywords = ["phera", "mandap", "hindu", "baraat"]
        if sikhKeywords.contains(where: text.contains) { return .sikh }
        if hinduKeywords.contains(where: text.contains) { return .hindu }
        return nil
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

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nonEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    /// Drops the em and en dashes used as connectors in hand-written copy, closing the
    /// gap they leave behind so the sentence still reads cleanly.
    var withoutDashes: String {
        replacingOccurrences(of: "—", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .squeezingSpaces
    }

    /// Collapses the double spaces that creep into hand-entered date strings.
    var squeezingSpaces: String {
        trimmed
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
