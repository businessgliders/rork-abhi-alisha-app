import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import Supabase
import SwiftUI
import UIKit

/// Where this person stands with the family chat, which decides the screen they see.
enum ChatPhase: Equatable {
    /// Signed in, but the profile hasn't come back yet (only ever seen offline).
    case loading
    case signedOut
    case pending
    case blocked
    case approved
}

/// Who is signed in to the chat, and what they're allowed to see.
///
/// Sign in with Apple hands an identity token to Supabase. The person's profile then
/// decides the gate: pending people wait to be welcomed in, blocked people see nothing,
/// approved people get the chat. The last known profile is kept on the phone so the
/// right screen appears instantly, then quietly refreshes on every app open.
@Observable
final class ChatSession {
    static let shared = ChatSession()

    private(set) var phase: ChatPhase = .loading
    private(set) var me: ChatProfile?
    private(set) var userID: UUID?

    var isNamePromptPresented = false
    /// The name Apple shared on first sign-in, offered as the starting point.
    var suggestedName = ""

    private(set) var isSigningIn = false
    var signInError: String?

    private(set) var isDeletingAccount = false
    var didDeleteFail = false

    private var currentNonce: String?
    private var didStart = false
    private var pushToken: String?
    private var waitingChannel: RealtimeChannelV2?
    private var waitingTask: Task<Void, Never>?

    private let defaults = UserDefaults.standard
    private enum Key {
        static let pushRegistration = "chat.pushRegistration"
    }

    nonisolated private struct NewProfile: Encodable, Sendable {
        let id: String
        let display_name: String?
    }

    nonisolated private struct NameChange: Encodable, Sendable {
        let display_name: String
    }

    nonisolated private struct PushParams: Encodable, Sendable {
        let p_token: String
        let p_platform: String
    }

    var isAdmin: Bool { me?.isAdmin == true }

    // MARK: - Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true
        Task {
            for await change in ChatBackend.client.auth.authStateChanges {
                await handle(change.event, session: change.session)
            }
        }
    }

    /// Every return to the app: is this person still waiting, or have they been welcomed in?
    func applicationDidBecomeActive() {
        guard userID != nil else { return }
        Task {
            await refreshProfile()
            if phase == .approved {
                await ChatOutbox.shared.flush()
                await ChatStore.shared.refreshAll()
            }
        }
    }

    private func handle(_ event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .signedOut, .userDeleted:
            await becomeSignedOut()
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
            guard let session else {
                if event == .initialSession { phase = .signedOut }
                return
            }
            if session.user.id != userID {
                await adopt(session.user.id)
            }
        default:
            break
        }
    }

    private func adopt(_ id: UUID) async {
        userID = id
        if let cached = ChatCache.load(ChatProfile.self, named: Self.profileCacheName(id)) {
            apply(cached, persist: false)
        } else {
            phase = .loading
        }
        await refreshProfile()
        // The APNs token is fetched for chat even before updates are switched on;
        // banners still only appear once the guest allows them.
        UIApplication.shared.registerForRemoteNotifications()
        await registerPushIfPossible()
    }

    // MARK: - Sign in with Apple

    /// Prepares the Apple request with a hashed one-time nonce; the raw value is kept
    /// to prove to Supabase that this token was asked for by this app, just now.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        signInError = nil
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            print("[Chat] Apple sign-in did not complete")
            signInError = "Sign in didn't finish. Please try again."

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                signInError = "Sign in didn't finish. Please try again."
                return
            }
            if let name = credential.fullName {
                let formatted = PersonNameComponentsFormatter.localizedString(from: name, style: .default)
                if let clean = ChatJSON.clean(formatted) { suggestedName = clean }
            }

            isSigningIn = true
            defer { isSigningIn = false }
            do {
                _ = try await ChatBackend.client.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
                )
                currentNonce = nil
            } catch {
                print("[Chat] Supabase sign-in failed")
                signInError = "We couldn't sign you in just now. Please try again."
            }
        }
    }

    // MARK: - Profile

    func refreshProfile() async {
        guard let userID else { return }
        do {
            if let profile = try await fetchProfile(userID) {
                apply(profile, persist: true)
                return
            }
            // No profile yet: create one, then read it back for its real status.
            _ = try? await ChatBackend.client
                .from("profiles")
                .insert(NewProfile(id: userID.lower, display_name: ChatJSON.clean(suggestedName)), returning: .minimal)
                .execute()
            if let profile = try await fetchProfile(userID) {
                apply(profile, persist: true)
            } else {
                apply(ChatProfile(id: userID, displayName: ChatJSON.clean(suggestedName), status: "pending"), persist: false)
            }
        } catch {
            // Offline: whatever we showed last stays on screen.
            print("[Chat] profile refresh postponed")
        }
    }

    private func fetchProfile(_ id: UUID) async throws -> ChatProfile? {
        let rows: [ChatProfile] = try await ChatBackend.client
            .from("profiles")
            .select(ChatProfile.columns)
            .eq("id", value: id.lower)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    private func apply(_ profile: ChatProfile, persist: Bool) {
        let wasApproved = phase == .approved
        me = profile
        if persist { ChatCache.save(profile, named: Self.profileCacheName(profile.id)) }

        let next: ChatPhase
        switch profile.access {
        case .approved: next = .approved
        case .blocked: next = .blocked
        case .pending: next = .pending
        }
        if next != phase {
            withAnimation(.calm) { phase = next }
        }

        if !profile.hasName, next != .blocked, !isNamePromptPresented {
            isNamePromptPresented = true
        }

        if next == .approved {
            stopWaiting()
            ChatOutbox.shared.activate(userID: profile.id)
            ChatStore.shared.activate(userID: profile.id)
            if !wasApproved {
                Task { await ChatStore.shared.refreshAll() }
            }
        } else if next == .pending {
            startWaiting(for: profile.id)
        } else {
            stopWaiting()
        }
    }

    /// Saves the name the family will see.
    func saveName(_ name: String) async -> Bool {
        guard let userID, let clean = ChatJSON.clean(name) else { return false }
        do {
            try await ChatBackend.client
                .from("profiles")
                .update(NameChange(display_name: clean), returning: .minimal)
                .eq("id", value: userID.lower)
                .execute()
            if var profile = me {
                profile.displayName = clean
                me = profile
                ChatCache.save(profile, named: Self.profileCacheName(profile.id))
            }
            isNamePromptPresented = false
            Task { await ChatStore.shared.refreshPeople() }
            return true
        } catch {
            print("[Chat] name could not be saved")
            return false
        }
    }

    // MARK: - Waiting to be welcomed in

    /// While pending, listen for the moment Abhi or Alisha approve this person, so the
    /// waiting screen can open into the chat without a relaunch.
    private func startWaiting(for id: UUID) {
        guard waitingChannel == nil else { return }
        let channel = ChatBackend.client.channel("waiting-\(id.lower)")
        let changes = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "profiles",
            filter: .eq("id", value: id.lower)
        )
        waitingChannel = channel
        waitingTask = Task {
            for await _ in changes {
                await ChatSession.shared.refreshProfile()
            }
        }
        Task {
            do { try await channel.subscribeWithError() } catch { print("[Chat] waiting listener unavailable") }
        }
    }

    private func stopWaiting() {
        waitingTask?.cancel()
        waitingTask = nil
        if let channel = waitingChannel {
            waitingChannel = nil
            Task { await ChatBackend.client.removeChannel(channel) }
        }
    }

    // MARK: - Push

    func pushTokenDidChange(_ token: String) {
        pushToken = token
        Task { await registerPushIfPossible() }
    }

    private func registerPushIfPossible() async {
        guard let userID, let token = pushToken ?? PushRegistrar.shared.currentToken else { return }
        let fingerprint = userID.lower + "|" + token
        guard defaults.string(forKey: Key.pushRegistration) != fingerprint else { return }
        do {
            try await ChatBackend.client
                .rpc("register_push_token", params: PushParams(p_token: token, p_platform: "ios"))
                .execute()
            defaults.set(fingerprint, forKey: Key.pushRegistration)
        } catch {
            // Silent: tried again on the next launch or token change.
        }
    }

    // MARK: - Leaving

    func signOut() async {
        try? await ChatBackend.client.auth.signOut(scope: .local)
        await becomeSignedOut()
    }

    /// Permanently deletes this account on the server, then signs out. Returns false,
    /// with nothing deleted, if the server couldn't be reached or said no.
    @discardableResult
    func deleteAccount() async -> Bool {
        guard !isDeletingAccount else { return false }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            let session = try await ChatBackend.client.auth.session
            var request = URLRequest(url: ChatBackend.url.appending(path: "functions/v1/delete-account"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(ChatBackend.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
            request.timeoutInterval = 30

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                print("[Chat] account deletion was refused")
                didDeleteFail = true
                return false
            }
            await signOut()
            return true
        } catch {
            print("[Chat] account deletion could not reach the server")
            didDeleteFail = true
            return false
        }
    }

    private func becomeSignedOut() async {
        stopWaiting()
        userID = nil
        me = nil
        isNamePromptPresented = false
        suggestedName = ""
        defaults.removeObject(forKey: Key.pushRegistration)
        ChatOutbox.shared.reset()
        await ChatStore.shared.reset()
        ChatCache.wipeAll()
        withAnimation(.calm) { phase = .signedOut }
    }

    // MARK: - Helpers

    private static func profileCacheName(_ id: UUID) -> String { "me-\(id.lower).json" }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            return UUID().uuidString + UUID().uuidString
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
