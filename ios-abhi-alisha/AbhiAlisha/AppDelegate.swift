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

    /// A note that arrives while the app is open still shows as a banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Tapping a wedding update opens the screen the payload names — the updates screen
    /// for "notifications", otherwise Home. The value is read defensively, so a missing
    /// or mangled payload can never crash, and the landing waits for the app to load.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = response.notification.request.content.userInfo
        await MainActor.run {
            DeepLinkRouter.shared.open(DeepLinkRouter.landing(fromPayload: payload))
        }
    }
}
