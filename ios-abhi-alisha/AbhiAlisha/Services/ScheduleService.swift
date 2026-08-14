import Foundation

nonisolated enum ScheduleServiceError: LocalizedError {
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "The schedule service replied with status \(code)."
        }
    }
}

/// Public read-only client for the base44 `ScheduleEvent` entity. No API key required.
nonisolated struct ScheduleService: Sendable {
    static let shared = ScheduleService()

    private let baseURL = URL(string: "https://aawedding.base44.app/api")!

    /// Fetches the schedule and returns both the parsed events and the raw payload for caching.
    func fetchEvents() async throws -> (events: [ScheduleEvent], raw: Data) {
        let url = baseURL.appending(path: "entities/ScheduleEvent")
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ScheduleServiceError.badResponse(http.statusCode)
        }
        let events = try ScheduleDecoder.decode(data)
        return (events, data)
    }
}
