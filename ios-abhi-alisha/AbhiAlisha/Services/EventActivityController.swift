import ActivityKit
import Foundation
import Observation

/// Keeps the Lock Screen and the Dynamic Island in step with the weekend.
///
/// A celebration starts carrying a Live Activity an hour before it begins and stops the
/// moment it ends — no guest has to do anything. `follow(_:)` lets someone raise one
/// early from a celebration's own page, and `stopFollowing(_:)` puts it away again.
@Observable
final class EventActivityController {
    static let shared = EventActivityController()

    /// The events currently showing on the Lock Screen.
    private(set) var followedIDs: Set<String> = []

    private init() {
        refreshFollowedIDs()
    }

    /// False when Live Activities are switched off for the app in Settings.
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func isFollowing(_ event: ScheduleEvent) -> Bool {
        followedIDs.contains(event.id)
    }

    /// Raises a celebration onto the Lock Screen by hand.
    @discardableResult
    func follow(_ event: ScheduleEvent) -> Bool {
        guard areActivitiesEnabled, let startsAt = event.startsAt else { return false }
        guard !isFollowing(event) else { return true }
        return start(event, startsAt: startsAt, at: Date())
    }

    func stopFollowing(_ event: ScheduleEvent) async {
        for activity in Activity<EventFollowAttributes>.activities
        where activity.attributes.eventID == event.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        refreshFollowedIDs()
    }

    /// Called on every clock tick: raises what has come due, retires what is over, and
    /// flips a countdown to "Happening now" as each celebration begins.
    func sync(events: [ScheduleEvent], at now: Date) async {
        guard areActivitiesEnabled else { return }

        let live = Activity<EventFollowAttributes>.activities
        let liveIDs = Set(live.map(\.attributes.eventID))

        for activity in live {
            let attributes = activity.attributes
            if now > attributes.conclusion {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            let phase: EventFollowAttributes.ContentState.Phase = now >= attributes.startsAt ? .now : .soon
            if activity.content.state.phase != phase {
                await activity.update(
                    ActivityContent(state: .init(phase: phase), staleDate: attributes.conclusion)
                )
            }
        }

        for event in events where event.deservesLiveActivity(at: now) {
            guard let startsAt = event.startsAt, !liveIDs.contains(event.id) else { continue }
            _ = start(event, startsAt: startsAt, at: now)
        }

        refreshFollowedIDs()
    }

    // MARK: - Internals

    @discardableResult
    private func start(_ event: ScheduleEvent, startsAt: Date, at now: Date) -> Bool {
        let attributes = EventFollowAttributes(event: event, startsAt: startsAt)
        let state = EventFollowAttributes.ContentState(phase: now >= startsAt ? .now : .soon)

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: attributes.conclusion),
                pushType: nil
            )
            refreshFollowedIDs()
            return true
        } catch {
            print("[EventActivityController] could not follow event: \(error.localizedDescription)")
            return false
        }
    }

    private func refreshFollowedIDs() {
        followedIDs = Set(Activity<EventFollowAttributes>.activities.map(\.attributes.eventID))
    }
}
