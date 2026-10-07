import ActivityKit
import Foundation
import Functions
import Supabase
import UIKit

/// Lets the couple's server put each celebration on the Lock Screen of every phone, even
/// with the app closed.
///
/// Two kinds of token go to the `register-live-activity` function, quietly and with no
/// sign-in: the phone's push-to-start token (so the server can raise a celebration an
/// hour before it begins), and each running activity's own update token (so it can
/// switch to "Happening now" and retire it when the event ends). A token is only sent
/// again when it changes. Failures stay silent and simply retry on the next launch.
@MainActor
final class LiveActivityRegistrar {
    static let shared = LiveActivityRegistrar()

    private var isStarted = false
    private var watchedActivityIDs: Set<String> = []
    private let defaults = UserDefaults.standard

    private enum Key {
        static let sent = "liveActivity.sentTokens"
    }

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        Task {
            for await data in Activity<EventFollowAttributes>.pushToStartTokenUpdates {
                await register(token: Self.hex(data), kind: "start", eventID: nil)
            }
        }

        // Every activity, whether the app or the server started it, reports its own
        // update token so the server can move it along.
        for activity in Activity<EventFollowAttributes>.activities {
            watch(activity)
        }
        Task {
            for await activity in Activity<EventFollowAttributes>.activityUpdates {
                watch(activity)
            }
        }
    }

    private func watch(_ activity: Activity<EventFollowAttributes>) {
        guard !watchedActivityIDs.contains(activity.id) else { return }
        watchedActivityIDs.insert(activity.id)
        let eventID = activity.attributes.eventID
        Task {
            for await data in activity.pushTokenUpdates {
                await register(token: Self.hex(data), kind: "update", eventID: eventID)
            }
        }
    }

    private func register(token: String, kind: String, eventID: String?) async {
        let fingerprint = [kind, eventID ?? "", token].joined(separator: "|")
        var sent = Set(defaults.stringArray(forKey: Key.sent) ?? [])
        guard !sent.contains(fingerprint) else { return }

        var payload: [String: JSONValue] = [
            "token": .string(token),
            "kind": .string(kind),
            "environment": .string(Self.environment)
        ]
        // Lets the server skip raising a celebration this phone is already showing.
        if let device = UIDevice.current.identifierForVendor?.uuidString.lowercased() {
            payload["device_id"] = .string(device)
        }
        if let eventID { payload["event_id"] = .string(eventID) }

        do {
            _ = try await ChatBackend.client.functions.invoke(
                "register-live-activity",
                options: .init(body: payload)
            ) { _, _ in true }
            sent.insert(fingerprint)
            // Keep the list small: only the most recent registrations matter.
            defaults.set(Array(sent.suffix(40)), forKey: Key.sent)
        } catch {
            print("[LiveActivity] registration postponed")
        }
    }

    /// Debug builds talk to Apple's sandbox push service; TestFlight and the App Store
    /// use production.
    private static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private nonisolated static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
