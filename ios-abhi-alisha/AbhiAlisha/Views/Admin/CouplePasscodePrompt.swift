import SwiftUI
import UIKit

/// The small card that rises after the crest is held. A wrong code shakes and clears —
/// no message, no count of attempts.
struct CouplePasscodePrompt: View {
    @Environment(AdminSession.self) private var session

    @State private var code = ""
    @State private var attempts = 0
    @State private var isChecking = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityHidden(true)

            card
                .padding(24)
        }
        .onAppear {
            isFocused = true
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            CrestWatermark(width: 74, finish: .pressed(BrandPalette.card))

            Eyebrow(text: "For the couple", size: 10)
                .padding(.top, 18)

            Text("Welcome back")
                .brandFont(.eventTitleSmall)
                .foregroundStyle(BrandPalette.ink)
                .padding(.top, 6)

            GoldRule(width: 34)
                .padding(.top, 12)

            SecureField("Passcode", text: $code)
                .font(.system(size: 18, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(BrandPalette.ink)
                .tint(BrandPalette.goldDeep)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($isFocused)
                .onSubmit(submit)
                .padding(.vertical, 15)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(BrandPalette.background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BrandPalette.gold.opacity(0.35), lineWidth: 1)
                )
                .modifier(ShakeEffect(animatableData: CGFloat(attempts)))
                .padding(.top, 22)

            GoldActionButton(
                title: "Enter",
                isBusy: isChecking,
                isEnabled: !code.isEmpty
            ) {
                submit()
            }
            .padding(.top, 14)

            Button("Cancel", action: close)
                .font(BrandLabel.font(size: 12, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.body)
                .frame(minHeight: 44)
                .padding(.top, 4)
        }
        .padding(.horizontal, 26)
        .padding(.top, 28)
        .padding(.bottom, 14)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(BrandPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(BrandPalette.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 30, y: 16)
    }

    private func submit() {
        guard !isChecking, !code.isEmpty else { return }
        isChecking = true
        let entered = code

        Task {
            let isValid = await session.unlock(with: entered)
            isChecking = false
            guard !isValid else {
                code = ""
                return
            }
            code = ""
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.linear(duration: 0.42)) {
                attempts += 1
            }
            isFocused = true
        }
    }

    private func close() {
        BrandHaptics.tick()
        isFocused = false
        session.dismissPrompt()
    }
}
