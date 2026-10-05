import Foundation
import Observation

/// Offline-first store for the announcements the couple has sent to every guest.
///
/// The disk cache renders first, then a quiet background refresh replaces it. A failed
/// refresh never removes what is already on screen, and nothing here ever shows a spinner.
/// When the feed was last opened is remembered on this phone, so a newer announcement
/// can light the unread dot.
@Observable
final class NotificationsStore {
    static let shared = NotificationsStore()

    /// Newest first.
    private(set) var records: [NotificationRecord] = []
    private(set) var lastOpenedAt: Date?

    private let api: WeddingAPI
    private let cache = JSONDiskCache(filename: "wedding-updates.json")
    private let defaults = UserDefaults.standard
    private static let lastOpenedKey = "announcements.lastOpenedAt"

    private var isRefreshing = false
    private var lastRefresh: Date?

    init(api: WeddingAPI = .shared) {
        self.api = api
        if let cached = cache.load(NotificationRecord.self) {
            records = NotificationRecord.ordered(cached)
        }
        lastOpenedAt = defaults.object(forKey: Self.lastOpenedKey) as? Date
    }

    /// Oldest at the top, like a chat.
    var feed: [NotificationRecord] { records.reversed() }

    var latest: NotificationRecord? { records.first }

    /// Something has arrived since the feed was last opened on this phone.
    var hasUnread: Bool {
        guard let newest = records.first?.sentAt else { return false }
        guard let lastOpenedAt else { return true }
        return newest > lastOpenedAt.addingTimeInterval(0.5)
    }

    /// Everything currently in the feed has now been seen.
    func markOpened() {
        let stamp = max(Date(), records.first?.sentAt ?? .distantPast)
        lastOpenedAt = stamp
        defaults.set(stamp, forKey: Self.lastOpenedKey)
    }

    /// Refreshes at most every few seconds, so returning to the screen stays quiet.
    func refreshIfNeeded() async {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 20 { return }
        await refresh()
    }

    /// Fetches the feed again right now — on pull-to-refresh, or when a new one arrives.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await api.fetch(NotificationRecord.self, entity: "Notification")
            lastRefresh = Date()
            let fresh = NotificationRecord.ordered(result.items)
            guard !fresh.isEmpty else { return }
            cache.save(result.raw)
            if fresh != records { records = fresh }
        } catch {
            print("[NotificationsStore] refresh failed")
        }
    }
}
