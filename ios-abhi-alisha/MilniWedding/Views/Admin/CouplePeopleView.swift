import SwiftUI

/// Couple's area → People: who's waiting, who helps host, who's a guest and who's
/// kept out. The host can hand the wedding over or delete it; co-hosts look after
/// guests and see the other co-hosts read-only.
struct CouplePeopleView: View {
    /// The wedding is gone (deleted): the hub closes and the app moves on.
    var onWeddingGone: () async -> Void = {}
    /// Members changed, so the hub's counts can follow.
    var onChange: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let context = WeddingContext.shared

    @State private var members: [HostMember] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var busy: Set<String> = []
    @State private var share: HostSharePayload?
    @State private var isInviting = false
    @State private var removing: HostMember?
    @State private var promoting: HostMember?
    @State private var weddingTitle: String?
    @State private var isConfirmingDelete = false
    @State private var deleteTyped = ""
    @State private var isDeleting = false

    private var weddingID: String { context.weddingID }
    private var amOwner: Bool { context.role?.lowercased() == "host" }
    private var myID: String? { ChatSession.shared.userID?.lower }
    private var isShowcase: Bool { weddingID.lowercased() == ActiveWedding.sampleID.lowercased() }
    private var fade: Animation { reduceMotion ? .easeInOut(duration: 0.25) : .calm }

    private func byName(_ list: [HostMember]) -> [HostMember] {
        list.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var waiting: [HostMember] {
        members.filter { $0.status.lowercased() == "pending" }
            .sorted { ($0.joinedAt ?? .distantPast) > ($1.joinedAt ?? .distantPast) }
    }

    private var cohosts: [HostMember] {
        let list = members.filter { $0.status.lowercased() == "approved" && $0.isCohost }
        return list.filter(\.isOwner) + byName(list.filter { !$0.isOwner })
    }

    private var guests: [HostMember] {
        byName(members.filter { $0.status.lowercased() == "approved" && !$0.isCohost })
    }

    private var blocked: [HostMember] {
        byName(members.filter { $0.status.lowercased() == "blocked" })
    }

    var body: some View {
        List {
            Section {
                AdminHeader(eyebrow: "Your wedding", title: "People")
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if let error {
                    AdminNote(text: error, symbol: "exclamationmark.circle")
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .transition(.opacity)
                }
            }

            if amOwner {
                Section {
                    inviteRow
                        .listRowBackground(BrandPalette.card)
                }
            }

            if isLoading && members.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            group("Waiting for approval", waiting, empty: nil)
            group("Co-hosts", cohosts, empty: nil)
            group("Guests", guests, empty: isLoading ? nil : "No guests yet. Share your join code to invite them.")
            group("Blocked", blocked, empty: nil)

            if amOwner && !isShowcase {
                Section {
                    deleteButton
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 18, leading: 0, bottom: 18, trailing: 0))
                } footer: {
                    Text("Deletes every event, photo, message and guest. This can't be undone.")
                        .font(BrandLabel.font(size: 11.5, weight: .regular))
                        .foregroundStyle(BrandPalette.body)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .tint(BrandPalette.goldDeep)
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BrandPalette.background, for: .navigationBar)
        .animation(fade, value: members)
        .animation(fade, value: error)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $share) { payload in
            HostShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Remove \(removing?.displayName ?? "this person")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove from the wedding", role: .destructive) {
                if let member = removing { Task { await remove(member) } }
            }
        } message: {
            Text("They'll lose access but can ask to join again with the code. To keep them out, block them instead.")
        }
        .alert(
            "Make \(promoting?.displayName ?? "them") the host?",
            isPresented: Binding(get: { promoting != nil }, set: { if !$0 { promoting = nil } })
        ) {
            Button("Make host") {
                if let member = promoting { Task { await transfer(to: member) } }
            }
            Button("Cancel", role: .cancel) { promoting = nil }
        } message: {
            Text("\(promoting?.displayName ?? "They") becomes the host. You'll become a co-host.")
        }
        .alert("Delete this wedding?", isPresented: $isConfirmingDelete) {
            TextField(titleToType, text: $deleteTyped)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Button("Delete forever", role: .destructive) { Task { await deleteWedding() } }
                .disabled(!deleteMatches)
            Button("Cancel", role: .cancel) { deleteTyped = "" }
        } message: {
            Text("Every event, photo, message and guest goes with it. This can't be undone. Type \(titleToType) to confirm.")
        }
    }

    // MARK: - Rows

    private var inviteRow: some View {
        Button {
            Task { await invite() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(BrandPalette.goldPale.opacity(0.6))
                    if isInviting {
                        ProgressView()
                    } else {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 15))
                            .foregroundStyle(BrandPalette.goldDeep)
                    }
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite a co-host")
                        .brandFont(.bodyText)
                        .foregroundStyle(BrandPalette.ink)
                    Text("Send a link. They can approve guests and edit the wedding.")
                        .font(BrandLabel.font(size: 11.5, weight: .regular))
                        .foregroundStyle(BrandPalette.body)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(isInviting)
    }

    @ViewBuilder
    private func group(_ title: String, _ list: [HostMember], empty: String?) -> some View {
        if !list.isEmpty || empty != nil {
            Section {
                if list.isEmpty, let empty {
                    Text(empty)
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                        .listRowBackground(BrandPalette.card)
                } else {
                    ForEach(list) { member in
                        row(member)
                            .listRowBackground(BrandPalette.card)
                    }
                }
            } header: {
                Eyebrow(text: list.isEmpty ? title : "\(title) · \(list.count)", size: 10)
            }
        }
    }

    private func isMe(_ member: HostMember) -> Bool { member.userID.lowercased() == myID }

    /// Whether I may act on this person at all.
    private func canManage(_ member: HostMember) -> Bool {
        if isMe(member) || member.isOwner { return false }
        if member.isCohost && member.status.lowercased() == "approved" { return amOwner }
        return true
    }

    @ViewBuilder
    private func row(_ member: HostMember) -> some View {
        let status = member.status.lowercased()
        HStack(spacing: 12) {
            avatar(member)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .brandFont(.bodyText)
                        .foregroundStyle(BrandPalette.ink)
                        .lineLimit(1)
                    if member.isOwner {
                        badge("Host")
                    } else if isMe(member) {
                        Text("You")
                            .font(BrandLabel.font(size: 11, weight: .semibold))
                            .foregroundStyle(BrandPalette.goldDeep)
                    }
                }
                Text(joinedText(member))
                    .font(BrandLabel.font(size: 11.5, weight: .regular))
                    .foregroundStyle(BrandPalette.body)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if busy.contains(member.id) {
                ProgressView()
            } else if status == "pending" && canManage(member) {
                pendingButtons(member)
            } else if canManage(member) {
                Menu {
                    actions(member)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BrandPalette.ink)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Actions for \(member.displayName)")
            }
        }
        .padding(.vertical, 3)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canManage(member) && !busy.contains(member.id) {
                swipeActions(member)
            }
        }
    }

    private func avatar(_ member: HostMember) -> some View {
        ZStack {
            MilniMonogram(initials: initials(member.displayName), size: 38, ring: BrandPalette.gold, textColor: BrandPalette.goldDeep)
            if let url = member.avatarURL.flatMap(URL.init(string:)) {
                RemoteImage(url: url, contentMode: .fill) { Color.clear }
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(BrandPalette.gold.opacity(0.5), lineWidth: 0.75))
            }
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }

    private func badge(_ text: String) -> some View {
        Text(text.uppercased())
            .font(BrandLabel.font(size: 9, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(BrandPalette.goldDeep)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(BrandPalette.gold.opacity(0.6), lineWidth: 0.75))
    }

    private func pendingButtons(_ member: HostMember) -> some View {
        HStack(spacing: 4) {
            Button("Decline") { Task { await setStatus(member, "blocked") } }
                .font(BrandLabel.font(size: 12, weight: .semibold))
                .foregroundStyle(BrandPalette.body)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.borderless)
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
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func swipeActions(_ member: HostMember) -> some View {
        let status = member.status.lowercased()
        if status == "pending" {
            Button("Decline") { Task { await setStatus(member, "blocked") } }
                .tint(BrandPalette.overdue)
            Button("Approve") { Task { await setStatus(member, "approved") } }
                .tint(BrandPalette.goldDeep)
        } else if status == "blocked" {
            Button("Remove") { removing = member }
                .tint(BrandPalette.overdue)
            Button("Unblock") { Task { await setStatus(member, "approved") } }
                .tint(BrandPalette.goldDeep)
        } else if member.isCohost {
            Button("Remove") { removing = member }
                .tint(BrandPalette.overdue)
            Button("Make guest") { Task { await setRole(member, "guest") } }
                .tint(BrandPalette.body)
        } else {
            Button("Block") { Task { await setStatus(member, "blocked") } }
                .tint(BrandPalette.overdue)
            Button("Remove") { removing = member }
                .tint(BrandPalette.body)
            if amOwner {
                Button("Co-host") { Task { await setRole(member, "cohost") } }
                    .tint(BrandPalette.goldDeep)
            }
        }
    }

    @ViewBuilder
    private func actions(_ member: HostMember) -> some View {
        let status = member.status.lowercased()
        if status == "blocked" {
            Button("Unblock and let in", systemImage: "checkmark") { Task { await setStatus(member, "approved") } }
            Button("Remove", systemImage: "person.crop.circle.badge.minus", role: .destructive) { removing = member }
        } else if member.isCohost {
            Button("Make guest", systemImage: "person") { Task { await setRole(member, "guest") } }
            Button("Make host", systemImage: "crown") { promoting = member }
            Divider()
            Button("Remove", systemImage: "person.crop.circle.badge.minus", role: .destructive) { removing = member }
        } else {
            if amOwner {
                Button("Make co-host", systemImage: "key.horizontal") { Task { await setRole(member, "cohost") } }
            }
            Divider()
            Button("Remove", systemImage: "person.crop.circle.badge.minus", role: .destructive) { removing = member }
            Button("Block", systemImage: "hand.raised", role: .destructive) { Task { await setStatus(member, "blocked") } }
        }
    }

    private func joinedText(_ member: HostMember) -> String {
        let role: String
        if member.isOwner { role = "Host" } else if member.isCohost { role = "Co-host" } else { role = "Guest" }
        guard let joined = member.joinedAt else { return role }
        let verb = member.status.lowercased() == "pending" ? "Asked" : "Joined"
        let sameYear = Calendar.current.isDate(joined, equalTo: .now, toGranularity: .year)
        let date = sameYear
            ? joined.formatted(.dateTime.month(.abbreviated).day())
            : joined.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(role) · \(verb) \(date)"
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    // MARK: - Delete

    private var titleToType: String { weddingTitle ?? context.snapshot.coupleNames }

    private var deleteMatches: Bool {
        func letters(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        let typed = letters(deleteTyped)
        return !typed.isEmpty && typed == letters(titleToType)
    }

    private var deleteButton: some View {
        Button {
            BrandHaptics.tick()
            deleteTyped = ""
            isConfirmingDelete = true
        } label: {
            HStack(spacing: 8) {
                if isDeleting {
                    ProgressView()
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(isDeleting ? "Deleting…" : "Delete this wedding")
                    .font(BrandLabel.font(size: 12, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(BrandPalette.overdue)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BrandPalette.overdue.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(isDeleting)
    }

    private func deleteWedding() async {
        guard deleteMatches, amOwner, !isShowcase else { return }
        let id = weddingID
        isDeleting = true
        defer { isDeleting = false }
        do {
            // The server compares this to the title exactly, so send the title itself.
            let row = try await HostAPI.shared.weddingRow(weddingID: id)
            let title = MilniJSON.string(row["title"]) ?? titleToType
            await HostAPI.shared.deleteFolder(bucket: HostAPI.assetsBucket, prefix: id.lowercased())
            await HostAPI.shared.deleteFolder(bucket: WeddingPhoto.bucket, prefix: id.lowercased())
            try await HostAPI.shared.deleteWedding(weddingID: id, confirm: title)
            BrandHaptics.soft()
            AdminSession.setFaceIDLock(false, for: id)
            await onWeddingGone()
        } catch {
            withAnimation(fade) { self.error = "We couldn't delete the wedding. \(error.hostMessage)" }
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await HostAPI.shared.members(weddingID: weddingID)
            withAnimation(fade) { members = loaded }
            error = nil
        } catch {
            withAnimation(fade) { self.error = error.hostMessage }
        }
        if weddingTitle == nil, let row = try? await HostAPI.shared.weddingRow(weddingID: weddingID) {
            weddingTitle = MilniJSON.string(row["title"])?.nonEmpty
        }
    }

    private func perform(_ member: HostMember, _ work: () async throws -> Void) async -> Bool {
        busy.insert(member.id)
        defer { busy.remove(member.id) }
        do {
            try await work()
            error = nil
            onChange()
            return true
        } catch {
            withAnimation(fade) { self.error = error.hostMessage }
            return false
        }
    }

    private func setStatus(_ member: HostMember, _ status: String) async {
        let ok = await perform(member) {
            try await HostAPI.shared.setStatus(weddingID: weddingID, userID: member.userID, status: status)
        }
        guard ok else { return }
        status == "approved" ? BrandHaptics.soft() : BrandHaptics.tick()
        withAnimation(fade) {
            if let index = members.firstIndex(where: { $0.id == member.id }) { members[index].status = status }
        }
    }

    private func setRole(_ member: HostMember, _ role: String) async {
        let ok = await perform(member) {
            try await HostAPI.shared.setRole(weddingID: weddingID, userID: member.userID, role: role)
        }
        guard ok else { return }
        BrandHaptics.soft()
        withAnimation(fade) {
            if let index = members.firstIndex(where: { $0.id == member.id }) { members[index].role = role }
        }
    }

    private func remove(_ member: HostMember) async {
        removing = nil
        let ok = await perform(member) {
            try await HostAPI.shared.remove(weddingID: weddingID, userID: member.userID)
        }
        guard ok else { return }
        BrandHaptics.tick()
        withAnimation(fade) { members.removeAll { $0.id == member.id } }
    }

    private func transfer(to member: HostMember) async {
        promoting = nil
        let ok = await perform(member) {
            try await HostAPI.shared.transferHost(weddingID: weddingID, userID: member.userID)
        }
        guard ok else { return }
        BrandHaptics.soft()
        withAnimation(fade) {
            for index in members.indices {
                if members[index].id == member.id {
                    members[index].role = "host"
                } else if members[index].isOwner {
                    members[index].role = "cohost"
                }
            }
        }
        await context.refreshMembership()
        await load()
    }

    private func invite() async {
        isInviting = true
        defer { isInviting = false }
        do {
            let code = try await HostAPI.shared.createCohostInvite(weddingID: weddingID)
            let message = "Help us host our wedding on Milni: https://milniapp.com/c/\(code)"
            share = HostSharePayload(items: [message])
            error = nil
        } catch {
            withAnimation(fade) { self.error = error.hostMessage }
        }
    }
}
