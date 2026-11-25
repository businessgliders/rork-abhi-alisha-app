import Foundation

/// A row of `public.conversations`: Questions & Chat, the family room, a group, or a
/// private chat.
nonisolated struct ChatConversation: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String?
    var kind: String?
    var createdBy: UUID?
    var createdAt: Date?
    var lastMessageAt: Date?
    var weddingID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case createdBy = "created_by"
        case createdAt = "created_at"
        case lastMessageAt = "last_message_at"
        case weddingID = "wedding_id"
    }

    static let columns = "id,kind,title,created_by,created_at,last_message_at,wedding_id"

    private var normalizedKind: String { kind?.lowercased() ?? "" }

    var isFamily: Bool { normalizedKind == "family" }

    /// Questions & Chat: open to every guest who has given a name.
    var isOpen: Bool { normalizedKind == "open" }

    /// A private chat between two people.
    var isDirectKind: Bool {
        normalizedKind == "direct"
    }

    var isGroupKind: Bool { normalizedKind == "group" }
}
