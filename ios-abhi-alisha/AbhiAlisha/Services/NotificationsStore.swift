import Foundation
import Observation

/// Offline-first store for the notes the couple has sent to every guest.
///
/// The disk cache renders first, then a quiet background refresh replaces it. A failed
/// refresh never removes what is already on screen, and nothing here ever shows a spinner.
@Observable
final class NotificationsStore {
    private(set) var records: [NotificationRecord] = []

    private let api: WeddingAPI
    private let cache = JSONDiskCache(filename: "wedding-updates.json")

    private var didRefresh = false
    private var isRefreshing = false

    init(api: WeddingAPI = .shared) {
        self.api = api
        if let cached = cache.load(NotificationRecord.self) {
            records = NotificationRecord.ordered(cached)
        }
    }

    /// Refreshes once per launch, quietly.
    func refreshIfNeeded() async {
        guard !didRefresh, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await api.fetch(NotificationRecord.self, entity: "Notification")
            let fresh = NotificationRecord.ordered(result.items)
            guard !fresh.isEmpty else { return }
            cache.save(result.raw)
            records = fresh
        } catch {
            print("[NotificationsStore] refresh failed")
        }
        didRefresh = true
    }
}
