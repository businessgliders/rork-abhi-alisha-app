import Foundation

/// The wedding an invitation link points at, as `get_wedding_preview` returns it.
nonisolated struct ClipWedding: Sendable, Hashable {
    let id: String
    let code: String
    var partnerOne: String
    var partnerTwo: String
    var title: String
    var startDate: String?
    var endDate: String?
    var venueName: String?
    var city: String?
    var country: String?
    var coverURL: URL?
    var theme: ClipTheme

    var coupleNames: String {
        if partnerOne.isEmpty || partnerTwo.isEmpty { return title }
        return "\(partnerOne) & \(partnerTwo)"
    }

    var initials: String {
        let joined = ((partnerOne.first.map(String.init) ?? "") + (partnerTwo.first.map(String.init) ?? "")).uppercased()
        return joined.isEmpty ? String(title.prefix(1)).uppercased() : joined
    }

    var place: String? {
        let parts = [venueName, city, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func dateRange(in zone: TimeZone) -> String? {
        guard let start = ClipDates.day(startDate, in: zone) else { return nil }
        var short = Date.FormatStyle.dateTime.month(.wide).day()
        short.timeZone = zone
        var full = Date.FormatStyle.dateTime.month(.wide).day().year()
        full.timeZone = zone
        guard let end = ClipDates.day(endDate, in: zone), end > start else { return start.formatted(full) }
        return "\(start.formatted(short)) – \(end.formatted(full))"
    }
}

/// One celebration on a public schedule.
nonisolated struct ClipEvent: Identifiable, Sendable, Hashable {
    let id: String
    var title: String
    var startsAt: Date?
    var venue: String?
    var dressCode: String?
}

nonisolated enum ClipDates {
    static func day(_ text: String?, in zone: TimeZone) -> Date? {
        guard let text, text.count >= 10 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func instant(_ text: String?) -> Date? {
        guard let text else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}

/// Plain read-only requests with the public key. No sign-in, nothing written, nothing stored
/// on a server: the clip only looks the invitation up.
nonisolated enum ClipAPI {
    static let base = URL(string: "https://lrowuakbxuoynlyxlmnr.supabase.co")!
    static let key = "sb_publishable_hZduLD-YAv3B-IIu9Igy7g_oMRvZTvT"

    enum Failure: Error { case notFound, offline }

    private static func request(_ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil) -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private static func rows(_ request: URLRequest) async throws -> [[String: Any]] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.offline
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        let json = try? JSONSerialization.jsonObject(with: data)
        if let array = json as? [[String: Any]] { return array }
        if let object = json as? [String: Any] { return [object] }
        return []
    }

    static func preview(code: String) async throws -> ClipWedding {
        let found = try await rows(request("rest/v1/rpc/get_wedding_preview", body: ["p_code": code]))
        guard let row = found.first else { throw Failure.notFound }
        let wedding = (row["wedding"] as? [String: Any]) ?? row
        guard let id = string(wedding["id"]) ?? string(row["wedding_id"]), !id.isEmpty else { throw Failure.notFound }
        let covers = (wedding["cover_urls"] as? [Any])?.compactMap { string($0) } ?? []
        return ClipWedding(
            id: id,
            code: code,
            partnerOne: string(wedding["partner_one"]) ?? "",
            partnerTwo: string(wedding["partner_two"]) ?? "",
            title: string(wedding["title"]) ?? "",
            startDate: string(wedding["start_date"]),
            endDate: string(wedding["end_date"]),
            venueName: string(wedding["venue_name"]),
            city: string(wedding["city"]),
            country: string(wedding["country"]),
            coverURL: covers.first.flatMap(URL.init(string:)),
            theme: ClipTheme.parse(wedding["theme"])
        )
    }

    /// The wedding's time zone, when its row is public.
    static func timeZone(weddingID: String) async -> TimeZone? {
        let found = try? await rows(request("rest/v1/weddings", query: [
            URLQueryItem(name: "select", value: "timezone"),
            URLQueryItem(name: "id", value: "eq.\(weddingID)")
        ]))
        return found?.first.flatMap { string($0["timezone"]) }.flatMap(TimeZone.init(identifier:))
    }

    /// The schedule, only when the couple made it public. A private wedding returns no
    /// rows, and the clip says the full schedule is in the app.
    static func publicSchedule(weddingID: String) async -> [ClipEvent] {
        let found = (try? await rows(request("rest/v1/events", query: [
            URLQueryItem(name: "select", value: "id,title,starts_at,venue_name,dress_code"),
            URLQueryItem(name: "wedding_id", value: "eq.\(weddingID)"),
            URLQueryItem(name: "order", value: "starts_at.asc")
        ]))) ?? []
        return found.compactMap { row in
            guard let id = string(row["id"]), let title = string(row["title"]), !title.isEmpty else { return nil }
            let dress = string(row["dress_code"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ClipEvent(
                id: id,
                title: title,
                startsAt: ClipDates.instant(string(row["starts_at"])),
                venue: string(row["venue_name"]),
                dressCode: (dress?.isEmpty ?? true) ? nil : dress
            )
        }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }
}

/// Reads a join code out of `https://milniapp.com/j/CODE` (or a bare code typed in).
nonisolated enum ClipLink {
    static func code(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let host = url.host?.lowercased(), host.hasSuffix("milniapp.com"),
              parts.first?.lowercased() == "j", let raw = parts.dropFirst().first else { return nil }
        return normalize(raw)
    }

    static func normalize(_ text: String) -> String? {
        let code = String(text.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(10))
        return (6...10).contains(code.count) ? code : nil
    }
}

/// Hands the invitation to the full app through the shared App Group, so it opens on
/// "Invitation found" after it's installed. Only the join code is kept, never anything
/// about the guest.
nonisolated enum ClipHandoffWriter {
    static let suite = "group.com.businessgliders.milni"
    static let codeKey = "clip.handoff.code"
    static let dateKey = "clip.handoff.date"

    static func save(code: String) {
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defaults.set(code, forKey: codeKey)
        defaults.set(Date().timeIntervalSince1970, forKey: dateKey)
    }
}
