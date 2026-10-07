import Foundation
import Network
import Observation
import Supabase
import SwiftUI
import UIKit

/// The Wedding Week photographs: read by every guest with no sign-in, added and managed
/// only by the couple.
///
/// The list is kept on the phone so the timeline opens instantly and offline, and
/// thumbnails go through `ImageCache`, so anything seen once stays available. New
/// photographs arrive live. Uploads are a queue saved to disk: each finished photo is
/// removed from it, failures retry with a growing pause, nothing moves while offline,
/// and whatever is left when the app closes carries on next time it opens.
@Observable
final class WeddingPhotoStore {
    static let shared = WeddingPhotoStore()

    private(set) var photos: [WeddingPhoto] = []
    private(set) var hasLoaded = false
    private(set) var queue: [WeddingUploadJob] = []
    /// How many photos this upload run started with, for "12 of 23".
    private(set) var runTotal = 0
    private(set) var isOnline = true
    private(set) var busyIDs: Set<String> = []
    var notice: String?

    private var channel: RealtimeChannelV2?
    private var listenTasks: [Task<Void, Never>] = []
    private var isUploading = false
    private var monitor: NWPathMonitor?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private var client: SupabaseClient { ChatBackend.client }

    private init() {
        photos = WeddingPhotoDisk.loadPhotos() ?? []
        queue = WeddingPhotoDisk.loadQueue() ?? []
        runTotal = queue.count
        hasLoaded = !photos.isEmpty
    }

    // MARK: - Reading

    func photos(for eventID: String) -> [WeddingPhoto] {
        let all = photos.filter { $0.eventID == eventID }
            .sorted { $0.sortDate < $1.sortDate }
        guard let cover = all.first(where: \.isCover) else { return all }
        return [cover] + all.filter { $0.id != cover.id }
    }

    var isUploadingAnything: Bool { !queue.isEmpty }
    var uploadedInRun: Int { max(runTotal - queue.count, 0) }

    // MARK: - Refresh and live updates

    func refresh() async {
        do {
            let rows: [WeddingPhoto] = try await client
                .from("event_photos")
                .select()
                .order("taken_at", ascending: true)
                .execute()
                .value
            withAnimation(.calm) {
                photos = rows
                hasLoaded = true
            }
            persist()
            ImageCache.shared.prefetch(rows.compactMap(\.thumbURL))
        } catch {
            hasLoaded = true
            print("[WeddingWeek] refresh postponed")
        }
        startListening()
    }

    private func startListening() {
        guard channel == nil else { return }
        let channel = client.channel("event-photos")
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "event_photos")
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "event_photos")
        let deletes = channel.postgresChange(DeleteAction.self, schema: "public", table: "event_photos")
        self.channel = channel
        listenTasks = [
            Task {
                for await change in inserts {
                    if let photo = try? change.decodeRecord(as: WeddingPhoto.self, decoder: ChatJSON.decoder) {
                        WeddingPhotoStore.shared.ingest(photo)
                    }
                }
            },
            Task {
                for await change in updates {
                    if let photo = try? change.decodeRecord(as: WeddingPhoto.self, decoder: ChatJSON.decoder) {
                        WeddingPhotoStore.shared.ingest(photo)
                    }
                }
            },
            Task {
                for await change in deletes {
                    if let id = change.oldRecord["id"].flatMap(Self.idString) {
                        WeddingPhotoStore.shared.forget(id)
                    } else {
                        // Without the old row there is no telling which one went; read again.
                        await WeddingPhotoStore.shared.refresh()
                    }
                }
            }
        ]
        Task {
            do { try await channel.subscribeWithError() } catch { print("[WeddingWeek] live updates unavailable") }
        }
    }

    private static func idString(_ value: AnyJSON) -> String? {
        switch value {
        case .string(let text): return text
        case .integer(let number): return String(number)
        case .double(let number): return String(Int(number))
        default: return nil
        }
    }

    private func ingest(_ photo: WeddingPhoto) {
        withAnimation(.calm) {
            if photo.isCover {
                for index in photos.indices where photos[index].eventID == photo.eventID && photos[index].id != photo.id {
                    photos[index].isCover = false
                }
            }
            if let index = photos.firstIndex(where: { $0.id == photo.id }) {
                photos[index] = photo
            } else {
                photos.append(photo)
            }
        }
        persist()
        if let url = photo.thumbURL { ImageCache.shared.prefetch([url]) }
    }

    private func forget(_ id: String) {
        withAnimation(.calm) { photos.removeAll { $0.id == id } }
        persist()
    }

    // MARK: - Uploading

    /// Stages the reviewed photos as jobs and starts sending them.
    func enqueue(_ prepared: [PreparedWeddingPhoto]) {
        let jobs: [WeddingUploadJob] = prepared.compactMap { item in
            guard let eventID = item.eventID else { return nil }
            return WeddingUploadJob(
                id: UUID(),
                eventID: eventID,
                caption: item.caption.trimmed.nonEmpty,
                isCover: item.isCover,
                takenAt: item.takenAt,
                fullName: item.fullName,
                thumbName: item.thumbName
            )
        }
        guard !jobs.isEmpty else { return }
        if queue.isEmpty { runTotal = 0 }
        runTotal += jobs.count
        withAnimation(.calm) { queue.append(contentsOf: jobs) }
        WeddingPhotoDisk.saveQueue(queue)
        resumeUploads()
    }

    /// Called on launch, on return to the foreground, and when the connection returns.
    func resumeUploads() {
        startMonitoring()
        guard !queue.isEmpty, !isUploading, isOnline else { return }
        guard ChatSession.shared.isAdmin else { return }
        isUploading = true
        beginBackgroundTime()
        Task {
            await drain()
            isUploading = false
            endBackgroundTime()
        }
    }

    private func drain() async {
        while let job = queue.first, isOnline {
            let ok = await upload(job)
            if ok {
                withAnimation(.calm) { queue.removeFirst() }
                WeddingPhotoDisk.saveQueue(queue)
                WeddingPhotoProcessor.discard([job.fullName, job.thumbName])
            } else {
                var failed = job
                failed.attempts += 1
                if failed.attempts >= 6 {
                    // Set it aside at the back so one stubborn photo can't block the rest.
                    queue.removeFirst()
                    failed.attempts = 0
                    queue.append(failed)
                    WeddingPhotoDisk.saveQueue(queue)
                    notice = "A photo is having trouble uploading. It will keep trying."
                    try? await Task.sleep(for: .seconds(30))
                } else {
                    queue[0] = failed
                    WeddingPhotoDisk.saveQueue(queue)
                    try? await Task.sleep(for: .seconds(min(pow(2, Double(failed.attempts)), 30)))
                }
            }
        }
        if queue.isEmpty {
            runTotal = 0
            BrandHaptics.tick()
        }
    }

    private func upload(_ job: WeddingUploadJob) async -> Bool {
        guard let fullURL = WeddingPhotoProcessor.stagedURL(job.fullName),
              let thumbURL = WeddingPhotoProcessor.stagedURL(job.thumbName),
              let full = try? Data(contentsOf: fullURL),
              let thumb = try? Data(contentsOf: thumbURL) else {
            // The staged files are gone; there is nothing left to send.
            return true
        }
        let bucket = client.storage.from(WeddingPhoto.bucket)
        let options = FileOptions(contentType: "image/jpeg", upsert: true)
        do {
            try await bucket.upload(job.photoPath, data: full, options: options)
            try await bucket.upload(job.thumbPath, data: thumb, options: options)

            if job.isCover {
                try await clearCover(for: job.eventID)
            }
            let insert = WeddingPhotoInsert(
                event_id: job.eventID,
                photo_path: job.photoPath,
                thumb_path: job.thumbPath,
                caption: job.caption,
                taken_at: job.takenAt.map(ChatJSON.isoString),
                is_cover: job.isCover
            )
            let row: WeddingPhoto = try await client
                .from("event_photos")
                .insert(insert, returning: .representation)
                .select()
                .single()
                .execute()
                .value
            ImageCache.shared.prefetch([row.thumbURL].compactMap { $0 })
            ingest(row)
            return true
        } catch {
            print("[WeddingWeek] upload will retry")
            return false
        }
    }

    // MARK: - Managing

    func setCaption(_ text: String, for photo: WeddingPhoto) async -> Bool {
        let clean = text.trimmed.nonEmpty
        return await change(photo) {
            try await self.client.from("event_photos")
                .update(WeddingCaptionChange(caption: clean), returning: .minimal)
                .eq("id", value: photo.id)
                .execute()
            self.mutate(photo.id) { $0.caption = clean }
        }
    }

    func makeCover(_ photo: WeddingPhoto) async {
        _ = await change(photo) {
            try await self.clearCover(for: photo.eventID)
            try await self.client.from("event_photos")
                .update(WeddingCoverChange(is_cover: true), returning: .minimal)
                .eq("id", value: photo.id)
                .execute()
            withAnimation(.calm) {
                for index in self.photos.indices where self.photos[index].eventID == photo.eventID {
                    self.photos[index].isCover = self.photos[index].id == photo.id
                }
            }
        }
    }

    /// Moves a photo to another celebration. It arrives there as an ordinary photo, so the
    /// other event's cover is never doubled; the files keep their original path.
    func move(_ photo: WeddingPhoto, to eventID: String) async {
        guard eventID != photo.eventID else { return }
        _ = await change(photo) {
            try await self.client.from("event_photos")
                .update(WeddingEventChange(event_id: eventID, is_cover: false), returning: .minimal)
                .eq("id", value: photo.id)
                .execute()
            withAnimation(.calm) {
                self.mutate(photo.id) {
                    $0.eventID = eventID
                    $0.isCover = false
                }
            }
        }
    }

    /// Removes both files, then the row, so nothing is left pointing at a missing photo.
    func delete(_ photo: WeddingPhoto) async {
        _ = await change(photo) {
            let paths = [photo.photoPath, photo.thumbPath].compactMap { $0 }.filter { !$0.isEmpty }
            _ = try await self.client.storage.from(WeddingPhoto.bucket).remove(paths: paths)
            try await self.client.from("event_photos")
                .delete(returning: .minimal)
                .eq("id", value: photo.id)
                .execute()
            withAnimation(.calm) { self.photos.removeAll { $0.id == photo.id } }
        }
    }

    // MARK: - Helpers

    private func clearCover(for eventID: String) async throws {
        try await client.from("event_photos")
            .update(WeddingCoverChange(is_cover: false), returning: .minimal)
            .eq("event_id", value: eventID)
            .eq("is_cover", value: true)
            .execute()
    }

    private func change(_ photo: WeddingPhoto, _ work: @escaping () async throws -> Void) async -> Bool {
        guard !busyIDs.contains(photo.id) else { return false }
        busyIDs.insert(photo.id)
        defer { busyIDs.remove(photo.id) }
        do {
            try await work()
            persist()
            BrandHaptics.tick()
            return true
        } catch {
            print("[WeddingWeek] change not saved")
            notice = "That change didn't save. Please check your connection and try again."
            return false
        }
    }

    private func mutate(_ id: String, _ body: (inout WeddingPhoto) -> Void) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        body(&photos[index])
    }

    private func persist() {
        WeddingPhotoDisk.savePhotos(photos)
    }

    // MARK: - Connectivity and background time

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = Self.makeMonitor { online in
            Task { @MainActor in
                WeddingPhotoStore.shared.connectivityChanged(online)
            }
        }
    }

    private nonisolated static func makeMonitor(onChange: @escaping @Sendable (Bool) -> Void) -> NWPathMonitor {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            onChange(path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "wedding.photos.connectivity"))
        return monitor
    }

    private func connectivityChanged(_ online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        if cameBack { resumeUploads() }
    }

    /// Asks iOS for a little extra time so a run keeps going after the app is put away.
    private func beginBackgroundTime() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "wedding-photos") {
            Task { @MainActor in WeddingPhotoStore.shared.endBackgroundTime() }
        }
    }

    private func endBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

/// The list and the upload queue, kept in Application Support.
nonisolated enum WeddingPhotoDisk {
    private static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = base.appending(path: "wedding-week", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static var photosURL: URL? { folder?.appending(path: "photos.json") }
    private static var queueURL: URL? { folder?.appending(path: "queue.json") }

    static func loadPhotos() -> [WeddingPhoto]? { load(photosURL) }
    static func savePhotos(_ photos: [WeddingPhoto]) { save(photos, to: photosURL) }
    static func loadQueue() -> [WeddingUploadJob]? { load(queueURL) }
    static func saveQueue(_ queue: [WeddingUploadJob]) { save(queue, to: queueURL) }

    private static func load<T: Decodable>(_ url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
