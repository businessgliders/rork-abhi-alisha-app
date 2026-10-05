import SwiftUI

// MARK: - Embossed paper card

/// The schedule card's stock: matte card colour with a letterpress inner shadow pooling
/// at the edges, a lit top lip, and a faint linen weave, so it reads as heavy invitation
/// paper rather than a flat panel.
struct EmbossedPaperCard<Content: View>: View {
    var cornerRadius: CGFloat = 26
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                ZStack {
                    shape
                        .fill(
                            BrandPalette.card
                                .shadow(.inner(color: BrandPalette.embossShadow.opacity(0.22), radius: 9, x: 0, y: -3))
                                .shadow(.inner(color: BrandPalette.embossLight.opacity(0.9), radius: 1.5, x: 0, y: 1.5))
                        )

                    LinenGrain()
                        .clipShape(shape)
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [BrandPalette.embossLight.opacity(0.9), BrandPalette.hairline, BrandPalette.hairline],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: BrandPalette.embossShadow.opacity(0.16), radius: 1, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.07), radius: 20, x: 0, y: 12)
    }
}

/// A woven texture: hairline warp and weft at uneven strength. It is seeded, so it
/// never shimmers between redraws.
struct LinenGrain: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            var random = SeededRandom(seed: 0x5EED_CAFE)
            let isDark = colorScheme == .dark
            let tone = isDark ? Color.white : Color(hex: 0x8A7650)
            let strength = isDark ? 0.035 : 0.05

            var y: CGFloat = 0
            while y < size.height {
                let alpha = strength * (0.35 + random.next() * 0.65)
                let rect = CGRect(x: 0, y: y, width: size.width, height: 0.5)
                context.fill(Path(rect), with: .color(tone.opacity(alpha)))
                y += 1.6 + random.next() * 1.4
            }

            var x: CGFloat = 0
            while x < size.width {
                let alpha = strength * 0.7 * (0.3 + random.next() * 0.7)
                let rect = CGRect(x: x, y: 0, width: 0.5, height: size.height)
                context.fill(Path(rect), with: .color(tone.opacity(alpha)))
                x += 1.8 + random.next() * 1.6
            }

            for _ in 0..<Int(size.width * size.height / 900) {
                let point = CGPoint(x: random.next() * size.width, y: random.next() * size.height)
                let dot = CGRect(origin: point, size: CGSize(width: 0.9, height: 0.9))
                context.fill(Path(ellipseIn: dot), with: .color(tone.opacity(strength * 1.6)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A small deterministic generator for the grain.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// A value in 0..<1.
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 33) / CGFloat(UInt64(1) << 31)
    }
}

extension View {
    /// Pressed into the paper: a lit lip just below the mark, as letterpress catches light.
    func debossed() -> some View {
        shadow(color: BrandPalette.embossLight.opacity(0.95), radius: 0, x: 0, y: 1)
            .shadow(color: BrandPalette.embossShadow.opacity(0.25), radius: 0, x: 0, y: -0.5)
    }
}

// MARK: - The pile behind

/// The celebrations still to come peek out beneath the card as sheets of the same stock,
/// each a little narrower and lower, so the card reads as the top of a stack.
struct StackedPaperBacking: View {
    let sheetsBehind: Int

    var body: some View {
        ZStack {
            ForEach((0..<sheetsBehind).reversed(), id: \.self) { index in
                let depth = CGFloat(index + 1)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        BrandPalette.card
                            .shadow(.inner(color: BrandPalette.embossShadow.opacity(0.12), radius: 6, x: 0, y: -2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(BrandPalette.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
                    .brightness(-0.015 * depth)
                    .scaleEffect(x: 1 - depth * 0.045, y: 1, anchor: .bottom)
                    .offset(y: depth * 7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.calm, value: sheetsBehind)
    }
}

// MARK: - First-visit tip

/// A small dark note hanging beneath "Add all to Calendar" on the first visit.
struct CalendarTip: View {
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            VStack(spacing: 0) {
                TipArrow()
                    .fill(BrandPalette.ink)
                    .frame(width: 16, height: 8)

                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(BrandPalette.goldPale)

                    Text("Add every celebration to your calendar in one tap")
                        .font(BrandLabel.font(size: 12, weight: .medium))
                        .foregroundStyle(BrandPalette.background)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(BrandPalette.background.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(BrandPalette.ink)
                )
            }
            .frame(maxWidth: 290)
            .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Tip: Add every celebration to your calendar in one tap")
        .accessibilityHint("Dismisses the tip")
    }
}

private struct TipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX + 3, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.midX - 3, y: rect.minY + 2))
        path.closeSubpath()
        return path
    }
}
