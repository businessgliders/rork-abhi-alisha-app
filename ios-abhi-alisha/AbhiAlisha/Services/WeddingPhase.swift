import Foundation
import Observation

/// Whether the wedding week is still ahead or behind us.
///
/// From noon on February 3, 2027 in Cancún, Home turns into a thank-you and the
/// Schedule reads as a keepsake. The couple can preview that state early from their area;
/// the preview is remembered on this phone only.
@Observable
final class WeddingPhase {
    static let shared = WeddingPhase()

    /// Feb 3, 2027, 12:00 PM in Cancún (UTC−5, no daylight saving).
    static let thankYouStart: Date = ISO8601DateFormatter().date(from: "2027-02-03T12:00:00-05:00") ?? .distantFuture

    var isPreviewingThankYou: Bool {
        didSet { UserDefaults.standard.set(isPreviewingThankYou, forKey: Self.previewKey) }
    }

    private static let previewKey = "wedding.previewThankYou"

    private init() {
        isPreviewingThankYou = UserDefaults.standard.bool(forKey: Self.previewKey)
    }

    func isThankYou(at now: Date) -> Bool {
        isPreviewingThankYou || now >= Self.thankYouStart
    }
}
