import Foundation
import Observation
import Supabase
import SwiftUI
import UIKit

/// A photo on its way up to the `outfits` bucket, shown in place straight away.
struct PendingOutfitUpload: Identifiable, Equatable {
    let id = UUID()
    let eventID: String
    let category: OutfitCategory
    let preview: UIImage
    var didFail = false

    static func == (lhs: PendingOutfitUpload, rhs: PendingOutfitUpload) -> Bool {
        lhs.id == rhs.id && lhs.didFail == rhs.didFail
    }
}

/// A guest's own looks for the wedding week.
///
/// Photos live in the private `outfits` bucket at `<user id>/<uuid>.jpg`, with a row in
/// `outfit_items` for each. The list and every photo already seen are kept on the phone,
/// so My Outfits opens instantly and works with no connection; the server is read
/// quietly behind it. The "Don't forget" ticks and Men/Women choice never leave the phone.
@Observable
final class OutfitStore {
    static let shared = OutfitStore()
    static let bucket = "outfits"
    static let noteLimit = 200

    private(set) var items: [OutfitItem] = []
    private(set) var uploads: [PendingOutfitUpload] = []
    private(set) var busyItemIDs: Set<String> = []
    private(set) var loadedEventIDs: Set<String> = []
    /// A short, calm line after something didn't save.
    var notice: String?

    var gender: OutfitGender {
        didSet { defaults.set(gender.rawValue, forKey: Key.gender) }
    }
    private(set) var ticks: Set<String>

    private var userID: UUID?
    private let defaults = UserDefaults.standard

    private enum Key {
        static let gender = "outfits.gender"
        static let ticks = "outfits.ticks"
    }

    private init() {
        gender = OutfitGender(rawValue: UserDefaults.standard.string(forKey: Key.gender) ?? "") ?? .women
        ticks = Set(UserDefaults.standard.stringArray(forKey: Key.ticks) ?? [])
    }

    // MARK: - Reading

    func items(for eventID: String, category: OutfitCategory) -> [OutfitItem] {
        items
            .filter { $0.eventID == eventID && $0.category == category.rawValue }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    func uploads(for eventID: String, category: OutfitCategory) -> [PendingOutfitUpload] {
        uploads.filter { $0.eventID == eventID && $0.category == category }
    }

    /// How many of the four slots hold at least one photo.
    func filledSlots(for eventID: String) -> Int {
        OutfitCategory.allCases.filter { category in
            items.contains { $0.eventID == eventID && $0.category == category.rawValue }
        }.count
    }

    /// The photo that stands for a look: the first outfit photo, else anything.
    func coverItem(for eventID: String) -> OutfitItem? {
        items(for: eventID, category: .outfit).first
            ?? items.first { $0.eventID == eventID }
    }

    // MARK: - Session

    /// Picks up whoever is signed in to the chat, loading their saved looks from the phone.
    func syncUser() {
        let current = ChatSession.shared.userID
        guard current != userID else { return }
        userID = current
        loadedEventIDs = []
        uploads = []
        if let current {
            items = OutfitDisk.loadItems(for: current) ?? []
        } else {
            items = []
        }
    }

    /// Signing out forgets every look and photo this phone was holding.
    func reset() {
        userID = nil
        items = []
        uploads = []
        loadedEventIDs = []
        OutfitPhotoCache.shared.wipe()
        OutfitDisk.wipe()
    }

    // MARK: - Refresh

    /// One celebration's photos, read again from the server.
    func refresh(eventID: String) async {
        syncUser()
        guard userID != nil else { return }
        do {
            let rows: [OutfitItem] = try await ChatBackend.client
                .from("outfit_items")
                .select()
                .eq("event_id", value: eventID)
                .execute()
                .value
            items.removeAll { $0.eventID == eventID }
            items.append(contentsOf: rows)
            loadedEventIDs.insert(eventID)
            persist()
            OutfitPhotoCache.shared.prefetch(rows.map(\.photoPath))
        } catch {
            print("[Outfits] refresh postponed")
        }
    }

    /// Every look at once, for the My Outfits list.
    func refreshAll() async {
        syncUser()
        guard let userID else { return }
        do {
            let rows: [OutfitItem] = try await ChatBackend.client
                .from("outfit_items")
                .select()
                .eq("user_id", value: userID.lower)
                .execute()
                .value
            items = rows
            loadedEventIDs = Set(rows.map(\.eventID))
            persist()
            let covers = Set(rows.map(\.eventID)).compactMap { coverItem(for: $0)?.photoPath }
            OutfitPhotoCache.shared.prefetch(covers)
        } catch {
            print("[Outfits] refresh postponed")
        }
    }

    // MARK: - Adding

    /// Resizes, uploads to `<user id>/<uuid>.jpg`, then records the row. The photo shows in
    /// place at once and only disappears if it truly couldn't be saved.
    func add(_ image: UIImage, eventID: String, category: OutfitCategory) async {
        syncUser()
        guard let userID else { return }
        let pending = PendingOutfitUpload(eventID: eventID, category: category, preview: image)
        withAnimation(.calm) { uploads.append(pending) }

        do {
            guard let data = await OutfitImageProcessor.jpeg(from: image) else { throw OutfitError.encoding }
            let path = "\(userID.lower)/\(UUID().uuidString.lowercased()).jpg"
            try await upload(data, to: path)
            OutfitPhotoCache.shared.store(data, for: path)

            let insert = OutfitItemInsert(event_id: eventID, category: category.rawValue, photo_path: path, note: nil)
            let row: OutfitItem
            do {
                row = try await ChatBackend.client
                    .from("outfit_items")
                    .insert(insert, returning: .representation)
                    .select()
                    .single()
                    .execute()
                    .value
            } catch {
                // The row never landed, so the file would be orphaned.
                _ = try? await ChatBackend.client.storage.from(Self.bucket).remove(paths: [path])
                throw error
            }

            withAnimation(.calm) {
                uploads.removeAll { $0.id == pending.id }
                items.append(row)
            }
            persist()
            BrandHaptics.tick()
        } catch {
            print("[Outfits] photo could not be saved")
            withAnimation(.calm) { uploads.removeAll { $0.id == pending.id } }
            notice = "That photo didn't save. Please check your connection and try again."
        }
    }

    // MARK: - Changing

    /// Swaps a photo for a new one, keeping its note and its place.
    func replace(_ item: OutfitItem, with image: UIImage) async {
        guard let userID, !busyItemIDs.contains(item.id) else { return }
        busyItemIDs.insert(item.id)
        defer { busyItemIDs.remove(item.id) }

        do {
            guard let data = await OutfitImageProcessor.jpeg(from: image) else { throw OutfitError.encoding }
            let path = "\(userID.lower)/\(UUID().uuidString.lowercased()).jpg"
            try await upload(data, to: path)
            OutfitPhotoCache.shared.store(data, for: path)
            try await ChatBackend.client
                .from("outfit_items")
                .update(OutfitPathChange(photo_path: path), returning: .minimal)
                .eq("id", value: item.id)
                .execute()

            let oldPath = item.photoPath
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                withAnimation(.calm) { items[index].photoPath = path }
            }
            persist()
            OutfitPhotoCache.shared.remove(oldPath)
            _ = try? await ChatBackend.client.storage.from(Self.bucket).remove(paths: [oldPath])
            BrandHaptics.tick()
        } catch {
            print("[Outfits] photo could not be replaced")
            notice = "That photo didn't change. Please try again."
        }
    }

    /// Saves a note of up to 200 characters; an empty note clears it.
    @discardableResult
    func setNote(_ text: String, for item: OutfitItem) async -> Bool {
        let clean = String(text.trimmed.prefix(Self.noteLimit)).nonEmpty
        do {
            try await ChatBackend.client
                .from("outfit_items")
                .update(OutfitNoteChange(note: clean), returning: .minimal)
                .eq("id", value: item.id)
                .execute()
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].note = clean
            }
            persist()
            return true
        } catch {
            print("[Outfits] note could not be saved")
            return false
        }
    }

    /// Removes the file first, then the row, so nothing is left pointing at a missing photo.
    func delete(_ item: OutfitItem) async {
        guard !busyItemIDs.contains(item.id) else { return }
        busyItemIDs.insert(item.id)
        defer { busyItemIDs.remove(item.id) }

        do {
            _ = try await ChatBackend.client.storage.from(Self.bucket).remove(paths: [item.photoPath])
            try await ChatBackend.client
                .from("outfit_items")
                .delete(returning: .minimal)
                .eq("id", value: item.id)
                .execute()
            withAnimation(.calm) { items.removeAll { $0.id == item.id } }
            persist()
            OutfitPhotoCache.shared.remove(item.photoPath)
        } catch {
            print("[Outfits] photo could not be deleted")
            notice = "That photo couldn't be removed just now. Please try again."
        }
    }

    // MARK: - Don't forget

    func isTicked(_ text: String, eventID: String) -> Bool {
        ticks.contains(Self.tickKey(text, eventID: eventID))
    }

    func toggleTick(_ text: String, eventID: String) {
        let key = Self.tickKey(text, eventID: eventID)
        if ticks.contains(key) { ticks.remove(key) } else { ticks.insert(key) }
        defaults.set(Array(ticks), forKey: Key.ticks)
    }

    func tickedCount(_ texts: [String], eventID: String) -> Int {
        texts.filter { isTicked($0, eventID: eventID) }.count
    }

    // MARK: - Helpers

    private func upload(_ data: Data, to path: String) async throws {
        try await ChatBackend.client.storage
            .from(Self.bucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
    }

    private func persist() {
        guard let userID else { return }
        OutfitDisk.saveItems(items, for: userID)
    }

    private static func tickKey(_ text: String, eventID: String) -> String {
        eventID + "|" + text
    }

    private enum OutfitError: Error {
        case encoding
    }
}
