import Foundation
import Observation

/// Where a tap on a widget, or on the Live Activity, wants the app to land.
///
/// The tab is switched immediately; the celebration to open is left here for the
/// Schedule to pick up and clear once it has arrived.
@Observable
final class DeepLinkRouter {
    var pendingEventID: String?

    /// Reads one of our own links. Returns the tab to show, if the link is ours.
    func handle(_ url: URL) -> AppTab? {
        guard url.scheme == WeddingGroup.Link.scheme else { return nil }
        if let eventID = WeddingGroup.Link.eventID(from: url) {
            pendingEventID = eventID
            return .schedule
        }
        return .home
    }
}
