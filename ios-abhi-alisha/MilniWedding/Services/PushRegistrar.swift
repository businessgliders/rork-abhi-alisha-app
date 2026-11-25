import Foundation
import Observation
import UIKit
import UserNotifications

/// Wedding updates: when to ask, and telling the couple's backend where to reach this phone.
///
/// When the wedding opens and updates are not yet decided (or are switched off), the
/// "Stay in the loop" sheet asks; "Not now" keeps it away for a week on this phone, and
/// a guest who has just joined is always asked once. The system prompt only follows a
/// tap on "Turn on updates". The device token is sent to `registerDevice` whenever
/// it (or the guest's name) differs from what was last sent, and failures stay silent.
@Observable
final class PushRegistrar {
    static let shared = PushRegistrar()

    private(set) var status: UNAuthorizationStatus = .notDetermined
    var isExplainerPresented = false
    /// The compact first-open card (retired: the full explainer sheet asks instead).
    var isFirstOpenCardPresented = false

    private var deviceToken: String?
    private var isSending = false
    private let defaults = UserDefaults.standard

    private enum Key {
        static let launchCount = "push.launchCount"
        static let didOfferOnLaunch = "push.didOfferOnLaunch"
        static let lastRegistration = "push.lastRegistration"
        static let snoozedUntil = "push.snoozedUntil"
    }

    /// Updates are switched on in any form the system allows.
    var isEnabled: Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    var isDenied: Bool { status == .denied }

    // MARK: - Launch

    /// Called once per real launch (not on every return to the foreground).
    func applicationDidLaunch() {
        let launches = defaults.integer(forKey: Key.launchCount) + 1
        defaults.set(launches, forKey: Key.launchCount)

#if DEBUG && targetEnvironment(simulator)
        if ScreenshotFixture.suspendNetwork { return }
#endif
        Task {
            await refreshStatus()
            if isEnabled {
                // Every launch: the token may have rotated since last time.
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Offering the explainer

    /// Shown at most once per launch, however often the wedding screens are rebuilt.
    private var didOfferThisLaunch = false
    /// A guest just joined: ask once they land on Home, even inside a snooze.
    private var pendingJoinOffer = false

    /// A guest has just joined a wedding.
    func offerAfterJoin() {
        pendingJoinOffer = true
    }

    /// Called each time the wedding screens appear. Not yet decided or switched off, and
    /// not snoozed: the "Stay in the loop" sheet rises after a short pause.
    func offerIfNeeded(isSample: Bool) async {
        await refreshStatus()
        if isEnabled {
            pendingJoinOffer = false
            UIApplication.shared.registerForRemoteNotifications()
            return
        }
        guard !isSample, !ScreenshotCapture.isActive else { return }
        let afterJoin = pendingJoinOffer
        guard afterJoin || (!didOfferThisLaunch && !isSnoozed) else { return }
        guard status == .notDetermined || status == .denied else { return }

        // Let the welcome curtain lift and the names write themselves across the hero.
        try? await Task.sleep(for: .seconds(afterJoin ? 2.4 : 3.2))
        guard !Task.isCancelled, !isEnabled, !isExplainerPresented else { return }
        pendingJoinOffer = false
        didOfferThisLaunch = true
        defaults.set(true, forKey: Key.didOfferOnLaunch)
        isExplainerPresented = true
    }

    /// "Not now": quiet on this phone for a week.
    func snooze() {
        defaults.set(Date().addingTimeInterval(7 * 24 * 3600), forKey: Key.snoozedUntil)
    }

    private var isSnoozed: Bool {
        guard let until = defaults.object(forKey: Key.snoozedUntil) as? Date else { return false }
        return until > Date()
    }

    func refreshStatus() async {
        status = await Self.currentStatus()
    }

    /// Back from Settings, updates may have just been switched on (or off).
    func applicationDidBecomeActive() {
        Task {
            let wasEnabled = isEnabled
            await refreshStatus()
            if isEnabled, !wasEnabled {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Asking

    /// Shows the system prompt. Only ever called from the explainer.
    func requestPermission() async {
        defaults.set(true, forKey: Key.didOfferOnLaunch)
        let granted = await Self.askForPermission()
        await refreshStatus()
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Opening the explainer by hand also counts as having been offered.
    func markOffered() {
        defaults.set(true, forKey: Key.didOfferOnLaunch)
    }

    // MARK: - Registration

    /// The current APNs token, once the system has handed one over.
    var currentToken: String? { deviceToken }

    func didRegister(tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        ChatSession.shared.pushTokenDidChange(token)
        Task {
            // The family chat may fetch a token before wedding updates are switched on;
            // the couple's list only hears about phones that have said yes.
            await refreshStatus()
            guard isEnabled else { return }
            await sendRegistrationIfChanged()
        }
    }

    /// After an RSVP lookup, so the couple's list knows whose phone this is.
    func guestNameMayHaveChanged() {
        guard deviceToken != nil, isEnabled else { return }
        Task { await sendRegistrationIfChanged() }
    }

    private func sendRegistrationIfChanged() async {
        guard let token = deviceToken, !isSending else { return }
        let name = RSVPService.shared.lastMatch?.displayName
        let fingerprint = token + "|" + (name ?? "")
        guard defaults.string(forKey: Key.lastRegistration) != fingerprint else { return }

        var payload: [String: JSONValue] = ["device_token": .string(token)]
        if let name { payload["guest_name"] = .string(name) }

        isSending = true
        defer { isSending = false }
        do {
            let reply = try await WeddingFunctions.shared.call("registerDevice", payload)
            if reply.isSuccess {
                defaults.set(fingerprint, forKey: Key.lastRegistration)
            }
        } catch {
            // Silent by design: it will simply try again next launch.
        }
    }

    // MARK: - System calls, kept off the main actor

    private nonisolated static func currentStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private nonisolated static func askForPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
}
