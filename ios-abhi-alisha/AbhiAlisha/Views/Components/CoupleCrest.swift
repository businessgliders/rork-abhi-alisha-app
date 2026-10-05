import SwiftUI

/// The crest, which also quietly holds the door to the couple's area: pressed and held
/// for three seconds, a fine gold ring traces around it and the passcode prompt rises.
/// Nothing about it looks like a button, and it says nothing to VoiceOver.
struct CoupleCrest: View {
    static let holdDuration: Double = 3

    var width: CGFloat = 116
    var finish: CrestWatermark.Finish = .pressed(BrandPalette.background)
    var isHoldable: Bool = true

    @Environment(AdminSession.self) private var session: AdminSession?
    @State private var isHolding = false

    var body: some View {
        if isHoldable, let session {
            crest
                .overlay { holdRing }
                .background { Color.clear.contentShape(Rectangle()) }
                .onLongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 24) {
                    isHolding = false
                    session.requestEntry()
                } onPressingChanged: { pressing in
                    if pressing { BrandHaptics.tick() }
                    withAnimation(pressing ? .linear(duration: Self.holdDuration) : .easeOut(duration: 0.35)) {
                        isHolding = pressing
                    }
                }
        } else {
            crest
        }
    }

    private var crest: some View {
        CrestWatermark(width: width, finish: finish)
    }

    private var holdRing: some View {
        Circle()
            .trim(from: 0, to: isHolding ? 1 : 0)
            .stroke(
                BrandPalette.gold.opacity(0.85),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .frame(width: width * 1.08, height: width * 1.08)
            .shadow(color: BrandPalette.gold.opacity(0.45), radius: 6)
            .opacity(isHolding ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
