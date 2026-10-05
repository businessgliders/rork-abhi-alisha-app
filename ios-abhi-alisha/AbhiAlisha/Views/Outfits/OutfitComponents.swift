import SwiftUI
import UIKit

/// Where a celebration's own look opens, in any navigation stack.
struct OutfitLookRoute: Hashable {
    let eventID: String
}

extension BrandFontSpec {
    /// The couple's dress code, set as a line of display type.
    static let dressCodeLine = BrandFontSpec(.playfairItalic, size: 21, weight: 450, textStyle: .title3, maxSize: 32)
    static let outfitRowTitle = BrandFontSpec(.playfairItalic, size: 19, weight: 500, textStyle: .headline, maxSize: 30)
}

/// A thin gold ring that fills as the four parts of a look are photographed.
struct OutfitProgressRing: View {
    let filled: Int
    var total: Int = OutfitCategory.allCases.count
    var size: CGFloat = 46
    var lineWidth: CGFloat = 2.5
    var showsCount = true

    @State private var shown: Double = 0

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(filled) / Double(total), 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(BrandPalette.gold.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    LinearGradient(
                        colors: [BrandPalette.goldPale, BrandPalette.gold, BrandPalette.goldDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if showsCount {
                Text("\(filled)/\(total)")
                    .font(BrandLabel.font(size: size * 0.24, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(filled == total ? BrandPalette.goldDeep : BrandPalette.body)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.calmSlow.delay(0.15)) { shown = progress }
        }
        .onChange(of: progress) { _, value in
            withAnimation(.calm) { shown = value }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled) of \(total) pieces planned")
    }
}

/// One of the guest's own outfit photos, from memory, then the phone, then the bucket.
struct OutfitThumbnail: View {
    let path: String
    var iconSize: CGFloat = 26

    @State private var image: UIImage?

    init(path: String, iconSize: CGFloat = 26) {
        self.path = path
        self.iconSize = iconSize
        _image = State(initialValue: OutfitPhotoCache.shared.cached(path))
    }

    var body: some View {
        BrandPalette.hairline.opacity(0.6)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                } else {
                    IconWatermark(key: .sparkle, size: iconSize, opacity: 0.35)
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.35), value: image == nil)
            .task(id: path) {
                if let ready = OutfitPhotoCache.shared.cached(path) {
                    image = ready
                    return
                }
                let loaded = await OutfitPhotoCache.shared.image(for: path)
                guard !Task.isCancelled else { return }
                if let loaded { image = loaded }
            }
    }
}

/// "Only you can see your outfit photos."
struct OutfitPrivacyLine: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock")
                .font(.system(size: 10, weight: .medium))
            Text("Only you can see your outfit photos.")
                .brandFont(.bodySmall)
        }
        .foregroundStyle(BrandPalette.body.opacity(0.75))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A slim gold-lined two-way switch, drawn like Story's.
struct OutfitGenderPicker: View {
    @Binding var selection: OutfitGender

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OutfitGender.allCases) { option in
                let isSelected = option == selection
                Button {
                    guard !isSelected else { return }
                    BrandHaptics.tick()
                    withAnimation(.calm) { selection = option }
                } label: {
                    Text(option.title.uppercased())
                        .font(BrandLabel.font(size: 10.5, weight: isSelected ? .semibold : .medium))
                        .tracking(1.6)
                        .foregroundStyle(isSelected ? BrandPalette.goldDeep : BrandPalette.tabInactive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(BrandPalette.card)
                                    .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(BrandPalette.hairline.opacity(0.55)))
        .overlay(Capsule(style: .continuous).stroke(BrandPalette.gold.opacity(0.28), lineWidth: 0.75))
    }
}

/// The way into a celebration's own look, shown on the event detail sheet.
struct MyOutfitEntryCard: View {
    let eventID: String

    @State private var outfits = OutfitStore.shared

    var body: some View {
        let filled = outfits.filledSlots(for: eventID)
        let cover = outfits.coverItem(for: eventID)

        HStack(spacing: 16) {
            OutfitProgressRing(filled: filled, size: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(filled == 0 ? "Plan my look" : "My look")
                    .brandFont(.outfitRowTitle)
                    .foregroundStyle(BrandPalette.ink)
                Text(summary(filled))
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 6)

            if let cover {
                OutfitThumbnail(path: cover.photoPath, iconSize: 18)
                    .frame(width: 46, height: 58)
                    .clipShape(.rect(cornerRadius: 10))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(BrandPalette.gold)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BrandPalette.card))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BrandPalette.gold.opacity(0.4), lineWidth: 1)
        )
    }

    private func summary(_ filled: Int) -> String {
        switch filled {
        case 0: return "Outfit, jewellery, shoes and accessories"
        case 4: return "All four pieces ready"
        default: return "\(filled) of 4 pieces planned"
        }
    }
}
