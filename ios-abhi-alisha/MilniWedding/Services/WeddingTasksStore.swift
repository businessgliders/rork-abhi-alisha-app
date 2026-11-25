import Foundation
import Observation
import SwiftUI
import Supabase

/// What the compose sheet hands back.
nonisolated struct ChecklistDraft: Sendable {
    var title: String
    var notes: String?
    var category: String?
    var dueDate: Date?
}

/// One wedding's checklist, read from and written to `wedding_tasks`.
///
/// Changes land on screen at once and are sent straight away; the host and co-hosts see
/// each other's ticks live. A saved copy per wedding opens the list instantly next time.
@Observable
final class WeddingTasksStore {
    let weddingID: String

    private(set) var items: [ChecklistItem] = []
    private(set) var hasLoadedFromServer = false
    private(set) var loadFailed = false
    private(set) var savingCount = 0
    /// A plain-words problem to show, cleared on the next success.
    var errorMessage: String?

    private var channel: RealtimeChannelV2?
    private var listenTasks: [Task<Void, Never>] = []
    private var client: SupabaseClient { ChatBackend.client }

    init(weddingID: String) {
        self.weddingID = weddingID.lowercased()
        restore()
    }

    // MARK: - Reading

    var visibleItems: [ChecklistItem] {
        items.filter { $0.title != nil }
    }

    var completedCount: Int { visibleItems.filter(\.isDone).count }
    var totalCount: Int { visibleItems.count }

    var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    var hasPendingChanges: Bool { savingCount > 0 }

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

    var categories: [String] { sections.map(\.name) }

    nonisolated private static func inOrder(_ lhs: ChecklistItem, _ rhs: ChecklistItem) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return (lhs.title ?? "").localizedCaseInsensitiveCompare(rhs.title ?? "") == .orderedAscending
    }

    // MARK: - Loading and live updates

    func refresh() async {
        do {
            let response = try await client.from("wedding_tasks")
                .select()
                .eq("wedding_id", value: weddingID)
                .order("sort_order", ascending: true)
                .execute()
            let rows = try JSONDecoder().decode([[String: JSONValue]].self, from: response.data)
            let fresh = rows.compactMap(ChecklistItem.init(raw:))
            // Keep anything still on its way up.
            let local = items.filter(\.isLocalOnly)
            items = fresh + local
            hasLoadedFromServer = true
            loadFailed = false
            persist()
        } catch {
            loadFailed = true
            if items.isEmpty { errorMessage = error.hostMessage }
        }
        startListening()
    }

    func startListening() {
        guard channel == nil else { return }
        let channel = client.channel("wedding-tasks-\(weddingID)")
        let filter = RealtimePostgresFilter.eq("wedding_id", value: weddingID)
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "wedding_tasks", filter: filter)
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "wedding_tasks", filter: filter)
        let deletes = channel.postgresChange(DeleteAction.self, schema: "public", table: "wedding_tasks")
        self.channel = channel
        listenTasks = [
            Task { [weak self] in
                for await change in inserts {
                    self?.ingest(Self.jsonRecord(change.record))
                }
            },
            Task { [weak self] in
                for await change in updates {
                    self?.ingest(Self.jsonRecord(change.record))
                }
            },
            Task { [weak self] in
                for await change in deletes {
                    guard let self else { return }
                    if let id = Self.jsonRecord(change.oldRecord)?["id"]?.stringValue {
                        withAnimation(.calm) { self.items.removeAll { $0.id == id } }
                        self.persist()
                    } else {
                        await self.refresh()
                    }
                }
            }
        ]
        Task {
            do { try await channel.subscribeWithError() } catch { print("[Tasks] live updates unavailable") }
        }
    }

    func stopListening() {
        listenTasks.forEach { $0.cancel() }
        listenTasks = []
        if let channel {
            self.channel = nil
            Task { await ChatBackend.client.removeChannel(channel) }
        }
    }

    private func ingest(_ raw: [String: JSONValue]?) {
        guard let raw, let item = ChecklistItem(raw: raw),
              raw["wedding_id"]?.stringValue?.lowercased() ?? weddingID == weddingID else { return }
        withAnimation(.calm) {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = item
            } else if !items.contains(where: { $0.isLocalOnly && $0.title == item.title }) {
                // A task added here is placed by its own save reply instead.
                items.append(item)
            }
        }
        persist()
    }

    private nonisolated static func jsonRecord(_ record: [String: AnyJSON]) -> [String: JSONValue]? {
        guard let data = try? JSONEncoder().encode(record) else { return nil }
        return try? JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    // MARK: - Changes

    func toggle(_ item: ChecklistItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let isDone = !items[index].isDone
        var changes: [String: JSONValue] = ["done": .bool(isDone)]
        if isDone {
            changes["done_by"] = ChatSession.shared.userID.map { .string($0.lower) } ?? .null
            changes["done_at"] = .string(HostAPI.iso(Date()))
        } else {
            changes["done_by"] = .null
            changes["done_at"] = .null
        }
        // Older rows may carry another done key; keep it in step.
        let key = items[index].doneKey
        if key != "done" { items[index].fields[key] = .bool(isDone) }
        Self.apply(changes, to: &items[index])
        persist()
        send(update: item.id, changes)
    }

    func add(_ draft: ChecklistDraft) {
        addAll([draft])
    }

    func addAll(_ drafts: [ChecklistDraft]) {
        guard !drafts.isEmpty else { return }
        for (offset, draft) in drafts.enumerated() {
            let order = nextSortOrder(in: draft.category) + Double(offset)
            var row: [String: JSONValue] = [
                "wedding_id": .string(weddingID),
                "title": .string(draft.title),
                "done": .bool(false),
                "sort_order": .number(order)
            ]
            if let notes = draft.notes { row["notes"] = .string(notes) }
            if let category = draft.category { row["category"] = .string(category) }
            if let due = draft.dueDate { row["due_date"] = .string(ChecklistDates.string(from: due)) }
            if let me = ChatSession.shared.userID?.lower { row["created_by"] = .string(me) }

            let localID = ChecklistItem.localPrefix + UUID().uuidString
            var fields = row
            fields["id"] = .string(localID)
            items.append(ChecklistItem(id: localID, fields: fields))
            send(insert: row, localID: localID)
        }
        persist()
    }

    func edit(_ item: ChecklistItem, with draft: ChecklistDraft) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let current = items[index]
        var changes: [String: JSONValue] = [:]
        if current.title != draft.title { changes["title"] = .string(draft.title) }
        if current.notes != draft.notes { changes["notes"] = draft.notes.map(JSONValue.string) ?? .null }
        if current.category != draft.category {
            changes["category"] = draft.category.map(JSONValue.string) ?? .null
        }
        let newDue = draft.dueDate.map(ChecklistDates.string(from:))
        let oldDue = current.dueDate.map(ChecklistDates.string(from:))
        if newDue != oldDue { changes["due_date"] = newDue.map(JSONValue.string) ?? .null }
        guard !changes.isEmpty else { return }
        Self.apply(changes, to: &items[index])
        persist()
        send(update: item.id, changes)
    }

    func delete(_ item: ChecklistItem) {
        items.removeAll { $0.id == item.id }
        persist()
        guard !item.isLocalOnly else { return }
        Task {
            savingCount += 1
            defer { savingCount -= 1 }
            do {
                try await client.from("wedding_tasks").delete().eq("id", value: item.id).execute()
                errorMessage = nil
            } catch {
                errorMessage = error.hostMessage
                await refresh()
            }
        }
    }

    /// Drag to reorder within a category. Every task is renumbered in on-screen order,
    /// so categories keep their place and the order is the same on every phone.
    func move(in sectionName: String, from source: IndexSet, to destination: Int) {
        var ordered = sections
        guard let index = ordered.firstIndex(where: { $0.name == sectionName }) else { return }
        var moved = ordered[index].items
        moved.move(fromOffsets: source, toOffset: destination)
        ordered[index] = ChecklistSection(name: sectionName, items: moved)

        var changed: [(String, Int)] = []
        for (position, item) in ordered.flatMap(\.items).enumerated() {
            guard let itemIndex = items.firstIndex(where: { $0.id == item.id }) else { continue }
            if items[itemIndex].sortOrder != Double(position) {
                items[itemIndex].fields["sort_order"] = .number(Double(position))
                if !item.isLocalOnly { changed.append((item.id, position)) }
            }
        }
        persist()
        guard !changed.isEmpty else { return }
        Task {
            savingCount += 1
            defer { savingCount -= 1 }
            do {
                for (id, position) in changed {
                    try await client.from("wedding_tasks")
                        .update(["sort_order": AnyJSON.integer(position)])
                        .eq("id", value: id)
                        .execute()
                }
                errorMessage = nil
            } catch {
                errorMessage = error.hostMessage
                await refresh()
            }
        }
    }

    // MARK: - Sending

    private func send(update id: String, _ changes: [String: JSONValue]) {
        guard !id.hasPrefix(ChecklistItem.localPrefix) else { return }
        Task {
            savingCount += 1
            defer { savingCount -= 1 }
            do {
                try await client.from("wedding_tasks")
                    .update(changes.mapValues(Self.any))
                    .eq("id", value: id)
                    .execute()
                errorMessage = nil
            } catch {
                errorMessage = error.hostMessage
                await refresh()
            }
        }
    }

    private func send(insert row: [String: JSONValue], localID: String) {
        Task {
            savingCount += 1
            defer { savingCount -= 1 }
            do {
                let response = try await client.from("wedding_tasks")
                    .insert(row.mapValues(Self.any), returning: .representation)
                    .execute()
                let rows = (try? JSONDecoder().decode([[String: JSONValue]].self, from: response.data)) ?? []
                if let saved = rows.first.flatMap(ChecklistItem.init(raw:)) {
                    withAnimation(.calm) {
                        if let index = items.firstIndex(where: { $0.id == localID }) {
                            if items.contains(where: { $0.id == saved.id }) {
                                items.remove(at: index)
                            } else {
                                items[index] = saved
                            }
                        } else {
                            // Deleted while it was on its way up.
                            Task { _ = try? await self.client.from("wedding_tasks").delete().eq("id", value: saved.id).execute() }
                        }
                    }
                    persist()
                }
                errorMessage = nil
            } catch {
                items.removeAll { $0.id == localID }
                persist()
                errorMessage = error.hostMessage
            }
        }
    }

    nonisolated static func any(_ value: JSONValue) -> AnyJSON {
        switch value {
        case .string(let text): return .string(text)
        case .number(let number):
            if number.rounded() == number, abs(number) < 1e15 { return .integer(Int(number)) }
            return .double(number)
        case .bool(let flag): return .bool(flag)
        case .object(let object): return .object(object.mapValues(any))
        case .array(let list): return .array(list.map(any))
        case .null: return .null
        }
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
        let orders = visibleItems.map(\.sortOrder).filter { $0 < .greatestFiniteMagnitude }
        return (orders.max() ?? -1) + 1
    }

    // MARK: - Disk

    private var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("wedding-tasks-\(weddingID).json")
    }

    private func persist() {
        guard let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let saved = items.filter { !$0.isLocalOnly }
            let data = try JSONEncoder().encode(saved)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("[Tasks] could not save locally")
        }
    }

    private func restore() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([ChecklistItem].self, from: data) else { return }
        items = saved
    }
}
