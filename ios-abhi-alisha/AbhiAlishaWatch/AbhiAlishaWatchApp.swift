import SwiftUI
import WatchConnectivity

@main
struct AbhiAlishaWatchApp: App {
    init() {
        WatchTheme.registerFontsIfNeeded()
        WatchWeddingReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchScheduleScreen()
                .id(WatchWeddingReceiver.shared.weddingID)
        }
    }
}

/// Listens for the wedding the iPhone has open and points the schedule and
/// complications at it.
@MainActor
@Observable
final class WatchWeddingReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchWeddingReceiver()

    private(set) var weddingID: String = WatchWedding.current.id

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func apply(_ context: [String: Any]) {
        guard WatchWedding.save(context: context) else { return }
        weddingID = WatchWedding.current.id
        Task { await WatchScheduleStore.shared.weddingDidChange() }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        nonisolated(unsafe) let sendable = context
        Task { @MainActor in WatchWeddingReceiver.shared.apply(sendable) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        nonisolated(unsafe) let sendable = applicationContext
        Task { @MainActor in WatchWeddingReceiver.shared.apply(sendable) }
    }
}
