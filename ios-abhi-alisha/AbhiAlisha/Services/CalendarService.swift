import EventKit
import Foundation

/// Saves a celebration to the guest's own calendar. Write-only access is requested
/// the first time, and every failure resolves to a readable outcome rather than a throw.
@MainActor
final class CalendarService {
    static let shared = CalendarService()

    enum Outcome {
        case added
        case denied
        case failed

        var message: String {
            switch self {
            case .added: return "Added to your calendar"
            case .denied: return "Allow calendar access in Settings to save this"
            case .failed: return "Couldn't add this one — please try again"
            }
        }
    }

    private let store = EKEventStore()

    private init() {}

    func add(_ event: ScheduleEvent) async -> Outcome {
        guard let start = event.startsAt else { return .failed }

        do {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            guard granted else { return .denied }

            let entry = EKEvent(eventStore: store)
            entry.title = event.title
            entry.startDate = start
            entry.endDate = event.endsAt ?? start.addingTimeInterval(2 * 3600)
            entry.timeZone = TimeZone(identifier: "America/Cancun")
            entry.notes = event.description
            let place = [event.locationName, event.locationAddress].compactMap { $0 }
            if !place.isEmpty {
                entry.location = place.joined(separator: ", ")
            }
            guard let calendar = store.defaultCalendarForNewEvents else { return .failed }
            entry.calendar = calendar

            try store.save(entry, span: .thisEvent, commit: true)
            return .added
        } catch {
            print("[CalendarService] could not save event")
            return .failed
        }
    }
}
