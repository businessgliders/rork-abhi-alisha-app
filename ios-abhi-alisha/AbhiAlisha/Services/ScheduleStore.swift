import Foundation
import Observation
import WidgetKit

/// Offline-first schedule store.
///
/// Launch order: bundled snapshot (works with zero connection) → disk cache →
/// quiet background refresh. Cached content is never covered by a spinner.
///
/// The cache lives in the App Group, so every save here is also what the widgets and
/// the Live Activity will read the next time the system asks them to draw.
@Observable
final class ScheduleStore {
    private(set) var events: [ScheduleEvent] = []
    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?
    private(set) var isShowingOfflineData = false
    /// Ticks roughly every minute so countdowns and the lit bulb advance on their own.
    private(set) var now: Date = Date()

    private let service: ScheduleService
    private let cache: ScheduleCache
    private var minuteTask: Task<Void, Never>?

    init(service: ScheduleService = .shared, cache: ScheduleCache = .shared) {
        self.service = service
        self.cache = cache
        cache.adoptLegacyCacheIfNeeded()
        loadLocal()
    }

    deinit {
        minuteTask?.cancel()
    }

    // MARK: - Local first

    private func loadLocal() {
        let bundled = cache.loadBundledSnapshot()
        if let cached = cache.load(), !cached.isEmpty {
            events = cached
            lastUpdated = cache.lastUpdated
        } else if !bundled.isEmpty {
            events = bundled
        }
        isShowingOfflineData = events.isEmpty == false && lastUpdated == nil
    }

    // MARK: - Refresh

    /// Fetches quietly in the background. Failures keep the cached content on screen.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await service.fetchEvents()
            guard !result.events.isEmpty else { return }
            cache.save(rawData: result.raw)
            events = result.events
            lastUpdated = Date()
            isShowingOfflineData = false
            WidgetCenter.shared.reloadAllTimelines()
            await EventActivityController.shared.sync(events: events, at: Date())
        } catch {
            isShowingOfflineData = true
            print("[ScheduleStore] refresh failed: \(error.localizedDescription)")
        }
    }

    func startClock() {
        guard minuteTask == nil else { return }
        minuteTask = Task { [weak self] in
            // The first pass raises anything already due before the first minute is up.
            if let self {
                await EventActivityController.shared.sync(events: self.events, at: Date())
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                let moment = Date()
                self.now = moment
                await EventActivityController.shared.sync(events: self.events, at: moment)
            }
        }
    }

    // MARK: - Derived timeline

    /// The event to highlight: happening now, else the next upcoming, else the last one.
    func currentIndex(at date: Date? = nil) -> Int? {
        guard !events.isEmpty else { return nil }
        let reference = date ?? now
        if let live = events.firstIndex(where: { $0.isHappening(at: reference) }) {
            return live
        }
        if let upcoming = events.firstIndex(where: { ($0.startsAt ?? .distantFuture) > reference }) {
            return upcoming
        }
        return events.indices.last
    }

    /// First event that has not started yet — the Home "Next" card.
    var nextEvent: ScheduleEvent? {
        events.first { ($0.startsAt ?? .distantFuture) > now }
    }

    /// The wedding ceremony the countdown runs to: the first religious ceremony,
    /// falling back to the first event of the weekend.
    var mainCeremony: ScheduleEvent? {
        events.first { $0.ceremonyType != nil } ?? events.first
    }
}
