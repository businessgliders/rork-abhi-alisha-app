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
    /// A co-host invite from a link, waiting to be accepted.
    var pendingCohostInvite: CohostInvite?

    struct CohostInvite: Identifiable, Equatable {
        let code: String
        var id: String { code }
    }

    enum OnboardingEntry: Equatable {
        case splash
        case choose
        case joinCode
        case create
    }

    /// Joining or creating another wedding from inside one: shown in its own full-screen
    /// cover above the app, so nothing underneath (the launch gate, a refresh, a sign-in)
    /// can replace it halfway through.
    struct FlowRequest: Identifiable, Equatable {
        let id = UUID()
        let entry: OnboardingEntry
    }

    var flowRequest: FlowRequest?

    func presentFlow(_ entry: OnboardingEntry) {
        flowRequest = FlowRequest(entry: entry)
    }

    func closeFlow() {
        flowRequest = nil
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

    var theme: WeddingTheme { snapshot.resolvedTheme }

    // MARK: - What guests may do

    /// The couple's choices for guests. A setting that was never saved counts as on.
    struct GuestSettings: Codable, Equatable, Sendable {
        var chat = true
        var dms = true
        var uploads = true
        var autoApprove = true
    }

    private(set) var guestSettings = GuestSettings()

    /// Hosts always keep every tool; guests follow the couple's choices.
    var canGuestChat: Bool { isHost || guestSettings.chat }
    var canGuestDM: Bool { isHost || guestSettings.dms }
    var canGuestUpload: Bool { isHost || guestSettings.uploads }

    /// Who sees the Wedding Week upload button: the couple, and approved guests while
    /// the couple allows guest photos.
    var canUploadWeddingPhotos: Bool {
        let session = ChatSession.shared
        if session.isAdmin { return true }
        return !isSample && guestSettings.uploads && session.isFamilyMember
    }

    private static func guestSettingsKey(_ id: String) -> String {
        "milni.guestSettings.\(id.lowercased())"
    }

    /// Shows a change at once, before (or after) it reaches the server.
    func applyGuestSettings(_ settings: GuestSettings) {
        guestSettings = settings
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.guestSettingsKey(weddingID))
        }
    }

    private func restoreGuestSettings(for id: String) {
        if let data = defaults.data(forKey: Self.guestSettingsKey(id)),
           let saved = try? JSONDecoder().decode(GuestSettings.self, from: data) {
            guestSettings = saved
        } else {
            guestSettings = GuestSettings()
        }
    }

    func refreshGuestSettings() async {
        guard !isSample, !weddingID.isEmpty else { return }
        let id = weddingID
        guard let response = try? await ChatBackend.client.from("weddings")
            .select("settings,auto_approve")
            .eq("id", value: id)
            .limit(1)
            .execute(),
              let row = MilniJSON.rows(response.data).first,
              id == weddingID else { return }
        applyGuestSettings(Self.guestSettings(from: row))
    }

    static func guestSettings(from row: [String: Any]) -> GuestSettings {
        let settings = row["settings"] as? [String: Any] ?? [:]
        func flag(_ key: String) -> Bool { (settings[key] as? Bool) ?? true }
        return GuestSettings(
            chat: flag("guest_chat"),
            dms: flag("guest_dms"),
            uploads: flag("guest_photo_uploads"),
            autoApprove: (row["auto_approve"] as? Bool) ?? true
        )
    }

    /// After leaving or deleting the open wedding: go to another one, or start over.
    func didLeaveCurrentWedding() async {
        let leftID = weddingID.lowercased()
        await refreshMyWeddings()
        myWeddings.removeAll { $0.id.lowercased() == leftID }
        if let next = myWeddings.first {
            open(next)
        } else {
            defaults.removeObject(forKey: Key.currentWeddingID)
            role = nil
            status = nil
            goToOnboarding(.choose)
        }
    }

    /// The theme's appearance: forced light or dark, or nil to follow the phone.
    /// Midnight always runs dark.
    var colorScheme: ColorScheme? {
        switch snapshot.resolvedTheme.forcedDark {
        case true?: return .dark
        case false?: return .light
        case nil: return nil
        }
    }

    private init() {
        BrandTheme.theme = snapshot.resolvedTheme
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

    private func show(_ incoming: WeddingSnapshot, sample: Bool, role: String? = nil, status: String? = nil) {
        var snapshot = incoming.keepingNames(from: self.snapshot)
        // A list row may arrive without the theme: keep the one already saved for it.
        if snapshot.theme == nil, snapshot.id.lowercased() == self.snapshot.id.lowercased() {
            snapshot.theme = self.snapshot.theme
        }
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
        BrandTheme.theme = snapshot.resolvedTheme

        if previousID.lowercased() != snapshot.id.lowercased() {
            Task { await Self.resetStoresForNewWedding() }
        }
        restoreGuestSettings(for: snapshot.id)
        if !sample { Task { await self.refreshGuestSettings() } }
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
            var snapshot = fresh.snapshot.keepingNames(from: self.snapshot)
            if snapshot.theme == nil { snapshot.theme = self.snapshot.theme }
            if snapshot != self.snapshot {
                let presetChanged = snapshot.resolvedTheme != self.snapshot.resolvedTheme
                ActiveWedding.save(snapshot)
                BrandTheme.theme = snapshot.resolvedTheme
                withAnimation(.easeInOut(duration: 0.7)) {
                    self.snapshot = snapshot
                    if presetChanged { shellKey = UUID() }
                }
                WidgetCenter.shared.reloadAllTimelines()
                WatchBridge.shared.send(snapshot)
            }
        }
        await refreshMembership()
        await refreshGuestSettings()
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
        // Once they land on Home, ask about wedding updates.
        PushRegistrar.shared.offerAfterJoin()
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
        preset: String,
        venue: CoupleVenue? = nil,
        events: [(title: String, kind: String)] = []
    ) async throws -> WeddingSummary {
        let timezone = venue?.timeZone ?? .current
        let id = try await MilniAPI.shared.createWedding(
            partnerOne: partnerOne,
            partnerTwo: partnerTwo,
            start: start,
            end: end,
            timezone: timezone,
            preset: preset
        )
        // The venue and the full preset theme are written onto the new row.
        var fields: [String: AnyJSON] = ["theme": HostAPI.anyJSON(WeddingTheme.preset(preset).json)]
        if let venue {
            fields["venue_name"] = .string(venue.name)
            fields["address"] = venue.address.isEmpty ? .null : .string(venue.address)
            fields["city"] = venue.city.isEmpty ? .null : .string(venue.city)
            fields["country"] = venue.country.isEmpty ? .null : .string(venue.country)
            fields["lat"] = .double(venue.latitude)
            fields["lng"] = .double(venue.longitude)
            fields["timezone"] = .string(timezone.identifier)
        }
        do {
            try await HostAPI.shared.updateWedding(weddingID: id, fields: fields)
        } catch {
            print("[Milni] venue/theme update failed")
        }
        do {
            try await HostAPI.shared.insertStarterEvents(weddingID: id, events: events)
        } catch {
            print("[Milni] starter events failed")
        }
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
                "timezone": timezone.identifier,
                "venue_name": venue?.name ?? NSNull(),
                "city": venue?.city ?? NSNull(),
                "country": venue?.country ?? NSNull(),
                "theme": WeddingTheme.preset(preset).json,
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
        // The join cover, or onboarding, picks the code up from wherever it is.
        if flowRequest != nil || stage == .onboarding { return true }
        if stage == .wedding {
            presentFlow(.joinCode)
        } else {
            goToOnboarding(.joinCode)
        }
        return true
    }

    // MARK: - Co-host invites

    /// `milni://cohost/CODE` or `https://milniapp.com/c/CODE`.
    nonisolated static func cohostCode(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let candidate: String?
        if url.scheme?.lowercased() == "milni" {
            if url.host?.lowercased() == "cohost" {
                candidate = parts.first
            } else if parts.first?.lowercased() == "cohost" {
                candidate = parts.dropFirst().first
            } else {
                candidate = nil
            }
        } else if let host = url.host?.lowercased(), host.hasSuffix("milniapp.com"), parts.first?.lowercased() == "c" {
            candidate = parts.dropFirst().first
        } else {
            candidate = nil
        }
        guard let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 4, raw.count <= 64,
              raw.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return raw
    }

    /// A co-host link opened from anywhere: shown as an invitation sheet.
    func handleCohostLink(_ url: URL) -> Bool {
        guard let code = Self.cohostCode(from: url) else { return false }
        pendingCohostInvite = CohostInvite(code: code)
        return true
    }

    /// Accepts a co-host invite, then opens that wedding as a co-host.
    func acceptCohost(code: String) async throws {
        let weddingID = try await HostAPI.shared.acceptCohostInvite(code: code)
        if let weddingID, !weddingID.isEmpty, weddingID.lowercased() != self.weddingID.lowercased() || stage != .wedding {
            try await open(weddingID: weddingID)
        }
        await refreshMembership()
        await refreshMyWeddings()
    }

    /// Before a push opens its screen: switch to the wedding it was sent from.
    func prepareForPush(weddingID: String?) async {
        guard let weddingID, !weddingID.isEmpty, weddingID.lowercased() != self.weddingID.lowercased() else { return }
        try? await open(weddingID: weddingID)
    }
}
