import EventKit
import Foundation
import Observation

/// Saves celebrations to the guest's own calendar, never twice.
///
/// Every calendar entry the app creates is remembered on the phone by celebration, with
/// a fingerprint of what was written. A second "Add all" adds only what's new and updates
/// only what changed. Write-only access is asked for first; because write-only access
/// can't read entries back, updating a changed time asks to upgrade to full access, and
/// only then. Every failure resolves to a readable outcome rather than a throw.
@Observable
final class CalendarService {
    static let shared = CalendarService()

    enum Outcome {
        case added
        case alreadyAdded
        case denied
        case failed

        var message: String {
            switch self {
            case .added: return "Added to your calendar"
            case .alreadyAdded: return "Already in your calendar"
            case .denied: return "Allow calendar access in Settings to save this"
            case .failed: return "Couldn't add this one, please try again"
            }
        }
    }

    enum BatchOutcome {
        case done(added: Int, updated: Int)
        case upToDate
        case needsFullAccess(added: Int)
        case denied
        case failed

        var message: String {
            switch self {
            case .done(let added, let updated):
                var parts: [String] = []
                if added > 0 { parts.append("Added \(added) \(added == 1 ? "celebration" : "celebrations")") }
                if updated > 0 { parts.append("updated \(updated)") }
                let line = parts.joined(separator: ", ")
                return line.prefix(1).uppercased() + line.dropFirst()
            case .upToDate:
                return "Your calendar is up to date"
            case .needsFullAccess(let added):
                let lead = added > 0 ? "Added \(added). " : ""
                return lead + "To update changed times, allow full calendar access in Settings"
            case .denied:
                return "Allow calendar access in Settings to add the celebrations"
            case .failed:
                return "Couldn't reach your calendar, please try again"
            }
        }
    }

    nonisolated private struct SavedEntry: Codable, Sendable {
        var identifier: String
        var fingerprint: String
    }

    private(set) var isAddingAll = false
    private var saved: [String: SavedEntry] {
        didSet { persist() }
    }

    @ObservationIgnored private let store = EKEventStore()
    private static let savedKey = "calendar.savedEntries"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.savedKey),
           let decoded = try? JSONDecoder().decode([String: SavedEntry].self, from: data) {
            saved = decoded
        } else {
            saved = [:]
        }
    }

    /// True once every celebration on offer has been written to the calendar.
    func hasAddedAll(_ events: [ScheduleEvent]) -> Bool {
        let wanted = Self.candidates(events)
        return !wanted.isEmpty && wanted.allSatisfy { saved[$0.id] != nil }
    }

    func isAdded(_ event: ScheduleEvent) -> Bool {
        saved[event.id] != nil
    }

    // MARK: - One celebration

    func add(_ event: ScheduleEvent) async -> Outcome {
        guard event.startsAt != nil else { return .failed }
        if saved[event.id] != nil { return .alreadyAdded }
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else { return .denied }
            guard let calendar = store.defaultCalendarForNewEvents else { return .failed }
            try create(event, in: calendar)
            return .added
        } catch {
            print("[CalendarService] could not save event")
            return .failed
        }
    }

    // MARK: - Every celebration

    /// Adds each active celebration (not the farewell morning) with a one-hour alert.
    /// Already-added ones are left alone, or updated if their details changed.
    func addAll(_ events: [ScheduleEvent]) async -> BatchOutcome {
        guard !isAddingAll else { return .upToDate }
        isAddingAll = true
        defer { isAddingAll = false }

        let wanted = Self.candidates(events)
        guard !wanted.isEmpty else { return .failed }

        do {
            guard try await store.requestWriteOnlyAccessToEvents() else { return .denied }
            guard let calendar = store.defaultCalendarForNewEvents else { return .failed }

            var added = 0
            var changed: [ScheduleEvent] = []
            for event in wanted {
                if let entry = saved[event.id] {
                    if entry.fingerprint != Self.fingerprint(event) { changed.append(event) }
                } else {
                    try create(event, in: calendar)
                    added += 1
                }
            }

            guard !changed.isEmpty else {
                return added > 0 ? .done(added: added, updated: 0) : .upToDate
            }

            if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
                let upgraded = (try? await store.requestFullAccessToEvents()) ?? false
                guard upgraded else { return .needsFullAccess(added: added) }
            }

            var updated = 0
            for event in changed {
                if let identifier = saved[event.id]?.identifier,
                   !identifier.isEmpty,
                   let existing = store.event(withIdentifier: identifier) {
                    fill(existing, from: event)
                    try store.save(existing, span: .thisEvent, commit: true)
                    saved[event.id] = SavedEntry(identifier: identifier, fingerprint: Self.fingerprint(event))
                } else {
                    // Removed from the calendar by hand since; put it back.
                    try create(event, in: calendar)
                }
                updated += 1
            }
            return .done(added: added, updated: updated)
        } catch {
            print("[CalendarService] could not save events")
            return .failed
        }
    }

    // MARK: - Writing

    private func create(_ event: ScheduleEvent, in calendar: EKCalendar) throws {
        let entry = EKEvent(eventStore: store)
        entry.calendar = calendar
        fill(entry, from: event)
        entry.addAlarm(EKAlarm(relativeOffset: -3600))
        try store.save(entry, span: .thisEvent, commit: true)
        saved[event.id] = SavedEntry(identifier: entry.eventIdentifier ?? "", fingerprint: Self.fingerprint(event))
    }

    private func fill(_ entry: EKEvent, from event: ScheduleEvent) {
        guard let start = event.startsAt else { return }
        entry.title = event.title
        entry.startDate = start
        entry.endDate = event.endsAt ?? start.addingTimeInterval(2 * 3600)
        entry.timeZone = TimeZone(identifier: "America/Cancun")
        entry.location = Self.location(for: event)
        entry.notes = event.dressCode
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: Self.savedKey)
    }

    private static func location(for event: ScheduleEvent) -> String {
        guard let name = event.locationName else { return "AVA Resort Cancún" }
        return "\(name), AVA Resort Cancún"
    }

    private static func fingerprint(_ event: ScheduleEvent) -> String {
        [
            event.title,
            event.startsAt.map { String($0.timeIntervalSince1970) } ?? "",
            event.endsAt.map { String($0.timeIntervalSince1970) } ?? "",
            location(for: event),
            event.dressCode ?? ""
        ].joined(separator: "|")
    }

    private static func candidates(_ events: [ScheduleEvent]) -> [ScheduleEvent] {
        events.filter { $0.isActive != false && !$0.isFarewell && $0.startsAt != nil && !$0.isTimeToBeAnnounced }
    }
}
