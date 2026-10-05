import Foundation
import Supabase

/// The family chat's Supabase project. The publishable key is meant to live in the app:
/// row-level security on the server decides what each signed-in person can see.
nonisolated enum ChatBackend {
    static let url = URL(string: "https://lrowuakbxuoynlyxlmnr.supabase.co")!
    static let publishableKey = "sb_publishable_hZduLD-YAv3B-IIu9Igy7g_oMRvZTvT"

    static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: publishableKey,
        options: SupabaseClientOptions(
            db: .init(encoder: ChatJSON.encoder, decoder: ChatJSON.decoder),
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )

    /// Reads the id a conversation-creating function hands back, whatever shape it
    /// arrives in: a bare uuid, an object with an id, or a one-row array.
    static func decodeID(_ data: Data) -> UUID? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return id(in: object)
    }

    private static func id(in object: Any) -> UUID? {
        if let text = object as? String { return UUID(uuidString: text) }
        if let rows = object as? [Any], let first = rows.first { return id(in: first) }
        if let dict = object as? [String: Any] {
            for key in ["id", "conversation_id", "create_direct_conversation", "create_group_conversation"] {
                if let text = dict[key] as? String, let uuid = UUID(uuidString: text) { return uuid }
            }
        }
        return nil
    }

    /// How a failed write should be treated.
    enum Failure {
        /// The server already has this exact message (same `client_id`).
        case duplicate
        /// No connection right now; try again later, unchanged.
        case offline
        /// The server said no; only a person can decide to try again.
        case rejected
    }

    static func classify(_ error: Error, isOnline: Bool) -> Failure {
        if let postgrest = error as? PostgrestError {
            if postgrest.code == "23505" { return .duplicate }
            return isOnline ? .rejected : .offline
        }
        if error is URLError { return .offline }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .offline }
        return isOnline ? .rejected : .offline
    }
}

extension UUID {
    /// The lowercase form Postgres prints, used in every filter.
    nonisolated var lower: String { uuidString.lowercased() }
}
