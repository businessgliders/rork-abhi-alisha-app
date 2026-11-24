import Foundation
import WatchConnectivity

/// Tells the paired Watch which wedding is open, so its schedule and complications follow.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private var pending: [String: Any]?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated { session.activate() }
    }

    func send(_ snapshot: WeddingSnapshot) {
        let context: [String: Any] = [
            "wedding_id": snapshot.id,
            "partner_one": snapshot.partnerOne,
            "partner_two": snapshot.partnerTwo,
            "title": snapshot.title,
            "timezone": snapshot.timezone,
            "start_date": snapshot.startDate ?? "",
            "end_date": snapshot.endDate ?? "",
        ]
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = context
            activate()
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(context)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            guard let context = WatchBridge.shared.pending else { return }
            WatchBridge.shared.pending = nil
            if session.isPaired, session.isWatchAppInstalled {
                try? session.updateApplicationContext(context)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
