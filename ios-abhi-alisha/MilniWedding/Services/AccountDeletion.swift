import AuthenticationServices
import Foundation
import Observation
import Supabase
import SwiftUI
import UIKit

/// One-time wipe of everything this phone saved: the signed-in session, defaults,
/// app-group files, caches and Spotlight entries. Used by "Reset app" and by account deletion.
nonisolated enum LocalWipe {
    static func cachesDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    /// Deletes everything inside a folder, keeping the folder itself.
    static func removeContents(of directory: URL) {
        let contents: [URL]
        if let listed = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            contents = listed
        } else {
            contents = []
        }
        for item in contents {
            do {
                try FileManager.default.removeItem(at: item)
            } catch {
                print("[Account] could not clear \(item.lastPathComponent)")
            }
        }
    }
}

/// Runs "Delete account": checks for hosted weddings first, asks Apple to confirm
/// for Apple accounts, then asks the server to remove the account. On success the
/// phone is wiped and the person lands on the welcome screen with a short notice.
@Observable
final class AccountDeletion {
    static let shared = AccountDeletion()

    /// True from the moment the request is sent until an outcome is on screen.
    private(set) var isDeleting = false
    /// Shows the plain-words failure alert ("There was a problem...").
    var didFail = false
    /// Weddings this person still hosts; deletion waits until they hand one over.
    private(set) var hostingWeddings: [HostedWedding] = []
    var isHostingSheetPresented = false
    /// The themed confirmation step for Apple accounts, with the Apple copy.
    var isConfirmSheetPresented = false
    /// Set once the server confirmed the deletion, before the phone is wiped.
    private(set) var didFinishDeletion = false
    /// Brief line shown on the welcome screen after a successful deletion.
    private(set) var deletionNotice: String?

    private var noticeTask: Task<Void, Never>?

    /// Named accounts all sign in with Apple; guests are name-only and skip the Apple step.
    private var isAppleAccount: Bool {
        let session = ChatSession.shared
        return session.isSignedIn && !session.isAnonymous
    }

    /// Entry point once the person has confirmed they want to delete.
    @discardableResult
    func start() async -> Bool {
        guard ChatSession.shared.isSignedIn, !isDeleting else { return false }

        // Hosts first: nothing is deleted while a wedding is theirs to host.
        let hosted = WeddingContext.shared.myWeddings.filter {
            $0.role?.lowercased() == "host" && $0.status?.lowercased() != "removed"
        }
        if !hosted.isEmpty {
            hostingWeddings = hosted.map {
                HostedWedding(id: $0.id, title: $0.coupleNames)
            }
            isHostingSheetPresented = true
            return false
        }

        var appleCode: String?
        if isAppleAccount {
            let outcome = await AppleDeletionCoordinator.shared.requestCode()
            switch outcome {
            case .cancelled:
                // The Apple sheet was dismissed: the deletion is abandoned, quietly.
                return false
            case .code(let code):
                appleCode = code
            case .noCode:
                appleCode = nil
            }
        }

        return await sendDeletionRequest(appleCode: appleCode)
    }

    private func sendDeletionRequest(appleCode: String?) async -> Bool {
        isDeleting = true
        defer { isDeleting = false }
        do {
            let session = try await ChatBackend.client.auth.session
            var request = URLRequest(
                url: ChatBackend.url.appending(path: "functions/v1/delete-account")
            )
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(ChatBackend.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let appleCode {
                request.httpBody = try JSONSerialization.data(
                    withJSONObject: ["apple_authorization_code": appleCode]
                )
            } else {
                request.httpBody = Data("{}".utf8)
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                didFail = true
                return false
            }
            if http.statusCode == 409 {
                let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let parsed = Self.hostWeddings(from: payload?["weddings"])
                hostingWeddings = parsed
                guard !parsed.isEmpty else {
                    didFail = true
                    return false
                }
                isHostingSheetPresented = true
                return false
            }
            guard (200..<300).contains(http.statusCode),
                  let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  payload["ok"] as? Bool == true else {
                didFail = true
                return false
            }
            await finishDeletion()
            return true
        } catch {
            print("[Account] deletion could not reach the server")
            didFail = true
            return false
        }
    }

    /// Clears the phone and shows the welcome screen with a short notice.
    func wipePhoneState() async {
        await ChatSession.shared.signOut()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        let appGroup = WeddingGroup.identifier
        UserDefaults(suiteName: appGroup)?.removePersistentDomain(forName: appGroup)
        if let group = WeddingGroup.containerURL {
            LocalWipe.removeContents(of: group)
        }
        if let caches = LocalWipe.cachesDirectory() {
            LocalWipe.removeContents(of: caches)
        }
        URLCache.shared.removeAllCachedResponses()
        WeddingContext.shared.goToOnboarding(.splash)
    }

    private func finishDeletion() async {
        await wipePhoneState()
        didFinishDeletion = true
        deletionNotice = String(localized: "Your account has been deleted")
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.deletionNotice = nil
        }
    }

    // MARK: - Host list from the 409 answer

    private static func hostWeddings(from payload: Any?) -> [HostedWedding] {
        guard let rows = payload as? [[String: Any]] else { return [] }
        let known = WeddingContext.shared.myWeddings
        return rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let title = (row["title"] as? String) ?? ""
            let summary = known.first { $0.id == id }
            return HostedWedding(id: id, title: summary?.coupleNames ?? title)
        }
    }
}

/// One wedding the person still hosts, shown in the "hand over hosting" sheet.
struct HostedWedding: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

/// Asks Apple for a fresh authorization code as the final confirmation step.
/// The sheet is presented over the key window; any cancel or failure ends quietly.
private final class AppleDeletionCoordinator: NSObject, @unchecked Sendable {
    static let shared = AppleDeletionCoordinator()

    enum Outcome: Sendable {
        case code(String)
        case noCode
        case cancelled
    }

    private enum Ask {
        case waiting(CheckedContinuation<Outcome, Never>)
        case finished
    }

    private let lock = NSLock()
    private var ask: Ask?
    /// The window is captured when the request starts, so the sheet always has an anchor.
    private var anchor: ASPresentationAnchor = .init()

    @MainActor
    func requestCode() async -> Outcome {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        anchor = Self.keyWindow() ?? ASPresentationAnchor()
        return await withCheckedContinuation { continuation in
            lock.lock()
            if ask != nil {
                lock.unlock()
                continuation.resume(returning: .cancelled)
                return
            }
            ask = .waiting(continuation)
            lock.unlock()
            controller.performRequests()
        }
    }

    private func finish(_ outcome: Outcome) {
        lock.lock()
        let current = ask
        ask = .finished
        lock.unlock()
        guard case .waiting(let continuation) = current else { return }
        continuation.resume(returning: outcome)
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

extension AppleDeletionCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.noCode)
            return
        }
        guard let data = credential.authorizationCode, let code = String(data: data, encoding: .utf8),
              !code.isEmpty else {
            // Apple confirmed the person, but sent no code: the server simply skips revocation.
            finish(.noCode)
            return
        }
        finish(.code(code))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        // A dismissed sheet (or any Apple-side hiccup) cancels the deletion with no error shown.
        finish(.cancelled)
    }
}

extension AppleDeletionCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }
}
