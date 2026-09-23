import Foundation

/// One party's reply, looked up by the name on their invitation or by their invite code.
///
/// Only the matched party is ever shown: the app never lists everybody, and
/// email addresses are deliberately not decoded at all.
///
/// The couple's form writes `attending` as "yes"/"no" and both counts as decimals,
/// so every field here is decoded leniently rather than assuming a type.
nonisolated struct RSVPRecord: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let guestName: String?
    let guestNames: [String]?
    let guestCount: Int?
    let kidsCount: Int?
    let attending: Bool?
    let dietaryRestrictions: String?
    let events: [String]?
    let message: String?
    let inviteCode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case guestName = "guest_name"
        case guestNames = "guest_names"
        case guestCount = "guest_count"
        case kidsCount = "kids_count"
        case attending
        case dietaryRestrictions = "dietary_restrictions"
        case events
        case message
        case inviteCode = "invite_code"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        guestName = try container.decodeIfPresent(String.self, forKey: .guestName)?.nonEmpty
        guestNames = try container.decodeIfPresent([String].self, forKey: .guestNames)?
            .compactMap { $0.nonEmpty }
        guestCount = Self.decodeCount(from: container, forKey: .guestCount)
        kidsCount = Self.decodeCount(from: container, forKey: .kidsCount)
        attending = Self.decodeAttending(from: container)
        dietaryRestrictions = try container
            .decodeIfPresent(String.self, forKey: .dietaryRestrictions)?
            .meaningfulNote
        events = try container.decodeIfPresent([String].self, forKey: .events)?
            .compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
        message = try container.decodeIfPresent(String.self, forKey: .message)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode)?.nonEmpty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(guestName, forKey: .guestName)
        try container.encodeIfPresent(guestNames, forKey: .guestNames)
        try container.encodeIfPresent(guestCount, forKey: .guestCount)
        try container.encodeIfPresent(kidsCount, forKey: .kidsCount)
        try container.encodeIfPresent(attending, forKey: .attending)
        try container.encodeIfPresent(dietaryRestrictions, forKey: .dietaryRestrictions)
        try container.encodeIfPresent(events, forKey: .events)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(inviteCode, forKey: .inviteCode)
    }

    // MARK: - Lenient decoding

    /// Counts arrive as `3.0`, but a string or a plain integer must not break the lookup.
    private static func decodeCount(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(value.rounded())
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// `attending` is written as "yes"/"no", but a real boolean is honoured too.
    private static func decodeAttending(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> Bool? {
        if let value = try? container.decodeIfPresent(Bool.self, forKey: .attending) {
            return value
        }
        guard let raw = try? container.decodeIfPresent(String.self, forKey: .attending),
              let value = raw.trimmingCharacters(in: .whitespaces).nonEmpty?.lowercased()
        else { return nil }

        if ["yes", "y", "true", "attending", "accepted", "confirmed"].contains(value) {
            return true
        }
        if ["no", "n", "false", "declined", "not attending", "regrets"].contains(value) {
            return false
        }
        return nil
    }

    // MARK: - Presentation

    /// The party's full name, as the couple wrote it.
    var displayName: String? {
        guestName ?? guestNames?.first
    }

    /// The name to greet them with.
    var firstName: String? {
        guard let guestName else { return guestNames?.first }
        return guestName.components(separatedBy: " ").first?.nonEmpty ?? guestName
    }

    /// Everyone in the party, without repeating the party's own name.
    var partyMembers: [String] {
        let names = guestNames ?? []
        guard let guestName else { return names }
        return names.filter { $0.caseInsensitiveCompare(guestName) != .orderedSame }
    }

    /// Whether they replied yes, no, or nothing at all.
    var isAttending: Bool? { attending }

    /// "3 guests · 2 children", with either half left out when it's zero.
    var partyLine: String? {
        var parts: [String] = []
        if let guestCount, guestCount > 0 {
            parts.append(guestCount == 1 ? "1 guest" : "\(guestCount) guests")
        }
        if let kidsCount, kidsCount > 0 {
            parts.append(kidsCount == 1 ? "1 child" : "\(kidsCount) children")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    // MARK: - Matching

    /// Case-insensitive match on the party's name, anyone travelling with them, or
    /// the invite code printed on their card.
    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }

        if let inviteCode, inviteCode.compare(needle, options: .caseInsensitive) == .orderedSame {
            return true
        }

        return allNames.contains { name in
            name.localizedCaseInsensitiveCompare(needle) == .orderedSame
                || name.localizedStandardContains(needle)
        }
    }

    /// True only when a whole name reads exactly as typed.
    func matchesExactly(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        if let inviteCode, inviteCode.compare(needle, options: .caseInsensitive) == .orderedSame {
            return true
        }
        return allNames.contains { $0.localizedCaseInsensitiveCompare(needle) == .orderedSame }
    }

    /// True when a name begins with what was typed — how a half-typed first name lands.
    func matchesPrefix(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        return allNames.contains { name in
            name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }
    }

    private var allNames: [String] {
        var names = guestNames ?? []
        if let guestName { names.append(guestName) }
        return names
    }
}

extension String {
    /// Drops notes that only say there's nothing to say, so the card doesn't
    /// show a "Dietary notes: none" row.
    var meaningfulNote: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = trimmed.nonEmpty else { return nil }
        let dismissals: Set<String> = [
            "none", "no", "n/a", "na", "nah", "nope", "nil", "-", "none.", "no."
        ]
        return dismissals.contains(value.lowercased()) ? nil : value
    }
}
