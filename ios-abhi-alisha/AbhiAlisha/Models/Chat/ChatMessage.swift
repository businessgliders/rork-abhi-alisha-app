import Foundation

/// A row of `public.messages`.
nonisolated struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let conversationID: UUID
    let senderID: UUID
    var body: String?
    var clientID: UUID?
    var createdAt: Date
    var deletedAt: Date?
    var editedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case body
        case clientID = "client_id"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
        case editedAt = "edited_at"
    }

    static let columns = "id,conversation_id,sender_id,body,client_id,created_at,deleted_at,edited_at"

    /// What a deleted message reads, and what its stored text is overwritten with.
    static let deletedText = "Message deleted"

    var isDeleted: Bool { deletedAt != nil }

    /// The text to show; deleted messages never surface their old words.
    var displayText: String {
        if isDeleted { return Self.deletedText }
        return ChatJSON.clean(body) ?? ""
    }
}

/// A message written on this phone that the server hasn't confirmed yet.
///
/// It keeps its `clientID` for life, so every retry is the same message: if an earlier
/// attempt actually landed, the server rejects the repeat as a duplicate and nothing
/// is ever sent twice.
nonisolated struct PendingMessage: Codable, Identifiable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        case queued
        case sending
        case failed
    }

    let clientID: UUID
    let conversationID: UUID
    let senderID: UUID
    let body: String
    let createdAt: Date
    var state: State

    var id: UUID { clientID }
}
