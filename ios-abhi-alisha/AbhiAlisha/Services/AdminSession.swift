import Foundation
import LocalAuthentication
import Observation

/// The couple's area: who may open it, and whether it's on screen.
///
/// Only the wedding's approved host and co-hosts get in; there is no passcode. Each
/// wedding can optionally ask for Face ID (or the phone's passcode) on this phone.
@Observable
final class AdminSession {
    var isAdminPresented = false
    private(set) var isAuthenticating = false

    /// The host pill was tapped.
    func requestEntry() {
        let context = WeddingContext.shared
        guard context.isHost else { return }
        let weddingID = context.weddingID
        BrandHaptics.soft()
        guard Self.isFaceIDLockOn(for: weddingID) else {
            isAdminPresented = true
            return
        }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            let passed = await Self.authenticate(reason: "Open your couple's area")
            isAuthenticating = false
            if passed { isAdminPresented = true }
        }
    }

    // MARK: - Face ID lock (per wedding, this phone only)

    private static func key(_ weddingID: String) -> String {
        "couple.faceid.\(weddingID.lowercased())"
    }

    static func isFaceIDLockOn(for weddingID: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(weddingID))
    }

    static func setFaceIDLock(_ isOn: Bool, for weddingID: String) {
        UserDefaults.standard.set(isOn, forKey: key(weddingID))
    }

    /// Whether this phone can check its owner at all (it needs a passcode set).
    static var canLock: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// "Face ID", "Touch ID", "Optic ID", or a plain fallback.
    static var biometryName: String {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "your passcode"
        }
    }

    /// A phone with no passcode can't be checked, so it simply lets the host in.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
