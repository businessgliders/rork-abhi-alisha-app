import Foundation

/// The container the app, the widgets and the Live Activity all read from.
///
/// Everything the widget shows comes from here — it never reaches the network itself.
/// If the App Group is ever unavailable (an unsigned build, a misconfigured profile) the
/// app quietly falls back to its own caches folder and simply keeps working alone.
nonisolated enum WeddingGroup: Sendable {
    /// Must match the group named in both targets' entitlements.
    static let identifier = "group.com.businessgliders.abhialisha"

    /// The shared folder, when the App Group is actually granted.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Where a shared file should live: the group container if we have it, the process's
    /// own caches folder otherwise.
    static func fileURL(_ name: String) -> URL? {
        if let containerURL {
            return containerURL.appendingPathComponent(name)
        }
        return FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(name)
    }

    /// The app's own private copy of a file, from before the App Group existed.
    static func legacyFileURL(_ name: String) -> URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(name)
    }

    /// Deep links carried by a widget tap.
    enum Link {
        static let scheme = "abhialisha"

        static var home: URL? { URL(string: "\(scheme)://home") }

        static func event(_ id: String) -> URL? {
            var components = URLComponents()
            components.scheme = scheme
            components.host = "event"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
            return components.url
        }

        /// The event id carried by a link, if it is one of ours and names an event.
        static func eventID(from url: URL) -> String? {
            guard url.scheme == scheme, url.host == "event" else { return nil }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "id" }?
                .value?
                .nonEmpty
        }
    }
}
