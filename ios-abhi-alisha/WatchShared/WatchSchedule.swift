import Foundation
import WidgetKit

/// The weekend as the watch sees it, with the same rules as the phone: cached JSON
/// first, bundled snapshot second, and quiet refreshes on top. Nothing here networks
/// on the complication's behalf, so an entry is always answerable instantly.
nonisolated struct WatchSchedule: Sendable {
    let events: [WatchEvent]

    /// Saved copy first, bundled snapshot second. One of the two always answers.
    static func load() -> WatchSchedule {
        let cache = WatchScheduleCache()
        if let cached = cache.load(), !cached.isEmpty {
            return WatchSchedule(events: cached)
        }
        return WatchSchedule(events: cache.loadBundledSnapshot())
    }

    /// Only celebrations with a real start time can drive a countdown or a gauge.
    var timedEvents: [WatchEvent] {
        events.filter { $0.startsAt != nil }
    }

    /// The ceremony the countdown runs to: the first religious ceremony of the
    /// weekend, falling back to whatever happens first.
    var ceremony: WatchEvent? {
        if let ref = WatchWedding.current.mainEventRef, let match = timedEvents.first(where: { $0.id == ref }) {
            return match
        }
        return timedEvents.min { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
    }

    /// Whole days until the ceremony, counted by calendar day rather than by elapsed
    /// hours — so the morning of still reads as the same number all day.
    func daysRemaining(at now: Date) -> Int? {
        guard let target = ceremony?.startsAt else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: target)
        ).day
    }

    func happening(at now: Date) -> WatchEvent? {
        timedEvents.first { $0.isHappening(at: now) }
    }

    func upcoming(at now: Date) -> WatchEvent? {
        timedEvents.first { ($0.startsAt ?? .distantFuture) > now }
    }

    /// What a complication should be showing right now: whatever is underway, else
    /// what's next.
    func focus(at now: Date) -> WatchEvent? {
        happening(at: now) ?? upcoming(at: now)
    }

    /// How far along the weekend is, from its first celebration to the ceremony —
    /// the corner gauge fills along this line. Clamped, so it never under- or overflows.
    func countdownProgress(at now: Date) -> Double? {
        guard let target = ceremony?.startsAt else { return nil }
        guard let start = timedEvents.first?.startsAt, start < target else {
            return target <= now ? 1 : 0
        }
        let total = target.timeIntervalSince(start)
        guard total > 0 else { return nil }
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }

    /// Moments the complications redraw at: every hour for a day, plus the exact
    /// instant each celebration begins and ends, so "Happening now" turns over on
    /// time with no connection at all.
    func refreshDates(from now: Date, hours: Int = 24) -> [Date] {
        let horizon = now.addingTimeInterval(Double(hours) * 3600)
        var dates: [Date] = [now]

        let calendar = Calendar.current
        if var hour = calendar.nextDate(
            after: now,
            matching: DateComponents(minute: 0),
            matchingPolicy: .nextTime
        ) {
            while hour <= horizon {
                dates.append(hour)
                hour = hour.addingTimeInterval(3600)
            }
        }

        for event in timedEvents {
            for boundary in [event.startsAt, event.end].compactMap({ $0 })
            where boundary > now && boundary <= horizon {
                dates.append(boundary)
            }
        }

        return Array(Set(dates)).sorted()
    }

    /// Smart Stack weight: loud from an hour before a celebration until it ends,
    /// silent the rest of the time.
    func relevance(at date: Date) -> TimelineEntryRelevance {
        if let happening = happening(at: date) {
            return TimelineEntryRelevance(score: 100, duration: happening.end.timeIntervalSince(date))
        }
        if let next = upcoming(at: date), let start = next.startsAt,
           start.timeIntervalSince(date) <= 3600 {
            return TimelineEntryRelevance(score: 100, duration: next.end.timeIntervalSince(date))
        }
        return TimelineEntryRelevance(score: 0)
    }
}

/// Disk cache for the watch's own copy of the schedule. It lives in the shared
/// container when the App Group is granted — which is what lets the complications
/// read exactly what the app last fetched — and falls back to the process's own
/// caches folder otherwise. Either way the watch keeps working alone.
nonisolated struct WatchScheduleCache: Sendable {
    /// Must match the group named in both watch targets' entitlements.
    private static let appGroup = "group.com.businessgliders.abhialisha"
    /// Abhi & Alisha keep the original file name, so existing watches keep their copy.
    private var fileName: String {
        let wedding = WatchWedding.current
        return wedding.isSample ? "watch-schedule-events.json" : "watch-schedule-events-\(wedding.id.lowercased()).json"
    }

    private var fileURL: URL? {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) {
            return container.appendingPathComponent(fileName)
        }
        return FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName)
    }

    /// Raw JSON is cached verbatim so a future field never gets dropped by this build.
    func save(rawData: Data) {
        guard let fileURL else { return }
        do {
            try rawData.write(to: fileURL, options: .atomic)
        } catch {
            print("[WatchScheduleCache] save failed: \(error.localizedDescription)")
        }
    }

    func load() -> [WatchEvent]? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return WatchScheduleDecoder.decode(data)
    }

    var lastUpdated: Date? {
        guard let fileURL else { return nil }
        return try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
    }

    /// The snapshot shipped inside the watch bundle, used on a first launch with no
    /// signal — the same copy the iPhone app ships with.
    func loadBundledSnapshot() -> [WatchEvent] {
        // The bundled copy is Abhi & Alisha's schedule; any other wedding starts empty.
        guard WatchWedding.current.isSample else { return [] }
        guard let url = Bundle.main.url(forResource: "schedule_snapshot", withExtension: "json") else {
            print("[WatchScheduleCache] bundled snapshot missing")
            return []
        }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return WatchScheduleDecoder.decode(data)
    }
}

nonisolated enum WatchScheduleDecoder {
    /// Decodes the entity array, keeps only active events and sorts by `sort_order` —
    /// identical rules to the phone. One unreadable row never spoils the rest.
    static func decode(_ data: Data) -> [WatchEvent] {
        let rows = (try? JSONDecoder().decode([LenientRow<WatchEvent>].self, from: data)) ?? []
        return rows.compactMap(\.value)
            .filter { $0.isActive != false }
            .filter { !$0.title.isEmpty }
            .sorted { lhs, rhs in
                let left = lhs.sortOrder ?? .greatestFiniteMagnitude
                let right = rhs.sortOrder ?? .greatestFiniteMagnitude
                if left != right { return left < right }
                return (lhs.startsAt ?? .distantFuture) < (rhs.startsAt ?? .distantFuture)
            }
    }

    /// Decodes one row, keeping `nil` instead of throwing when its shape is unexpected.
    private struct LenientRow<T: Decodable & Sendable>: Decodable, Sendable {
        let value: T?

        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }
}

/// The watch's own line to the current wedding's schedule in Supabase: the public
/// events table, read with the publishable key, exactly as the phone reads it.
nonisolated enum WatchScheduleFetcher {
    private static let baseURL = "https://lrowuakbxuoynlyxlmnr.supabase.co"
    private static let publishableKey = "sb_publishable_hZduLD-YAv3B-IIu9Igy7g_oMRvZTvT"

    /// Returns the decoded events plus the mapped payload, which is what gets cached.
    static func fetch(for wedding: WatchWedding = .current) async throws -> (events: [WatchEvent], raw: Data) {
        var components = URLComponents(string: "\(baseURL)/rest/v1/events")!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "wedding_id", value: "eq.\(wedding.id.lowercased())"),
            URLQueryItem(name: "hidden", value: "eq.false"),
            URLQueryItem(name: "order", value: "starts_at,sort"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        let mapped = rows.map { row(from: $0, zone: wedding.timeZone) }
        let raw = try JSONSerialization.data(withJSONObject: mapped)
        return (WatchScheduleDecoder.decode(raw), raw)
    }

    /// One Supabase events row in the shape the watch already decodes.
    private static func row(from row: [String: Any], zone: TimeZone) -> [String: Any] {
        let details = (row["details"] as? [String: Any]) ?? [:]
        var out: [String: Any] = [:]
        out["id"] = text(row["ref"]) ?? text(row["id"]) ?? UUID().uuidString
        out["title"] = text(row["title"]) ?? ""
        if let starts = text(row["starts_at"]) {
            out["starts_at"] = starts
            if let date = WatchEvent.date(from: starts) {
                out["date"] = text(details["date"]) ?? format(date, "EEEE, MMMM d, yyyy", zone)
                out["time"] = text(details["time"]) ?? format(date, "h:mm a", zone)
            }
        }
        if let ends = text(row["ends_at"]) { out["ends_at"] = ends }
        if let icon = text(details["icon_key"]) {
            out["icon_key"] = icon
        } else if let kind = text(row["kind"])?.lowercased() {
            let icons = [
                "welcome": "flutes", "cocktails": "flutes", "party": "flutes",
                "haldi": "paisley", "mehndi": "paisley", "sangeet": "paisley",
                "reception": "sparkle", "farewell": "sun", "brunch": "sun"
            ]
            if let icon = icons[kind] { out["icon_key"] = icon }
        }
        if let sort = row["sort"] as? Double { out["sort_order"] = sort }
        else if let sort = row["sort"] as? Int { out["sort_order"] = Double(sort) }
        if let venue = text(row["venue_name"]) { out["location_name"] = venue }
        if let dress = text(row["dress_code"]) { out["dress_code"] = dress }
        if let description = text(row["description"]) { out["description"] = description }
        out["is_active"] = (row["hidden"] as? Bool) != true
        return out
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func format(_ date: Date, _ pattern: String, _ zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// The watch app's schedule: loads what's on disk instantly, then refreshes quietly.
/// A failed refresh changes nothing on screen.
@MainActor
@Observable
final class WatchScheduleStore {
    static let shared = WatchScheduleStore()

    private(set) var events: [WatchEvent]
    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?

    private init() {
        events = WatchSchedule.load().events
        lastUpdated = WatchScheduleCache().lastUpdated
    }

    /// The phone opened another wedding: show its cached copy at once, then fetch.
    func weddingDidChange() async {
        events = WatchSchedule.load().events
        lastUpdated = WatchScheduleCache().lastUpdated
        WidgetCenter.shared.reloadAllTimelines()
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let wedding = WatchWedding.current
        guard let fresh = try? await WatchScheduleFetcher.fetch(for: wedding) else { return }
        // The phone may have switched weddings while this was in flight.
        guard WatchWedding.current == wedding else { return }
        WatchScheduleCache().save(rawData: fresh.raw)
        events = fresh.events
        lastUpdated = Date()
        // The complications redraw from the same cache.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
