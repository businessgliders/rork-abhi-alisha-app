import SwiftUI

/// Whether this phone has agreed to the chat's community guidelines.
nonisolated enum CommunityGuidelines {
    static let storageKey = "chat.guidelinesAccepted"

    static var isAccepted: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }
}

/// Shown the first time someone posts in any chat. "I agree" sends what they typed;
/// "Cancel" leaves the draft exactly as it was.
struct CommunityGuidelinesSheet: View {
    let onAgree: () -> Void

    @AppStorage(CommunityGuidelines.storageKey) private var isAccepted = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "hand.raised")
                    .symbolVariant(.none)
                    .font(.system(size: 24, weight: .ultraLight))
                    .foregroundStyle(BrandPalette.goldDeep)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(BrandPalette.card))
                    .overlay(Circle().stroke(BrandPalette.gold.opacity(0.55), lineWidth: 1))
                    .accessibilityHidden(true)
                    .padding(.top, 30)

                Eyebrow(text: "Before you post")
                    .padding(.top, 22)

                Text("Community guidelines")
                    .brandFont(.eventTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                GoldRule(width: 40)
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 16) {
                    rule("heart", "Be kind.")
                    rule("nosign", "No offensive, hateful or explicit content.")
                    rule("flag", "Messages can be reported and users removed.")
                }
                .padding(.top, 26)

                GoldActionButton(title: "I agree") {
                    isAccepted = true
                    BrandHaptics.tick()
                    dismiss()
                    onAgree()
                }
                .padding(.top, 30)

                Button("Cancel") {
                    BrandHaptics.tick()
                    dismiss()
                }
                .font(BrandLabel.font(size: 12, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.body)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
            .readableWidth(480)
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }

    private func rule(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .symbolVariant(.none)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(BrandPalette.goldDeep)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(BrandPalette.gold.opacity(0.4), lineWidth: 1))
            Text(text)
                .brandFont(.bodyText)
                .foregroundStyle(BrandPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
