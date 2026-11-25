import Foundation
import Network
import Observation
import Supabase

/// Messages written on this phone that the server hasn't confirmed yet.
///
/// Every message keeps the `client_id` it was born with, so a retry is always the same
/// message. If a send reached the server but the reply was lost, the retry comes back
/// as a duplicate-key error, which means it was already delivered. Nothing is ever lost
/// (the queue is saved to disk) and nothing is ever sent twice.
@Observable
final class ChatOutbox {
    static let shared = ChatOutbox()

    private(set) var items: [PendingMessage] = []
    private(set) var isOnline = true

    private var userID: UUID?
    private var isFlushing = false
    private var needsAnotherFlush = false
    private var monitor: NWPathMonitor?

    nonisolated private struct NewMessage: Encodable, Sendable {
        let conversation_id: String
        let sender_id: String
        let body: String
        let client_id: String
    }

    // MARK: - Lifecycle

    func activate(userID: UUID) {
        guard self.userID != userID else {
            Task { await flush() }
            return
        }
        self.userID = userID
        let saved = ChatCache.load([PendingMessage].self, named: ChatCache.outboxName(for: userID)) ?? []
        // Anything that was mid-flight when the app closed simply goes again.
        items = saved.map { item in
            var item = item
            if item.state == .sending { item.state = .queued }
            return item
        }
        startMonitoring()
        Task { await flush() }
    }

    func reset() {
        userID = nil
        items = []
    }

    // MARK: - Writing

    func enqueue(_ text: String, in conversationID: UUID) {
        guard let userID else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        items.append(
            PendingMessage(
                clientID: UUID(),
                conversationID: conversationID,
                senderID: userID,
                body: body,
                createdAt: Date(),
                state: .queued
            )
        )
        persist()
        Task { await flush() }
    }

    func retry(_ clientID: UUID) {
        guard let index = items.firstIndex(where: { $0.clientID == clientID }) else { return }
        items[index].state = .queued
        persist()
        Task { await flush() }
    }

    func discard(_ clientID: UUID) {
        items.removeAll { $0.clientID == clientID }
        persist()
    }

    func pending(in conversationID: UUID) -> [PendingMessage] {
        items.filter { $0.conversationID == conversationID }
    }

    // MARK: - Sending

    /// Sends queued messages in the order they were written. Stops at the first sign of
    /// no connection and waits for the network to come back.
    func flush() async {
        guard userID != nil else { return }
        guard !isFlushing else {
            needsAnotherFlush = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }

        let queue = items.filter { $0.state == .queued }.map(\.clientID)
        for clientID in queue {
            guard let index = items.firstIndex(where: { $0.clientID == clientID }),
                  items[index].state == .queued else { continue }
            items[index].state = .sending
            let item = items[index]

            do {
                let row: ChatMessage = try await ChatBackend.client
                    .from("messages")
                    .insert(
                        NewMessage(
                            conversation_id: item.conversationID.lower,
                            sender_id: item.senderID.lower,
                            body: item.body,
                            client_id: item.clientID.lower
                        ),
                        returning: .representation
                    )
                    .select(ChatMessage.columns)
                    .single()
                    .execute()
                    .value
                items.removeAll { $0.clientID == clientID }
                persist()
                ChatStore.shared.didDeliver(row)
            } catch {
                switch ChatBackend.classify(error, isOnline: isOnline) {
                case .duplicate:
                    items.removeAll { $0.clientID == clientID }
                    persist()
                    ChatStore.shared.didDeliverEarlier(conversationID: item.conversationID)
                case .offline:
                    setState(.queued, for: clientID)
                    // A timeout while the phone still has a connection: try again
                    // shortly with the same client_id. If the first attempt landed,
                    // the retry comes back as a duplicate and is simply dropped.
                    if isOnline { scheduleRetry() }
                    return
                case .rejected:
                    print("[Chat] a message could not be sent")
                    setState(.failed, for: clientID)
                }
            }
        }

        if needsAnotherFlush {
            needsAnotherFlush = false
            await flush()
        }
    }

    private var retryTask: Task<Void, Never>?

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task {
            try? await Task.sleep(for: .seconds(4))
            retryTask = nil
            await flush()
        }
    }

    private func setState(_ state: PendingMessage.State, for clientID: UUID) {
        guard let index = items.firstIndex(where: { $0.clientID == clientID }) else { return }
        items[index].state = state
        persist()
    }

    private func persist() {
        guard let userID else { return }
        ChatCache.save(items, named: ChatCache.outboxName(for: userID))
    }

    // MARK: - Connectivity

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = Self.makeMonitor { online in
            Task { @MainActor in
                ChatOutbox.shared.connectivityChanged(online)
            }
        }
    }

    private func connectivityChanged(_ online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        if cameBack {
            Task {
                await flush()
                await ChatStore.shared.reconnect()
            }
        }
    }

    private nonisolated static func makeMonitor(onChange: @escaping @Sendable (Bool) -> Void) -> NWPathMonitor {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            onChange(path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "chat.connectivity"))
        return monitor
    }
}
