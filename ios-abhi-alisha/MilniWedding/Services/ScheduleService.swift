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

/// Reads the open wedding's events from Milni, shaped like the original feed.
nonisolated struct ScheduleService: Sendable {
    static let shared = ScheduleService()

    func fetchEvents() async throws -> (events: [ScheduleEvent], raw: Data) {
        let wedding = ActiveWedding.snapshot
        return try await MilniAPI.shared.events(weddingID: wedding.id, timezone: wedding.timeZone)
    }
}
