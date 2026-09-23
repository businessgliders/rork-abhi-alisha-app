import Foundation
import Observation

/// The couple's private area: whether it's unlocked, and what's on screen.
///
/// The code is confirmed by the backend and then kept in the Keychain, so it isn't asked
/// for again. Locking, or the backend refusing the saved code, forgets it.
@Observable
final class AdminSession {
    private(set) var code: String?
    var isPromptPresented = false
    var isAdminPresented = false

    private let keychain = KeychainStore(service: "abhialisha.couple", account: "sender-code")

    init() {
        code = keychain.read()
    }

    var isUnlocked: Bool { code != nil }

    /// The crest was held long enough.
    func requestEntry() {
        BrandHaptics.soft()
        if isUnlocked {
            isAdminPresented = true
        } else {
            isPromptPresented = true
        }
    }

    func dismissPrompt() {
        isPromptPresented = false
    }

    /// Returns false for a wrong code — and, deliberately, for no connection too, so the
    /// prompt never explains why.
    func unlock(with entered: String) async -> Bool {
        let candidate = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return false }
        guard await AdminService.shared.verify(code: candidate) else { return false }

        keychain.write(candidate)
        code = candidate
        isPromptPresented = false
        try? await Task.sleep(for: .milliseconds(320))
        isAdminPresented = true
        return true
    }

    func lock() {
        keychain.delete()
        code = nil
        isAdminPresented = false
    }

    /// The backend no longer accepts the saved code (it was changed elsewhere).
    func invalidate() {
        lock()
    }
}
