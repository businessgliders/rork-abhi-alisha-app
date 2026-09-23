import Foundation
import Observation

/// Where a tap on a widget, the Live Activity, or a notification wants the app to land.
///
/// The tab is switched immediately; the celebration to open is left here for the
/// Schedule to pick up and clear once it has arrived.
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var pendingEventID: String?
    /// A tab asked for from outside the view tree, e.g. by a notification tap.
    var pendingTab: AppTab?

    /// Reads one of our own links. Returns the tab to show, if the link is ours.
    func handle(_ url: URL) -> AppTab? {
        guard url.scheme == WeddingGroup.Link.scheme else { return nil }
        if let eventID = WeddingGroup.Link.eventID(from: url) {
            pendingEventID = eventID
            return .schedule
        }
        return .home
    }

    func open(_ tab: AppTab) {
        pendingTab = tab
    }
}
