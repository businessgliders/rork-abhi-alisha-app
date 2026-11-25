import SwiftUI
import UIKit

/// The system share sheet, for text, links, images and files.
struct HostShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct HostSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// Everyone in the wedding: let people in, keep people out, and choose co-hosts.
struct HostGuestsView: View {
    var onChange: () -> Void = {}

    @State private var members: [HostMember] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var error: String?
    @State private var share: HostSharePayload?
    @State private var isInviting = false
    @State private var removing: HostMember?

    private let context = WeddingContext.shared
    private var weddingID: String { context.weddingID }
    private var amOwner: Bool { context.role?.lowercased() == "host" }
    private var myID: String? { ChatSession.shared.userID?.lower }

    private var filtered: [HostMember] {
        let text = query.hostTrimmed.lowercased()
        let list = text.isEmpty ? members : members.filter { $0.displayName.lowercased().contains(text) }
        return list.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var groups: [(title: String, members: [HostMember])] {
        let pending = filtered.filter { $0.status.lowercased() == "pending" }
        let cohosts = filtered.filter { $0.status.lowercased() == "approved" && $0.isCohost }
        let approved = filtered.filter { $0.status.lowercased() == "approved" && !$0.isCohost }
        let blocked = filtered.filter { $0.status.lowercased() == "blocked" }
        return [("Pending", pending), ("Approved", approved), ("Co-hosts", cohosts), ("Blocked", blocked)]
            .filter { !$0.members.isEmpty }
    }

    var body: some View {
        List {
            Section {
                Button {
                    Task { await invite() }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Milni.midnight)
                            if isInviting {
                                ProgressView().tint(Milni.champagne)
                            } else {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Milni.champagne)
                            }
                        }
                        .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Invite a co-host")
                                .font(Milni.cormorant(21, weight: 500))
                                .foregroundStyle(HostStyle.ink)
                            Text("They can approve guests and edit the wedding")
                                .font(Milni.inter(12))
                                .foregroundStyle(HostStyle.muted)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .disabled(isInviting)
                .listRowBackground(HostStyle.card)
            }

            if let error {
                HostErrorLine(message: error)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if isLoading && members.isEmpty {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if groups.isEmpty {
                HostEmptyLine(text: query.isEmpty ? "No guests yet." : "No one by that name.")
                    .listRowBackground(Color.clear)
            }

            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.members) { member in
                        row(member)
                            .listRowBackground(HostStyle.card)
                    }
                } header: {
                    HostCaps("\(group.title) · \(group.members.count)", color: HostStyle.goldText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(HostPaper())
        .searchable(text: $query, prompt: "Search guests")
        .navigationTitle("Guests & co-hosts")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.calm, value: members)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $share) { payload in
            HostShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Remove \(removing?.displayName ?? "this guest")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove from the wedding", role: .destructive) {
                if let member = removing { Task { await remove(member) } }
            }
        } message: {
            Text("They'll lose access but can ask to join again with the code. To keep them out, block them instead.")
        }
    }

    @ViewBuilder
    private func row(_ member: HostMember) -> some View {
        let isMe = member.userID.lowercased() == myID
        let locked = isMe || (member.isOwner && !amOwner)
        HStack(spacing: 12) {
            MilniMonogram(initials: initials(member.displayName), size: 36, ring: HostStyle.gold, textColor: HostStyle.goldText)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(Milni.inter(16, weight: 600))
                        .foregroundStyle(HostStyle.ink)
                        .lineLimit(1)
                    if isMe {
                        Text("You").font(Milni.inter(11, weight: 600)).foregroundStyle(HostStyle.goldText)
                    }
                }
                Text(subtitle(member))
                    .font(Milni.inter(12))
                    .foregroundStyle(HostStyle.muted)
            }
            Spacer(minLength: 6)
            if !locked {
                Menu {
                    actions(member)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HostStyle.ink)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Actions for \(member.displayName)")
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !locked {
                if member.status.lowercased() == "pending" {
                    Button("Approve") { Task { await setStatus(member, "approved") } }
                        .tint(HostStyle.ink)
                }
                if member.status.lowercased() != "blocked" {
                    Button("Block", role: .destructive) { Task { await setStatus(member, "blocked") } }
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ member: HostMember) -> some View {
        let status = member.status.lowercased()
        if status != "approved" {
            Button("Approve", systemImage: "checkmark") { Task { await setStatus(member, "approved") } }
        }
        if status != "pending" {
            Button("Back to pending", systemImage: "clock") { Task { await setStatus(member, "pending") } }
        }
        if amOwner, status == "approved" {
            if member.isCohost {
                Button("Make a guest", systemImage: "person") { Task { await setRole(member, "guest") } }
            } else {
                Button("Make a co-host", systemImage: "key.horizontal") { Task { await setRole(member, "cohost") } }
            }
        }
        Divider()
        if status != "blocked" {
            Button("Block", systemImage: "hand.raised", role: .destructive) { Task { await setStatus(member, "blocked") } }
        }
        Button("Remove", systemImage: "person.crop.circle.badge.minus", role: .destructive) { removing = member }
    }

    private func subtitle(_ member: HostMember) -> String {
        var parts: [String] = []
        if member.isOwner { parts.append("Host") } else if member.isCohost { parts.append("Co-host") }
        if let joined = member.joinedAt { parts.append("joined \(HostTime.relative(joined))") }
        return parts.isEmpty ? "Guest" : parts.joined(separator: " · ").capitalizingFirst
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    // MARK: Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            members = try await HostAPI.shared.members(weddingID: weddingID)
            error = nil
        } catch {
            self.error = error.hostMessage
        }
    }

    private func setStatus(_ member: HostMember, _ status: String) async {
        do {
            try await HostAPI.shared.setStatus(weddingID: weddingID, userID: member.userID, status: status)
            BrandHaptics.soft()
            if let index = members.firstIndex(where: { $0.id == member.id }) { members[index].status = status }
            error = nil
            onChange()
        } catch {
            self.error = error.hostMessage
        }
    }

    private func setRole(_ member: HostMember, _ role: String) async {
        do {
            try await HostAPI.shared.setRole(weddingID: weddingID, userID: member.userID, role: role)
            BrandHaptics.soft()
            if let index = members.firstIndex(where: { $0.id == member.id }) { members[index].role = role }
            error = nil
        } catch {
            self.error = error.hostMessage
        }
    }

    private func remove(_ member: HostMember) async {
        removing = nil
        do {
            try await HostAPI.shared.remove(weddingID: weddingID, userID: member.userID)
            BrandHaptics.tick()
            members.removeAll { $0.id == member.id }
            error = nil
            onChange()
        } catch {
            self.error = error.hostMessage
        }
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
            self.error = error.hostMessage
        }
    }
}

extension String {
    var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}
