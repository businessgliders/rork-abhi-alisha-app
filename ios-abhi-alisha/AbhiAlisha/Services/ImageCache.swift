import CryptoKit
import Foundation
import UIKit

/// A thread-safe store of decoded photographs that can be read without awaiting.
///
/// This is what lets a photograph already in hand be drawn on a view's very first
/// layout pass, so nothing ever flashes a placeholder before the picture appears.
nonisolated private final class ImageMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: UIImage] = [:]

    func image(for key: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func store(_ image: UIImage, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = image
    }
}

/// Disk-and-memory cache for the couple's photographs.
///
/// Once a photograph has been seen it is available with no connection, which keeps the
/// hero slideshow and the outfit inspiration working on resort Wi-Fi or none at all.
actor ImageCache {
    static let shared = ImageCache()

    private nonisolated let memory = ImageMemory()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private let directory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = caches.appendingPathComponent("photographs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    /// The photograph if it is already decoded and in memory — answered immediately,
    /// with no await and no loading state.
    nonisolated func cached(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        return memory.image(for: Self.key(for: url))
    }

    /// Quietly warms photographs that are about to be needed — the next few cards in a
    /// stack, the neighbours of the picture being looked at — so they are simply there.
    nonisolated func prefetch(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            for url in urls where self.cached(for: url) == nil {
                _ = await self.image(for: url)
            }
        }
    }

    /// Returns the photograph from memory, then disk, then the network.
    func image(for url: URL) async -> UIImage? {
        let key = Self.key(for: url)

        if let cached = memory.image(for: key) { return cached }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [directory] in
            if let fileURL = directory?.appendingPathComponent(key),
               let data = try? Data(contentsOf: fileURL),
               let image = UIImage(data: data) {
                return image
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return nil
                }
                guard let image = UIImage(data: data) else { return nil }
                if let fileURL = directory?.appendingPathComponent(key) {
                    try? data.write(to: fileURL, options: .atomic)
                }
                return image
            } catch {
                return nil
            }
        }

        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { memory.store(image, for: key) }
        return image
    }

    private static func key(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
