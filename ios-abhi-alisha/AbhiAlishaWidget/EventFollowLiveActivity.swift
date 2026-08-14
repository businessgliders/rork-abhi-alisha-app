import ActivityKit
import SwiftUI
import WidgetKit

/// The wedding days on the Lock Screen and in the Dynamic Island: gold on deep navy,
/// counting down to a celebration and then simply saying it is underway.
struct EventFollowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventFollowAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(WidgetPalette.night)
                .activitySystemActionForegroundColor(WidgetPalette.nightGold)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityMotif(key: context.attributes.iconKey, size: 34)
                        .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ActivityCountdown(context: context, alignment: .trailing)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .brandFont(.widgetTitleSmall)
                        .foregroundStyle(WidgetPalette.nightInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ActivityFooter(context: context)
                        .padding(.top, 2)
                }
            } compactLeading: {
                ActivityMotif(key: context.attributes.iconKey, size: 17)
            } compactTrailing: {
                CompactCountdown(context: context)
            } minimal: {
                ActivityMotif(key: context.attributes.iconKey, size: 17)
            }
            .widgetURL(WeddingGroup.Link.event(context.attributes.eventID))
            .keylineTint(WidgetPalette.nightGold)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<EventFollowAttributes>

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ActivityMotif(key: context.attributes.iconKey, size: 44)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 0) {
                WidgetEyebrow(
                    text: context.state.phase == .now ? "Happening Now" : "Up Next",
                    size: 9,
                    color: WidgetPalette.nightGold
                )

                Text(context.attributes.title)
                    .brandFont(.widgetTitle)
                    .foregroundStyle(WidgetPalette.nightInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 5)

                if let location = context.attributes.locationName {
                    Text(location)
                        .brandFont(.widgetBody)
                        .foregroundStyle(WidgetPalette.nightBody)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 3)
                }
            }

            Spacer(minLength: 0)

            ActivityCountdown(context: context, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }
}

// MARK: - Pieces

/// The celebration's own line-art motif, stroked in gold.
private struct ActivityMotif: View {
    let key: EventIconKey
    var size: CGFloat

    var body: some View {
        LineArtIcon(key: key)
            .stroke(
                WidgetPalette.nightGold.opacity(0.9),
                style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A live countdown to the start, replaced by a steady line once it's underway.
private struct ActivityCountdown: View {
    let context: ActivityViewContext<EventFollowAttributes>
    var alignment: HorizontalAlignment = .trailing

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            if context.state.phase == .now {
                Text("Happening now")
                    .brandFont(.widgetTitleSmall)
                    .foregroundStyle(WidgetPalette.nightGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(context.attributes.startsAt, style: .timer)
                    .brandFont(.widgetTitleSmall)
                    .monospacedDigit()
                    .foregroundStyle(WidgetPalette.nightGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)

                Text("UNTIL IT BEGINS")
                    .font(BrandLabel.font(size: 7.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(WidgetPalette.nightBody)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(minWidth: 74, alignment: alignment == .trailing ? .trailing : .leading)
    }
}

/// The tight version for the Dynamic Island's trailing corner.
private struct CompactCountdown: View {
    let context: ActivityViewContext<EventFollowAttributes>

    var body: some View {
        Group {
            if context.state.phase == .now {
                Text("Now")
                    .font(BrandLabel.font(size: 12, weight: .semibold))
            } else {
                Text(context.attributes.startsAt, style: .timer)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(WidgetPalette.nightGold)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: 56)
    }
}

/// Where it is and what to wear — each line dropped entirely when it isn't published.
private struct ActivityFooter: View {
    let context: ActivityViewContext<EventFollowAttributes>

    private var lines: [String] {
        [context.attributes.locationName, context.attributes.dressCode].compactMap { $0 }
    }

    var body: some View {
        if lines.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 2) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .brandFont(.widgetBodySmall)
                        .foregroundStyle(WidgetPalette.nightBody)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
