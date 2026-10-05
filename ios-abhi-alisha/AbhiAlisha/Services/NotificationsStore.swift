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

    /// Newest first: the server's records plus anything just sent from this phone that
    /// the server hasn't listed yet.
    var records: [NotificationRecord] {
        guard !justSent.isEmpty else { return serverRecords }
        return NotificationRecord.ordered(serverRecords + justSent)
    }

    private var serverRecords: [NotificationRecord] = []
    /// Announcements this admin just sent, held until the server's copy appears.
    private var justSent: [NotificationRecord] = []
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
            serverRecords = NotificationRecord.ordered(cached)
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

    /// Shows a just-sent announcement at the bottom of the feed straight away.
    func addJustSent(title: String, body: String) {
        let record = NotificationRecord(
            id: "local-\(UUID().uuidString)",
            title: title,
            body: body,
            sentAt: Date()
        )
        justSent.append(record)
        markOpened()
    }

    /// Fetches again a few times after a send, so the server's copy replaces ours quickly.
    func refreshAfterSend() async {
        for delay in [0.8, 2.5, 6.0] {
            try? await Task.sleep(for: .seconds(delay))
            await refresh()
            if justSent.isEmpty { break }
        }
        markOpened()
    }

    /// Drops local copies the server now lists, matched by their words.
    private func reconcileJustSent() {
        guard !justSent.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-15 * 60)
        justSent.removeAll { local in
            if let sentAt = local.sentAt, sentAt < cutoff { return true }
            return serverRecords.contains { $0.title == local.title && $0.body == local.body }
        }
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
            if fresh != serverRecords { serverRecords = fresh }
            reconcileJustSent()
        } catch {
            print("[NotificationsStore] refresh failed")
        }
    }
}
