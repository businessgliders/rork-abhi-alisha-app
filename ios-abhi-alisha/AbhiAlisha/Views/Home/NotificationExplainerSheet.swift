import SwiftUI
import UIKit

/// Why updates are worth having — shown before the iPhone's own prompt, never instead of it.
struct NotificationExplainerSheet: View {
    @Environment(PushRegistrar.self) private var push
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isAsking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                bell
                    .padding(.top, 34)

                Eyebrow(text: "Stay in the loop")
                    .padding(.top, 24)

                Text("Wedding Updates")
                    .brandFont(.eventTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                GoldRule(width: 40)
                    .padding(.top, 14)

                Text(introduction)
                    .brandFont(.bodyItalic)
                    .lineSpacing(BrandFontSpec.bodyItalic.lineSpacing)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 18) {
                    reason("clock", "Schedule changes", "If a time or a venue moves, you'll hear it first.")
                    reason("bus", "Shuttle times", "When to be in the lobby, and where to meet.")
                    reason("sparkles", "Moments not to miss", "The grand entrances, the first dance, the sparklers.")
                }
                .padding(.top, 30)

                primaryButton
                    .padding(.top, 34)

                Button("Not now") {
                    BrandHaptics.tick()
                    dismiss()
                }
                .font(BrandLabel.font(size: 12, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.body)
                .frame(minHeight: 44)
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .readableWidth(480)
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .presentationDetents([.fraction(0.86), .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }

    private var introduction: String {
        push.isDenied
            ? "Updates are switched off for this app. You can turn them on in Settings whenever you like."
            : "A gentle note from Abhi & Alisha, only when it matters. Never anything else."
    }

    private var bell: some View {
        Image(systemName: "bell")
            .symbolVariant(.none)
            .font(.system(size: 26, weight: .ultraLight))
            .foregroundStyle(BrandPalette.goldDeep)
            .frame(width: 78, height: 78)
            .background(Circle().fill(BrandPalette.card))
            .overlay(Circle().stroke(BrandPalette.gold.opacity(0.55), lineWidth: 1))
            .overlay(Circle().stroke(BrandPalette.gold.opacity(0.18), lineWidth: 1).padding(-8))
            .shadow(color: BrandPalette.gold.opacity(0.22), radius: 18)
            .accessibilityHidden(true)
    }

    private func reason(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .symbolVariant(.none)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(BrandPalette.goldDeep)
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(BrandPalette.gold.opacity(0.4), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.ink)
                Text(detail)
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var primaryButton: some View {
        GoldActionButton(
            title: push.isDenied ? "Open Settings" : "Turn on updates",
            isBusy: isAsking
        ) {
            if push.isDenied {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
                dismiss()
                return
            }
            isAsking = true
            Task {
                await push.requestPermission()
                isAsking = false
                dismiss()
            }
        }
    }
}
