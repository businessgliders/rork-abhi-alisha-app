import UIKit
import UserNotifications

/// Receives the push token and notification taps, which SwiftUI has no direct hook for.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        PushRegistrar.shared.applicationDidLaunch()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistrar.shared.didRegister(tokenData: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Push] registration unavailable on this device")
    }

    // The completion-handler forms are used on purpose. The `async` forms finish on a
    // background thread, and UIKit aborts the app when a notification tap is completed
    // off the main thread — which is exactly the crash build 3 had.

    /// A note that arrives while the app is open still shows as a banner, except a chat
    /// message for the conversation already on screen, which simply appears in place.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let conversationID = DeepLinkRouter.conversationIDValue(in: notification.request.content.userInfo)
        let isChat = DeepLinkRouter.opensValue(in: notification.request.content.userInfo) == "chat"
        let finish = PresentationCompletion(completionHandler)
        Self.onMainThread {
            // Anything that isn't a chat message is an announcement: fetch it so the
            // feed and its unread dot are current straight away.
            if !isChat, conversationID == nil {
                Task { await NotificationsStore.shared.refresh() }
            }
            if let conversationID,
               let id = UUID(uuidString: conversationID),
               ChatStore.shared.activeThreadID == id {
                finish.call([.list])
                return
            }
            finish.call([.banner, .list, .sound])
        }
    }

    /// Tapping a wedding update opens the screen the payload names — the updates screen
    /// for "notifications", otherwise Home — and for Schedule notes, the celebration it
    /// names. Both values are read defensively, so a missing or mangled payload can never
    /// crash: an unknown celebration simply leaves Schedule on whatever is on now, and
    /// the landing waits for the app to load. The landing is recorded first, then the
    /// system is told the tap is handled.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let screen = DeepLinkRouter.screenValue(in: userInfo)
        let eventID = DeepLinkRouter.eventIDValue(in: userInfo)
        let conversationID = DeepLinkRouter.conversationIDValue(in: userInfo)
        let opens = DeepLinkRouter.opensValue(in: userInfo)
        let isChat = opens == "chat"
        let isAnnouncement = opens == "announcements" || opens == "announcement"
        let finish = TapCompletion(completionHandler)
        Self.onMainThread {
            // A new announcement brings the feed up to date on its way in.
            Task { await NotificationsStore.shared.refresh() }
            if isAnnouncement {
                DeepLinkRouter.shared.pendingAnnouncements = true
                DeepLinkRouter.shared.open(.tab(.chat))
                finish.call()
                return
            }
            // A chat message ("opens": "chat") opens its conversation's thread. Without a
            // readable conversation it still lands on the Chat list, never somewhere else.
            if isChat || conversationID != nil {
                DeepLinkRouter.shared.pendingConversationID = conversationID.flatMap { UUID(uuidString: $0) }
                DeepLinkRouter.shared.open(.tab(.chat))
                finish.call()
                return
            }
            let landing = DeepLinkRouter.landing(forScreen: screen)
            if case .tab(.schedule) = landing, let eventID {
                DeepLinkRouter.shared.pendingEventID = eventID
            }
            DeepLinkRouter.shared.open(landing)
            finish.call()
        }
    }

    /// Runs straight away when already on the main thread (a cold-start tap), otherwise
    /// hops there first.
    private nonisolated static func onMainThread(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
        }
    }
}

/// Carries the system's completion handler to the main thread. The system hands it over
/// without a Sendable annotation; it is only ever called once, on the main thread.
private nonisolated final class TapCompletion: @unchecked Sendable {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    func call() { handler() }
}

private nonisolated final class PresentationCompletion: @unchecked Sendable {
    private let handler: (UNNotificationPresentationOptions) -> Void
    init(_ handler: @escaping (UNNotificationPresentationOptions) -> Void) { self.handler = handler }
    func call(_ options: UNNotificationPresentationOptions) { handler(options) }
}
