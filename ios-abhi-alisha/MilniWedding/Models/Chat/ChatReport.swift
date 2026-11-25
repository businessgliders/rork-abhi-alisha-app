import Foundation

/// A row of `public.message_reports`.
nonisolated struct ChatReport: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let messageID: UUID
    let reporterID: UUID?
    var reason: String?
    var createdAt: Date?
    var resolvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case messageID = "message_id"
        case reporterID = "reporter_id"
        case reason
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }

    static let columns = "id,message_id,reporter_id,reason,created_at,resolved_at"
}

/// A row of `public.user_blocks`.
nonisolated struct ChatBlock: Codable, Hashable, Sendable {
    let blockerID: UUID
    let blockedID: UUID
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case blockerID = "blocker_id"
        case blockedID = "blocked_id"
        case createdAt = "created_at"
    }

    static let columns = "blocker_id,blocked_id,created_at"
}
