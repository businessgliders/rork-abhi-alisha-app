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

    private struct Payload: Encodable, Sendable {
        let title: String
        let body: String
        let screen: String
        let eventID: String?

        enum CodingKeys: String, CodingKey {
            case title
            case body
            case screen
            case eventID = "event_id"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(title, forKey: .title)
            try container.encode(body, forKey: .body)
            try container.encode(screen, forKey: .screen)
            try container.encodeIfPresent(eventID, forKey: .eventID)
        }
    }

    func send(title: String, body: String, destination: AnnouncementDestination) async -> AnnouncementSendOutcome {
        let payload = Payload(
            title: title,
            body: body,
            screen: destination.screen,
            eventID: destination.eventID
        )
        do {
            let sent: Int? = try await ChatBackend.client.functions.invoke(
                "send-announcement",
                options: FunctionInvokeOptions(body: payload)
            ) { data, _ in
                Self.sentCount(in: data)
            }
            return .sent(sent)
        } catch FunctionsError.httpError(let code, _) where code == 403 {
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
