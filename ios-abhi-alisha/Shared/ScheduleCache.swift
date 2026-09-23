import Foundation

/// Disk cache for the schedule so every screen works with zero connection.
///
/// It lives in the App Group container, which is what lets the widgets and the Live
/// Activity read exactly the same events the app last saw without fetching anything of
/// their own. A copy written by an older build, before the group existed, is adopted the
/// first time it is found.
nonisolated struct ScheduleCache: Sendable {
    static let shared = ScheduleCache()

    private static let fileName = "schedule-events.json"

    private var fileURL: URL? { WeddingGroup.fileURL(Self.fileName) }
    private var legacyURL: URL? { WeddingGroup.legacyFileURL(Self.fileName) }

    /// Raw JSON payloads are cached verbatim so a future field never gets dropped by this build.
    func save(rawData: Data) {
        guard let fileURL else { return }
        do {
            try rawData.write(to: fileURL, options: .atomic)
        } catch {
            print("[ScheduleCache] save failed: \(error.localizedDescription)")
        }
    }

    func load() -> [ScheduleEvent]? {
        guard let url = readableURL else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try ScheduleDecoder.decode(data)
        } catch {
            print("[ScheduleCache] load failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The cached payload exactly as the API sent it, for the couple's editor.
    func loadRaw() -> Data? {
        guard let url = readableURL else { return nil }
        return try? Data(contentsOf: url)
    }

    var lastUpdated: Date? {
        guard let url = readableURL else { return nil }
        return try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    /// The shared copy, falling back to one left behind by an earlier build.
    private var readableURL: URL? {
        let manager = FileManager.default
        if let fileURL, manager.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        if let legacyURL, manager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }
        return nil
    }

    /// Copies a pre-App-Group cache into the shared container, so the widgets have
    /// something real to show before the first refresh of this launch lands.
    func adoptLegacyCacheIfNeeded() {
        let manager = FileManager.default
        guard let fileURL, let legacyURL, fileURL != legacyURL else { return }
        guard !manager.fileExists(atPath: fileURL.path),
              manager.fileExists(atPath: legacyURL.path) else { return }
        do {
            try manager.copyItem(at: legacyURL, to: fileURL)
        } catch {
            print("[ScheduleCache] could not adopt earlier cache: \(error.localizedDescription)")
        }
    }

    /// The snapshot shipped inside the app, used on a first launch with no signal.
    /// It is bundled with the widget too, so an empty container is never an empty widget.
    func loadBundledSnapshot() -> [ScheduleEvent] {
        guard let url = Bundle.main.url(forResource: "schedule_snapshot", withExtension: "json") else {
            print("[ScheduleCache] bundled snapshot missing")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try ScheduleDecoder.decode(data)
        } catch {
            print("[ScheduleCache] bundled snapshot unreadable: \(error.localizedDescription)")
            return []
        }
    }
}

nonisolated enum ScheduleDecoder {
    /// Decodes the entity array, keeps only active events and sorts by `sort_order`.
    static func decode(_ data: Data) throws -> [ScheduleEvent] {
        let decoder = JSONDecoder()
        let events = try decoder.decode([ScheduleEvent].self, from: data)
        return events
            .filter { $0.isActive != false }
            .filter { !$0.title.isEmpty }
            .sorted { lhs, rhs in
                let left = lhs.sortOrder ?? .greatestFiniteMagnitude
                let right = rhs.sortOrder ?? .greatestFiniteMagnitude
                if left != right { return left < right }
                return (lhs.startsAt ?? .distantFuture) < (rhs.startsAt ?? .distantFuture)
            }
    }
}
