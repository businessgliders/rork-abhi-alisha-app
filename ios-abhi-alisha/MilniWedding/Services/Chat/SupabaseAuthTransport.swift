import Foundation
import Supabase

/// One authenticated request path for everything the app sends to Supabase —
/// REST queries, RPCs, storage and edge functions all ride the same session.
///
/// supabase-swift stamps `Authorization: Bearer <anon key>` on every request as its
/// base header, and swaps in the signed-in person's token only when it can read a
/// valid session at the moment the request leaves. When a refresh has failed — the
/// phone idle for an hour, a flaky network — the swap silently doesn't happen and
/// requests went out as the anon key: reads came back empty (the join code showed as
/// dots, a private wedding's names vanished), and writes either changed nothing while
/// the app reported success, or the server answered 401.
///
/// This `URLProtocol` sits on the session every Supabase request rides. It replaces
/// the anon bearer with the signed-in person's token, refreshes a token that is close
/// to expiring, and on a 401 refreshes once and sends the request once more. The auth
/// endpoints themselves are never touched: the auth client manages its own tokens.
final class SupabaseAuthURLProtocol: URLProtocol {
    /// The session Supabase requests ride on; only this protocol is installed on it.
    nonisolated static let supabaseSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SupabaseAuthURLProtocol.self]
        return URLSession(configuration: configuration)
    }()

    /// A plain session for the request we forward, so it never loops back through us.
    private static let plainSession = URLSession(configuration: .ephemeral)

    override class func canInit(with request: URLRequest) -> Bool {
        guard request.url?.scheme?.lowercased() == "https" else { return false }
        guard request.url?.host == ChatBackend.url.host else { return false }
        // Never touch the auth endpoints: the auth client owns its tokens, and its
        // refresh request must pass through untouched to avoid a loop.
        return !request.url!.path.contains("/auth/")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    // MARK: - Sending

    private var loadTask: Task<Void, Never>?

    override func startLoading() {
        let original = request
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (response, data) = try await Self.send(with: original)
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        loadTask?.cancel()
        loadTask = nil
    }

    /// Sends `original` with its Authorization header corrected, and retries once on
    /// a 401 after forcing a refresh.
    private static func send(with original: URLRequest) async throws -> (HTTPURLResponse, Data) {
        // The system hands the body over as a stream that can only be read once, so
        // read it up front and reuse it for the retry.
        let body = bodyData(of: original)
        let (response, data) = try await sendOnce(with: original, body: body)
        guard response.statusCode == 401 else { return (response, data) }
        // A 401 with no session is the server's honest answer for someone signed out.
        guard ChatBackend.isSignedIn else { return (response, data) }
        // The token was no good even after the library's own refresh attempt: force a
        // fresh one and send the request a single second time.
        guard await refreshedToken() != nil else { return (response, data) }
        return try await sendOnce(with: original, body: body)
    }

    private static func sendOnce(with original: URLRequest, body: Data?) async throws -> (HTTPURLResponse, Data) {
        var outgoing = URLRequest(url: original.url!)
        outgoing.httpMethod = original.httpMethod
        outgoing.allHTTPHeaderFields = original.allHTTPHeaderFields
        outgoing.cachePolicy = original.cachePolicy
        outgoing.timeoutInterval = original.timeoutInterval
        // Correct the header just before the request leaves.
        if let token = await bestToken() {
            outgoing.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        outgoing.httpBody = body

        let (data, response) = try await plainSession.data(for: outgoing)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (http, data)
    }

    // MARK: - The Authorization header

    /// The token to send: the signed-in person's, freshened when it expires within a
    /// minute. Nil when signed out, so the anon bearer is left exactly as it is.
    private static func bestToken() async -> String? {
        guard let session = ChatBackend.client.auth.currentSession else { return nil }
        let until = session.expiresAt - Date().timeIntervalSince1970
        if until < 60 {
            return await refreshedToken()
        }
        return session.accessToken
    }

    /// Forces a refresh and returns the new token, or the old one if the refresh
    /// failed (the auth client already joins concurrent refreshes, so this stays one
    /// network call however many requests are in flight).
    private static func refreshedToken() async -> String? {
        guard let session = ChatBackend.client.auth.currentSession else { return nil }
        if let fresh = try? await ChatBackend.client.auth.refreshSession(refreshToken: session.refreshToken) {
            return fresh.accessToken
        }
        return session.accessToken
    }

    // MARK: - Request bodies

    /// The system hands a URLProtocol the body as a stream; read it back so the
    /// request can be sent (and retried) whole.
    private static func bodyData(of request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 16_384
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
