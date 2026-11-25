import Foundation

/// A per-wedding quiet switch, kept on this phone only — the backend is never told.
/// When a wedding is muted here, its pushes show nothing while the app is open, and the
/// widget reads the same switch from the shared container.
nonisolated enum WeddingMute {
    private static let prefix = "milni.muted."

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: WeddingGroup.identifier) ?? .standard
    }

    private static func key(_ weddingID: String) -> String {
        prefix + weddingID.lowercased()
    }

    static func isMuted(_ weddingID: String) -> Bool {
        defaults.bool(forKey: key(weddingID))
    }

    static func setMuted(_ weddingID: String, _ muted: Bool) {
        defaults.set(muted, forKey: key(weddingID))
    }
}
