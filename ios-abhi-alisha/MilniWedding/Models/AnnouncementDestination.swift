import Foundation

/// Where an announcement sends guests when they tap its notification.
nonisolated enum AnnouncementDestination: Hashable, Sendable {
    case announcements
    case schedule
    case event(id: String, title: String)
    case gallery
    case rsvp
    case travel
    case faq
    case chat

    /// The `screen` value sent with the push.
    var screen: String {
        switch self {
        case .announcements: return "announcements"
        case .schedule: return "schedule"
        case .event: return "event"
        case .gallery: return "gallery"
        case .rsvp: return "rsvp"
        case .travel: return "travel"
        case .faq: return "faq"
        case .chat: return "chat"
        }
    }

    var eventID: String? {
        if case .event(let id, _) = self { return id }
        return nil
    }

    /// The short name on the "Opens to" pill.
    var label: String {
        switch self {
        case .announcements: return "Announcements"
        case .schedule: return "Schedule"
        case .event(_, let title): return title
        case .gallery: return "Gallery"
        case .rsvp: return "RSVP"
        case .travel: return "Travel & Stay"
        case .faq: return "FAQ"
        case .chat: return "Chat"
        }
    }

    /// The fuller line in the confirmation preview.
    var previewLabel: String {
        if case .event(_, let title) = self { return "Schedule · \(title)" }
        return label
    }

    var symbolName: String {
        switch self {
        case .announcements: return "megaphone"
        case .schedule: return "calendar"
        case .event: return "sparkles"
        case .gallery: return "photo.on.rectangle"
        case .rsvp: return "envelope.open"
        case .travel: return "airplane"
        case .faq: return "questionmark.circle"
        case .chat: return "bubble.left.and.bubble.right"
        }
    }

    /// Every fixed choice besides a specific celebration, in menu order.
    static let screens: [AnnouncementDestination] = [.announcements, .schedule]
    static let more: [AnnouncementDestination] = [.gallery, .rsvp, .travel, .faq, .chat]

    /// Turns a saved announcement's `screen` and `event_id` into where its button opens,
    /// with the same mapping a push tap follows. Nil means nothing worth showing: the
    /// screen was never saved (older rows), it points back at the Announcements feed
    /// itself, or the celebration it named has left the schedule.
    static func resolve(screen: String?, eventID: String?, events: [ScheduleEvent]) -> AnnouncementDestination? {
        let raw = (screen ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "", "announcements", "announcement", "notifications", "notification":
            return nil
        case "event", "schedule", "itinerary":
            if let eventID, let event = events.first(where: { $0.id == eventID }) {
                return .event(id: event.id, title: event.title.trimmed)
            }
            // A named celebration the schedule no longer lists has nowhere precise to
            // go; a plain schedule note still opens the Schedule.
            return raw == "event" ? nil : .schedule
        case "gallery", "photos":
            return .gallery
        case "rsvp":
            return .rsvp
        case "travel", "travel_stay", "travel-stay", "stay", "resort":
            return .travel
        case "faq", "faqs", "questions":
            return .faq
        case "chat", "message", "messages":
            return .chat
        default:
            return nil
        }
    }
}

/// Guesses where an announcement should open from its words. Case-insensitive, whole
/// words (plurals allowed), and the first rule that matches wins.
nonisolated enum AnnouncementRouteDetector {
    private struct EventRule {
        let keywords: [String]
        /// A word the matching celebration's title contains.
        let titleToken: String
    }

    private static let eventRules: [EventRule] = [
        EventRule(keywords: ["welcome party", "welcome"], titleToken: "welcome"),
        EventRule(keywords: ["haldi", "choora"], titleToken: "haldi"),
        EventRule(keywords: ["sangeet", "jaggo"], titleToken: "sangeet"),
        EventRule(keywords: ["anand karaj", "gurdwara", "sikh ceremony"], titleToken: "anand karaj"),
        EventRule(keywords: ["hindu", "pheras", "mandap"], titleToken: "hindu"),
        EventRule(keywords: ["reception"], titleToken: "reception")
    ]

    private static let screenRules: [(keywords: [String], destination: AnnouncementDestination)] = [
        (["shuttle", "bus", "time change", "moved", "schedule", "itinerary", "tomorrow", "tonight"], .schedule),
        (["photo", "pictures", "gallery", "album"], .gallery),
        (["rsvp", "respond", "confirm attendance"], .rsvp),
        (["flight", "airport", "transfer", "hotel", "room", "check-in"], .travel),
        (["question", "faq"], .faq),
        (["chat", "say hi", "join the conversation"], .chat)
    ]

    static func detect(title: String, message: String, events: [ScheduleEvent]) -> AnnouncementDestination {
        let text = "\(title)\n\(message)".lowercased()
        guard text.trimmed.isEmpty == false else { return .announcements }

        for rule in eventRules where contains(text, anyOf: rule.keywords) {
            if let event = events.first(where: { $0.title.lowercased().contains(rule.titleToken) }) {
                return .event(id: event.id, title: event.title.trimmed)
            }
        }

        for event in events {
            let name = event.title.trimmed.lowercased()
            if name.count >= 4, contains(text, phrase: name) {
                return .event(id: event.id, title: event.title.trimmed)
            }
        }

        for rule in screenRules where contains(text, anyOf: rule.keywords) {
            return rule.destination
        }
        return .announcements
    }

    private static func contains(_ text: String, anyOf phrases: [String]) -> Bool {
        phrases.contains { contains(text, phrase: $0) }
    }

    /// Whole-word match, so "bus" never fires on "busy", while "photos" still counts.
    private static func contains(_ text: String, phrase: String) -> Bool {
        let words = phrase
            .split(whereSeparator: \.isWhitespace)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !words.isEmpty else { return false }
        let pattern = "(?<![\\p{L}\\p{N}])" + words.joined(separator: "\\s+") + "(?:s|es)?(?![\\p{L}\\p{N}])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
