import Foundation

/// The wedding the paired iPhone has open, as the watch remembers it. The phone sends it
/// over WatchConnectivity; until it does, the watch shows Abhi & Alisha as before.
nonisolated struct WatchWedding: Sendable, Equatable {
    static let sampleID = "84faefbc-2e43-4c6c-ac61-fb38d4563679"
    private static let appGroup = "group.com.businessgliders.abhialisha"
    private static let storageKey = "watch.current-wedding"

    var id: String
    var title: String
    var partnerOne: String
    var partnerTwo: String
    var timezone: String

    static let sample = WatchWedding(
        id: sampleID,
        title: "Abhi & Alisha",
        partnerOne: "Abhi",
        partnerTwo: "Alisha",
        timezone: "America/Cancun"
    )

    var isSample: Bool { id.lowercased() == Self.sampleID }

    var coupleNames: String {
        let one = partnerOne.trimmingCharacters(in: .whitespacesAndNewlines)
        let two = partnerTwo.trimmingCharacters(in: .whitespacesAndNewlines)
        if one.isEmpty || two.isEmpty { return title }
        return "\(one) & \(two)"
    }

    var coupleNamesSpoken: String { coupleNames.replacingOccurrences(of: "&", with: "and") }

    var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .current }

    // MARK: - Storage

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var current: WatchWedding {
        guard let stored = defaults.dictionary(forKey: storageKey) as? [String: String],
              let id = stored["id"], !id.isEmpty else { return .sample }
        return WatchWedding(
            id: id,
            title: stored["title"] ?? "",
            partnerOne: stored["partner_one"] ?? "",
            partnerTwo: stored["partner_two"] ?? "",
            timezone: stored["timezone"] ?? TimeZone.current.identifier
        )
    }

    /// Saves what the phone sent. Returns true when the wedding changed.
    @discardableResult
    static func save(context: [String: Any]) -> Bool {
        guard let id = context["wedding_id"] as? String, !id.isEmpty else { return false }
        let previous = current
        let next = WatchWedding(
            id: id,
            title: context["title"] as? String ?? "",
            partnerOne: context["partner_one"] as? String ?? "",
            partnerTwo: context["partner_two"] as? String ?? "",
            timezone: (context["timezone"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? TimeZone.current.identifier
        )
        defaults.set([
            "id": next.id,
            "title": next.title,
            "partner_one": next.partnerOne,
            "partner_two": next.partnerTwo,
            "timezone": next.timezone,
        ], forKey: storageKey)
        return previous != next
    }
}
