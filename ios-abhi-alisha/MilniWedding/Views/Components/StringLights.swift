import SwiftUI

/// Geometry helper for a gently drooping wire drawn as a quadratic curve.
struct DroopingWire: Shape {
    /// How far the centre of the wire sags, in points.
    var sag: CGFloat = 34
    var startY: CGFloat = 0
    var endY: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.minY + startY)
        let end = CGPoint(x: rect.maxX, y: rect.minY + endY)
        path.move(to: start)
        path.addQuadCurve(
            to: end,
            control: CGPoint(x: rect.midX, y: (start.y + end.y) / 2 + sag * 2)
        )
        return path
    }

    /// Point on the wire at parameter `t` (0…1).
    static func point(t: CGFloat, width: CGFloat, startY: CGFloat, endY: CGFloat, sag: CGFloat) -> CGPoint {
        let controlY = (startY + endY) / 2 + sag * 2
        let inverse = 1 - t
        let x = inverse * inverse * 0 + 2 * inverse * t * (width / 2) + t * t * width
        let y = inverse * inverse * startY + 2 * inverse * t * controlY + t * t * endY
        return CGPoint(x: x, y: y)
    }
}

/// A single hanging festoon bulb: hairline drop wire, glass envelope, warm filament.
struct FestoonBulb: View {
    var isLit: Bool
    var dropLength: CGFloat = 16
    var size: CGFloat = 13
    /// Breathing glow phase, driven by the parent so bulbs stay in sync.
    var glowPhase: Bool = false

    /// The lit bulb reads as a crisp 17pt glass envelope, not a smear of light.
    private var litSize: CGFloat { 17 }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(BrandPalette.gold.opacity(isLit ? 0.9 : 0.5))
                .frame(width: 1, height: dropLength)

            ZStack {
                if isLit {
                    // A contained halo: it hugs the glass instead of bleeding into the wire.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hex: 0xFFE6B0).opacity(0.5),
                                    Color(hex: 0xE8BE68).opacity(0.14),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: litSize * 0.42,
                                endRadius: litSize * 1.05
                            )
                        )
                        .frame(width: litSize * 2.1, height: litSize * 2.1)
                        .scaleEffect(glowPhase ? 1.05 : 0.96)
                        .blur(radius: 1.5)
                }

                Circle()
                    .fill(
                        isLit
                            ? LinearGradient(
                                colors: [Color(hex: 0xFFF3D6), Color(hex: 0xE6BC63)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(
                                colors: [
                                    BrandPalette.goldPale.opacity(0.5),
                                    BrandPalette.gold.opacity(0.5)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                isLit ? Color(hex: 0xFBE2AC) : BrandPalette.gold.opacity(0.6),
                                lineWidth: isLit ? 1 : 0.8
                            )
                    )
                    .frame(width: isLit ? litSize : size, height: isLit ? litSize : size)
                    .shadow(
                        color: isLit ? Color(hex: 0xE8BE68).opacity(0.55) : .clear,
                        radius: isLit ? 5 : 0
                    )
            }
            .frame(width: litSize * 2.2, height: litSize * 2.2)
        }
        .opacity(isLit ? 1 : 0.85)
    }
}

/// Decorative, non-interactive string of lights used across the top of the Home hero.
struct DecorativeLightString: View {
    var bulbCount: Int = 9
    var sag: CGFloat = 26
    var startY: CGFloat = 6
    var endY: CGFloat = 22

    @State private var glowPhase = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .topLeading) {
                DroopingWire(sag: sag, startY: startY, endY: endY)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xD8BC77).opacity(0.35),
                                Color(hex: 0xEBD49A).opacity(0.8),
                                Color(hex: 0xD8BC77).opacity(0.35)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )

                ForEach(0..<bulbCount, id: \.self) { index in
                    let t = (CGFloat(index) + 0.5) / CGFloat(bulbCount)
                    let point = DroopingWire.point(t: t, width: width, startY: startY, endY: endY, sag: sag)

                    TinyBulb(delay: Double(index) * 0.18, glowPhase: glowPhase)
                        .position(x: point.x, y: point.y + 11)
                }
            }
        }
        .frame(height: sag + 46)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                glowPhase = true
            }
        }
    }
}

private struct TinyBulb: View {
    let delay: Double
    let glowPhase: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(hex: 0xEBD49A).opacity(0.5))
                .frame(width: 0.8, height: 9)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xFFF2D2), Color(hex: 0xE3BE72)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 7
                    )
                )
                .frame(width: 6, height: 6)
                .shadow(color: Color(hex: 0xFFDE9E).opacity(glowPhase ? 0.85 : 0.45), radius: glowPhase ? 7 : 4)
                .animation(
                    .easeInOut(duration: 3.4).repeatForever(autoreverses: true).delay(delay),
                    value: glowPhase
                )
        }
    }
}
