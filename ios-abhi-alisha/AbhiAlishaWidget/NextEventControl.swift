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
                Label("Next event", systemImage: "sparkles")
            }
        }
        .displayName("Next event")
        .description("Opens the wedding's next celebration.")
    }
}
