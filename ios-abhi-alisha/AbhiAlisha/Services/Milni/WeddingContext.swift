import Foundation
import Observation
import Supabase
import SwiftUI
import WidgetKit

/// The wedding the app is showing, and whether the person still needs onboarding.
///
/// Every tab reads the current wedding from here. Opening a wedding saves it for the
/// widgets and Watch, applies its colours, and recreates the wedding screens so each
/// store starts clean for that wedding.
@Observable
final class WeddingContext {
    static let shared = WeddingContext()

    enum Stage: Equatable {
        case launching
        case onboarding
        case wedding
    }

    private(set) var stage: Stage = .launching
    private(set) var snapshot: WeddingSnapshot = ActiveWedding.snapshot
    private(set) var myWeddings: [WeddingSummary] = []
    private(set) var role: String?
    private(set) var status: String?
    /// Browsing the sample wedding, signed out and read-only.
    private(set) var isSample = false
    /// Changes every time a wedding opens, so the wedding screens are rebuilt.
    private(set) var shellKey = UUID()
    /// The onboarding screen to open on, when sent there from inside a wedding.
    var onboardingEntry: OnboardingEntry = .splash
    /// A join code from a link, waiting for the onboarding flow to pick it up.
    var pendingJoinCode: String?

    enum OnboardingEntry: Equatable {
        case splash
        case choose
        case joinCode
        case create
    }

    private let defaults = UserDefaults.standard
    private enum Key {
        static let currentWeddingID = "milni.currentWeddingId"
        static let hasSeenIntro = "milni.hasSeenIntro"
        static let legacyChecked = "milni.legacyChecked"
        static let legacyAbhi = "milni.legacyAbhi"
    }

    private var didBootstrap = false

    var weddingID: String { snapshot.id }

    var hasSeenIntro: Bool {
        get { defaults.bool(forKey: Key.hasSeenIntro) }
        set { defaults.set(newValue, forKey: Key.hasSeenIntro) }
    }

    /// The couple and their co-hosts, once approved.
    var isHost: Bool {
        guard !isSample else { return false }
        let role = role?.lowercased() ?? ""
        return ["host", "cohost", "co-host", "co_host"].contains(role) && status?.lowercased() == "approved"
    }

    var theme: BrandThemeColors { BrandTheme.colors(for: snapshot.preset) }

    /// Midnight always runs dark; blush and emerald always light; ivory follows the phone.
    var colorScheme: ColorScheme? {
        switch snapshot.preset.lowercased() {
        case "midnight": return .dark
        case "blush", "emerald": return .light
        default: return nil
        }
    }

    private init() {
        BrandTheme.preset = snapshot.preset
    }

    // MARK: - Launch

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        migrateLegacyIfNeeded()

        // A wedding opened before: show it straight away from the phone, refresh behind.
        if let stored = defaults.string(forKey: Key.currentWeddingID), !stored.isEmpty {
            let cached = ActiveWedding.snapshot
            let snapshot = cached.id.lowercased() == stored.lowercased()
                ? cached
                : (stored.lowercased() == ActiveWedding.sampleID ? .sample : cached)
            show(snapshot, sample: false)
            Task { await self.refreshCurrent() }
            return
        }

        // Signed in from before: open their weddings.
        if (try? await ChatBackend.client.auth.session) != nil {
            do {
                let weddings = try await MilniAPI.shared.myWeddings()
                myWeddings = weddings
                if let first = weddings.first {
                    show(first.snapshot, sample: false, role: first.role, status: first.status)
                    Task { await self.refreshCurrent() }
                    return
                }
            } catch {
                print("[Milni] my weddings unavailable")
            }
        }
        goToOnboarding(.splash)
    }

    /// Guests who used the app before Milni keep landing in Abhi & Alisha.
    private func migrateLegacyIfNeeded() {
        guard !defaults.bool(forKey: Key.legacyChecked) else { return }
        defaults.set(true, forKey: Key.legacyChecked)
        guard defaults.string(forKey: Key.currentWeddingID) == nil else { return }
        let fm = FileManager.default
        var evidence: [URL] = []
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.businessgliders.abhialisha") {
            evidence.append(group.appending(path: "schedule-events.json"))
        }
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            evidence.append(caches.appending(path: "schedule-events.json"))
            evidence.append(caches.appending(path: "wedding-content.json"))
        }
        let usedBefore = evidence.contains { fm.fileExists(atPath: $0.path) }
            || defaults.object(forKey: "announcements.lastOpenedAt") != nil
        if usedBefore {
            defaults.set(ActiveWedding.sampleID, forKey: Key.currentWeddingID)
            defaults.set(true, forKey: Key.legacyAbhi)
            hasSeenIntro = true
            ActiveWedding.save(.sample)
        }
    }

    // MARK: - Opening weddings

    /// Opens a wedding by id: from the list if known, else from the server.
    func open(weddingID: String) async throws {
        let id = weddingID.lowercased()
        if let known = myWeddings.first(where: { $0.id.lowercased() == id }) {
            open(known)
            return
        }
        guard let summary = try await MilniAPI.shared.wedding(id: id) else { throw MilniError.notFound }
        open(summary)
        await refreshMembership()
    }

    func open(_ summary: WeddingSummary) {
        show(summary.snapshot, sample: false, role: summary.role, status: summary.status)
        // The join and list RPCs leave out main_event_ref, rsvp_url and lat/lng: read the
        // wedding row itself so the countdown and weather use them straight away.
        Task { await self.refreshCurrent() }
    }

    /// The sample wedding, read-only and signed out. Not remembered across launches.
    func openSample() async {
        var snapshot = WeddingSnapshot.sample
        if let fresh = try? await MilniAPI.shared.wedding(slug: "abhi-alisha") {
            snapshot = fresh.snapshot
        }
        show(snapshot, sample: true)
    }

    /// Switches to another of my weddings with a cross-fade into its colours.
    func switchTo(_ summary: WeddingSummary) {
        guard summary.id.lowercased() != weddingID.lowercased() || isSample else {
            // Already the open wedding (re-entering its code): just go back to it.
            returnToWedding()
            return
        }
        open(summary)
    }

    func goToOnboarding(_ entry: OnboardingEntry) {
        onboardingEntry = entry
        withAnimation(.easeInOut(duration: 0.6)) { stage = .onboarding }
    }

    /// Back out of onboarding to the wedding that was open, if there was one.
    func returnToWedding() {
        let hasWedding = isSample || defaults.string(forKey: Key.currentWeddingID) != nil
        guard hasWedding, !snapshot.id.isEmpty else {
            onboardingEntry = .choose
            return
        }
        withAnimation(.easeInOut(duration: 0.6)) { stage = .wedding }
    }

    private func show(_ snapshot: WeddingSnapshot, sample: Bool, role: String? = nil, status: String? = nil) {
        let changed = snapshot.id.lowercased() != self.snapshot.id.lowercased() || sample != isSample || stage != .wedding
        let previousID = self.snapshot.id
        self.role = role
        self.status = status
        isSample = sample
        ChatSession.shared.setMembership(role: role, status: status, weddingID: snapshot.id, isSample: sample)

        if sample {
            defaults.removeObject(forKey: Key.currentWeddingID)
        } else {
            defaults.set(snapshot.id.lowercased(), forKey: Key.currentWeddingID)
        }
        ActiveWedding.save(snapshot)
        BrandTheme.preset = snapshot.preset

        if previousID.lowercased() != snapshot.id.lowercased() {
            Task { await Self.resetStoresForNewWedding() }
        }
        withAnimation(.easeInOut(duration: 0.7)) {
            self.snapshot = snapshot
            if changed { shellKey = UUID() }
            stage = .wedding
        }
        WidgetCenter.shared.reloadAllTimelines()
        WatchBridge.shared.send(snapshot)
    }

    private static func resetStoresForNewWedding() async {
        await ChatStore.shared.switchWedding()
        OutfitStore.shared.switchWedding()
        WeddingPhotoStore.shared.switchWedding()
        NotificationsStore.shared.switchWedding()
    }

    // MARK: - Refreshing

    /// Brings the open wedding's details, my role and my list of weddings up to date.
    func refreshCurrent() async {
        guard !isSample else { return }
        if let fresh = try? await MilniAPI.shared.wedding(id: weddingID), !fresh.id.isEmpty {
            let snapshot = fresh.snapshot
            if snapshot != self.snapshot {
                let presetChanged = snapshot.preset != self.snapshot.preset
                ActiveWedding.save(snapshot)
                BrandTheme.preset = snapshot.preset
                withAnimation(.easeInOut(duration: 0.7)) {
                    self.snapshot = snapshot
                    if presetChanged { shellKey = UUID() }
                }
                WidgetCenter.shared.reloadAllTimelines()
                WatchBridge.shared.send(snapshot)
            }
        }
        await refreshMembership()
        await refreshMyWeddings()
    }

    func refreshMyWeddings() async {
        guard (try? await ChatBackend.client.auth.session) != nil else { return }
        if let weddings = try? await MilniAPI.shared.myWeddings() {
            myWeddings = weddings
            if let mine = weddings.first(where: { $0.id.lowercased() == weddingID.lowercased() }),
               role == nil, mine.role != nil {
                role = mine.role
                status = mine.status
                ChatSession.shared.setMembership(role: role, status: status, weddingID: weddingID, isSample: isSample)
            }
        }
    }

    func refreshMembership() async {
        guard !isSample else { return }
        var resolved = ChatSession.shared.userID?.lower
        if resolved == nil {
            resolved = (try? await ChatBackend.client.auth.session)?.user.id.lower
        }
        guard let userID = resolved else { return }
        do {
            if let membership = try await MilniAPI.shared.membership(weddingID: weddingID, userID: userID) {
                role = membership.role
                status = membership.status
            } else if defaults.bool(forKey: Key.legacyAbhi), weddingID.lowercased() == ActiveWedding.sampleID {
                // A guest from before Milni: add them to Abhi & Alisha once they're signed in.
                _ = try? await MilniAPI.shared.join(code: "ABHIALISHA")
                if let membership = try? await MilniAPI.shared.membership(weddingID: weddingID, userID: userID) {
                    role = membership.role
                    status = membership.status
                }
            }
            ChatSession.shared.setMembership(role: role, status: status, weddingID: weddingID, isSample: isSample)
        } catch {
            print("[Milni] membership unavailable")
        }
    }

    /// Called when someone signs in or out while a wedding is open.
    func sessionDidChange() {
        Task {
            await refreshMembership()
            await refreshMyWeddings()
        }
    }

    // MARK: - Joining and creating

    /// Joins with a code, then opens that wedding.
    func join(code: String, preview: WeddingSummary) async throws {
        let joinedID = try await MilniAPI.shared.join(code: code)
        let id = joinedID ?? preview.id
        var summary = preview
        if summary.id.lowercased() != id.lowercased(),
           let fresh = try? await MilniAPI.shared.wedding(id: id) {
            summary = fresh
        }
        if let userID = ChatSession.shared.userID?.lower,
           let membership = try? await MilniAPI.shared.membership(weddingID: summary.id, userID: userID) {
            summary.role = membership.role
            summary.status = membership.status
        } else {
            summary.role = summary.role ?? "guest"
            summary.status = summary.status ?? "pending"
        }
        pendingSummary = summary
    }

    /// The wedding just joined or created, opened once its welcome screen is done.
    private(set) var pendingSummary: WeddingSummary?

    func enterPending() {
        guard let summary = pendingSummary else { return }
        pendingSummary = nil
        if !myWeddings.contains(where: { $0.id == summary.id }) { myWeddings.append(summary) }
        open(summary)
    }

    func create(
        partnerOne: String,
        partnerTwo: String,
        start: Date,
        end: Date,
        preset: String
    ) async throws -> WeddingSummary {
        let id = try await MilniAPI.shared.createWedding(
            partnerOne: partnerOne,
            partnerTwo: partnerTwo,
            start: start,
            end: end,
            timezone: .current,
            preset: preset
        )
        var summary: WeddingSummary
        if let fresh = try? await MilniAPI.shared.wedding(id: id) {
            summary = fresh
        } else {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            summary = WeddingSummary(row: [
                "id": id,
                "title": "\(partnerOne) & \(partnerTwo)",
                "partner_one": partnerOne,
                "partner_two": partnerTwo,
                "start_date": formatter.string(from: start),
                "end_date": formatter.string(from: end),
                "timezone": TimeZone.current.identifier,
                "theme": ["preset": preset],
            ])
        }
        summary.role = "host"
        summary.status = "approved"
        pendingSummary = summary
        return summary
    }

    // MARK: - Links

    /// Reads a join code out of a link: milniapp.com/j/CODE or milni://join/CODE.
    nonisolated static func joinCode(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let candidate: String?
        if url.scheme?.lowercased() == "milni" {
            if url.host?.lowercased() == "join" {
                candidate = parts.first
            } else if parts.first?.lowercased() == "join" {
                candidate = parts.dropFirst().first
            } else {
                candidate = nil
            }
        } else if let host = url.host?.lowercased(), host.hasSuffix("milniapp.com"), parts.first?.lowercased() == "j" {
            candidate = parts.dropFirst().first
        } else {
            candidate = nil
        }
        guard let code = candidate.map(normalize), (6...10).contains(code.count) else { return nil }
        return code
    }

    nonisolated static func normalize(_ text: String) -> String {
        String(text.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(10))
    }

    /// A join link opened from anywhere: shown as an invitation over whatever is on screen.
    func handleJoinLink(_ url: URL) -> Bool {
        guard let code = Self.joinCode(from: url) else { return false }
        pendingJoinCode = code
        if stage != .onboarding { goToOnboarding(.joinCode) }
        return true
    }

    /// Before a push opens its screen: switch to the wedding it was sent from.
    func prepareForPush(weddingID: String?) async {
        guard let weddingID, !weddingID.isEmpty, weddingID.lowercased() != self.weddingID.lowercased() else { return }
        try? await open(weddingID: weddingID)
    }
}
