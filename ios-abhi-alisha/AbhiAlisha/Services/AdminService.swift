import Foundation

nonisolated enum AdminError: Error, Sendable {
    /// The backend refused the code.
    case unauthorized
    /// The backend understood but will never accept this request (e.g. already deleted).
    case rejected
    /// No connection, or the server had a moment. Worth trying again.
    case unavailable
}

/// The couple's admin calls. Every function receives the Keychain code in its body as
/// `code`, and never any device tokens back. Announcements are sent from the
/// Announcements chat through `AnnouncementService` instead.
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
