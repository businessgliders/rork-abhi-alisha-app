import Foundation

nonisolated enum AdminError: Error, Sendable {
    /// The backend refused the code.
    case unauthorized
    /// The backend understood but will never accept this request (e.g. already deleted).
    case rejected
    /// No connection, or the server had a moment. Worth trying again.
    case unavailable
}

nonisolated struct SendReceipt: Sendable {
    let deliveredCount: Int?
}

/// The couple's admin calls. Every function receives the Keychain code in its body —
/// `code` everywhere, `sender_code` for sending — and never any device tokens back.
nonisolated struct AdminService: Sendable {
    static let shared = AdminService()

    private let functions: WeddingFunctions = .shared

    func verify(code: String) async -> Bool {
        do {
            let reply = try await functions.call("verifyAdminCode", ["code": .string(code)])
            return reply.body?["valid"]?.boolValue == true
        } catch {
            return false
        }
    }

    // MARK: - Notifications

    func sendToAll(title: String, body: String, code: String) async throws -> SendReceipt {
        let reply = try await perform("sendPushToAll", [
            "title": .string(title),
            "body": .string(body),
            "sender_code": .string(code)
        ])
        let countKeys = ["delivered_count", "delivered", "sent_count", "sent", "success_count", "successCount", "count"]
        let count = countKeys.lazy.compactMap { reply?[$0]?.doubleValue }.first.map { Int($0) }
        return SendReceipt(deliveredCount: count)
    }

    private let historyCache = JSONDiskCache(filename: "couple-notifications.json")

    /// Newest first. Read from the public entity; tokens are never part of it.
    func notificationHistory() async throws -> [NotificationRecord] {
        let result = try await WeddingAPI.shared.fetch(NotificationRecord.self, entity: "Notification")
        historyCache.save(result.raw)
        return Self.ordered(result.items)
    }

    /// The history as last seen, so the screen opens with something even offline.
    func cachedNotificationHistory() -> [NotificationRecord] {
        Self.ordered(historyCache.load(NotificationRecord.self) ?? [])
    }

    private static func ordered(_ records: [NotificationRecord]) -> [NotificationRecord] {
        records
            .filter(\.hasContent)
            .sorted { ($0.sentAt ?? .distantPast) > ($1.sentAt ?? .distantPast) }
    }

    // MARK: - Checklist

    func listChecklist(code: String) async throws -> [ChecklistItem] {
        let body = try await perform("listChecklist", ["code": .string(code)])
        let rows = body?["items"]?.arrayValue ?? body?.arrayValue ?? []
        return rows.compactMap { $0.objectValue.flatMap(ChecklistItem.init(raw:)) }
    }

    /// No id creates; an id updates.
    func saveChecklistItem(id: String?, data: [String: JSONValue], code: String) async throws -> ChecklistItem? {
        var payload: [String: JSONValue] = ["code": .string(code), "data": .object(data)]
        if let id { payload["id"] = .string(id) }
        let body = try await perform("saveChecklistItem", payload)
        let raw = body?["item"]?.objectValue ?? body?.objectValue
        return raw.flatMap(ChecklistItem.init(raw:))
    }

    func deleteChecklistItem(id: String, code: String) async throws {
        _ = try await perform("deleteChecklistItem", ["code": .string(code), "id": .string(id)])
    }

    // MARK: - Timeline

    func updateEvent(id: String, data: [String: JSONValue], code: String) async throws -> [String: JSONValue]? {
        let body = try await perform("updateScheduleEvent", [
            "code": .string(code),
            "id": .string(id),
            "data": .object(data)
        ])
        return body?["event"]?.objectValue
    }

    // MARK: - Transport

    private func perform(_ name: String, _ payload: [String: JSONValue]) async throws -> JSONValue? {
        let reply: WeddingFunctions.Reply
        do {
            reply = try await functions.call(name, payload)
        } catch {
            throw AdminError.unavailable
        }

        if reply.isUnauthorized { throw AdminError.unauthorized }
        if let message = reply.body?["error"]?.stringValue?.lowercased(),
           message.contains("unauthori") || message.contains("invalid code") {
            throw AdminError.unauthorized
        }
        if reply.isSuccess { return reply.body }
        if (400..<500).contains(reply.status) { throw AdminError.rejected }
        throw AdminError.unavailable
    }
}
