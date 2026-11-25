import SwiftUI

/// Placeholder for the sections still being written: Story, Gallery, Details.
struct ComingSoonView: View {
    let eyebrow: String
    let title: String
    let note: String
    let icon: EventIconKey

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: eyebrow)

                Text(title)
                    .brandFont(.screenTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .padding(.top, 10)

                GoldRule(width: 58, alignment: .leading)
                    .padding(.top, 16)

                VStack(spacing: 20) {
                    IconWatermark(key: icon, size: 108, opacity: 0.32)

                    Text(note)
                        .brandFont(.bodyItalic)
                        .lineSpacing(BrandFontSpec.bodyItalic.lineSpacing)
                        .foregroundStyle(BrandPalette.body)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 90)
            }
            .padding(.horizontal, 22)
            .padding(.top, ScreenChrome.contentReserve)
            .padding(.bottom, FloatingTabBar.contentReserve + 24)
            .readableWidth()
            .crestCorner()
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
    }
}
