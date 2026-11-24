import SwiftUI

/// The invitation card's colours: midnight and champagne for the house style, or a deep
/// version of the wedding's own theme with its accent turned to foil.
struct InvitationPalette: Equatable {
    let fill: Color
    let accent: Color
    let foil: [Color]
    let text: Color

    init(preset: String) {
        let theme = BrandTheme.colors(for: preset)
        switch preset.lowercased() {
        case "blush", "emerald":
            let deep = BrandThemeColors.mix(theme.ink, theme.accent, 0.12)
            let light = BrandThemeColors.mix(theme.accent, 0xFFFFFF, 0.45)
            fill = Color(hex: deep)
            accent = Color(hex: light)
            foil = [
                Color(hex: BrandThemeColors.mix(theme.accent, 0xFFFFFF, 0.25)),
                Color(hex: BrandThemeColors.mix(theme.accent, 0xFFFFFF, 0.7)),
                Color(hex: BrandThemeColors.mix(theme.accent, 0xFFFFFF, 0.35)),
            ]
            text = Color(hex: BrandThemeColors.mix(theme.background, 0xFFFFFF, 0.2))
        default:
            fill = Milni.midnight
            accent = Milni.champagne
            foil = [Color(hex: 0xA9864E), Color(hex: 0xE6CF9A), Color(hex: 0xB89360)]
            text = Color(hex: 0xF4EBDC)
        }
    }
}

/// A 300×420 card with a double inset border, drawing rings and the couple's names in foil.
struct MilniInvitationCard: View {
    let partnerOne: String
    let partnerTwo: String
    let detail: String
    var preset: String = "ivory"
    var drawsRings = true

    var body: some View {
        let palette = InvitationPalette(preset: preset)
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.fill)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(palette.accent.opacity(0.85), lineWidth: 0.8)
                .padding(12)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(palette.accent.opacity(0.45), lineWidth: 0.6)
                .padding(17)

            VStack(spacing: 0) {
                MilniRings(color: palette.accent, lineWidth: 0.9, duration: drawsRings ? 2.2 : 0.01, showsOuter: false, breathes: false, delay: drawsRings ? 0.5 : 0)
                    .frame(width: 58, height: 58)

                Text("together with their families")
                    .font(Milni.cormorant(15, italic: true))
                    .foregroundStyle(palette.text.opacity(0.8))
                    .padding(.top, 22)

                VStack(spacing: -6) {
                    Text(partnerOne.isEmpty ? "Partner" : partnerOne)
                    Text("&")
                        .font(Milni.cormorant(30, italic: true))
                    Text(partnerTwo.isEmpty ? "Partner" : partnerTwo)
                }
                .font(Milni.cormorant(44))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .modifier(MilniFoil(base: palette.foil))
                .padding(.top, 14)
                .padding(.horizontal, 34)

                Rectangle()
                    .fill(palette.accent.opacity(0.6))
                    .frame(width: 34, height: 0.8)
                    .padding(.top, 20)

                Text(detail.uppercased())
                    .font(Milni.inter(10, weight: 600))
                    .tracking(2)
                    .foregroundStyle(palette.accent)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 16)
                    .padding(.horizontal, 36)
            }
        }
        .frame(width: 300, height: 420)
        // Flatten the card first, so the sheen and the shadow see one surface and never
        // a second copy of the names.
        .compositingGroup()
        .milniSheen(period: 3, intensity: 0.16)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
        .compositingGroup()
        .shadow(color: Color(hex: 0x17130F, opacity: 0.28), radius: 30, y: 22)
        .shadow(color: Color(hex: 0x17130F, opacity: 0.12), radius: 6, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Invitation. Together with their families, \(partnerOne) and \(partnerTwo). \(detail)")
    }
}
