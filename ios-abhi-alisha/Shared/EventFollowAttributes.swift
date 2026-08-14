import ActivityKit
import Foundation

/// A celebration a guest is following on the Lock Screen and in the Dynamic Island.
///
/// Everything fixed about the event travels in the attributes; only the phase changes,
/// which keeps the content state far inside the 4 KB ActivityKit allows. The countdown
/// itself is drawn by SwiftUI from `startsAt`, so no update is needed as it ticks.
nonisolated struct EventFollowAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Sendable {
            /// Still to come — a countdown to the start.
            case soon
            /// Underway.
            case now
        }

        var phase: Phase
    }

    let eventID: String
    let title: String
    let startsAt: Date
    let endsAt: Date?
    let locationName: String?
    let dressCode: String?
    let iconKeyRaw: String

    var iconKey: EventIconKey {
        EventIconKey(rawValue: iconKeyRaw) ?? .sparkle
    }

    /// The moment the activity should disappear on its own.
    var conclusion: Date {
        endsAt ?? startsAt.addingTimeInterval(2 * 3600)
    }

    init(event: ScheduleEvent, startsAt: Date) {
        eventID = event.id
        title = event.title
        self.startsAt = startsAt
        endsAt = event.endsAt
        locationName = event.locationName
        dressCode = event.dressCode
        iconKeyRaw = event.iconKey.rawValue
    }
}

extension ScheduleEvent {
    /// How long before a celebration the Lock Screen starts carrying it.
    static let followLeadTime: TimeInterval = 60 * 60

    /// True while the event is worth following: from an hour before it begins until it ends.
    func deservesLiveActivity(at now: Date) -> Bool {
        guard let startsAt, !isTimeToBeAnnounced else { return false }
        let end = endsAt ?? startsAt.addingTimeInterval(2 * 3600)
        return now >= startsAt.addingTimeInterval(-Self.followLeadTime) && now <= end
    }
}
