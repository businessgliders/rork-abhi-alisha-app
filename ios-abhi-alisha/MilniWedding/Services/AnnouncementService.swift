import Foundation
import Supabase

/// How a send ended.
nonisolated enum AnnouncementSendOutcome: Sendable, Equatable {
    /// Gone out; `sent` is how many guests the server reached, when it says.
    case sent(Int?)
    /// The server said this account isn't an admin (403).
    case forbidden
    /// No connection, or the server had a moment.
    case failed
}

/// Sends an announcement to every guest through the `send-announcement` edge function.
/// The signed-in admin's session rides along automatically; the server checks the role.
nonisolated struct AnnouncementService: Sendable {
    static let shared = AnnouncementService()

    private struct Row: Encodable, Sendable {
        let wedding_id: String
        let title: String
        let body: String
        let screen: String
        let event_ref: String?
        let sent_by: String?

        enum CodingKeys: String, CodingKey { case wedding_id, title, body, screen, event_ref, sent_by }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(wedding_id, forKey: .wedding_id)
            try container.encode(title, forKey: .title)
            try container.encode(body, forKey: .body)
            try container.encode(screen, forKey: .screen)
            try container.encodeIfPresent(event_ref, forKey: .event_ref)
            try container.encodeIfPresent(sent_by, forKey: .sent_by)
        }
    }

    private struct Invoke: Encodable, Sendable {
        let wedding_id: String
        let announcement_id: String
    }

    /// Saves the announcement to the open wedding, then asks the server to deliver it.
    func send(title: String, body: String, destination: AnnouncementDestination) async -> AnnouncementSendOutcome {
        let weddingID = ActiveWedding.id
        do {
            let userID = try? await ChatBackend.client.auth.session.user.id.lower
            let row = Row(
                wedding_id: weddingID,
                title: title,
                body: body,
                screen: destination.screen,
                event_ref: destination.eventID,
                sent_by: userID
            )
            let response = try await ChatBackend.client
                .from("announcements")
                .insert(row, returning: .representation)
                .select("id")
                .single()
                .execute()
            guard let id = MilniJSON.string(MilniJSON.rows(response.data).first?["id"]) else { return .failed }
            let sent: Int? = try await ChatBackend.client.functions.invoke(
                "send-announcement",
                options: FunctionInvokeOptions(body: Invoke(wedding_id: weddingID, announcement_id: id))
            ) { data, _ in
                Self.sentCount(in: data)
            }
            return .sent(sent)
        } catch FunctionsError.httpError(let code, _) where code == 403 {
            return .forbidden
        } catch let error as PostgrestError where error.code == "42501" {
            return .forbidden
        } catch {
            print("[Announcements] send failed")
            return .failed
        }
    }

    /// Reads `sent` from the reply, whether it arrives as a number or a string.
    private static func sentCount(in data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let number = object["sent"] as? NSNumber { return number.intValue }
        if let text = object["sent"] as? String { return Int(text.trimmed) }
        return nil
    }
}
