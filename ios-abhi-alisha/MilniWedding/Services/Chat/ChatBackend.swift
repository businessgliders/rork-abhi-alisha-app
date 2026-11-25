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
            auth: .init(emitLocalSessionAsInitialSession: true),
            global: .init(session: SupabaseAuthURLProtocol.supabaseSession)
        )
    )

    /// True while the app holds a session — an anonymous guest counts. While this is
    /// on, no request may ever go out with the anon key in its place.
    static var isSignedIn: Bool { client.auth.currentSession != nil }

    /// Refreshes the session up front when its token expires within a minute, so a
    /// request never has to discover the expiry for itself.
    static func ensureFreshSession() async {
        guard let session = client.auth.currentSession,
              session.expiresAt - Date().timeIntervalSince1970 < 60 else { return }
        _ = try? await client.auth.refreshSession(refreshToken: session.refreshToken)
    }

    /// Keeps the session fresh while the app is open: wakes just before the token
    /// expires, sleeps until then, and re-checks when the app comes back to the
    /// foreground. Referencing this value starts it; it lives as long as the app.
    static let sessionUpkeep: Void = {
        Task {
            while true {
                guard let session = client.auth.currentSession else {
                    try? await Task.sleep(for: .seconds(10))
                    continue
                }
                let until = session.expiresAt - Date().timeIntervalSince1970
                if until > 60 {
                    try? await Task.sleep(for: .seconds(until - 60))
                } else {
                    _ = try? await client.auth.refreshSession(refreshToken: session.refreshToken)
                    try? await Task.sleep(for: .seconds(10))
                }
            }
        }
    }()

    /// Thrown when a change reached the server but matched no rows — row-level security
    /// answers such a change with success and zero rows, which must never be shown as
    /// a save that worked.
    struct NothingChanged: LocalizedError {
        var errorDescription: String? { "We couldn't save that. Please try again." }
    }

    /// Runs a mutation and throws unless the server reports it actually changed a row.
    /// The call must have requested the affected count (`FetchOptions(count: .exact)`).
    static func verifyAffected(_ count: Int?, _ what: String = "change") throws {
        if count == 0 {
            print("[Milni] \(what) matched no rows (row-level security or already gone)")
            throw NothingChanged()
        }
    }

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

extension PostgrestResponse where T == Void {
    /// Confirms the server actually changed a row, for a mutation that asked for the
    /// affected count with `FetchOptions(count: .exact)`.
    func verify(_ what: String) throws {
        try ChatBackend.verifyAffected(count, what)
    }
}

extension UUID {
    /// The lowercase form Postgres prints, used in every filter.
    nonisolated var lower: String { uuidString.lowercased() }
}
