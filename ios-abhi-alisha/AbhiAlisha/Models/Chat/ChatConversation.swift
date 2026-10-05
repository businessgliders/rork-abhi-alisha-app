import Foundation

/// A row of `public.conversations`: the family room, a group, or a private chat.
nonisolated struct ChatConversation: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String?
    var kind: String?
    var createdBy: UUID?
    var createdAt: Date?
    var lastMessageAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case createdBy = "created_by"
        case createdAt = "created_at"
        case lastMessageAt = "last_message_at"
    }

    static let columns = "id,title,kind,created_by,created_at,last_message_at"

    private var normalizedKind: String { kind?.lowercased() ?? "" }

    var isFamily: Bool { normalizedKind == "family" }

    /// A private chat between two people.
    var isDirectKind: Bool {
        ["direct", "dm", "one_to_one", "private"].contains(normalizedKind)
    }

    var isGroupKind: Bool { normalizedKind == "group" }
}
