import Foundation
import Network
import Observation

/// A change waiting to reach the backend.
nonisolated struct ChecklistOperation: Codable, Hashable, Identifiable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case create
        case update
        case delete
    }

    var id: UUID = UUID()
    var kind: Kind
    var itemID: String
    var data: [String: JSONValue]
}

/// What the compose sheet hands back.
nonisolated struct ChecklistDraft: Sendable {
    var title: String
    var notes: String?
    var category: String?
    var dueDate: Date?
}

nonisolated private struct ChecklistSnapshot: Codable {
    var items: [ChecklistItem]
    var pending: [ChecklistOperation]
}

/// The wedding-day checklist, offline first.
///
/// Every change lands on screen and on disk immediately, then joins a queue that is sent
/// in order whenever there's a connection — straight away if there is one, or the moment
/// the network returns. Items created offline carry a local id until the backend names them.
@Observable
final class ChecklistStore {
    private(set) var items: [ChecklistItem] = []
    private(set) var pending: [ChecklistOperation] = []
    private(set) var isSyncing = false
    private(set) var hasLoadedFromServer = false
    private(set) var loadFailed = false

    private let session: AdminSession
    private let service: AdminService = .shared
    private var inFlightID: UUID?
    private var monitor: NWPathMonitor?

    init(session: AdminSession) {
        self.session = session
        restore()
    }

    // MARK: - Reading

    var visibleItems: [ChecklistItem] {
        items.filter { $0.isActive && $0.title != nil }
    }

    var completedCount: Int { visibleItems.filter(\.isDone).count }
    var totalCount: Int { visibleItems.count }

    var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    var hasPendingChanges: Bool { !pending.isEmpty }

    /// Grouped by category; categories follow the order of their first task.
    var sections: [ChecklistSection] {
        let grouped = Dictionary(grouping: visibleItems) { $0.category ?? "General" }
        return grouped
            .map { ChecklistSection(name: $0.key, items: $0.value.sorted(by: Self.inOrder)) }
            .sorted { lhs, rhs in
                let left = lhs.items.first?.sortOrder ?? .greatestFiniteMagnitude
                let right = rhs.items.first?.sortOrder ?? .greatestFiniteMagnitude
                if left != right { return left < right }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    /// Categories already in use, for the compose sheet's suggestions.
    var categories: [String] {
        sections.map(\.name)
    }

    private static func inOrder(_ lhs: ChecklistItem, _ rhs: ChecklistItem) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return (lhs.title ?? "").localizedCaseInsensitiveCompare(rhs.title ?? "") == .orderedAscending
    }

    // MARK: - Connection

    /// Watches the network so queued changes go out the moment it returns.
    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                await self?.sync()
            }
        }
        monitor.start(queue: DispatchQueue(label: "abhialisha.checklist.network"))
        self.monitor = monitor
    }

    // MARK: - Changes

    func toggle(_ item: ChecklistItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let key = items[index].doneKey
        let value = JSONValue.bool(!items[index].isDone)
        items[index].fields[key] = value
        enqueueUpdate(item.id, [key: value])
    }

    func add(_ draft: ChecklistDraft) {
        let id = ChecklistItem.localPrefix + UUID().uuidString
        var data: [String: JSONValue] = [
            "title": .string(draft.title),
            "is_done": .bool(false),
            "sort_order": .number(nextSortOrder(in: draft.category))
        ]
        if let notes = draft.notes { data["notes"] = .string(notes) }
        if let category = draft.category { data["category"] = .string(category) }
        if let due = draft.dueDate { data["due_date"] = .string(ChecklistDates.string(from: due)) }

        var fields = data
        fields["id"] = .string(id)
        items.append(ChecklistItem(id: id, fields: fields))
        pending.append(ChecklistOperation(kind: .create, itemID: id, data: data))
        commit()
    }

    func edit(_ item: ChecklistItem, with draft: ChecklistDraft) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let current = items[index]
        var changes: [String: JSONValue] = [:]

        if current.title != draft.title {
            changes["title"] = .string(draft.title)
        }
        if current.notes != draft.notes {
            changes["notes"] = draft.notes.map(JSONValue.string) ?? .null
        }
        if current.category != draft.category {
            changes["category"] = draft.category.map(JSONValue.string) ?? .null
        }
        let newDue = draft.dueDate.map(ChecklistDates.string(from:))
        let oldDue = current.dueDate.map(ChecklistDates.string(from:))
        if newDue != oldDue {
            changes[current.dueKey] = newDue.map(JSONValue.string) ?? .null
        }

        guard !changes.isEmpty else { return }
        Self.apply(changes, to: &items[index])
        enqueueUpdate(item.id, changes)
    }

    func delete(_ item: ChecklistItem) {
        items.removeAll { $0.id == item.id }
        pending.removeAll { $0.itemID == item.id && $0.id != inFlightID }
        // Something the backend never saw needs no delete; one mid-flight is caught
        // when it lands (see `settleCreate`).
        if !item.isLocalOnly {
            pending.append(ChecklistOperation(kind: .delete, itemID: item.id, data: [:]))
        }
        commit()
    }

    // MARK: - Sync

    /// Sends queued changes, then reloads from the backend once nothing is waiting.
    func refresh() async {
        guard let code = session.code else { return }
        await sync()
        guard pending.isEmpty else { return }

        do {
            let serverItems = try await service.listChecklist(code: code)
            items = overlayPending(on: serverItems)
            hasLoadedFromServer = true
            loadFailed = false
            persist()
        } catch AdminError.unauthorized {
            session.invalidate()
        } catch {
            loadFailed = true
        }
    }

    func sync() async {
        guard !isSyncing, let code = session.code, !pending.isEmpty else { return }
        isSyncing = true
        defer {
            isSyncing = false
            inFlightID = nil
        }

        while let operation = pending.first {
            inFlightID = operation.id
            do {
                switch operation.kind {
                case .create:
                    let created = try await service.saveChecklistItem(id: nil, data: operation.data, code: code)
                    settleCreate(localID: operation.itemID, server: created)
                case .update:
                    _ = try await service.saveChecklistItem(id: operation.itemID, data: operation.data, code: code)
                case .delete:
                    try await service.deleteChecklistItem(id: operation.itemID, code: code)
                }
                pending.removeAll { $0.id == operation.id }
            } catch AdminError.unauthorized {
                persist()
                session.invalidate()
                return
            } catch AdminError.rejected {
                // The backend will never take this one; don't let it block the rest.
                pending.removeAll { $0.id == operation.id }
            } catch {
                // Offline or a server hiccup: keep everything and try again later.
                persist()
                return
            }
            inFlightID = nil
            persist()
        }
    }

    // MARK: - Queue bookkeeping

    private func enqueueUpdate(_ id: String, _ changes: [String: JSONValue]) {
        if let index = pending.lastIndex(where: {
            $0.itemID == id && $0.kind != .delete && $0.id != inFlightID
        }) {
            for (key, value) in changes { pending[index].data[key] = value }
        } else {
            pending.append(ChecklistOperation(kind: .update, itemID: id, data: changes))
        }
        commit()
    }

    private func settleCreate(localID: String, server: ChecklistItem?) {
        guard let serverID = server?.id else { return }
        for index in pending.indices where pending[index].itemID == localID {
            pending[index].itemID = serverID
        }
        if let index = items.firstIndex(where: { $0.id == localID }) {
            items[index].id = serverID
            items[index].fields["id"] = .string(serverID)
        } else {
            // Deleted while it was on its way up.
            pending.append(ChecklistOperation(kind: .delete, itemID: serverID, data: [:]))
        }
    }

    /// Server truth, with anything still queued laid over it.
    private func overlayPending(on server: [ChecklistItem]) -> [ChecklistItem] {
        var result = server
        for operation in pending {
            switch operation.kind {
            case .create:
                if let local = items.first(where: { $0.id == operation.itemID }),
                   !result.contains(where: { $0.id == operation.itemID }) {
                    result.append(local)
                }
            case .update:
                if let index = result.firstIndex(where: { $0.id == operation.itemID }) {
                    Self.apply(operation.data, to: &result[index])
                }
            case .delete:
                result.removeAll { $0.id == operation.itemID }
            }
        }
        return result
    }

    private static func apply(_ data: [String: JSONValue], to item: inout ChecklistItem) {
        for (key, value) in data {
            if value.isNull {
                item.fields.removeValue(forKey: key)
            } else {
                item.fields[key] = value
            }
        }
    }

    private func nextSortOrder(in category: String?) -> Double {
        let peers = visibleItems.filter { $0.category == category }
        let orders = (peers.isEmpty ? visibleItems : peers)
            .map(\.sortOrder)
            .filter { $0 < .greatestFiniteMagnitude }
        return (orders.max() ?? Double(visibleItems.count)) + 1
    }

    private func commit() {
        persist()
        Task { await sync() }
    }

    // MARK: - Disk

    private static var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("couple-checklist.json")
    }

    private func persist() {
        guard let url = Self.fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(ChecklistSnapshot(items: items, pending: pending))
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("[ChecklistStore] could not save locally")
        }
    }

    private func restore() {
        guard let url = Self.fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ChecklistSnapshot.self, from: data) else { return }
        items = snapshot.items
        pending = snapshot.pending
    }
}
