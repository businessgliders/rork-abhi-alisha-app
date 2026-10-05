import Foundation
import Supabase
import UIKit

/// Where a guest's own outfit list and photos are kept on the phone, in Application
/// Support so they stay readable with no connection. Signing out removes all of it.
nonisolated enum OutfitDisk {
    static var root: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = base.appending(path: "outfits", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static var photoFolder: URL? {
        guard let root else { return nil }
        let folder = root.appending(path: "photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func photoURL(for path: String) -> URL? {
        let name = path.replacingOccurrences(of: "/", with: "_")
        return photoFolder?.appending(path: name)
    }

    private static func itemsURL(for user: UUID) -> URL? {
        root?.appending(path: "items-\(user.lower).json")
    }

    static func loadItems(for user: UUID) -> [OutfitItem]? {
        guard let url = itemsURL(for: user), let data = try? Data(contentsOf: url) else { return nil }
        return try? ChatJSON.decoder.decode([OutfitItem].self, from: data)
    }

    static func saveItems(_ items: [OutfitItem], for user: UUID) {
        guard let url = itemsURL(for: user), let data = try? ChatJSON.encoder.encode(items) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func wipe() {
        guard let root else { return }
        try? FileManager.default.removeItem(at: root)
    }
}

/// Memory, then disk, then a one-hour signed link from the private `outfits` bucket.
/// Once a photo has been seen it is kept on the phone for good.
nonisolated final class OutfitPhotoCache: @unchecked Sendable {
    static let shared = OutfitPhotoCache()

    private let memory = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        memory.countLimit = 80
    }

    /// Answered immediately, with no await, when the photo is already decoded.
    func cached(_ path: String) -> UIImage? {
        memory.object(forKey: path as NSString)
    }

    func store(_ data: Data, for path: String) {
        if let url = OutfitDisk.photoURL(for: path) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        if let image = UIImage(data: data) {
            memory.setObject(image, forKey: path as NSString)
        }
    }

    func image(for path: String) async -> UIImage? {
        guard !path.isEmpty else { return nil }
        if let ready = cached(path) { return ready }
        if let url = OutfitDisk.photoURL(for: path),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            memory.setObject(image, forKey: path as NSString)
            return image
        }

        let task: Task<UIImage?, Never> = lock.withLock {
            if let existing = inFlight[path] { return existing }
            let created = Task<UIImage?, Never> { await OutfitPhotoCache.download(path) }
            inFlight[path] = created
            return created
        }
        let image = await task.value
        lock.withLock { inFlight[path] = nil }
        return image
    }

    func prefetch(_ paths: [String]) {
        let missing = paths.filter { cached($0) == nil }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) {
            for path in missing {
                _ = await OutfitPhotoCache.shared.image(for: path)
            }
        }
    }

    func remove(_ path: String) {
        memory.removeObject(forKey: path as NSString)
        if let url = OutfitDisk.photoURL(for: path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func wipe() {
        memory.removeAllObjects()
    }

    private static func download(_ path: String) async -> UIImage? {
        do {
            let signed = try await ChatBackend.client.storage
                .from(OutfitStore.bucket)
                .createSignedURL(path: path, expiresIn: 3600)
            var request = URLRequest(url: signed)
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            shared.store(data, for: path)
            return image
        } catch {
            return nil
        }
    }
}

/// Shrinks a photo to at most 1600 pixels on its long edge and encodes it as JPEG 0.8.
nonisolated enum OutfitImageProcessor {
    static func jpeg(from image: UIImage) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            encode(image)
        }.value
    }

    private static func encode(_ image: UIImage, maxEdge: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > 0 else { return nil }
        let ratio = min(1, maxEdge / longest)
        let target = CGSize(width: floor(pixelWidth * ratio), height: floor(pixelHeight * ratio))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
