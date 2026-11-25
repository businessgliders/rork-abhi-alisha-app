import SwiftUI

/// A row of choice pills that wraps onto further lines, like words on a line.
struct WrappingPillRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? max(0, x - spacing) : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A gold-outline choice pill for the couple's pickers — softly filled when selected.
struct AdminChoicePill: View {
    let title: String
    var detail: String? = nil
    var iconKey: EventIconKey? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let iconKey {
                    LineArtIcon(key: iconKey)
                        .stroke(
                            isSelected ? BrandPalette.goldDeep : BrandPalette.body.opacity(0.75),
                            style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .brandFont(.bodyText)
                        .foregroundStyle(isSelected ? BrandPalette.ink : BrandPalette.body)
                        .lineLimit(1)

                    if let detail {
                        Text(detail.uppercased())
                            .font(BrandLabel.font(size: 8.5, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(BrandPalette.goldDeep.opacity(isSelected ? 1 : 0.75))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isSelected ? BrandPalette.gold.opacity(0.14) : BrandPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(
                        isSelected ? BrandPalette.gold.opacity(0.65) : BrandPalette.hairline,
                        lineWidth: 1
                    )
            )
            .animation(.calm, value: isSelected)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Page header for the couple's screens: eyebrow, Playfair title, gold rule, and the
/// pressed crest in the corner, travelling with the page as it does in the guest app.
struct AdminHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: eyebrow)

                Text(title)
                    .brandFont(.screenTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                GoldRule(width: 58, alignment: .leading)
                    .padding(.top, 2)
            }
            .padding(.top, 34)

            Spacer(minLength: 0)

            CrestWatermark(width: 96, finish: .pressed(BrandPalette.background))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An example shown in an empty field: lighter, italic, and prefixed "e.g.", so it can
/// never be mistaken for words already typed.
enum AdminExample {
    static func prompt(_ example: String) -> Text {
        Text("e.g. \(example)")
            .font(BrandFontSpec.bodyItalic.resolved)
            .foregroundStyle(BrandPalette.body.opacity(0.45))
    }
}

/// A labelled cream input well.
struct AdminField<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: label, size: 9.5)
                Spacer(minLength: 8)
                if let hint {
                    Text(hint)
                        .font(BrandLabel.font(size: 10, weight: .medium))
                        .foregroundStyle(BrandPalette.body.opacity(0.7))
                        .monospacedDigit()
                }
            }

            content
                .brandFont(.bodyText)
                .foregroundStyle(BrandPalette.ink)
                .tint(BrandPalette.goldDeep)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(BrandPalette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BrandPalette.gold.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

/// Tucked at the foot of the couple's area: shows this phone the after-the-wedding Home
/// and Schedule now, without waiting for February 3.
struct ThankYouPreviewToggle: View {
    @State private var phase = WeddingPhase.shared

    var body: some View {
        @Bindable var phase = phase

        Toggle(isOn: $phase.isPreviewingThankYou) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Preview post-wedding mode")
                    .font(BrandLabel.font(size: 11, weight: .semibold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(BrandPalette.body)
                Text("Only on this phone. Starts for everyone Feb 3, noon.")
                    .font(BrandLabel.font(size: 10, weight: .regular))
                    .foregroundStyle(BrandPalette.body.opacity(0.7))
            }
        }
        .tint(BrandPalette.goldDeep)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BrandPalette.hairline, lineWidth: 1)
        )
        .onChange(of: phase.isPreviewingThankYou) { _, _ in BrandHaptics.tick() }
    }
}

/// A soft line shown in place of content that couldn't load.
struct AdminNote: View {
    let text: String
    var symbol: String = "leaf"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .ultraLight))
                .foregroundStyle(BrandPalette.gold)
            Text(text)
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}
