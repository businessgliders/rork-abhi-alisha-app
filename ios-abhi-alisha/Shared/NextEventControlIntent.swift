import AppIntents
import Foundation

/// The Control Center / Lock Screen button: opens whatever celebration is underway or
/// next, falling back to the schedule when nothing is left. Compiled into both the app
/// and the widget extension under the same name.
///
/// The tap lands as an `OpenURLIntent`, which both launches Milni and hands it the
/// link — so `openAppWhenRun` must stay off: with it on, the system performs a plain
/// "open the app" and the URL never reaches the app's `onOpenURL`. The link carries the
/// wedding id, so the app can switch weddings first, then open the celebration.
@available(iOS 18.0, *)
struct OpenNextEventControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Next event"
    static let description = IntentDescription("Opens the wedding's next celebration.")

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let event = WeddingTimeline.load().focus(at: .now)
        let url = event.flatMap { WeddingGroup.Link.event($0.id, wedding: ActiveWedding.id) }
            ?? WeddingGroup.Link.schedule
            ?? URL(string: "\(WeddingGroup.Link.scheme)://schedule")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}
