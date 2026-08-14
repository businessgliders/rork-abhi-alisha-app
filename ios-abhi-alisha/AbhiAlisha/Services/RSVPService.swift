import Foundation

/// Looks up one party's reply by the name on their invitation, or by their invite code.
///
/// The list of guests is never surfaced: only the single matching party is returned,
/// and the last match is cached so it is still there with no connection.
nonisolated struct RSVPService: Sendable {
    static let shared = RSVPService()

    nonisolated enum Outcome: Sendable {
        case found(RSVPRecord)
        case notFound
        case offline
    }

    private let api: WeddingAPI = .shared
    private let cache = JSONDiskCache(filename: "rsvp-last-match.json")

    /// The party this guest looked up last time, if any.
    var lastMatch: RSVPRecord? {
        cache.load(RSVPRecord.self)?.first
    }

    func lookup(name: String) async -> Outcome {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return .notFound }

        do {
            let result = try await api.fetch(RSVPRecord.self, entity: "RSVP")
            guard let match = bestMatch(in: result.items, for: needle) else {
                return .notFound
            }
            if let data = try? JSONEncoder().encode([match]) {
                cache.save(data)
            }
            return .found(match)
        } catch {
            // No connection: fall back to the party this guest already looked up.
            if let cached = lastMatch, cached.matches(needle) {
                return .found(cached)
            }
            return .offline
        }
    }

    /// Forget the remembered party, so a shared phone doesn't keep someone else's reply.
    func forgetLastMatch() {
        cache.clear()
    }

    /// A whole name (or invite code) read exactly wins; then a name starting with what
    /// was typed; then any name that merely contains it.
    private func bestMatch(in records: [RSVPRecord], for needle: String) -> RSVPRecord? {
        if let exact = records.first(where: { $0.matchesExactly(needle) }) { return exact }
        if let prefix = records.first(where: { $0.matchesPrefix(needle) }) { return prefix }
        return records.first { $0.matches(needle) }
    }
}
