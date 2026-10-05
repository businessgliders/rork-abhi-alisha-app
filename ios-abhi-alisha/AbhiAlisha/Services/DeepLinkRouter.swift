import Foundation
import Observation

/// Where a notification tap wants to land once the app is up.
enum Landing: Equatable {
    /// One of the five tabs.
    case tab(AppTab)
    /// The screen of past updates, raised over whichever tab is showing.
    case notifications
    /// The Announcements chat, where a prepared note waits in the admin's composer.
    case announcementsComposer
}

/// A part of the Resort page a notification can scroll to.
enum ResortSection: Equatable {
    case top
    case questions
}

/// Where a tap on a widget, the Live Activity, or a notification wants the app to land.
///
/// Nothing navigates from here directly. A landing is held as pending and only consumed
/// once the root view is alive, so a tap that wakes the app waits for it to finish
/// loading before anything moves.
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var pendingEventID: String?
    /// Set when a note asked for the Gallery, which now lives inside Story.
    var pendingStoryGallery = false
    /// The conversation a chat notification asked to open.
    var pendingConversationID: UUID?
    /// An announcement was tapped: open the Announcements feed in Chat.
    var pendingAnnouncements = false
    /// An announcement asked for the RSVP lookup on Home.
    var pendingRSVP = false
    /// An announcement asked for a part of the Resort page.
    var pendingResortSection: ResortSection?
    /// Where a notification tap wants to land, held until the root view can act on it.
    var pending: Landing?
    /// The screen of past updates, raised over whichever tab is showing.
    var isNotificationsPresented = false

    /// Reads one of our own links. Returns the tab to show, if the link is ours.
    func handle(_ url: URL) -> AppTab? {
        guard url.scheme == WeddingGroup.Link.scheme else { return nil }
        if let eventID = WeddingGroup.Link.eventID(from: url) {
            pendingEventID = eventID
            return .schedule
        }
        return .home
    }

    func open(_ landing: Landing) {
        pending = landing
    }

    /// Reads the payload's `screen` and `event_id` without ever assuming they are there.
    static func landing(fromPayload payload: [AnyHashable: Any]) -> Landing {
        landing(forScreen: screenValue(in: payload), eventID: eventIDValue(in: payload))
    }

    /// Turns a push's `screen` (and `event_id`) into a landing, setting whatever the
    /// destination screen needs to open in the right place. No screen, or
    /// "notifications" / "announcements", opens the Announcements chat; an unknown
    /// value does too, so every announcement lands somewhere that shows it.
    static func landing(forScreen rawScreen: String?, eventID: String? = nil) -> Landing {
        let screen = rawScreen?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let router = shared

        switch screen {
        case "", "notifications", "notification", "announcements", "announcement":
            router.pendingAnnouncements = true
            return .tab(.chat)
        case "event", "schedule", "itinerary":
            if let eventID { router.pendingEventID = eventID }
            return .tab(.schedule)
        case "gallery", "photos":
            router.pendingStoryGallery = true
            return .tab(.story)
        case "rsvp":
            router.pendingRSVP = true
            return .tab(.home)
        case "travel", "travel_stay", "travel-stay", "stay", "resort":
            router.pendingResortSection = .top
            return .tab(.resort)
        case "faq", "faqs", "questions":
            router.pendingResortSection = .questions
            return .tab(.resort)
        case "chat", "message", "messages":
            return .tab(.chat)
        default:
            if let tab = AppTab(rawValue: screen) { return .tab(tab) }
            router.pendingAnnouncements = true
            return .tab(.chat)
        }
    }

    /// Custom keys ride beside `aps`; some senders tuck them inside it. Only a real
    /// String counts — numbers, booleans, and dictionaries are treated as absent.
    /// Safe to call from any thread, so the notification delegate can read the payload
    /// where the system hands it over and pass only a plain String to the main thread.
    nonisolated static func screenValue(in payload: [AnyHashable: Any]) -> String? {
        if let screen = payload["screen"] as? String { return screen }
        if let aps = payload["aps"] as? [AnyHashable: Any],
           let screen = aps["screen"] as? String { return screen }
        return nil
    }

    /// The celebration a Schedule note should open on, read with the same defensive
    /// rules as `screen`: only a real, non-empty String counts. A nil here leaves the
    /// Schedule on whatever is happening now.
    nonisolated static func eventIDValue(in payload: [AnyHashable: Any]) -> String? {
        if let id = payload["event_id"] as? String { return id.nonEmpty }
        if let aps = payload["aps"] as? [AnyHashable: Any],
           let id = aps["event_id"] as? String { return id.nonEmpty }
        return nil
    }

    /// What a chat push asks to open: `"opens": "chat"` marks a family chat message.
    /// Read with the same defensive rules; anything else is treated as absent.
    nonisolated static func opensValue(in payload: [AnyHashable: Any]) -> String? {
        if let opens = payload["opens"] as? String { return opens.nonEmpty?.lowercased() }
        if let aps = payload["aps"] as? [AnyHashable: Any],
           let opens = aps["opens"] as? String { return opens.nonEmpty?.lowercased() }
        return nil
    }

    /// The conversation a chat notification belongs to, read with the same defensive
    /// rules. A missing or mangled value simply opens the Chat tab's list.
    nonisolated static func conversationIDValue(in payload: [AnyHashable: Any]) -> String? {
        if let id = payload["conversation_id"] as? String { return id.nonEmpty }
        if let aps = payload["aps"] as? [AnyHashable: Any] {
            if let id = aps["conversation_id"] as? String { return id.nonEmpty }
            // The chat sender also names the conversation as the notification's thread.
            if opensValue(in: payload) == "chat", let id = aps["thread-id"] as? String { return id.nonEmpty }
        }
        return nil
    }
}
