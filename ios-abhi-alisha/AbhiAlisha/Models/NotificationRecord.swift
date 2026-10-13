import Foundation

/// One note the couple sent to every guest, as kept by the `Notification` entity.
nonisolated struct NotificationRecord: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let body: String?
    let sentAt: Date?
    let deliveredCount: Int?
    /// The `screen` value saved with the send; older rows have none.
    let screen: String?
    /// The celebration a screen of "event" points at, when one was saved.
    let eventID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case message
        case sentAt = "sent_at"
        case createdDate = "created_date"
        case deliveredCount = "delivered_count"
        case screen
        case eventID = "event_id"
    }

    /// A record made on this phone, shown until the server's copy arrives.
    init(
        id: String,
        title: String?,
        body: String?,
        sentAt: Date?,
        deliveredCount: Int? = nil,
        screen: String? = nil,
        eventID: String? = nil
    ) {
        self.id = id
        self.title = title?.nonEmpty
        self.body = body?.nonEmpty
        self.sentAt = sentAt
        self.deliveredCount = deliveredCount
        self.screen = screen?.nonEmpty
        self.eventID = eventID?.nonEmpty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? container.decodeIfPresent(String.self, forKey: .title))?.nonEmpty

        let bodyText = (try? container.decodeIfPresent(String.self, forKey: .body))
            ?? (try? container.decodeIfPresent(String.self, forKey: .message))
        body = bodyText?.nonEmpty

        let sent = (try? container.decodeIfPresent(String.self, forKey: .sentAt))
            ?? (try? container.decodeIfPresent(String.self, forKey: .createdDate))
        sentAt = ScheduleEvent.date(from: sent)

        if let value = try? container.decodeIfPresent(Double.self, forKey: .deliveredCount) {
            deliveredCount = Int(value.rounded())
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .deliveredCount) {
            deliveredCount = Int(text.trimmed)
        } else {
            deliveredCount = nil
        }

        screen = (try? container.decodeIfPresent(String.self, forKey: .screen))?.nonEmpty
        eventID = (try? container.decodeIfPresent(String.self, forKey: .eventID))?.nonEmpty
    }

    var hasContent: Bool { title != nil || body != nil }

    /// Where this announcement's button opens, resolved against the schedule — the same
    /// mapping a tap on its notification follows. Nil when there is nothing to open: no
    /// screen saved (older rows), the Announcements feed itself, or an unknown value.
    func destination(events: [ScheduleEvent]) -> AnnouncementDestination? {
        AnnouncementDestination.resolve(screen: screen, eventID: eventID, events: events)
    }

    /// Newest first, dropping rows with nothing to read.
    static func ordered(_ records: [NotificationRecord]) -> [NotificationRecord] {
        records
            .filter(\.hasContent)
            .sorted { ($0.sentAt ?? .distantPast) > ($1.sentAt ?? .distantPast) }
    }
}
