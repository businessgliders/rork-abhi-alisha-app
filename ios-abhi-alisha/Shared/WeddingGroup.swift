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

        static var schedule: URL? { URL(string: "\(scheme)://schedule") }

        /// True when the link asks for the schedule tab rather than one event.
        static func isSchedule(_ url: URL) -> Bool {
            url.scheme == scheme && url.host == "schedule"
        }

        /// One celebration; `wedding` names the wedding the celebration belongs to, so
        /// the app can switch weddings before opening it. Older links without a wedding
        /// keep working — the app then opens the event on whatever wedding is active.
        static func event(_ id: String, wedding: String? = nil) -> URL? {
            var components = URLComponents()
            components.scheme = scheme
            components.host = "event"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
            if let wedding, !wedding.isEmpty {
                components.queryItems?.append(URLQueryItem(name: "wedding", value: wedding))
            }
            return components.url
        }

        /// The event id carried by a link, if it is one of ours and names an event.
        static func eventID(from url: URL) -> String? {
            guard url.scheme == scheme, url.host == "event" else { return nil }
            return queryValue("id", from: url)
        }

        /// The wedding id carried by an event link, if it names one.
        static func weddingID(from url: URL) -> String? {
            guard url.scheme == scheme, url.host == "event" else { return nil }
            return queryValue("wedding", from: url)
        }

        private static func queryValue(_ name: String, from url: URL) -> String? {
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == name }?
                .value?
                .nonEmpty
        }
    }
}
