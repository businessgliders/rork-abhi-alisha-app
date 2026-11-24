import SwiftUI

/// The couple's crest, or their monogram when the wedding has no crest. Purely
/// decorative: hosts reach their tools from the Host pill on Home.
struct CoupleCrest: View {
    var width: CGFloat = 116
    var finish: CrestWatermark.Finish = .pressed(BrandPalette.background)
    /// Kept for existing call sites; the crest no longer opens anything.
    var isHoldable: Bool = true

    var body: some View {
        CrestWatermark(width: width, finish: finish)
    }
}
