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
/// Two ways in. Sign in with Apple hands an identity token to Supabase, for the family
/// chat. A name-only guest is signed in anonymously, just for Questions & Chat; if they
/// later sign in with Apple, that identity is linked to the same account so their name
/// and messages carry over. The person's profile then decides the gate: pending people
/// wait to be welcomed into the family chat, blocked people see nothing, approved people
/// get it. The last known profile is kept on the phone so the right screen appears
/// instantly, then quietly refreshes on every app open.
@Observable
final class ChatSession {
    static let shared = ChatSession()

    private(set) var phase: ChatPhase = .loading
    private(set) var me: ChatProfile?
    private(set) var userID: UUID?
    /// A name-only guest: in Questions & Chat, but not (yet) known to the family chat.
    private(set) var isAnonymous = false

    private(set) var isJoiningAsGuest = false
    /// The name a guest just gave, saved the moment their new profile exists.
    private var pendingGuestName: String?

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
    private var lateProfileTask: Task<Void, Never>?

    private let defaults = UserDefaults.standard
    private enum Key {
        static let pushRegistration = "chat.pushRegistration"
    }

    nonisolated private struct NameChange: Encodable, Sendable {
        let display_name: String
    }

    nonisolated private struct PushParams: Encodable, Sendable {
        let p_token: String
        let p_platform: String
    }

    var isAdmin: Bool { me?.isAdmin == true && !isAnonymous }

    var isSignedIn: Bool { userID != nil }

    /// Signed in with Apple and welcomed in: the family's own conversations are open.
    var isFamilyMember: Bool { phase == .approved && !isAnonymous }

    /// Questions & Chat is open to anyone signed in, in any way, who hasn't been removed.
    var canUseOpenChannel: Bool { userID != nil && phase != .blocked }

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
            if phase == .approved || phase == .pending {
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
            let anonymous = session.user.isAnonymous
            if session.user.id != userID {
                // A different account than the one on screen: start clean for it.
                if userID != nil { await clearLocalState() }
                isAnonymous = anonymous
                await adopt(session.user.id)
            } else if anonymous != isAnonymous {
                // A guest who just linked Apple: same account, now known to the family chat.
                withAnimation(.calm) { isAnonymous = anonymous }
                await refreshProfile()
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
            let credentials = OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)

            if isAnonymous, userID != nil {
                await linkApple(credentials)
                return
            }
            do {
                _ = try await ChatBackend.client.auth.signInWithIdToken(credentials: credentials)
                currentNonce = nil
            } catch {
                print("[Chat] Supabase sign-in failed")
                signInError = "We couldn't sign you in just now. Please try again."
            }
        }
    }

    /// A name-only guest signing in with Apple: the Apple identity joins their existing
    /// account, so their name and Questions & Chat history stay theirs. If that Apple ID
    /// already has its own account, they're signed in to that one instead.
    private func linkApple(_ credentials: OpenIDConnectCredentials) async {
        do {
            _ = try await ChatBackend.client.auth.linkIdentityWithIdToken(credentials: credentials)
            currentNonce = nil
            withAnimation(.calm) { isAnonymous = false }
            await refreshProfile()
        } catch let error as AuthError where error.errorCode == .identityAlreadyExists {
            print("[Chat] Apple ID already has an account, signing in to it")
            do {
                _ = try await ChatBackend.client.auth.signInWithIdToken(credentials: credentials)
                currentNonce = nil
            } catch {
                signInError = "This Apple ID already has a family chat account. Sign out of the guest chat, then sign in with Apple."
            }
        } catch {
            print("[Chat] Apple identity could not be linked")
            signInError = "We couldn't sign you in just now. Please try again."
        }
    }

    // MARK: - Name-only guests

    /// Joins Questions & Chat with just a name: signs in anonymously, waits for the
    /// server to create the profile, then saves the name on it. A database trigger adds
    /// the new account to the open conversation, and the push token is registered as
    /// part of signing in. Returns false, with nothing changed, if it couldn't start.
    func joinAsGuest(name: String) async -> Bool {
        guard let clean = ChatJSON.clean(name), !isJoiningAsGuest else { return false }
        isJoiningAsGuest = true
        defer { isJoiningAsGuest = false }
        pendingGuestName = clean

        do {
            if userID == nil {
                let session = try await ChatBackend.client.auth.signInAnonymously()
                if session.user.id != userID {
                    isAnonymous = session.user.isAnonymous
                    await adopt(session.user.id)
                }
            }
            // The profile row arrives from a trigger a beat after the account exists.
            for _ in 0..<32 where me == nil {
                try await Task.sleep(for: .milliseconds(250))
            }
            if me != nil {
                _ = await saveName(clean)
            }
            // Otherwise the name is saved by `apply` the moment the profile turns up.
            return true
        } catch {
            print("[Chat] guest sign-in failed")
            pendingGuestName = nil
            return false
        }
    }

    // MARK: - Profile

    /// Reads this person's own profile. The row is created by the server the moment the
    /// account is made, so the app only ever reads it. Straight after a first sign-in it
    /// can lag by a beat, so a missing row is read again a couple of times before waiting
    /// a little longer in the background.
    func refreshProfile() async {
        guard let userID else { return }
        let delays: [Duration] = [.zero, .milliseconds(700), .milliseconds(1500)]
        do {
            for delay in delays {
                if delay > .zero { try await Task.sleep(for: delay) }
                guard self.userID == userID else { return }
                if let profile = try await fetchProfile(userID) {
                    lateProfileTask?.cancel()
                    lateProfileTask = nil
                    apply(profile, persist: true)
                    return
                }
            }
            print("[Chat] profile not ready yet, checking again shortly")
            scheduleLateProfileRead(for: userID)
        } catch is CancellationError {
            return
        } catch {
            // Offline: whatever we showed last stays on screen.
            print("[Chat] profile refresh postponed")
        }
    }

    /// One quiet follow-up read when the server hasn't finished creating the profile.
    private func scheduleLateProfileRead(for id: UUID) {
        guard lateProfileTask == nil else { return }
        lateProfileTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, ChatSession.shared.userID == id else { return }
            ChatSession.shared.lateProfileTask = nil
            await ChatSession.shared.refreshProfile()
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
        let previous = phase
        let wasActive = phase == .approved || phase == .pending
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

        if !profile.hasName, next != .blocked {
            if let guestName = pendingGuestName {
                // A guest's name, given before the profile existed.
                Task { _ = await ChatSession.shared.saveName(guestName) }
            } else if !isNamePromptPresented, !isJoiningAsGuest {
                isNamePromptPresented = true
            }
        }

        // Anyone not removed can use Questions & Chat, so the store runs for every
        // signed-in person; the family chat itself still waits for approval.
        if next != .blocked {
            ChatOutbox.shared.activate(userID: profile.id)
            ChatStore.shared.activate(userID: profile.id)
            if !wasActive || next != previous {
                Task { await ChatStore.shared.refreshAll() }
            }
        }
        // Listens for approval, removal, or a name change, live.
        startWaiting(for: profile.id)
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
            pendingGuestName = nil
            isNamePromptPresented = false
            Task { await ChatStore.shared.refreshPeople() }
            return true
        } catch {
            print("[Chat] name could not be saved")
            return false
        }
    }

    // MARK: - Listening to my own profile

    /// Listens for the moment Abhi or Alisha approve (or remove) this person, so the
    /// waiting screen opens into the chat, or Questions & Chat closes, without a relaunch.
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
        await clearLocalState()
        withAnimation(.calm) { phase = .signedOut }
    }

    /// Forgets everything this phone knows about the account that was signed in.
    private func clearLocalState() async {
        stopWaiting()
        lateProfileTask?.cancel()
        lateProfileTask = nil
        userID = nil
        me = nil
        isAnonymous = false
        pendingGuestName = nil
        isNamePromptPresented = false
        suggestedName = ""
        defaults.removeObject(forKey: Key.pushRegistration)
        ChatOutbox.shared.reset()
        await ChatStore.shared.reset()
        ChatCache.wipeAll()
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
