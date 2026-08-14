import SwiftUI
import WidgetKit

/// "Days to go" — the countdown to the ceremony, as a Home Screen tile or a Lock Screen
/// ring. Tapping it opens the app on Home.
struct CountdownWidget: Widget {
    let kind = "AbhiAlishaCountdown"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeddingProvider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Days to Go")
        .description("The countdown to Abhi and Alisha's wedding day.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
        .containerBackgroundRemovable(false)
    }
}

struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: WeddingEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularCountdown(entry: entry)
        case .systemMedium:
            MediumCountdown(entry: entry)
                .widgetURL(WeddingGroup.Link.home)
                .containerBackground(WidgetPalette.paper, for: .widget)
        default:
            SmallCountdown(entry: entry)
                .widgetURL(WeddingGroup.Link.home)
                .containerBackground(WidgetPalette.paper, for: .widget)
        }
    }
}

// MARK: - The countdown itself

/// How the number reads on any given day. The wedding is a single day in a guest's life,
/// so the tile speaks differently before it, during it, and after.
nonisolated enum CountdownPhrase: Sendable {
    case counting(Int)
    case today
    case married
    /// No ceremony date published yet — the tile carries the couple instead of a number.
    case couple

    init(daysRemaining: Int?) {
        guard let daysRemaining else {
            self = .couple
            return
        }
        if daysRemaining > 0 {
            self = .counting(daysRemaining)
        } else if daysRemaining == 0 {
            self = .today
        } else {
            self = .married
        }
    }

    var caption: String {
        switch self {
        case .counting(let days): return days == 1 ? "Day" : "Days"
        case .today: return "The Wedding Day"
        case .married: return "Abhi & Alisha"
        case .couple: return "The Wedding"
        }
    }
}

/// The big gold numeral, or the word that stands in for it.
private struct CountdownNumeral: View {
    let phrase: CountdownPhrase
    var numeralSpec: BrandFontSpec = .widgetNumeral
    var wordSpec: BrandFontSpec = .widgetNumeralWord

    var body: some View {
        Group {
            switch phrase {
            case .counting(let days):
                Text("\(days)")
                    .brandFont(numeralSpec)
                    .contentTransition(.numericText())
            case .today:
                Text("Today")
                    .brandFont(wordSpec)
            case .married:
                Text("Married")
                    .brandFont(wordSpec)
            case .couple:
                Text("Abhi & Alisha")
                    .brandFont(wordSpec)
            }
        }
        .foregroundStyle(WidgetPalette.gold)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

// MARK: - Small

private struct SmallCountdown: View {
    let entry: WeddingEntry

    private var phrase: CountdownPhrase {
        CountdownPhrase(daysRemaining: entry.daysRemaining)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // The crest sits in the corner, barely there, as it does on every screen.
            WidgetCrest(width: 82, opacity: 0.12)
                .offset(x: 22, y: 16)

            VStack(alignment: .leading, spacing: 0) {
                WidgetEyebrow(text: "Abhi & Alisha")

                Spacer(minLength: 4)

                CountdownNumeral(phrase: phrase)

                WidgetRule(width: 22)
                    .padding(.top, 7)

                Text(phrase.caption.uppercased())
                    .font(BrandLabel.font(size: 10, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(WidgetPalette.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch phrase {
        case .counting(let days): return "\(days) days until the wedding"
        case .today: return "The wedding is today"
        case .married: return "Abhi and Alisha are married"
        case .couple: return "Abhi and Alisha"
        }
    }
}

// MARK: - Medium

private struct MediumCountdown: View {
    let entry: WeddingEntry

    private var phrase: CountdownPhrase {
        CountdownPhrase(daysRemaining: entry.daysRemaining)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetEyebrow(text: "Abhi & Alisha")

                Spacer(minLength: 4)

                CountdownNumeral(phrase: phrase, numeralSpec: .widgetNumeral, wordSpec: .widgetTitle)

                Text(phrase.caption.uppercased())
                    .font(BrandLabel.font(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(WidgetPalette.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 6)
            }
            .frame(width: 112, alignment: .leading)

            Rectangle()
                .fill(WidgetPalette.hairline)
                .frame(width: 1)
                .padding(.vertical, 2)
                .padding(.horizontal, 16)

            nextBlock
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The celebration on the horizon. Every line is dropped rather than left empty.
    @ViewBuilder
    private var nextBlock: some View {
        if let event = entry.event {
            VStack(alignment: .leading, spacing: 0) {
                WidgetEyebrow(
                    text: entry.isHappeningNow ? "Happening Now" : "Next",
                    color: entry.isHappeningNow ? WidgetPalette.gold : WidgetPalette.goldDeep
                )

                Text(event.title)
                    .brandFont(.widgetTitle)
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 6)

                if let timing = event.timingLine {
                    Text(timing)
                        .brandFont(.widgetBody)
                        .foregroundStyle(WidgetPalette.body)
                        .lineLimit(2)
                        .padding(.top, 5)
                }

                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetEyebrow(text: "AVA Resort Cancún")
                Text("The celebrations are complete.")
                    .brandFont(.widgetBody)
                    .foregroundStyle(WidgetPalette.body)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Lock Screen ring

/// Days remaining, and nothing else. Drawn in whatever tint the Lock Screen is using.
private struct CircularCountdown: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: WeddingEntry

    private var phrase: CountdownPhrase {
        CountdownPhrase(daysRemaining: entry.daysRemaining)
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: -1) {
                numeral

                if case .counting = phrase {
                    Text("DAYS")
                        .font(BrandLabel.font(size: 8, weight: .semibold))
                        .tracking(1.1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(tint)
            .padding(3)
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(WeddingGroup.Link.home)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var numeral: some View {
        switch phrase {
        case .counting(let days):
            Text("\(days)")
                .brandFont(.accessoryNumeral)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        case .today:
            Text("Today")
                .brandFont(.accessoryTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        case .married, .couple:
            Text("A & A")
                .brandFont(.accessoryTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    /// Full colour keeps the gold; every other mode hands the tint to the system so the
    /// complication matches the wallpaper rather than fighting it.
    private var tint: Color {
        renderingMode == .fullColor ? WidgetPalette.gold : .primary
    }

    private var accessibilityText: String {
        switch phrase {
        case .counting(let days): return "\(days) days until the wedding"
        case .today: return "The wedding is today"
        case .married: return "Abhi and Alisha are married"
        case .couple: return "Abhi and Alisha"
        }
    }
}
