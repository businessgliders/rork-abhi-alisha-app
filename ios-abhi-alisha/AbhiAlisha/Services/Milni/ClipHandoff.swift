import Foundation

/// An invitation opened in the App Clip, waiting in the shared App Group for the full
/// app's first launch. Read once, then cleared; ignored after two weeks.
enum ClipHandoff {
    private static let suite = "group.com.businessgliders.milni"
    private static let codeKey = "clip.handoff.code"
    private static let dateKey = "clip.handoff.date"

    static func takeCode() -> String? {
        guard let defaults = UserDefaults(suiteName: suite),
              let code = defaults.string(forKey: codeKey) else { return nil }
        let saved = defaults.double(forKey: dateKey)
        defaults.removeObject(forKey: codeKey)
        defaults.removeObject(forKey: dateKey)
        guard Date().timeIntervalSince1970 - saved < 14 * 24 * 3600 else { return nil }
        return WeddingContext.normalize(code)
    }

    /// Opens "Invitation found" for a code the clip left behind.
    static func openIfWaiting(in context: WeddingContext) {
        guard let code = takeCode(), (6...10).contains(code.count),
              let url = URL(string: "https://milniapp.com/j/\(code)") else { return }
        _ = context.handleJoinLink(url)
    }
}
