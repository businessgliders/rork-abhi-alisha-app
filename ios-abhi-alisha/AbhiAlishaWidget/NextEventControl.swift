import AppIntents
import SwiftUI
import WidgetKit

/// "Next event" in Control Center, on the Lock Screen and on the Action button.
@available(iOS 18.0, *)
struct NextEventControl: ControlWidget {
    static let kind = "com.businessgliders.abhialisha.control.next-event"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenNextEventControlIntent()) {
                Label {
                    Text(Self.labelLine)
                } icon: {
                    Image(systemName: "sparkles")
                }
            }
        }
        .displayName("Next event")
        .description("Opens the wedding's next celebration.")
    }

    /// The celebration underway or next, read from the shared app group the last time
    /// the widget process rendered the control. Controls don't redraw on a schedule,
    /// so a stale name here just means the phone hasn't re-rendered it yet.
    static var labelLine: String {
        let focus = WeddingTimeline.load().focus(at: .now)
        guard let focus else {
            return String(localized: "Next event")
        }
        var text = focus.title
        if let start = focus.startsAt {
            let formatter = DateFormatter()
            formatter.timeZone = ActiveWedding.snapshot.timeZone
            formatter.locale = Locale.current
            formatter.setLocalizedDateFormatFromTemplate("d MMM, h:mm")
            text += " · " + formatter.string(from: start)
        }
        return text
    }
}
