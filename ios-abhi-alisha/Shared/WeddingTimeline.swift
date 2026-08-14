import Foundation

/// The weekend as the widgets see it: read from the shared cache, fall back to the
/// bundled snapshot, and answer questions about a moment in time. No networking, ever.
nonisolated struct WeddingTimeline: Sendable {
    let events: [ScheduleEvent]

    /// Shared cache first, bundled snapshot second. One of the two always answers.
    static func load() -> WeddingTimeline {
        let cache = ScheduleCache.shared
        if let cached = cache.load(), !cached.isEmpty {
            return WeddingTimeline(events: cached)
        }
        return WeddingTimeline(events: cache.loadBundledSnapshot())
    }

    /// Only events with a real start time can drive a countdown or a Live Activity.
    var timedEvents: [ScheduleEvent] {
        events.filter { $0.startsAt != nil }
    }

    /// The ceremony the countdown runs to: the first religious ceremony of the weekend,
    /// falling back to whatever happens first.
    var ceremony: ScheduleEvent? {
        timedEvents.first { $0.ceremonyType != nil } ?? timedEvents.first
    }

    /// Whole days between today and the ceremony, counted by calendar day rather than by
    /// elapsed hours — so the morning of still reads as the same number all day.
    func daysRemaining(at now: Date) -> Int? {
        guard let target = ceremony?.startsAt else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: target)
        ).day
    }

    func happening(at now: Date) -> ScheduleEvent? {
        timedEvents.first { $0.isHappening(at: now) }
    }

    func upcoming(at now: Date) -> ScheduleEvent? {
        timedEvents.first { ($0.startsAt ?? .distantFuture) > now }
    }

    /// What a widget should be showing right now: whatever is underway, else what's next.
    func focus(at now: Date) -> ScheduleEvent? {
        happening(at: now) ?? upcoming(at: now)
    }

    /// Moments the widgets need to redraw at: every hour for a day, plus the exact
    /// instant each celebration begins and ends so "Happening now" turns over on time.
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
            for boundary in [event.startsAt, event.endsAt].compactMap({ $0 })
            where boundary > now && boundary <= horizon {
                dates.append(boundary)
            }
        }

        return Array(Set(dates)).sorted()
    }
}
