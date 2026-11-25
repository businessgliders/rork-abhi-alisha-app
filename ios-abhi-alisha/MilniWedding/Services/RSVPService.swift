import Foundation
import Supabase

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

// MARK: - Guest-list lookup (the join flow's RSVP step)

extension RSVPService {
    /// Asks the couple's `rsvp-lookup` function for parties that read like this name,
    /// exactly as the guest typed it. At most three come back for the pick-me cards.
    ///
    /// A function that isn't set up yet (404), or one that doesn't apply to this
    /// wedding (501), means the step is skipped — never an error shown. So does any
    /// connection trouble: joining must never wait on the guest list.
    func search(name: String, weddingID: String) async -> [RSVPRecord] {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        guard let reply = await callLookup([
            "action": .string("search"),
            "name": .string(needle),
            "wedding_id": .string(weddingID),
        ]) else { return [] }
        if reply.status == 404 || reply.status == 501 { return [] }
        guard (200..<300).contains(reply.status) else { return [] }
        return Array(Self.records(in: reply.body).prefix(3))
    }

    /// Remembers the party the guest picked. The server records it when it can; the
    /// phone remembers it either way, so Home greets them with their own reply.
    func confirm(_ record: RSVPRecord, weddingID: String) async {
        // 404/501, or any other answer: the pick is still remembered below.
        _ = await callLookup([
            "action": .string("confirm"),
            "id": .string(record.id),
            "wedding_id": .string(weddingID),
        ])
        if let data = try? JSONEncoder().encode([record]) {
            cache.save(data)
        }
    }

    private func callLookup(_ payload: [String: JSONValue]) async -> WeddingFunctions.Reply? {
        var request = URLRequest(url: ChatBackend.url.appending(path: "functions/v1/rsvp-lookup"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(ChatBackend.publishableKey, forHTTPHeaderField: "apikey")
        if let token = try? await ChatBackend.client.auth.session.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(payload)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              let body = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return WeddingFunctions.Reply(status: http.statusCode, body: body)
    }

    /// Reads the parties out of a reply — a bare array, or wrapped under a key. A
    /// `{ found: false }` is simply no matches.
    private static func records(in body: JSONValue?) -> [RSVPRecord] {
        guard let body, body["found"]?.boolValue != false else { return [] }
        var rows: [JSONValue] = []
        if let array = body.arrayValue {
            rows = array
        } else if body.objectValue != nil {
            for key in ["matches", "results", "rsvps", "records", "data"] {
                if let array = body[key]?.arrayValue { rows = array; break }
            }
        }
        return rows.compactMap { row in
            guard let record = row.decode(RSVPRecord.self) else { return nil }
            return record.displayName == nil ? nil : record
        }
    }
}
