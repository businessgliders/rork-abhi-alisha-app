import SwiftUI
import UIKit

// MARK: - Appearance preference

/// The look of the app on this phone: follow the phone's own setting, or force light or
/// dark. Kept on the phone. Themes with a look of their own (Midnight) keep it.
nonisolated enum AppearancePreference {
    static let key = "milni.appearance"

    static var raw: String {
        get { UserDefaults.standard.string(forKey: key) ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// `nil` means "follow the phone".
    static func scheme(for rawValue: String) -> ColorScheme? {
        switch rawValue {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

/// Settings: this person's place in the wedding — profile, weddings, notifications,
/// appearance, privacy, what this phone keeps, help, and the account itself.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var session = ChatSession.shared
    private let context = WeddingContext.shared

    @State private var appearance = AppearancePreference.raw
    @State private var areLiveActivitiesOn = EventActivityController.shared.areActivitiesEnabled

    @State private var isShowingWeddings = false
    @State private var isShowingBlocked = false
    @State private var isShowingReports = false
    @State private var photoReports = PhotoReportStore.shared

    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingReset = false
    @State private var isResetting = false

    @State private var cacheBytes = SettingsCache.totalBytes()
    @State private var freedBytes: Int64 = 0

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            BrandPalette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    profileSection
                        .padding(.top, 30)
                    weddingsSection
                        .padding(.top, 42)
                    notificationsSection
                        .padding(.top, 42)
                    appearanceSection
                        .padding(.top, 42)
                    privacySection
                        .padding(.top, 42)
                    storageSection
                        .padding(.top, 42)
                    helpSection
                        .padding(.top, 42)
                    accountSection
                        .padding(.top, 42)

                    footer
                        .padding(.top, 46)
                }
                .padding(.horizontal, 20)
                .padding(.top, ScreenChrome.contentReserve)
                .padding(.bottom, 48)
                .readableWidth()
            }
            .scrollIndicators(.hidden)

            if isResetting {
                resettingOverlay
                    .transition(.opacity)
            }
        }
        .animation(.softFade, value: isResetting)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            areLiveActivitiesOn = EventActivityController.shared.areActivitiesEnabled
        }
        .sheet(isPresented: $isShowingWeddings) {
            WeddingSwitcherSheet()
        }
        .fullScreenCover(isPresented: $isShowingBlocked) {
            BlockedPeopleView()
        }
        .fullScreenCover(isPresented: $isShowingReports) {
            ReportsView()
        }
        // The same confirmations the chat used to own, with their calm failure note.
        .chatAccountDialogs(isConfirmingSignOut: $isConfirmingSignOut, isConfirmingDelete: $isConfirmingDelete)
        .alert("Reset Milni on this phone?", isPresented: $isConfirmingReset) {
            Button("Reset", role: .destructive) {
                Task { await performReset() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll be signed out and this phone will forget every wedding, draft and saved answer. Nothing is removed from the weddings themselves. To come back, sign in again and use your wedding code.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "This phone")

                Text("Settings")
                    .brandFont(.screenTitle)
                    .foregroundStyle(BrandPalette.ink)

                GoldRule(width: 58, alignment: .leading)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                BrandHaptics.soft()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BrandPalette.goldDeep)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(BrandPalette.card))
                    .overlay(Circle().stroke(BrandPalette.hairline, lineWidth: 1))
            }
            .accessibilityLabel("Close settings")
            .padding(.top, 4)
        }
    }

    // MARK: - You

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(text: "You")

            MatteCard(cornerRadius: 22) {
                HStack(spacing: 14) {
                    ChatAvatar(initials: profileInitials, size: 54, showsCrest: session.isFamilyMember)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profileName)
                            .brandFont(.chatName)
                            .foregroundStyle(BrandPalette.ink)
                            .lineLimit(1)
                        Text(session.isAnonymous
                             ? "Joined with just a name, no account"
                             : "Signed in with Apple")
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body)
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var profileName: String {
        let name = session.me?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Guest" : name
    }

    private var profileInitials: String {
        let parts = profileName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        let joined = String(letters).uppercased()
        return joined.isEmpty ? "?" : joined
    }

    // MARK: - Your weddings

    private var weddingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(text: "Your weddings")

            VStack(spacing: 10) {
                ForEach(context.myWeddings) { wedding in
                    weddingRow(wedding)
                }

                ExperienceRow(
                    symbol: "arrow.left.arrow.right",
                    title: "Switch, share or leave",
                    detail: "Share an invite, manage a wedding, or leave one."
                ) {
                    isShowingWeddings = true
                }
            }
        }
    }

    private func weddingRow(_ wedding: WeddingSummary) -> some View {
        HStack(spacing: 14) {
            Text(wedding.initials)
                .font(Milni.cormorant(19, weight: 600))
                .foregroundStyle(BrandPalette.goldDeep)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(BrandPalette.gold.opacity(0.5), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(wedding.coupleNames)
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.ink)
                    .lineLimit(1)
                Text(wedding.dateRange ?? "Dates to come")
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if let badge = badgeText(for: wedding) {
                Text(badge)
                    .font(BrandLabel.font(size: 9.5, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(BrandPalette.goldDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(BrandPalette.gold.opacity(0.14)))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(BrandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func badgeText(for wedding: WeddingSummary) -> String? {
        if wedding.status?.lowercased() == "pending" { return "Pending" }
        if wedding.role?.lowercased() == "host" { return "Host" }
        if wedding.roleBadge == "Co-host" { return "Co-host" }
        return nil
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(text: "Notifications")

            VStack(spacing: 10) {
                ExperienceRow(
                    symbol: "bell",
                    title: "Wedding updates",
                    detail: pushDetail,
                    action: openSystemSettings
                ) {
                    ExperienceStatusPill(text: session.isSignedIn && pushEnabled ? "On" : "Off",
                                         isOn: pushEnabled)
                }

                ExperienceRow(
                    symbol: "platter.filled.bottom.iphone",
                    title: "Follow along on Lock Screen",
                    detail: areLiveActivitiesOn
                        ? "Each celebration appears on your Lock Screen an hour before it begins."
                        : "Turn on Live Activities in Settings to follow each celebration.",
                    action: openSystemSettings
                ) {
                    ExperienceStatusPill(text: areLiveActivitiesOn ? "On" : "Off", isOn: areLiveActivitiesOn)
                }

                if !context.myWeddings.isEmpty {
                    Text("Choose which weddings may buzz this phone. Quiet ones still show in the app.")
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)

                    ForEach(context.myWeddings) { wedding in
                        muteRow(wedding)
                    }
                }
            }
        }
    }

    private var pushEnabled: Bool { PushRegistrar.shared.isEnabled }

    private var pushDetail: String {
        if pushEnabled { return "Schedule changes, shuttle times and moments not to miss." }
        if PushRegistrar.shared.isDenied { return "Switched off for this app. Turn them on in Settings." }
        return "Turn them on in Settings to hear about every change."
    }

    private func muteRow(_ wedding: WeddingSummary) -> some View {
        Toggle(isOn: muteBinding(wedding)) {
            HStack(spacing: 14) {
                Image(systemName: "bell.slash")
                    .symbolVariant(.none)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(BrandPalette.goldDeep)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(BrandPalette.gold.opacity(0.45), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(wedding.coupleNames)
                        .brandFont(.bodyText)
                        .foregroundStyle(BrandPalette.ink)
                        .lineLimit(1)
                    Text("Announcements and chat")
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                }
                .multilineTextAlignment(.leading)
            }
        }
        .tint(BrandPalette.goldDeep)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(BrandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
        .accessibilityHint("Stops this wedding's notifications while the app is open and on the Lock Screen")
    }

    private func muteBinding(_ wedding: WeddingSummary) -> Binding<Bool> {
        Binding(
            get: { WeddingMute.isMuted(wedding.id) },
            set: { WeddingMute.setMuted(wedding.id, $0) }
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    @Environment(\.openURL) private var openURL

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(text: "Appearance")

            MatteCard(cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Look")
                        .brandFont(.bodyText)
                        .foregroundStyle(BrandPalette.ink)

                    Picker("Look", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .tint(BrandPalette.goldDeep)

                    Text("Themes with a look of their own keep it.")
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: appearance) { _, raw in
                AppearancePreference.raw = raw
            }
        }
    }

    // MARK: - Privacy & safety

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(text: "Privacy & safety")

            VStack(spacing: 10) {
                ExperienceRow(
                    symbol: "hand.raised",
                    title: "Blocked people",
                    detail: "People whose messages you never see."
                ) {
                    isShowingBlocked = true
                }

                if session.isAdmin {
                    ExperienceRow(
                        symbol: "flag",
                        title: "Reports",
                        detail: "Messages and photos reported in this wedding."
                    ) {
                        isShowingReports = true
                    } trailing: {
                        if photoReports.openCount > 0 {
                            OpenReportsBadge(count: photoReports.openCount)
                        } else {
                            ExperienceChevron()
                        }
                    }
                    .task { await photoReports.refresh() }
                }
            }
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(text: "On this phone")

            VStack(spacing: 10) {
                ExperienceRow(
                    symbol: "arrow.down.circle",
                    title: "Clear cache",
                    detail: cacheDetail
                ) {
                    Task { await clearCache() }
                }

                if freedBytes > 0 {
                    Text("Freed \(SettingsCache.formatted(freedBytes))")
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.goldDeep)
                        .padding(.horizontal, 6)
                        .transition(.opacity)
                }

                DangerRow(
                    symbol: "arrow.counterclockwise",
                    title: "Reset this app",
                    detail: "Signs you out and forgets every wedding, draft and saved answer on this phone."
                ) {
                    isConfirmingReset = true
                }
            }
            .animation(.softFade, value: freedBytes)
        }
    }

    private var cacheDetail: String {
        "Photographs and saved copies take \(SettingsCache.formatted(cacheBytes)). Signing in is kept."
    }

    private func clearCache() async {
        URLCache.shared.removeAllCachedResponses()
        await ImageCache.shared.clearAll()
        let before = cacheBytes
        SettingsCache.clear()
        cacheBytes = SettingsCache.totalBytes()
        freedBytes = max(before - cacheBytes, 0)
    }

    // MARK: - Help & legal

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(text: "Help & legal")

            VStack(spacing: 10) {
                ExperienceRow(
                    symbol: "envelope",
                    title: "Email the team",
                    detail: "Questions about the wedding or the app."
                ) {
                    openURL(URL(string: "mailto:gurpreen@businessgliders.com")!)
                }

                ExperienceRow(
                    symbol: "hand.raised.shield",
                    title: "Privacy policy",
                    detail: "What the app keeps, and what it never does."
                ) {
                    openURL(URL(string: "https://milniapp.com/privacy")!)
                }

                ExperienceRow(
                    symbol: "ladybug",
                    title: "Report a problem",
                    detail: "Sends an email with your version and phone filled in."
                ) {
                    openURL(problemReportURL)
                }
            }
        }
    }

    private var problemReportURL: URL {
        var parts: [String] = []
        parts.append("app=\(Self.versionLine)")
        parts.append("ios=\(UIDevice.current.systemVersion)")
        parts.append("model=\(UIDevice.current.model)")
        let subject = "Milni problem report"
        let body = "What happened? \n\n\n— \(parts.joined(separator: "; "))"
        let query = "subject=\(Self.mailEncoded(subject))&body=\(Self.mailEncoded(body))"
        return URL(string: "mailto:gurpreen@businessgliders.com?\(query)")!
    }

    private static var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static func mailEncoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(text: "Account")

            if session.isAnonymous {
                Text("You joined Questions & Chat with just a name. Signing out means you'll need the wedding code to come back as you.")
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)

                // The same quiet offer as on My Experience: keep the week across devices.
                SaveYourSpotCard()
            }

            VStack(spacing: 10) {
                ExperienceRow(
                    symbol: "rectangle.portrait.and.arrow.right",
                    title: session.isAnonymous ? "Leave Questions & Chat" : "Sign out",
                    detail: session.isAnonymous
                        ? "Your messages stay in the chat."
                        : "You can sign in again any time."
                ) {
                    isConfirmingSignOut = true
                }

                DangerRow(
                    symbol: "trash",
                    title: "Delete Account",
                    detail: "Removes your name and every chat message, permanently."
                ) {
                    isConfirmingDelete = true
                }
            }
        }
    }

    // MARK: - Reset

    private var resettingOverlay: some View {
        ZStack {
            BrandPalette.background.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 18) {
                BreathingCrest(width: 92)
                Text("Putting everything away")
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
            }
        }
    }

    /// Signs out quietly, then forgets everything this phone saved: its answers, the
    /// shared wedding copy the widget reads, and every cache. The next thing on screen
    /// is the welcome, exactly as on a phone that had never opened Milni.
    private func performReset() async {
        isResetting = true
        defer { isResetting = false }
        await AccountDeletion.shared.wipePhoneState()
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Milni · version \(Self.versionLine)")
            .font(BrandLabel.font(size: 11, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(BrandPalette.body.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Milni version \(Self.versionLine)")
    }
}

// MARK: - Danger row

/// The destructive rows: same matte card, but the words are in red.
private struct DangerRow: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button {
            BrandHaptics.soft()
            action()
        } label: {
            MatteCard(cornerRadius: 22) {
                HStack(spacing: 16) {
                    Image(systemName: symbol)
                        .symbolVariant(.none)
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(BrandPalette.overdue)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(BrandPalette.overdue.opacity(0.35), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .brandFont(.bodyText)
                            .foregroundStyle(BrandPalette.overdue)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detail)
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(BrandPalette.body.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Cache measuring

/// Reads and clears the app's own caches folder: the photograph cache inside it, the
/// saved copies of schedules and content, and everything else iOS lets us keep there.
private enum SettingsCache {
    static func cachesDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    static func totalBytes() -> Int64 {
        guard let caches = cachesDirectory() else { return 0 }
        return directorySize(caches)
    }

    static func clear() {
        guard let caches = cachesDirectory() else { return }
        removeContents(of: caches)
    }

    static func removeContents(of directory: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for item in items {
            try? fm.removeItem(at: item)
        }
    }

    private static func directorySize(_ directory: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
