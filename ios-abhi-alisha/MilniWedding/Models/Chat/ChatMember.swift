import Foundation

/// A row of `public.conversation_members`: who is in a conversation, and how far
/// they've read.
nonisolated struct ChatMember: Codable, Hashable, Sendable {
    let conversationID: UUID
    let userID: UUID
    var lastReadAt: Date?
    var joinedAt: Date?
    /// No pushes for this conversation. Only ever offered for Questions & Chat.
    var muted: Bool?

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case userID = "user_id"
        case lastReadAt = "last_read_at"
        case joinedAt = "joined_at"
        case muted
    }

    static let columns = "conversation_id,user_id,last_read_at,joined_at,muted"
}
