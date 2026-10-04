import SwiftUI
import WidgetKit

/// Just enough of a celebration to draw a complication, resolved once when the entry
/// is made so nothing is computed while the snapshot is being rendered.
nonisolated struct ComplicationEvent: Sendable, Hashable {
    let id: String
    let title: String
    let timeLine: String?
    let location: String?
    let iconKey: WatchIconKey
    let startsAt: Date?

    init(_ event: WatchEvent) {
        id = event.id
        title = event.title
        timeLine = event.displayTime
        location = event.locationName
        iconKey = event.iconKey
        startsAt = event.startsAt
    }
}

nonisolated struct WeddingEntry: TimelineEntry {
    let date: Date
    let daysRemaining: Int?
    let event: ComplicationEvent?
    let isHappeningNow: Bool
    let progress: Double?
    let relevance: TimelineEntryRelevance

    static func make(at date: Date, from schedule: WatchSchedule) -> WeddingEntry {
        let happening = schedule.happening(at: date)
        let focus = happening ?? schedule.upcoming(at: date)
        return WeddingEntry(
            date: date,
            daysRemaining: schedule.daysRemaining(at: date),
            event: focus.map(ComplicationEvent.init),
            isHappeningNow: happening != nil,
            progress: schedule.countdownProgress(at: date),
            relevance: schedule.relevance(at: date)
        )
    }

    /// Shown in the face gallery and for a beat while a real entry is being made.
    static var placeholder: WeddingEntry {
        .make(at: Date(), from: .load())
    }
}

/// Reads the schedule the watch app cached in the shared container, or the snapshot
/// bundled inside this extension. It never makes a network call of its own, yet the
/// entries still turn over at every start and end — they were drawn in ahead of time.
nonisolated struct WeddingProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeddingEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WeddingEntry) -> Void) {
        completion(.make(at: Date(), from: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeddingEntry>) -> Void) {
        let schedule = WatchSchedule.load()
        let entries = schedule
            .refreshDates(from: Date())
            .map { WeddingEntry.make(at: $0, from: schedule) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// The four complications — circle, corner, inline and rectangle — drawn in the
/// wedding's black and gold, with the Smart Stack relevance carried on every entry.
struct WeddingComplications: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeddingComplications", provider: WeddingProvider()) { entry in
            WeddingComplicationView(entry: entry)
        }
        .configurationDisplayName("Abhi & Alisha")
        .description("Days until the wedding, and whatever is happening next.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct WeddingComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeddingEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            corner
        case .accessoryInline:
            inline
        default:
            rectangular
        }
    }

    /// Days until the ceremony — the celebration's own mark while it's underway.
    private var circular: some View {
        Group {
            if entry.isHappeningNow, let event = entry.event {
                WatchLineArtIcon(key: event.iconKey)
                    .stroke(
                        WatchTheme.gold,
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 26, height: 26)
                    .widgetAccentable()
                    .accessibilityLabel("\(event.title) is happening now")
            } else if let days = entry.daysRemaining {
                Text(verbatim: "\(days)")
                    .font(.watchPlayfair(22))
                    .foregroundStyle(WatchTheme.gold)
                    .widgetAccentable()
                    .accessibilityLabel("\(days) days until the wedding")
            } else {
                Image("crest")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22)
                    .foregroundStyle(WatchTheme.gold)
                    .accessibilityLabel("Abhi and Alisha")
            }
        }
    }

    /// Days remaining with a curved gauge filling as the wedding gets closer.
    private var corner: some View {
        Gauge(value: entry.progress ?? 0, in: 0...1) {
            Text(verbatim: "Days")
        } currentValueLabel: {
            Text(verbatim: "\(entry.daysRemaining ?? 0)")
                .font(.watchPlayfair(15))
                .foregroundStyle(WatchTheme.gold)
                .widgetAccentable()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(WatchTheme.gold)
        .widgetLabel {
            Text(verbatim: "DAYS")
        }
        .accessibilityLabel("\(entry.daysRemaining ?? 0) days until the wedding")
    }

    /// One quiet line: the next celebration and its time.
    private var inline: some View {
        Text(verbatim: inlineText)
            .font(.watchCormorant(15, weight: .semibold))
            .foregroundStyle(WatchTheme.cream)
            .widgetAccentable()
            .lineLimit(1)
    }

    private var inlineText: String {
        guard let event = entry.event else {
            if let days = entry.daysRemaining, days > 0 { return Self.countdownLine(days) }
            return "The Celebrations"
        }
        if entry.isHappeningNow { return "\(event.title) · Now" }
        // Close in, the celebration leads; farther out, the countdown does.
        if let startsAt = event.startsAt,
           startsAt.timeIntervalSince(entry.date) <= 24 * 3600,
           let time = event.timeLine {
            return "\(event.title) · \(time)"
        }
        if let days = entry.daysRemaining, days > 0 { return Self.countdownLine(days) }
        guard let time = event.timeLine else { return event.title }
        return "\(event.title) · \(time)"
    }

    /// The X-Large face renders this line in giant type — the countdown is its moment.
    private static func countdownLine(_ days: Int) -> String {
        days == 1 ? "1 DAY TO GO" : "\(days) DAYS TO GO"
    }

    /// Name, time and place — "Happening now" rides above the name while it's on.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.isHappeningNow {
                Text("HAPPENING NOW")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(WatchTheme.gold)
                    .widgetAccentable()
            }

            if let event = entry.event {
                Text(event.title)
                    .font(.watchPlayfair(13.5, weight: .semibold))
                    .foregroundStyle(WatchTheme.cream)
                    .lineLimit(1)

                Text(verbatim: [event.timeLine, event.location].compactMap { $0 }.joined(separator: "  ·  "))
                    .font(.watchCormorant(11.5))
                    .foregroundStyle(WatchTheme.creamDim)
                    .lineLimit(1)
            } else {
                Text("The Celebrations")
                    .font(.watchPlayfair(13.5, weight: .semibold))
                    .foregroundStyle(WatchTheme.cream)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
