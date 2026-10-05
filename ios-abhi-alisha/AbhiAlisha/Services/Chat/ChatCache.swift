import Foundation

/// Everything the conversation list needs to draw itself before the network answers.
nonisolated struct ChatListSnapshot: Codable, Sendable {
    var conversations: [ChatConversation] = []
    var members: [ChatMember] = []
    var profiles: [ChatProfile] = []
    var previews: [ChatMessage] = []
    var blocked: [UUID] = []
}

/// This phone's saved copy of the chat, kept per person in Application Support so the
/// list and recent threads open instantly and offline. Signing out wipes it.
nonisolated enum ChatCache {
    private static var root: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = base.appending(path: "chat", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func file(_ name: String) -> URL? {
        root?.appending(path: name)
    }

    static func load<T: Decodable>(_ type: T.Type, named name: String) -> T? {
        guard let url = file(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? ChatJSON.decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, named name: String) {
        guard let url = file(name), let data = try? ChatJSON.encoder.encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func listName(for user: UUID) -> String { "list-\(user.lower).json" }
    static func threadName(for user: UUID, conversation: UUID) -> String {
        "thread-\(user.lower)-\(conversation.lower).json"
    }
    static func outboxName(for user: UUID) -> String { "outbox-\(user.lower).json" }

    /// Removes every saved conversation, message, and unsent note on this phone.
    static func wipeAll() {
        guard let root else { return }
        try? FileManager.default.removeItem(at: root)
    }
}
