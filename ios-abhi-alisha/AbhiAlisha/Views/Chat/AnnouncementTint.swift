import SwiftUI

/// The one paper stock every announcement is printed on: warm cream with a pale gold
/// edge. Only the latest card carries the accent — a firmer gold border and a soft glow.
struct AnnouncementTint: Equatable, Sendable {
    let paper: Color
    let ink: Color
    let secondary: Color
    let edge: Color

    static let cream = AnnouncementTint(
        paper: tint(0xFBF8F2, 0x221E18),
        ink: tint(0x2B2622, 0xF3EDE1),
        secondary: tint(0x6D6459, 0xB6AB9A),
        edge: BrandPalette.gold.opacity(0.32)
    )

    /// The latest card's border.
    static let latestEdge: Color = BrandPalette.gold
    /// The latest card's soft halo.
    static let latestGlow: Color = BrandPalette.gold.opacity(0.32)
}

/// A fixed colour that keeps its warmth after dark.
private func tint(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
    })
}

/// Cream paper with linen grain and the right edge: pale gold for older notes, a 1.5pt
/// gold border with a soft glow for the latest.
struct AnnouncementPaper: ViewModifier {
    let cornerRadius: CGFloat
    let isLatest: Bool
    var isLifted: Bool = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let stock = AnnouncementTint.cream

        content
            .background(
                ZStack {
                    shape.fill(stock.paper)
                    LinenGrain()
                        .clipShape(shape)
                        .opacity(0.75)
                        .allowsHitTesting(false)
                }
            )
            .overlay(
                shape.stroke(
                    isLatest ? AnnouncementTint.latestEdge : stock.edge,
                    lineWidth: isLatest ? 1.5 : 1
                )
            )
            .shadow(color: isLatest ? AnnouncementTint.latestGlow : .clear, radius: 14, x: 0, y: 0)
            .shadow(color: Color.black.opacity(isLifted ? 0.09 : 0.06), radius: isLifted ? 16 : 9, x: 0, y: isLifted ? 9 : 4)
    }
}

extension View {
    /// Prints the view on announcement paper.
    func announcementPaper(cornerRadius: CGFloat, isLatest: Bool, isLifted: Bool = true) -> some View {
        modifier(AnnouncementPaper(cornerRadius: cornerRadius, isLatest: isLatest, isLifted: isLifted))
    }
}
