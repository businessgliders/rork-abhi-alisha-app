import SwiftUI

/// Home's quiet invitation to wedding updates. Once they're on, it steps back to a single
/// line and never asks again.
struct NotifyUpdatesCard: View {
    @Environment(PushRegistrar.self) private var push

    var body: some View {
        if push.isEnabled {
            updatesOn
                .transition(.opacity)
        } else {
            invitation
                .transition(.opacity)
        }
    }

    private var invitation: some View {
        Button {
            BrandHaptics.soft()
            push.markOffered()
            push.isExplainerPresented = true
        } label: {
            MatteCard(cornerRadius: 22) {
                HStack(spacing: 16) {
                    Image(systemName: "bell")
                        .symbolVariant(.none)
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(BrandPalette.goldDeep)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(BrandPalette.gold.opacity(0.5), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Notify me about updates")
                            .brandFont(.bodyText)
                            .foregroundStyle(BrandPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Schedule changes, shuttle times, and moments not to miss.")
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(BrandPalette.gold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Explains wedding updates before asking to send them")
    }

    private var updatesOn: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .semibold))
            Text("Wedding updates on")
                .font(BrandLabel.font(size: 10, weight: .semibold))
                .tracking(1.6)
                .textCase(.uppercase)
        }
        .foregroundStyle(BrandPalette.gold.opacity(0.85))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
