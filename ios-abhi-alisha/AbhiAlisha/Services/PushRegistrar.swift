import Foundation
import Observation
import UIKit
import UserNotifications

/// Wedding updates: when to ask, and telling the couple's backend where to reach this phone.
///
/// Permission is never asked on first launch. The explainer rises on the second launch,
/// or whenever the guest taps "Notify me about updates", and the system prompt only
/// follows once they've read why. The device token is sent to `registerDevice` whenever
/// it (or the guest's name) differs from what was last sent, and failures stay silent.
@Observable
final class PushRegistrar {
    static let shared = PushRegistrar()

    private(set) var status: UNAuthorizationStatus = .notDetermined
    var isExplainerPresented = false

    private var deviceToken: String?
    private var isSending = false
    private let defaults = UserDefaults.standard

    private enum Key {
        static let launchCount = "push.launchCount"
        static let didOfferOnLaunch = "push.didOfferOnLaunch"
        static let lastRegistration = "push.lastRegistration"
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

        Task {
            await refreshStatus()
            if isEnabled {
                // Every launch: the token may have rotated since last time.
                UIApplication.shared.registerForRemoteNotifications()
                return
            }
            guard status == .notDetermined,
                  launches >= 2,
                  !defaults.bool(forKey: Key.didOfferOnLaunch) else { return }
            // Let the names finish writing themselves across the hero first.
            try? await Task.sleep(for: .seconds(3.6))
            defaults.set(true, forKey: Key.didOfferOnLaunch)
            isExplainerPresented = true
        }
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

    func didRegister(tokenData: Data) {
        deviceToken = tokenData.map { String(format: "%02x", $0) }.joined()
        Task { await sendRegistrationIfChanged() }
    }

    /// After an RSVP lookup, so the couple's list knows whose phone this is.
    func guestNameMayHaveChanged() {
        guard deviceToken != nil else { return }
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
