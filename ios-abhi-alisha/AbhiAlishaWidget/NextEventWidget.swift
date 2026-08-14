import SwiftUI
import WidgetKit

/// "Next celebration" — whatever is underway, or whatever comes next. Tapping it opens
/// that celebration on the Schedule tab.
struct NextEventWidget: Widget {
    let kind = "AbhiAlishaNextEvent"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeddingProvider()) { entry in
            NextEventWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Celebration")
        .description("The celebration happening now, or the one still to come.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
        .containerBackgroundRemovable(false)
    }
}

struct NextEventWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: WeddingEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            RectangularNextEvent(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(link)
        default:
            MediumNextEvent(entry: entry)
                .containerBackground(WidgetPalette.paper, for: .widget)
                .widgetURL(link)
        }
    }

    /// Straight to this celebration when we know which one it is, Home otherwise.
    private var link: URL? {
        guard let id = entry.event?.id else { return WeddingGroup.Link.home }
        return WeddingGroup.Link.event(id)
    }
}

// MARK: - Medium

private struct MediumNextEvent: View {
    let entry: WeddingEntry

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // The celebration's own line-art motif, engraved faintly behind the words.
            LineArtIcon(key: entry.event?.iconKey ?? .sparkle)
                .stroke(
                    WidgetPalette.gold.opacity(0.17),
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 86, height: 86)
                .offset(x: 14, y: -10)
                .accessibilityHidden(true)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let event = entry.event {
            VStack(alignment: .leading, spacing: 0) {
                WidgetEyebrow(
                    text: entry.isHappeningNow ? "Happening Now" : "Next",
                    size: 9,
                    color: WidgetPalette.gold
                )

                Text(event.title)
                    .brandFont(.widgetTitle)
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 7)
                    .padding(.trailing, 58)

                WidgetRule(width: 24, opacity: 0.6)
                    .padding(.top, 9)

                Spacer(minLength: 4)

                if let timing = event.timingLine {
                    Text(timing)
                        .brandFont(.widgetBody)
                        .foregroundStyle(WidgetPalette.body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if let location = event.location {
                    Text(location)
                        .brandFont(.widgetBodySmall)
                        .foregroundStyle(WidgetPalette.body.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 2)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                WidgetEyebrow(text: "Abhi & Alisha", size: 9)
                Text("The celebrations are complete.")
                    .brandFont(.widgetTitleSmall)
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Lock Screen strip

/// Name and time, in whatever tint the Lock Screen is using.
private struct RectangularNextEvent: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: WeddingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let event = entry.event {
                Text(entry.isHappeningNow ? "HAPPENING NOW" : "NEXT")
                    .font(BrandLabel.font(size: 8.5, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(accent)
                    .lineLimit(1)

                Text(event.title)
                    .brandFont(.accessoryTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                if let timing = event.timeLine ?? event.dateLine {
                    Text(timing)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            } else {
                Text("ABHI & ALISHA")
                    .font(BrandLabel.font(size: 8.5, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(accent)
                Text("Celebrations complete")
                    .brandFont(.accessoryTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var accent: Color {
        renderingMode == .fullColor ? WidgetPalette.gold : .primary
    }
}
