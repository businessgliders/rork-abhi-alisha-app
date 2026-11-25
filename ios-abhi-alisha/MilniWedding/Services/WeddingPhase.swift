import Foundation
import Observation

/// Whether the wedding week is still ahead or behind us.
///
/// From noon on the wedding's last day, Home turns into a thank-you and the
/// Schedule reads as a keepsake. The couple can preview that state early from their area;
/// the preview is remembered on this phone only.
@Observable
final class WeddingPhase {
    static let shared = WeddingPhase()

    /// Noon on the wedding's last day, in the wedding's own time zone.
    static var thankYouStart: Date { ActiveWedding.snapshot.thankYouStart }

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
