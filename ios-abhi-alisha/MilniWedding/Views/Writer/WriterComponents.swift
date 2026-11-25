import SwiftUI

/// A small selectable capsule: gold when picked, hairline otherwise.
struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            BrandHaptics.tick()
            action()
        } label: {
            Text(title)
                .brandFont(.bodySmall)
                .foregroundStyle(isSelected ? Color.white : BrandPalette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? BrandPalette.goldDeep : BrandPalette.card))
                .overlay(Capsule().stroke(isSelected ? Color.clear : BrandPalette.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A row of chips that wraps onto as many lines as it needs.
struct ChipFlow<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let selection: Item
    let label: (Item) -> String
    let select: (Item) -> Void

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(items) { item in
                ChoiceChip(title: label(item), isSelected: item == selection) {
                    withAnimation(.softFade) { select(item) }
                }
            }
        }
    }
}

/// Lays children left to right, wrapping like words.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// "On-device · private": a gold eyebrow with a lock.
struct PrivateBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .semibold))
            Text("On-device · private")
                .font(BrandLabel.font(size: 9.5, weight: .semibold))
                .tracking(1.4)
                .textCase(.uppercase)
        }
        .foregroundStyle(BrandPalette.goldDeep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Written on your phone. Private."))
    }
}

/// The gold primary button used by the writers.
struct WriterPrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button {
            BrandHaptics.soft()
            action()
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().tint(.white)
                } else if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
                    .font(BrandLabel.font(size: 12.5, weight: .semibold))
                    .tracking(1.4)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(BrandPalette.goldDeep))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(isBusy)
    }
}

/// A quiet outline button.
struct WriterSecondaryButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button {
            BrandHaptics.tick()
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(BrandLabel.font(size: 11, weight: .semibold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(BrandPalette.goldDeep)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .overlay(Capsule().stroke(BrandPalette.gold.opacity(0.6), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}
