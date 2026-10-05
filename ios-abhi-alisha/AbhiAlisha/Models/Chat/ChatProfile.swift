import Foundation

/// Where someone stands with the family chat.
nonisolated enum ChatAccess: String, Codable, Sendable {
    case pending
    case approved
    case blocked
}

/// A row of `public.profiles`: one person who has signed in to the chat.
nonisolated struct ChatProfile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var displayName: String?
    var status: String?
    var role: String?
    var avatarURL: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case status
        case role
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
    }

    static let columns = "id,display_name,status,role,avatar_url,created_at"

    /// The name shown everywhere; never blank.
    var name: String { ChatJSON.clean(displayName) ?? "Family member" }

    var hasName: Bool { ChatJSON.clean(displayName) != nil }

    var initials: String { ChatJSON.initials(for: displayName) }

    /// Unknown or missing values are treated as still waiting to be welcomed in.
    var access: ChatAccess {
        switch status?.lowercased() {
        case "approved": return .approved
        case "blocked": return .blocked
        default: return .pending
        }
    }

    var isAdmin: Bool { role?.lowercased() == "admin" }
}
