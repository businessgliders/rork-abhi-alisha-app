import Foundation

/// Calls the couple's backend functions (`/api/functions/<name>`), anonymously — no key
/// and no auth header. Admin functions carry the couple's code inside the body instead.
nonisolated struct WeddingFunctions: Sendable {
    static let shared = WeddingFunctions()

    private let baseURL = URL(string: "https://aawedding.base44.app/api/functions")!

    /// What a function answered. Only transport failures throw; any status comes back here.
    nonisolated struct Reply: Sendable {
        let status: Int
        let body: JSONValue?

        /// A 2xx that doesn't carry an `error` field.
        var isSuccess: Bool {
            (200..<300).contains(status) && body?["error"] == nil
        }

        var isUnauthorized: Bool {
            status == 401 || status == 403
        }
    }

    func call(
        _ name: String,
        _ payload: [String: JSONValue],
        timeout: TimeInterval = 20
    ) async throws -> Reply {
        var request = URLRequest(url: baseURL.appending(path: name))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = try? JSONDecoder().decode(JSONValue.self, from: data)
        return Reply(status: status, body: body)
    }
}
