import Foundation
import WidgetKit

/// Just enough of a celebration to draw a widget, resolved once when the entry is made
/// so nothing is computed while the snapshot is being rendered.
///
/// Every field that could be blank stays optional — a widget omits a line rather than
/// leaving an empty one behind.
nonisolated struct EventSummary: Sendable, Hashable {
    let id: String
    let title: String
    let dateLine: String?
    let timeLine: String?
    let location: String?
    let iconKey: EventIconKey
    let startsAt: Date?

    init(_ event: ScheduleEvent) {
        id = event.id
        title = event.title
        dateLine = event.displayDate
        timeLine = event.displayTime
        location = event.locationName
        iconKey = event.iconKey
        startsAt = event.startsAt
    }

    /// Date and time on one line, joined only when both are actually known.
    var timingLine: String? {
        let parts = [dateLine, timeLine].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}

nonisolated struct WeddingEntry: TimelineEntry {
    let date: Date
    let daysRemaining: Int?
    let event: EventSummary?
    let isHappeningNow: Bool

    static func make(at date: Date, from timeline: WeddingTimeline) -> WeddingEntry {
        let happening = timeline.happening(at: date)
        let focus = happening ?? timeline.upcoming(at: date)
        return WeddingEntry(
            date: date,
            daysRemaining: timeline.daysRemaining(at: date),
            event: focus.map(EventSummary.init),
            isHappeningNow: happening != nil
        )
    }

    /// Shown in the widget gallery and for a beat while a real entry is being made.
    static var placeholder: WeddingEntry {
        WeddingEntry.make(at: Date(), from: .load())
    }
}

/// Reads the schedule the app already cached in the shared container, or the snapshot
/// bundled inside the widget itself. It never makes a network call of its own.
nonisolated struct WeddingProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeddingEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WeddingEntry) -> Void) {
        completion(WeddingEntry.make(at: Date(), from: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeddingEntry>) -> Void) {
        let timeline = WeddingTimeline.load()
        let now = Date()
        // An entry every hour for the next day, plus one at the exact moment each
        // celebration begins and ends, so "Happening now" turns over on time.
        let entries = timeline
            .refreshDates(from: now)
            .map { WeddingEntry.make(at: $0, from: timeline) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
