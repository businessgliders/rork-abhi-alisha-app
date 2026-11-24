import AppIntents
import Foundation

/// The Control Center / Lock Screen button: opens whatever celebration is underway or next.
@available(iOS 18.0, *)
struct OpenNextEventControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Next event"
    static let description = IntentDescription("Opens the wedding's next celebration.")

    func perform() async throws -> some IntentResult & OpensIntent {
        let event = WeddingTimeline.load().focus(at: .now)
        let url = event.flatMap { WeddingGroup.Link.event($0.id) }
            ?? WeddingGroup.Link.home
            ?? URL(string: "\(WeddingGroup.Link.scheme)://home")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}
