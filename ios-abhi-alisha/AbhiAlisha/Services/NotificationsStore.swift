import Foundation
import Observation
import Supabase

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

    private let cache = JSONDiskCache(filename: "wedding-updates.json")
    private let defaults = UserDefaults.standard
    /// Each wedding remembers its own; Abhi & Alisha keep the original key.
    private static var lastOpenedKey: String { ActiveWedding.scopedName("announcements.lastOpenedAt") }

    private var isRefreshing = false
    private var lastRefresh: Date?
    private var liveChannel: RealtimeChannelV2?
    private var liveTask: Task<Void, Never>?
    private var liveWeddingID: String?

    init() {
        loadLocal()
    }

    private func loadLocal() {
        serverRecords = cache.load(NotificationRecord.self).map(NotificationRecord.ordered) ?? []
        lastOpenedAt = defaults.object(forKey: Self.lastOpenedKey) as? Date
    }

    /// Another wedding opened: show its announcements and listen for its new ones.
    func switchWedding() {
        justSent = []
        lastRefresh = nil
        loadLocal()
        stopListening()
        Task { await refresh() }
    }

    /// New announcements appear the moment they're sent.
    func startListening() {
        let weddingID = ActiveWedding.id
        guard liveWeddingID != weddingID else { return }
        stopListening()
        liveWeddingID = weddingID
        let channel = ChatBackend.client.channel("announcements-\(weddingID)")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "announcements",
            filter: .eq("wedding_id", value: weddingID)
        )
        liveChannel = channel
        liveTask = Task {
            for await _ in inserts {
                await NotificationsStore.shared.refresh()
            }
        }
        Task {
            do { try await channel.subscribeWithError() } catch { print("[NotificationsStore] live updates unavailable") }
        }
    }

    private func stopListening() {
        liveTask?.cancel()
        liveTask = nil
        liveWeddingID = nil
        if let channel = liveChannel {
            liveChannel = nil
            Task { await ChatBackend.client.removeChannel(channel) }
        }
    }

    /// Oldest at the top, like a chat.
    var feed: [NotificationRecord] { records.reversed() }

    var latest: NotificationRecord? { records.first }

    /// Something has arrived since the deck was last opened on this phone.
    var hasUnread: Bool {
        guard let newest = records.first else { return false }
        return isUnread(newest)
    }

    /// True when this record arrived after the deck was last opened on this phone.
    func isUnread(_ record: NotificationRecord) -> Bool {
        guard let sentAt = record.sentAt else { return false }
        guard let lastOpenedAt else { return true }
        return sentAt > lastOpenedAt.addingTimeInterval(0.5)
    }

    /// Everything currently in the feed has now been seen.
    func markOpened() {
        let stamp = max(Date(), records.first?.sentAt ?? .distantPast)
        lastOpenedAt = stamp
        defaults.set(stamp, forKey: Self.lastOpenedKey)
    }

    /// Shows a just-sent announcement at the front of the deck straight away, keeping
    /// where it opens so its button and colour are right before the server confirms.
    func addJustSent(title: String, body: String, destination: AnnouncementDestination? = nil) {
        let record = NotificationRecord(
            id: "local-\(UUID().uuidString)",
            title: title,
            body: body,
            sentAt: Date(),
            screen: destination?.screen,
            eventID: destination?.eventID
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
            let weddingID = ActiveWedding.id
            let raw = try await MilniAPI.shared.announcements(weddingID: weddingID)
            guard weddingID == ActiveWedding.id else { return }
            lastRefresh = Date()
            let fresh = NotificationRecord.ordered(MilniDecode.list(NotificationRecord.self, from: raw))
            if fresh.isEmpty, ActiveWedding.snapshot.isSampleWedding { return }
            cache.save(raw)
            if fresh != serverRecords { serverRecords = fresh }
            reconcileJustSent()
        } catch {
            print("[NotificationsStore] refresh failed")
        }
    }
}
