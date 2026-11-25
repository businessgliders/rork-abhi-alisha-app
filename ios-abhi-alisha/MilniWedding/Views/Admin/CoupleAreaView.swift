import Supabase
import SwiftUI

/// Where the couple's area leads.
enum CoupleRoute: Hashable {
    case checklist
    case events
    case announcements
    case photos
    case content
    case details
    case look
    case guests
}

/// The couple's area: one place for the host and co-hosts to plan the wedding and
/// decide what guests can do. Dressed in the wedding's own theme, light or dark.
struct CoupleAreaView: View {
    @Environment(AdminSession.self) private var admin
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let context = WeddingContext.shared

    @State private var tasks: WeddingTasksStore
    @State private var path: [CoupleRoute] = []
    @State private var members: [HostMember] = []
    @State private var eventCount: Int?
    @State private var code: String?
    @State private var codeFailed = false
    @State private var settings: WeddingContext.GuestSettings
    @State private var savingSetting: String?
    @State private var busy: Set<String> = []
    @State private var error: String?
    @State private var isShareKitPresented = false
    @State private var faceIDOn: Bool
    @State private var isConfirmingLeave = false
    @State private var isLeaving = false

    init() {
        let context = WeddingContext.shared
        _tasks = State(initialValue: WeddingTasksStore(weddingID: context.weddingID))
        _settings = State(initialValue: context.guestSettings)
        _faceIDOn = State(initialValue: AdminSession.isFaceIDLockOn(for: context.weddingID))
    }

    private var weddingID: String { context.weddingID }
    private var snapshot: WeddingSnapshot { context.snapshot }
    private var isOwner: Bool { context.role?.lowercased() == "host" }
    private var isMilniWedding: Bool { weddingID.lowercased() == ActiveWedding.sampleID.lowercased() }

    private var pending: [HostMember] {
        members.filter { $0.status.lowercased() == "pending" }
            .sorted { ($0.joinedAt ?? .distantPast) > ($1.joinedAt ?? .distantPast) }
    }

    private var fade: Animation { reduceMotion ? .easeInOut(duration: 0.25) : .calm }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    VStack(alignment: .leading, spacing: 34) {
                        if let error {
                            AdminNote(text: error, symbol: "exclamationmark.circle")
                                .transition(.opacity)
                        }
                        glance
                        if !pending.isEmpty {
                            waiting
                                .transition(.opacity)
                        }
                        planSection
                        guestSection
                        weddingSection
                        exitSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 26)
                    .padding(.bottom, 56)
                }
                .readableWidth(640)
            }
            .scrollIndicators(.hidden)
            .background(backdrop)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await load() }
            .navigationDestination(for: CoupleRoute.self) { route in
                destination(route)
            }
        }
        .tint(BrandPalette.goldDeep)
        .animation(fade, value: pending.map(\.id))
        .animation(fade, value: error)
        .task { await load() }
        .task { await tasks.refresh() }
        .onDisappear { tasks.stopListening() }
        .sheet(isPresented: $isShareKitPresented) {
            HostShareKit(code: $code)
                .environment(\.colorScheme, .light)
        }
        .confirmationDialog("Leave this wedding?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await leave() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop being a co-host of \(snapshot.coupleNames). The couple can invite you again.")
        }
        .onAppear {
            // Opened from the wedding switcher's "Manage": go straight to that screen.
            if let route = admin.initialRoute {
                admin.initialRoute = nil
                path = [route]
            }
        }
    }

    // MARK: - Header

    private var backdrop: some View {
        ZStack(alignment: .top) {
            BrandPalette.background
            LinearGradient(
                colors: [BrandPalette.goldPale.opacity(0.35), BrandPalette.background.opacity(0)],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            CrestWatermark(width: 150)
                .opacity(0.55)
                .padding(.top, 54)
                .padding(.trailing, 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: "Couple's area", size: 10.5)

                Text(snapshot.coupleNames)
                    .brandFont(.screenTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 10)
                    .padding(.trailing, 70)

                if !snapshot.cityAndDates.isEmpty {
                    Text(snapshot.cityAndDates)
                        .brandFont(.bodyItalic)
                        .foregroundStyle(BrandPalette.body)
                        .padding(.top, 6)
                }

                HStack(spacing: 8) {
                    chip(symbol: "key.horizontal", text: isOwner ? "You're the host" : "You're a co-host")
                    chip(symbol: "paintpalette", text: "\(themeName) theme")
                }
                .padding(.top, 16)

                GoldRule(width: 52, alignment: .leading)
                    .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 72)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                BrandHaptics.tick()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BrandPalette.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(BrandPalette.card))
                    .overlay(Circle().stroke(BrandPalette.hairline, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close the couple's area")
            .padding(.top, 14)
            .padding(.trailing, 14)
        }
    }

    private var themeName: String {
        switch snapshot.resolvedTheme.preset.lowercased() {
        case "ivory": return "Ivory"
        case "blush": return "Blush"
        case "emerald": return "Emerald"
        case "midnight": return "Midnight"
        default: return "Custom"
        }
    }

    private func chip(symbol: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(BrandLabel.font(size: 11, weight: .semibold))
                .tracking(0.6)
        }
        .foregroundStyle(BrandPalette.goldDeep)
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(Capsule().fill(BrandPalette.card))
        .overlay(Capsule().stroke(BrandPalette.gold.opacity(0.4), lineWidth: 0.75))
    }

    // MARK: - At a glance

    private var glance: some View {
        HStack(spacing: 10) {
            tile(
                value: tasks.totalCount == 0 && !tasks.hasLoadedFromServer ? "–" : "\(tasks.completedCount)/\(tasks.totalCount)",
                label: "Tasks done",
                route: .checklist
            )
            tile(value: eventCount.map(String.init) ?? "–", label: "Events", route: .events)
            tile(value: "\(pending.count)", label: "Waiting", route: .guests, isHighlighted: !pending.isEmpty)
        }
    }

    private func tile(value: String, label: String, route: CoupleRoute, isHighlighted: Bool = false) -> some View {
        Button {
            BrandHaptics.tick()
            path.append(route)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(isHighlighted ? BrandPalette.goldDeep : BrandPalette.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Eyebrow(text: label, color: BrandPalette.body, size: 9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(BrandPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isHighlighted ? BrandPalette.gold.opacity(0.7) : BrandPalette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(label.lowercased())")
    }

    // MARK: - Waiting for approval

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Waiting for you", size: 10)
            MatteCard(cornerRadius: 20) {
                VStack(spacing: 0) {
                    ForEach(Array(pending.enumerated()), id: \.element.id) { index, member in
                        if index > 0 { divider }
                        pendingRow(member)
                    }
                }
            }
        }
    }

    private func pendingRow(_ member: HostMember) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.ink)
                    .lineLimit(1)
                Text("Wants to join")
                    .font(BrandLabel.font(size: 11, weight: .regular))
                    .foregroundStyle(BrandPalette.body)
            }
            Spacer(minLength: 8)
            if busy.contains(member.id) {
                ProgressView()
            } else {
                Button("Decline") { Task { await setStatus(member, "blocked") } }
                    .font(BrandLabel.font(size: 12, weight: .semibold))
                    .foregroundStyle(BrandPalette.body)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                Button {
                    Task { await setStatus(member, "approved") }
                } label: {
                    Text("Approve")
                        .font(BrandLabel.font(size: 12, weight: .semibold))
                        .foregroundStyle(BrandPalette.card)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(BrandPalette.goldDeep))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Plan

    private var planSection: some View {
        section("Plan") {
            row("Checklist", symbol: "checklist", detail: tasks.totalCount > 0 ? "\(tasks.completedCount) of \(tasks.totalCount)" : nil, route: .checklist)
            divider
            row("Schedule & events", symbol: "calendar", detail: eventCount.map { $0 == 1 ? "1 event" : "\($0) events" }, route: .events)
            divider
            row("Announcements", symbol: "megaphone", route: .announcements)
            divider
            row("Gallery & albums", symbol: "photo.on.rectangle", route: .photos)
            divider
            row("FAQ, travel & stay", symbol: "book.closed", route: .content)
        }
    }

    // MARK: - Guests can…

    private var guestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Guests can…", size: 10)
            MatteCard(cornerRadius: 20) {
                VStack(spacing: 0) {
                    settingToggle(
                        "Join only once you approve them",
                        detail: "New guests wait for a host or co-host to let them in.",
                        key: "auto_approve",
                        isOn: Binding(get: { !settings.autoApprove }, set: { newValue in
                            update(key: "auto_approve") { $0.autoApprove = !newValue }
                        })
                    )
                    divider
                    settingToggle(
                        "Chat with everyone",
                        detail: "The shared Questions & Chat room.",
                        key: "guest_chat",
                        isOn: Binding(get: { settings.chat }, set: { newValue in
                            update(key: "guest_chat") { $0.chat = newValue }
                        })
                    )
                    divider
                    settingToggle(
                        "Send private messages",
                        detail: "Start one-to-one and group messages.",
                        key: "guest_dms",
                        isOn: Binding(get: { settings.dms }, set: { newValue in
                            update(key: "guest_dms") { $0.dms = newValue }
                        })
                    )
                    divider
                    settingToggle(
                        "Upload photos",
                        detail: "Add their own photos to Wedding Week.",
                        key: "guest_photo_uploads",
                        isOn: Binding(get: { settings.uploads }, set: { newValue in
                            update(key: "guest_photo_uploads") { $0.uploads = newValue }
                        })
                    )
                }
            }
            Text("Hosts and co-hosts can always do everything.")
                .brandFont(.bodySmall)
                .foregroundStyle(BrandPalette.body.opacity(0.8))
                .padding(.leading, 4)
        }
    }

    private func settingToggle(_ title: String, detail: String, key: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.ink)
                Text(detail)
                    .font(BrandLabel.font(size: 11.5, weight: .regular))
                    .foregroundStyle(BrandPalette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(BrandPalette.goldDeep)
        .disabled(savingSetting == key)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Your wedding

    private var weddingSection: some View {
        section("Your wedding") {
            row("Names, dates & venue", symbol: "heart.text.square", route: .details)
            divider
            row("Look, crest & cover photos", symbol: "paintpalette", route: .look)
            divider
            row("People", symbol: "person.2", detail: approvedCountText, route: .guests)
            divider
            codeRow
            divider
            faceIDRow
            if isMilniWedding {
                divider
                ThankYouPreviewToggle()
                    .padding(12)
            }
        }
    }

    private var approvedCountText: String? {
        let approved = members.filter { $0.status.lowercased() == "approved" }.count
        return approved == 0 ? nil : "\(approved)"
    }

    private var codeRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "qrcode")
                .font(.system(size: 15))
                .foregroundStyle(BrandPalette.goldDeep)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: "Join code", color: BrandPalette.body, size: 9)
                if let code {
                    Text(code)
                        .font(BrandLabel.font(size: 17, weight: .semibold))
                        .tracking(4)
                        .foregroundStyle(BrandPalette.ink)
                        .textSelection(.enabled)
                        .contentTransition(.numericText())
                } else if codeFailed {
                    Button {
                        BrandHaptics.tick()
                        Task { await loadCode() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Couldn't load the code · Retry")
                                .font(BrandLabel.font(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(BrandPalette.goldDeep)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Couldn't load the code. Retry.")
                } else {
                    Text("· · · · · ·")
                        .font(BrandLabel.font(size: 17, weight: .semibold))
                        .tracking(4)
                        .foregroundStyle(BrandPalette.body)
                        .accessibilityLabel("Join code is loading")
                }
            }
            Spacer(minLength: 8)
            Button {
                BrandHaptics.soft()
                isShareKitPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Share")
                        .font(BrandLabel.font(size: 12, weight: .semibold))
                }
                .foregroundStyle(BrandPalette.card)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(BrandPalette.goldDeep))
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("QR code, invite link, and a new code if you need one")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 66)
    }

    private var faceIDRow: some View {
        Toggle(isOn: Binding(get: { faceIDOn }, set: { setFaceID($0) })) {
            HStack(spacing: 14) {
                Image(systemName: "faceid")
                    .font(.system(size: 15))
                    .foregroundStyle(BrandPalette.goldDeep)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lock with \(AdminSession.biometryName == "your passcode" ? "passcode" : AdminSession.biometryName)")
                        .brandFont(.bodyText)
                        .foregroundStyle(BrandPalette.ink)
                    Text("Only on this phone.")
                        .font(BrandLabel.font(size: 11.5, weight: .regular))
                        .foregroundStyle(BrandPalette.body)
                }
            }
        }
        .tint(BrandPalette.goldDeep)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var exitSection: some View {
        VStack(spacing: 10) {
            if !isOwner {
                Button {
                    BrandHaptics.tick()
                    isConfirmingLeave = true
                } label: {
                    exitLabel("Leave this wedding", symbol: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(PressableStyle())
                .disabled(isLeaving)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func exitLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            if isLeaving {
                ProgressView()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(title)
                .font(BrandLabel.font(size: 12, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
        }
        .foregroundStyle(BrandPalette.overdue)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BrandPalette.overdue.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Building blocks

    private var divider: some View {
        Rectangle()
            .fill(BrandPalette.hairline)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: title, size: 10)
            MatteCard(cornerRadius: 20) {
                VStack(spacing: 0) { content() }
            }
        }
    }

    private func row(_ title: String, symbol: String, detail: String? = nil, route: CoupleRoute) -> some View {
        Button {
            BrandHaptics.tick()
            path.append(route)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(BrandPalette.goldDeep)
                    .frame(width: 22)
                Text(title)
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(BrandLabel.font(size: 12, weight: .medium))
                        .foregroundStyle(BrandPalette.body)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BrandPalette.gold)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private func destination(_ route: CoupleRoute) -> some View {
        switch route {
        case .checklist:
            AdminChecklistView()
                .environment(tasks)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(BrandPalette.background, for: .navigationBar)
        case .details:
            CoupleDetailsView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(BrandPalette.background, for: .navigationBar)
        case .events: hostScreen(HostEventsView())
        case .announcements: hostScreen(HostAnnouncementsView())
        case .photos: hostScreen(HostPhotosView())
        case .content: hostScreen(HostContentView())
        case .look: hostScreen(HostLookView())
        case .guests:
            CouplePeopleView(
                onWeddingGone: { await finishLeaving() },
                onChange: { Task { await load() } }
            )
        }
    }

    private func hostScreen<V: View>(_ view: V) -> some View {
        view
            .environment(\.colorScheme, .light)
            .toolbarBackground(HostStyle.paper, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }

    // MARK: - Data

    private func load() async {
#if DEBUG && targetEnvironment(simulator)
        if ScreenshotFixture.suspendNetwork {
            eventCount = ScheduleCache.shared.load()?.count
            settings = context.guestSettings
            return
        }
#endif
        async let membersTask = HostAPI.shared.members(weddingID: weddingID)
        async let codeTask = HostAPI.shared.joinCode(weddingID: weddingID)
        async let events = HostAPI.shared.count(table: "events", weddingID: weddingID)
        async let settingsTask: () = context.refreshGuestSettings()
        do {
            let loaded = try await membersTask
            withAnimation(fade) { members = loaded }
            error = nil
        } catch {
            withAnimation(fade) { self.error = error.hostMessage }
        }
        if let loadedCode = try? await codeTask, loadedCode != nil {
            withAnimation(fade) {
                code = loadedCode
                codeFailed = false
            }
        } else if code == nil {
            // The server answered but no code exists yet, or the read failed — let the
            // row offer a retry instead of dots that never fill in.
            withAnimation(fade) { codeFailed = true }
        }
        let count = await events
        withAnimation(fade) { eventCount = count }
        _ = await settingsTask
        if savingSetting == nil { settings = context.guestSettings }
    }

    /// Reads the join code on its own, so the row can offer a retry when it fails.
    private func loadCode() async {
        do {
            let loadedCode = try await HostAPI.shared.joinCode(weddingID: weddingID)
            withAnimation(fade) {
                if let loadedCode {
                    code = loadedCode
                    codeFailed = false
                } else {
                    codeFailed = true
                }
            }
        } catch {
            withAnimation(fade) { codeFailed = true }
        }
    }

    private func setStatus(_ member: HostMember, _ status: String) async {
        busy.insert(member.id)
        defer { busy.remove(member.id) }
        do {
            try await HostAPI.shared.setStatus(weddingID: weddingID, userID: member.userID, status: status)
            status == "approved" ? BrandHaptics.soft() : BrandHaptics.tick()
            withAnimation(fade) {
                if let index = members.firstIndex(where: { $0.id == member.id }) {
                    members[index].status = status
                }
            }
            error = nil
        } catch {
            withAnimation(fade) { self.error = error.hostMessage }
        }
    }

    /// Shows the change at once, then saves it. The settings object is merged, never
    /// replaced, so keys this build doesn't know about are kept.
    private func update(key: String, _ change: (inout WeddingContext.GuestSettings) -> Void) {
        let previous = settings
        var next = settings
        change(&next)
        guard next != previous else { return }
        BrandHaptics.tick()
        settings = next
        context.applyGuestSettings(next)
        savingSetting = key
        let weddingID = weddingID
        Task {
            defer { savingSetting = nil }
            do {
                if key == "auto_approve" {
                    try await HostAPI.shared.updateWedding(weddingID: weddingID, fields: ["auto_approve": .bool(next.autoApprove)])
                } else {
                    let response = try await ChatBackend.client.from("weddings")
                        .select("settings")
                        .eq("id", value: weddingID)
                        .limit(1)
                        .execute()
                    let rows = (try? JSONDecoder().decode([[String: JSONValue]].self, from: response.data)) ?? []
                    var merged = rows.first?["settings"]?.objectValue ?? [:]
                    let value: Bool
                    switch key {
                    case "guest_chat": value = next.chat
                    case "guest_dms": value = next.dms
                    default: value = next.uploads
                    }
                    merged[key] = .bool(value)
                    try await HostAPI.shared.updateWedding(
                        weddingID: weddingID,
                        fields: ["settings": .object(merged.mapValues(WeddingTasksStore.any))]
                    )
                }
                error = nil
            } catch {
                settings = previous
                context.applyGuestSettings(previous)
                withAnimation(fade) { self.error = "That change didn't save. Check your connection and try again." }
            }
        }
    }

    private func setFaceID(_ isOn: Bool) {
        guard isOn else {
            faceIDOn = false
            AdminSession.setFaceIDLock(false, for: weddingID)
            BrandHaptics.tick()
            return
        }
        guard AdminSession.canLock else {
            withAnimation(fade) { error = "Set a passcode on this iPhone to use this lock." }
            return
        }
        let weddingID = weddingID
        Task {
            if await AdminSession.authenticate(reason: "Lock your couple's area on this phone") {
                AdminSession.setFaceIDLock(true, for: weddingID)
                faceIDOn = true
                BrandHaptics.soft()
            }
        }
    }

    private func leave() async {
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await HostAPI.shared.leaveWedding(weddingID: weddingID)
            await finishLeaving()
        } catch {
            withAnimation(fade) { self.error = error.hostMessage }
        }
    }

    private func finishLeaving() async {
        AdminSession.setFaceIDLock(false, for: weddingID)
        admin.isAdminPresented = false
        try? await Task.sleep(for: .milliseconds(400))
        await context.didLeaveCurrentWedding()
    }
}

// MARK: - Names, dates & venue

/// The wedding's basic details, saved straight to the wedding.
struct CoupleDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    private let context = WeddingContext.shared

    @State private var partnerOne = ""
    @State private var partnerTwo = ""
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var venue = ""
    @State private var city = ""
    @State private var address = ""
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AdminHeader(eyebrow: "Your wedding", title: "Names, dates & venue")

                if let error {
                    AdminNote(text: error, symbol: "exclamationmark.circle")
                }

                if !isLoaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    AdminField(label: "First partner") {
                        TextField("Name", text: $partnerOne)
                            .textInputAutocapitalization(.words)
                    }
                    AdminField(label: "Second partner") {
                        TextField("Name", text: $partnerTwo)
                            .textInputAutocapitalization(.words)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Dates", size: 9.5)
                        DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                            .brandFont(.bodyText)
                        Toggle("Runs over several days", isOn: $hasEndDate)
                            .brandFont(.bodyText)
                            .tint(BrandPalette.goldDeep)
                        if hasEndDate {
                            DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                                .brandFont(.bodyText)
                                .transition(.opacity)
                        }
                    }
                    .foregroundStyle(BrandPalette.ink)

                    AdminField(label: "Venue") {
                        TextField("The resort, hall or home", text: $venue)
                            .textInputAutocapitalization(.words)
                    }
                    AdminField(label: "City") {
                        TextField("City", text: $city)
                            .textInputAutocapitalization(.words)
                    }
                    AdminField(label: "Address") {
                        TextField("Street address", text: $address, axis: .vertical)
                            .lineLimit(1...3)
                    }

                    GoldActionButton(
                        title: "Save changes",
                        isBusy: isSaving,
                        isEnabled: partnerOne.nonEmpty != nil && partnerTwo.nonEmpty != nil
                    ) {
                        Task { await save() }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
            .readableWidth(560)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(BrandPalette.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: hasEndDate)
        .animation(.easeInOut(duration: 0.25), value: error)
        .task { await load() }
    }

    private func load() async {
        do {
            let row = try await HostAPI.shared.weddingRow(weddingID: context.weddingID)
            partnerOne = MilniJSON.string(row["partner_one"]) ?? context.snapshot.partnerOne
            partnerTwo = MilniJSON.string(row["partner_two"]) ?? context.snapshot.partnerTwo
            if let start = MilniJSON.string(row["start_date"]).flatMap(ChecklistDates.parse) { startDate = start }
            if let end = MilniJSON.string(row["end_date"]).flatMap(ChecklistDates.parse) {
                endDate = end
                hasEndDate = !Calendar.current.isDate(end, inSameDayAs: startDate)
            } else {
                endDate = startDate
            }
            venue = MilniJSON.string(row["venue_name"]) ?? ""
            city = MilniJSON.string(row["city"]) ?? ""
            address = MilniJSON.string(row["address"]) ?? ""
            error = nil
        } catch {
            self.error = error.hostMessage
        }
        isLoaded = true
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        func text(_ value: String) -> AnyJSON { value.nonEmpty.map(AnyJSON.string) ?? .null }
        let end = hasEndDate ? max(endDate, startDate) : startDate
        let fields: [String: AnyJSON] = [
            "partner_one": .string(partnerOne.trimmed),
            "partner_two": .string(partnerTwo.trimmed),
            "start_date": .string(ChecklistDates.string(from: startDate)),
            "end_date": .string(ChecklistDates.string(from: end)),
            "venue_name": text(venue),
            "city": text(city),
            "address": text(address)
        ]
        do {
            try await HostAPI.shared.updateWedding(weddingID: context.weddingID, fields: fields)
            BrandHaptics.soft()
            await context.refreshCurrent()
            dismiss()
        } catch {
            self.error = error.hostMessage
        }
    }
}
