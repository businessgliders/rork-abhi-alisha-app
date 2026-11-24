import AppIntents
import Foundation

/// The Control Center / Lock Screen button: opens whatever celebration is underway or
/// next, falling back to the schedule when nothing is left. Compiled into both the app
/// and the widget extension under the same name; `openAppWhenRun` is what makes the
/// tap actually launch Milni — without it the intent runs inside the widget extension,
/// where an open-the-app request can silently do nothing.
@available(iOS 18.0, *)
struct OpenNextEventControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Next event"
    static let description = IntentDescription("Opens the wedding's next celebration.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let event = WeddingTimeline.load().focus(at: .now)
        let url = event.flatMap { WeddingGroup.Link.event($0.id) }
            ?? WeddingGroup.Link.schedule
            ?? URL(string: "\(WeddingGroup.Link.scheme)://schedule")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}
