import Foundation

nonisolated enum WeddingAPIError: LocalizedError {
    case badResponse(String, Int)
    case undecodable(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let entity, let code):
            return "\(entity) replied with status \(code)."
        case .undecodable(let entity):
            return "\(entity) returned rows this app couldn't read."
        }
    }
}

/// Public read-only client for the couple's base44 entities. No API key required.
nonisolated struct WeddingAPI: Sendable {
    static let shared = WeddingAPI()

    private let baseURL = URL(string: "https://aawedding.base44.app/api")!

    /// Fetches one entity collection and returns both the decoded items and the raw
    /// payload, so the cache can keep fields this build doesn't know about yet.
    func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        entity: String,
        timeout: TimeInterval = 12
    ) async throws -> (items: [T], raw: Data) {
        var request = URLRequest(url: baseURL.appending(path: "entities/\(entity)"))
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeddingAPIError.badResponse(entity, http.statusCode)
        }
        // One malformed record must never blank an entire screen, so rows are decoded
        // individually and anything unreadable is simply left out.
        let decoder = JSONDecoder()
        let rows = try decoder.decode([LenientRow<T>].self, from: data)
        let items = rows.compactMap(\.value)
        if items.isEmpty, !rows.isEmpty {
            throw WeddingAPIError.undecodable(entity)
        }
        return (items, data)
    }
}

/// Decodes one row, keeping `nil` instead of throwing when its shape is unexpected.
nonisolated private struct LenientRow<T: Decodable & Sendable>: Decodable, Sendable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// Stores a raw entity payload on disk so every screen opens instantly, offline.
nonisolated struct JSONDiskCache: Sendable {
    let filename: String

    private var fileURL: URL? {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory.appendingPathComponent(filename)
    }

    /// Removes the cached payload, e.g. when a remembered lookup is forgotten.
    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    func save(_ data: Data) {
        guard let fileURL else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[JSONDiskCache] save failed for \(filename)")
        }
    }

    func load<T: Decodable>(_ type: T.Type) -> [T]? {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            print("[JSONDiskCache] load failed for \(filename)")
            return nil
        }
    }
}
