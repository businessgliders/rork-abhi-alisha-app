import SwiftUI

/// Hand-drawn line-art motifs bundled in-app (no SF Symbols) so the watermarks
/// keep the engraved stationery feel of the invitation suite.
struct LineArtIcon: Shape {
    let key: EventIconKey

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2
        )
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * side, y: origin.y + y * side)
        }

        var path = Path()

        switch key {
        case .flutes:
            // Two champagne flutes tilted towards each other.
            for mirrored in [false, true] {
                let s: (CGFloat) -> CGFloat = { mirrored ? 1 - $0 : $0 }
                path.move(to: p(s(0.14), 0.10))
                path.addLine(to: p(s(0.40), 0.14))
                path.addCurve(
                    to: p(s(0.40), 0.46),
                    control1: p(s(0.40), 0.30),
                    control2: p(s(0.46), 0.40)
                )
                path.addCurve(
                    to: p(s(0.14), 0.10),
                    control1: p(s(0.24), 0.36),
                    control2: p(s(0.16), 0.26)
                )
                // stem + foot
                path.move(to: p(s(0.395), 0.455))
                path.addLine(to: p(s(0.47), 0.78))
                path.move(to: p(s(0.38), 0.84))
                path.addLine(to: p(s(0.58), 0.80))
            }
            // bubbles
            path.addEllipse(in: CGRect(x: p(0.48, 0.06).x, y: p(0.48, 0.06).y, width: side * 0.035, height: side * 0.035))
            path.addEllipse(in: CGRect(x: p(0.56, 0.14).x, y: p(0.56, 0.14).y, width: side * 0.025, height: side * 0.025))

        case .paisley:
            // Mango-shaped paisley: hooked tip, bulbous base, an echoed inner outline,
            // a curl in the belly and a trail of dots along the spine.
            path.move(to: p(0.72, 0.07))
            path.addCurve(
                to: p(0.16, 0.53),
                control1: p(0.40, 0.09),
                control2: p(0.17, 0.28)
            )
            path.addCurve(
                to: p(0.60, 0.93),
                control1: p(0.14, 0.78),
                control2: p(0.33, 0.93)
            )
            path.addCurve(
                to: p(0.72, 0.07),
                control1: p(0.93, 0.93),
                control2: p(0.95, 0.33)
            )

            // Inner echo, drawn a hairline inside the silhouette.
            path.move(to: p(0.68, 0.20))
            path.addCurve(
                to: p(0.29, 0.55),
                control1: p(0.45, 0.21),
                control2: p(0.29, 0.37)
            )
            path.addCurve(
                to: p(0.60, 0.82),
                control1: p(0.28, 0.72),
                control2: p(0.40, 0.82)
            )
            path.addCurve(
                to: p(0.68, 0.20),
                control1: p(0.82, 0.82),
                control2: p(0.84, 0.38)
            )

            // The curl in the belly.
            path.move(to: p(0.57, 0.42))
            path.addCurve(
                to: p(0.43, 0.66),
                control1: p(0.45, 0.45),
                control2: p(0.40, 0.57)
            )
            path.addCurve(
                to: p(0.62, 0.61),
                control1: p(0.50, 0.74),
                control2: p(0.63, 0.71)
            )

            // Dots following the spine towards the hooked tip.
            for (index, point) in [(0.61, 0.29), (0.68, 0.38), (0.72, 0.49)].enumerated() {
                let dot = side * (0.034 - CGFloat(index) * 0.004)
                let origin = p(CGFloat(point.0), CGFloat(point.1))
                path.addEllipse(in: CGRect(x: origin.x, y: origin.y, width: dot, height: dot))
            }

        case .arch:
            // Ogee doorway arch with a finial, as at a gurdwara entrance.
            path.move(to: p(0.20, 0.90))
            path.addLine(to: p(0.20, 0.46))
            path.addCurve(
                to: p(0.50, 0.10),
                control1: p(0.20, 0.26),
                control2: p(0.36, 0.28)
            )
            path.addCurve(
                to: p(0.80, 0.46),
                control1: p(0.64, 0.28),
                control2: p(0.80, 0.26)
            )
            path.addLine(to: p(0.80, 0.90))
            path.move(to: p(0.30, 0.90))
            path.addLine(to: p(0.30, 0.50))
            path.addCurve(
                to: p(0.50, 0.24),
                control1: p(0.30, 0.34),
                control2: p(0.40, 0.36)
            )
            path.addCurve(
                to: p(0.70, 0.50),
                control1: p(0.60, 0.36),
                control2: p(0.70, 0.34)
            )
            path.addLine(to: p(0.70, 0.90))
            path.move(to: p(0.50, 0.10))
            path.addLine(to: p(0.50, 0.02))
            path.move(to: p(0.12, 0.94))
            path.addLine(to: p(0.88, 0.94))

        case .mandap:
            // Four-post canopy with a scalloped valance.
            path.move(to: p(0.10, 0.34))
            path.addCurve(
                to: p(0.90, 0.34),
                control1: p(0.34, 0.10),
                control2: p(0.66, 0.10)
            )
            path.move(to: p(0.10, 0.34))
            path.addLine(to: p(0.90, 0.34))
            var x: CGFloat = 0.14
            while x < 0.88 {
                path.move(to: p(x, 0.34))
                path.addQuadCurve(to: p(x + 0.15, 0.34), control: p(x + 0.075, 0.46))
                x += 0.15
            }
            for postX in [0.14, 0.32, 0.68, 0.86] {
                path.move(to: p(postX, 0.36))
                path.addLine(to: p(postX, 0.90))
            }
            path.move(to: p(0.50, 0.14))
            path.addLine(to: p(0.50, 0.04))
            path.move(to: p(0.08, 0.92))
            path.addLine(to: p(0.92, 0.92))

        case .sparkle:
            // A four-point starburst with two smaller companions.
            func star(center: CGPoint, radius: CGFloat, waist: CGFloat) {
                path.move(to: CGPoint(x: center.x, y: center.y - radius))
                path.addQuadCurve(
                    to: CGPoint(x: center.x + radius, y: center.y),
                    control: CGPoint(x: center.x + waist, y: center.y - waist)
                )
                path.addQuadCurve(
                    to: CGPoint(x: center.x, y: center.y + radius),
                    control: CGPoint(x: center.x + waist, y: center.y + waist)
                )
                path.addQuadCurve(
                    to: CGPoint(x: center.x - radius, y: center.y),
                    control: CGPoint(x: center.x - waist, y: center.y + waist)
                )
                path.addQuadCurve(
                    to: CGPoint(x: center.x, y: center.y - radius),
                    control: CGPoint(x: center.x - waist, y: center.y - waist)
                )
            }
            star(center: p(0.44, 0.46), radius: side * 0.40, waist: side * 0.055)
            star(center: p(0.83, 0.20), radius: side * 0.15, waist: side * 0.022)
            star(center: p(0.80, 0.76), radius: side * 0.11, waist: side * 0.016)

        case .sun:
            // Rising sun over a horizon with alternating rays.
            let center = p(0.50, 0.62)
            let radius = side * 0.24
            path.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            for step in 0..<12 {
                let angle = CGFloat(step) / 12 * .pi * 2 - .pi / 2
                let inner = radius * 1.28
                let outer = radius * (step.isMultiple(of: 2) ? 1.74 : 1.50)
                path.move(to: CGPoint(
                    x: center.x + cos(angle) * inner,
                    y: center.y + sin(angle) * inner
                ))
                path.addLine(to: CGPoint(
                    x: center.x + cos(angle) * outer,
                    y: center.y + sin(angle) * outer
                ))
            }
        }

        return path
    }
}

/// A large, faint line-art watermark for the top-right corner of a card.
struct IconWatermark: View {
    let key: EventIconKey
    var size: CGFloat = 116
    var opacity: Double = 0.16

    var body: some View {
        LineArtIcon(key: key)
            .stroke(
                BrandPalette.gold.opacity(opacity),
                style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)
            )
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
