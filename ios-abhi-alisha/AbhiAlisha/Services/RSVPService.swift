import Foundation

/// Looks up one party's reply by the name on their invitation.
///
/// The guest list itself is locked on the server: the app sends only what the guest
/// typed to `lookupRsvp`, which returns that single party or `{ found: false }`. The
/// last match is cached so it is still there with no connection.
nonisolated struct RSVPService: Sendable {
    static let shared = RSVPService()

    nonisolated enum Outcome: Sendable {
        case found(RSVPRecord)
        /// More than one guest shares the name typed (usually a first name alone).
        /// Nobody's details are shown; the guest is asked to add their last name.
        case ambiguous
        case notFound
        case offline
    }

    private let functions: WeddingFunctions = .shared
    private let cache = JSONDiskCache(filename: "rsvp-last-match.json")

    /// The party this guest looked up last time, if any.
    var lastMatch: RSVPRecord? {
        cache.load(RSVPRecord.self)?.first
    }

    func lookup(name: String) async -> Outcome {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return .notFound }

        do {
            let reply = try await functions.call("lookupRsvp", ["name": .string(needle)])
            if reply.status == 404 { return .notFound }
            guard (200..<300).contains(reply.status) else {
                return cachedMatch(for: needle) ?? .offline
            }
            if Self.isAmbiguous(reply.body) { return .ambiguous }
            guard let record = Self.record(in: reply.body) else { return .notFound }
            if let data = try? JSONEncoder().encode([record]) {
                cache.save(data)
            }
            return .found(record)
        } catch {
            // No connection: fall back to the party this guest already looked up.
            return cachedMatch(for: needle) ?? .offline
        }
    }

    /// Forget the remembered party, so a shared phone doesn't keep someone else's reply.
    func forgetLastMatch() {
        cache.clear()
    }

    private func cachedMatch(for needle: String) -> Outcome? {
        guard let cached = lastMatch, cached.matches(needle) else { return nil }
        return .found(cached)
    }

    /// Several guests matched. Accepts an explicit flag or a list of more than one party,
    /// and in either case never picks one: showing the wrong person's reply is worse than asking.
    private static func isAmbiguous(_ body: JSONValue?) -> Bool {
        guard let body else { return false }
        if body["ambiguous"]?.boolValue == true || body["multiple"]?.boolValue == true {
            return true
        }
        if let count = body["match_count"]?.doubleValue, count > 1 { return true }
        if let rows = body.arrayValue, rows.count > 1 { return true }
        for key in ["matches", "rsvps", "results"] {
            if let rows = body[key]?.arrayValue, rows.count > 1 { return true }
        }
        return false
    }

    /// Reads the one record out of the reply — sent bare, or wrapped under a key —
    /// and treats `{ found: false }` or a record with no name as no match at all.
    private static func record(in body: JSONValue?) -> RSVPRecord? {
        guard let body else { return nil }
        if body["found"]?.boolValue == false { return nil }

        var candidate = body
        if let first = body.arrayValue?.first {
            candidate = first
        } else {
            for key in ["record", "rsvp", "data", "result", "guest"] {
                if let wrapped = body[key], wrapped.objectValue != nil {
                    candidate = wrapped
                    break
                }
            }
        }

        guard let record = candidate.decode(RSVPRecord.self),
              record.displayName != nil else { return nil }
        return record
    }
}
