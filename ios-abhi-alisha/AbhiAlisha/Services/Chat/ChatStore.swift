import Foundation
import Observation
import Supabase
import SwiftUI

/// One open (or recently opened) conversation's messages.
struct ChatThreadState {
    var messages: [ChatMessage] = []
    var hasMore = true
    var isLoadingOlder = false
    var didLoad = false
}

/// Everything the approved family member sees: conversations, people, messages, and,
/// for admins, who is waiting and what has been reported.
///
/// The last list and the newest page of each thread are saved on the phone, so every
/// screen opens instantly and offline, then refreshes quietly. Two kinds of live
/// listeners keep it current: an inbox channel (new conversations this person is added
/// to, plus new and changed messages anywhere they can see) and a per-thread channel
/// filtered to the open conversation.
@Observable
final class ChatStore {
    static let shared = ChatStore()
    static let pageSize = 50

    private(set) var userID: UUID?
    private(set) var conversations: [ChatConversation] = []
    private(set) var members: [UUID: [ChatMember]] = [:]
    private(set) var profiles: [UUID: ChatProfile] = [:]
    private(set) var previews: [UUID: ChatMessage] = [:]
    private(set) var blocked: Set<UUID> = []
    private(set) var threads: [UUID: ChatThreadState] = [:]
    private(set) var hasLoadedList = false

    private(set) var pendingPeople: [ChatProfile] = []
    private(set) var reports: [ChatReport] = []
    private(set) var reportedMessages: [UUID: ChatMessage] = [:]

    /// The conversation on screen right now, if any. Hides the tab bar and keeps
    /// banners for this conversation from interrupting it.
    var activeThreadID: UUID?

    private var inboxChannel: RealtimeChannelV2?
    private var inboxTasks: [Task<Void, Never>] = []
    private var threadChannels: [UUID: RealtimeChannelV2] = [:]
    private var threadTasks: [UUID: [Task<Void, Never>]] = [:]
    private var isRefreshing = false
    private var needsAnotherRefresh = false
    private var lastReadSync: [UUID: Date] = [:]

    private var client: SupabaseClient { ChatBackend.client }

    // MARK: - Payloads

    nonisolated private struct ReadMark: Encodable, Sendable { let last_read_at: String }
    nonisolated private struct Deletion: Encodable, Sendable { let deleted_at: String; let body: String }
    nonisolated private struct NewReport: Encodable, Sendable { let message_id: String; let reporter_id: String; let reason: String }
    nonisolated private struct NewBlock: Encodable, Sendable { let blocker_id: String; let blocked_id: String }
    nonisolated private struct Resolution: Encodable, Sendable { let resolved_at: String }
    nonisolated private struct DirectParams: Encodable, Sendable { let other_user: String }
    nonisolated private struct GroupParams: Encodable, Sendable { let group_title: String; let member_ids: [String] }
    nonisolated private struct LeaveParams: Encodable, Sendable { let conv: String }
    nonisolated private struct StatusParams: Encodable, Sendable { let target: String; let new_status: String }

    // MARK: - Lifecycle

    func activate(userID: UUID) {
        guard self.userID != userID else { return }
        self.userID = userID
        if let snapshot = ChatCache.load(ChatListSnapshot.self, named: ChatCache.listName(for: userID)) {
            conversations = snapshot.conversations
            members = Dictionary(grouping: snapshot.members, by: \.conversationID)
            profiles = Dictionary(snapshot.profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            previews = Dictionary(snapshot.previews.map { ($0.conversationID, $0) }, uniquingKeysWith: { first, _ in first })
            blocked = Set(snapshot.blocked)
            hasLoadedList = true
        }
        startInbox(for: userID)
    }

    func reset() async {
        inboxTasks.forEach { $0.cancel() }
        inboxTasks = []
        threadTasks.values.flatMap { $0 }.forEach { $0.cancel() }
        threadTasks = [:]
        let channels = Array(threadChannels.values) + [inboxChannel].compactMap { $0 }
        threadChannels = [:]
        inboxChannel = nil
        for channel in channels {
            await client.removeChannel(channel)
        }
        userID = nil
        conversations = []
        members = [:]
        profiles = [:]
        previews = [:]
        blocked = []
        threads = [:]
        pendingPeople = []
        reports = []
        reportedMessages = [:]
        activeThreadID = nil
        hasLoadedList = false
        lastReadSync = [:]
    }

    /// Back online: catch up on anything missed while the connection was down.
    func reconnect() async {
        guard userID != nil else { return }
        await refreshAll()
        if let active = activeThreadID {
            await loadLatest(active)
        }
    }

    // MARK: - People and conversations

    var me: UUID? { userID }

    func profile(_ id: UUID) -> ChatProfile? { profiles[id] }

    func name(of id: UUID) -> String {
        if id == userID { return "You" }
        return profiles[id]?.name ?? "Family member"
    }

    func firstName(of id: UUID) -> String {
        let full = name(of: id)
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    /// Approved family members someone can start a conversation with.
    var approvedPeople: [ChatProfile] {
        profiles.values
            .filter { $0.access == .approved && $0.id != userID && !blocked.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var blockedPeople: [ChatProfile] {
        blocked.map { profiles[$0] ?? ChatProfile(id: $0, displayName: nil, status: nil) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func conversation(_ id: UUID) -> ChatConversation? {
        conversations.first { $0.id == id }
    }

    func isFamily(_ conversation: ChatConversation) -> Bool {
        if conversation.isFamily { return true }
        guard !conversation.isGroupKind, !conversation.isDirectKind else { return false }
        return conversation.title?.lowercased().contains("family") == true
    }

    func isDirect(_ conversation: ChatConversation) -> Bool {
        if conversation.isDirectKind { return true }
        if isFamily(conversation) || conversation.isGroupKind { return false }
        return ChatJSON.clean(conversation.title) == nil && (members[conversation.id]?.count ?? 0) == 2
    }

    func isGroup(_ conversation: ChatConversation) -> Bool {
        !isFamily(conversation) && !isDirect(conversation)
    }

    func otherMember(in conversation: ChatConversation) -> UUID? {
        members[conversation.id]?.first { $0.userID != userID }?.userID
    }

    func memberIDs(of conversationID: UUID) -> [UUID] {
        (members[conversationID] ?? [])
            .map(\.userID)
            .sorted { name(of: $0).localizedCaseInsensitiveCompare(name(of: $1)) == .orderedAscending }
    }

    func title(for conversation: ChatConversation) -> String {
        if isFamily(conversation) {
            return ChatJSON.clean(conversation.title) ?? "The Family"
        }
        if isDirect(conversation) {
            if let other = otherMember(in: conversation) { return name(of: other) }
            return ChatJSON.clean(conversation.title) ?? "Private chat"
        }
        if let title = ChatJSON.clean(conversation.title) { return title }
        let others = memberIDs(of: conversation.id).filter { $0 != userID }.map(firstName(of:))
        return others.isEmpty ? "Group" : others.joined(separator: ", ")
    }

    func initials(for conversation: ChatConversation) -> String {
        if isDirect(conversation), let other = otherMember(in: conversation) {
            return profiles[other]?.initials ?? "·"
        }
        return ChatJSON.initials(for: title(for: conversation))
    }

    /// Family first, always; then whatever spoke most recently.
    var sortedConversations: [ChatConversation] {
        conversations.sorted { lhs, rhs in
            let lhsFamily = isFamily(lhs)
            let rhsFamily = isFamily(rhs)
            if lhsFamily != rhsFamily { return lhsFamily }
            return lastActivity(lhs) > lastActivity(rhs)
        }
    }

    func lastActivity(_ conversation: ChatConversation) -> Date {
        [conversation.lastMessageAt, previews[conversation.id]?.createdAt, conversation.createdAt]
            .compactMap { $0 }
            .max() ?? .distantPast
    }

    func previewText(for conversation: ChatConversation) -> String {
        guard let message = previews[conversation.id] else { return "No messages yet" }
        if blocked.contains(message.senderID) { return "Message hidden" }
        let text = message.isDeleted ? ChatMessage.deletedText : message.displayText
        if message.senderID == userID { return "You: " + text }
        if !isDirect(conversation) { return firstName(of: message.senderID) + ": " + text }
        return text
    }

    func isUnread(_ conversation: ChatConversation) -> Bool {
        guard let userID else { return false }
        let lastRead = members[conversation.id]?.first { $0.userID == userID }?.lastReadAt ?? .distantPast
        if let message = previews[conversation.id] {
            guard message.senderID != userID, !blocked.contains(message.senderID) else { return false }
            return message.createdAt > lastRead.addingTimeInterval(0.5)
        }
        guard let last = conversation.lastMessageAt else { return false }
        return last > lastRead.addingTimeInterval(0.5)
    }

    // MARK: - Refreshing

    /// Fetches the whole list again. Calls made while one is running are folded into
    /// a single follow-up, so a burst of live events never stacks up requests.
    func refreshAll() async {
        guard let userID else { return }
        if isRefreshing {
            needsAnotherRefresh = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let mine: [ChatMember] = try await client
                .from("conversation_members")
                .select(ChatMember.columns)
                .eq("user_id", value: userID.lower)
                .execute()
                .value
            let ids = mine.map(\.conversationID)

            var fetchedConversations: [ChatConversation] = []
            var fetchedMembers: [ChatMember] = mine
            if !ids.isEmpty {
                fetchedConversations = try await client
                    .from("conversations")
                    .select(ChatConversation.columns)
                    .in("id", values: Self.filterValues(ids))
                    .execute()
                    .value
                do {
                    let everyone: [ChatMember] = try await client
                        .from("conversation_members")
                        .select(ChatMember.columns)
                        .in("conversation_id", values: Self.filterValues(ids))
                        .execute()
                        .value
                    fetchedMembers = everyone.isEmpty ? mine : everyone
                } catch {
                    print("[Chat] members unavailable, keeping own memberships")
                }
            }

            var fetchedProfiles: [ChatProfile] = try await client
                .from("profiles")
                .select(ChatProfile.columns)
                .eq("status", value: "approved")
                .execute()
                .value
            let known = Set(fetchedProfiles.map(\.id))
            let missing = Array(Set(fetchedMembers.map(\.userID)).subtracting(known))
            if !missing.isEmpty {
                let extra: [ChatProfile] = (try? await client
                    .from("profiles")
                    .select(ChatProfile.columns)
                    .in("id", values: Self.filterValues(missing))
                    .execute()
                    .value) ?? []
                fetchedProfiles += extra
            }

            let blocks: [ChatBlock] = (try? await client
                .from("user_blocks")
                .select(ChatBlock.columns)
                .eq("blocker_id", value: userID.lower)
                .execute()
                .value) ?? []

            let fetchedPreviews = await Self.latestMessages(in: ids)

            guard self.userID == userID else { return }

            withAnimation(.calm) {
                conversations = fetchedConversations
                members = Dictionary(grouping: fetchedMembers, by: \.conversationID)
                var merged = profiles
                for profile in fetchedProfiles { merged[profile.id] = profile }
                profiles = merged
                var nextPreviews: [UUID: ChatMessage] = [:]
                for id in ids {
                    let local = previews[id]
                    let remote = fetchedPreviews[id]
                    if let local, let remote {
                        nextPreviews[id] = remote.createdAt >= local.createdAt ? remote : local
                    } else {
                        nextPreviews[id] = remote ?? local
                    }
                }
                previews = nextPreviews
                blocked = Set(blocks.map(\.blockedID))
                hasLoadedList = true
            }
            persistList()
        } catch {
            print("[Chat] list refresh postponed")
        }

        if ChatSession.shared.isAdmin {
            await refreshAdmin()
        }

        if needsAnotherRefresh {
            needsAnotherRefresh = false
            await refreshAll()
        }
    }

    /// Only the people list, after someone changes their own name.
    func refreshPeople() async {
        guard let userID else { return }
        if let rows: [ChatProfile] = try? await client
            .from("profiles")
            .select(ChatProfile.columns)
            .eq("id", value: userID.lower)
            .execute()
            .value, let me = rows.first {
            profiles[me.id] = me
        }
    }

    private nonisolated static func latestMessages(in ids: [UUID]) async -> [UUID: ChatMessage] {
        await withTaskGroup(of: (UUID, ChatMessage?).self) { group in
            for id in ids {
                group.addTask { (id, await ChatStore.latestMessage(in: id)) }
            }
            var result: [UUID: ChatMessage] = [:]
            for await (id, message) in group {
                if let message { result[id] = message }
            }
            return result
        }
    }

    private nonisolated static func latestMessage(in id: UUID) async -> ChatMessage? {
        do {
            let rows: [ChatMessage] = try await ChatBackend.client
                .from("messages")
                .select(ChatMessage.columns)
                .eq("conversation_id", value: id.lower)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            return nil
        }
    }

    private nonisolated static func filterValues(_ ids: [UUID]) -> [any PostgrestFilterValue] {
        ids.map { $0.lower }
    }

    private func persistList() {
        guard let userID else { return }
        let snapshot = ChatListSnapshot(
            conversations: conversations,
            members: members.values.flatMap { $0 },
            profiles: Array(profiles.values),
            previews: Array(previews.values),
            blocked: Array(blocked)
        )
        ChatCache.save(snapshot, named: ChatCache.listName(for: userID))
    }

    // MARK: - Threads

    func messages(in conversationID: UUID) -> [ChatMessage] {
        (threads[conversationID]?.messages ?? []).filter { !blocked.contains($0.senderID) }
    }

    func openThread(_ id: UUID) {
        activeThreadID = id
        if threads[id] == nil, let userID {
            let cached = ChatCache.load([ChatMessage].self, named: ChatCache.threadName(for: userID, conversation: id)) ?? []
            threads[id] = ChatThreadState(messages: cached, hasMore: true, isLoadingOlder: false, didLoad: !cached.isEmpty)
        }
        subscribeThread(id)
        Task {
            await loadLatest(id)
            markRead(id)
        }
    }

    func closeThread(_ id: UUID) {
        // Anything that arrived while reading counts as read on the way out.
        if activeThreadID == id, conversations.contains(where: { $0.id == id }) {
            lastReadSync[id] = nil
            markRead(id)
        }
        if activeThreadID == id { activeThreadID = nil }
        threadTasks[id]?.forEach { $0.cancel() }
        threadTasks[id] = nil
        if let channel = threadChannels.removeValue(forKey: id) {
            Task { await ChatBackend.client.removeChannel(channel) }
        }
    }

    func loadLatest(_ id: UUID) async {
        do {
            let rows: [ChatMessage] = try await client
                .from("messages")
                .select(ChatMessage.columns)
                .eq("conversation_id", value: id.lower)
                .order("created_at", ascending: false)
                .limit(Self.pageSize)
                .execute()
                .value
            var state = threads[id] ?? ChatThreadState()
            let fresh: [ChatMessage] = Array(rows.reversed())
            let oldestFresh = fresh.first?.createdAt ?? .distantFuture
            let freshIDs = Set(rows.map(\.id))
            // Keep anything older that was already paged in; the newest page is replaced.
            let older = state.messages.filter { $0.createdAt < oldestFresh && !freshIDs.contains($0.id) }
            withAnimation(.calm) {
                state.messages = older + fresh
                if !state.didLoad { state.hasMore = rows.count == Self.pageSize }
                state.didLoad = true
                threads[id] = state
            }
            if let newest = rows.first { updatePreview(with: newest) }
            persistThread(id)
        } catch {
            if threads[id] != nil { threads[id]?.didLoad = true }
            print("[Chat] thread refresh postponed")
        }
    }

    /// The previous page, when the reader scrolls up past the oldest message.
    func loadOlder(_ id: UUID) async {
        guard var state = threads[id], state.hasMore, !state.isLoadingOlder,
              let oldest = state.messages.first else { return }
        state.isLoadingOlder = true
        threads[id] = state
        do {
            let rows: [ChatMessage] = try await client
                .from("messages")
                .select(ChatMessage.columns)
                .eq("conversation_id", value: id.lower)
                .lt("created_at", value: ChatJSON.isoString(oldest.createdAt))
                .order("created_at", ascending: false)
                .limit(Self.pageSize)
                .execute()
                .value
            var current = threads[id] ?? state
            let existing = Set(current.messages.map(\.id))
            let older = rows.reversed().filter { !existing.contains($0.id) }
            current.messages = older + current.messages
            current.hasMore = rows.count == Self.pageSize
            current.isLoadingOlder = false
            threads[id] = current
        } catch {
            threads[id]?.isLoadingOlder = false
        }
    }

    private func persistThread(_ id: UUID) {
        guard let userID, let messages = threads[id]?.messages else { return }
        ChatCache.save(Array(messages.suffix(Self.pageSize)), named: ChatCache.threadName(for: userID, conversation: id))
    }

    /// Marks the thread read up to now, locally at once and on the server shortly after.
    func markRead(_ id: UUID) {
        guard let userID else { return }
        // Never behind the newest message, even if this phone's clock runs slow.
        let now = max(Date(), previews[id]?.createdAt ?? .distantPast)
        if var list = members[id], let index = list.firstIndex(where: { $0.userID == userID }) {
            list[index].lastReadAt = now
            members[id] = list
        } else {
            members[id, default: []].append(ChatMember(conversationID: id, userID: userID, lastReadAt: now, joinedAt: nil))
        }
        if let last = lastReadSync[id], now.timeIntervalSince(last) < 1.5 { return }
        lastReadSync[id] = now
        Task {
            do {
                try await client
                    .from("conversation_members")
                    .update(ReadMark(last_read_at: ChatJSON.isoString(now)), returning: .minimal)
                    .eq("conversation_id", value: id.lower)
                    .eq("user_id", value: userID.lower)
                    .execute()
            } catch {
                lastReadSync[id] = nil
            }
            persistList()
        }
    }

    // MARK: - Live

    private func startInbox(for userID: UUID) {
        guard inboxChannel == nil else { return }
        let channel = client.channel("inbox-\(userID.lower)")
        let joined = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "conversation_members",
            filter: .eq("user_id", value: userID.lower)
        )
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "messages")
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "messages")
        inboxChannel = channel
        inboxTasks = [
            Task {
                for await _ in joined {
                    await ChatStore.shared.refreshAll()
                }
            },
            Task {
                for await change in inserts {
                    if let message = try? change.decodeRecord(as: ChatMessage.self, decoder: ChatJSON.decoder) {
                        ChatStore.shared.ingest(message)
                    }
                }
            },
            Task {
                for await change in updates {
                    if let message = try? change.decodeRecord(as: ChatMessage.self, decoder: ChatJSON.decoder) {
                        ChatStore.shared.ingest(message)
                    }
                }
            }
        ]
        Task {
            do { try await channel.subscribeWithError() } catch { print("[Chat] inbox listener unavailable") }
        }
    }

    private func subscribeThread(_ id: UUID) {
        guard threadChannels[id] == nil else { return }
        let channel = client.channel("thread-\(id.lower)")
        let filter = RealtimePostgresFilter.eq("conversation_id", value: id.lower)
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "messages", filter: filter)
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "messages", filter: filter)
        threadChannels[id] = channel
        threadTasks[id] = [
            Task {
                for await change in inserts {
                    if let message = try? change.decodeRecord(as: ChatMessage.self, decoder: ChatJSON.decoder) {
                        ChatStore.shared.ingest(message)
                    }
                }
            },
            Task {
                for await change in updates {
                    if let message = try? change.decodeRecord(as: ChatMessage.self, decoder: ChatJSON.decoder) {
                        ChatStore.shared.ingest(message)
                    }
                }
            }
        ]
        Task {
            do { try await channel.subscribeWithError() } catch { print("[Chat] thread listener unavailable") }
        }
    }

    /// Folds one message (new or changed) into the thread, the list preview, and the
    /// unread state. The same message can arrive from both listeners and from the send
    /// reply; it is matched by id, so it only ever appears once.
    func ingest(_ message: ChatMessage) {
        let id = message.conversationID
        guard conversations.contains(where: { $0.id == id }) else {
            Task { await refreshAll() }
            return
        }

        if var state = threads[id] {
            withAnimation(.calm) {
                if let index = state.messages.firstIndex(where: { $0.id == message.id }) {
                    state.messages[index] = message
                } else {
                    state.messages.append(message)
                    state.messages.sort { $0.createdAt < $1.createdAt }
                }
                threads[id] = state
            }
            persistThread(id)
        }

        updatePreview(with: message)

        if let index = conversations.firstIndex(where: { $0.id == id }) {
            let current = conversations[index].lastMessageAt ?? .distantPast
            if message.createdAt > current {
                conversations[index].lastMessageAt = message.createdAt
            }
        }

        if activeThreadID == id, message.senderID != userID {
            markRead(id)
        }
        persistList()
    }

    private func updatePreview(with message: ChatMessage) {
        let id = message.conversationID
        if let current = previews[id] {
            if current.id == message.id || message.createdAt >= current.createdAt {
                previews[id] = message
            }
        } else {
            previews[id] = message
        }
    }

    // MARK: - Delivery from the outbox

    func didDeliver(_ message: ChatMessage) {
        ingest(message)
    }

    /// A retry was refused as a duplicate: the message had already landed. Fetch the
    /// newest page so the real row takes the pending one's place.
    func didDeliverEarlier(conversationID: UUID) {
        Task { await loadLatest(conversationID) }
    }

    // MARK: - Message actions

    /// Deletes for everyone, and overwrites the stored words so they're gone for good.
    func delete(_ message: ChatMessage) async -> Bool {
        guard let userID, message.senderID == userID else { return false }
        let now = Date()
        var updated = message
        updated.deletedAt = now
        updated.body = ChatMessage.deletedText
        ingest(updated)
        do {
            try await client
                .from("messages")
                .update(Deletion(deleted_at: ChatJSON.isoString(now), body: ChatMessage.deletedText), returning: .minimal)
                .eq("id", value: message.id.lower)
                .eq("sender_id", value: userID.lower)
                .execute()
            return true
        } catch {
            print("[Chat] message could not be deleted")
            ingest(message)
            return false
        }
    }

    func report(_ message: ChatMessage) async -> Bool {
        guard let userID else { return false }
        do {
            try await client
                .from("message_reports")
                .insert(
                    NewReport(message_id: message.id.lower, reporter_id: userID.lower, reason: "Reported from the app"),
                    returning: .minimal
                )
                .execute()
            return true
        } catch {
            if case .duplicate = ChatBackend.classify(error, isOnline: true) { return true }
            print("[Chat] report could not be sent")
            return false
        }
    }

    func block(_ person: UUID) async -> Bool {
        guard let userID, person != userID else { return false }
        withAnimation(.calm) { _ = blocked.insert(person) }
        do {
            try await client
                .from("user_blocks")
                .insert(NewBlock(blocker_id: userID.lower, blocked_id: person.lower), returning: .minimal)
                .execute()
            persistList()
            return true
        } catch {
            if case .duplicate = ChatBackend.classify(error, isOnline: true) { return true }
            print("[Chat] block could not be saved")
            withAnimation(.calm) { _ = blocked.remove(person) }
            return false
        }
    }

    func unblock(_ person: UUID) async -> Bool {
        guard let userID else { return false }
        do {
            try await client
                .from("user_blocks")
                .delete(returning: .minimal)
                .eq("blocker_id", value: userID.lower)
                .eq("blocked_id", value: person.lower)
                .execute()
            withAnimation(.calm) { _ = blocked.remove(person) }
            persistList()
            return true
        } catch {
            print("[Chat] unblock could not be saved")
            return false
        }
    }

    // MARK: - Starting and leaving conversations

    /// Opens the private chat with this person, reusing the one that already exists.
    func startDirect(with person: UUID) async -> UUID? {
        if let existing = conversations.first(where: { isDirect($0) && otherMember(in: $0) == person }) {
            return existing.id
        }
        do {
            let response = try await client
                .rpc("create_direct_conversation", params: DirectParams(other_user: person.lower))
                .execute()
            let id = ChatBackend.decodeID(response.data)
            await refreshAll()
            return id
        } catch {
            print("[Chat] private chat could not be started")
            return nil
        }
    }

    func startGroup(title: String, with people: [UUID]) async -> UUID? {
        guard let clean = ChatJSON.clean(title) else { return nil }
        do {
            let response = try await client
                .rpc("create_group_conversation", params: GroupParams(group_title: clean, member_ids: people.map(\.lower)))
                .execute()
            let id = ChatBackend.decodeID(response.data)
            await refreshAll()
            return id
        } catch {
            print("[Chat] group could not be created")
            return nil
        }
    }

    func leave(_ conversationID: UUID) async -> Bool {
        do {
            try await client
                .rpc("leave_group", params: LeaveParams(conv: conversationID.lower))
                .execute()
            closeThread(conversationID)
            withAnimation(.calm) {
                conversations.removeAll { $0.id == conversationID }
                members[conversationID] = nil
                previews[conversationID] = nil
                threads[conversationID] = nil
            }
            persistList()
            return true
        } catch {
            print("[Chat] could not leave the group")
            return false
        }
    }

    // MARK: - Admin

    func refreshAdmin() async {
        do {
            let waiting: [ChatProfile] = try await client
                .from("profiles")
                .select(ChatProfile.columns)
                .eq("status", value: "pending")
                .order("created_at", ascending: true)
                .execute()
                .value

            let open: [ChatReport] = try await client
                .from("message_reports")
                .select(ChatReport.columns)
                .is("resolved_at", value: nil)
                .order("created_at", ascending: false)
                .execute()
                .value

            var messages: [UUID: ChatMessage] = [:]
            let messageIDs = Array(Set(open.map(\.messageID)))
            if !messageIDs.isEmpty {
                let rows: [ChatMessage] = (try? await client
                    .from("messages")
                    .select(ChatMessage.columns)
                    .in("id", values: Self.filterValues(messageIDs))
                    .execute()
                    .value) ?? []
                for row in rows { messages[row.id] = row }
            }

            let people = Set(open.compactMap(\.reporterID) + messages.values.map(\.senderID))
            let unknown = Array(people.subtracting(Set(profiles.keys)))
            if !unknown.isEmpty {
                let rows: [ChatProfile] = (try? await client
                    .from("profiles")
                    .select(ChatProfile.columns)
                    .in("id", values: Self.filterValues(unknown))
                    .execute()
                    .value) ?? []
                for row in rows { profiles[row.id] = row }
            }

            withAnimation(.calm) {
                pendingPeople = waiting
                reports = open
                reportedMessages = messages
            }
        } catch {
            print("[Chat] admin lists postponed")
        }
    }

    /// Welcomes someone in, or turns them away.
    func setStatus(of person: ChatProfile, approved: Bool) async -> Bool {
        do {
            try await client
                .rpc("set_user_status", params: StatusParams(target: person.id.lower, new_status: approved ? "approved" : "blocked"))
                .execute()
            withAnimation(.calm) {
                pendingPeople.removeAll { $0.id == person.id }
                var updated = person
                updated.status = approved ? "approved" : "blocked"
                profiles[person.id] = updated
            }
            return true
        } catch {
            print("[Chat] status change failed")
            return false
        }
    }

    func resolve(_ report: ChatReport) async -> Bool {
        do {
            try await client
                .from("message_reports")
                .update(Resolution(resolved_at: ChatJSON.isoString(Date())), returning: .minimal)
                .eq("id", value: report.id.lower)
                .execute()
            withAnimation(.calm) {
                reports.removeAll { $0.id == report.id }
            }
            return true
        } catch {
            print("[Chat] report could not be resolved")
            return false
        }
    }
}
