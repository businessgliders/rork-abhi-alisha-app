import Foundation

/// One note the couple sent to every guest, as kept by the `Notification` entity.
nonisolated struct NotificationRecord: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let body: String?
    let sentAt: Date?
    let deliveredCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case message
        case sentAt = "sent_at"
        case createdDate = "created_date"
        case deliveredCount = "delivered_count"
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
    }

    var hasContent: Bool { title != nil || body != nil }
}
