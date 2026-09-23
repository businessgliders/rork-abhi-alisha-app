import SwiftUI

/// The app's one filled call to action: a gold gradient slab with cream caps.
struct GoldActionButton: View {
    let title: String
    var systemImage: String?
    var isBusy: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled, !isBusy else { return }
            BrandHaptics.soft()
            action()
        } label: {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(hex: 0xFFFBF1))
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(title)
                    .font(BrandLabel.font(size: 12.5, weight: .semibold))
                    .tracking(1.5)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Color(hex: 0xFFFBF1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(hex: 0xE0C982).opacity(0.5), lineWidth: 0.75)
            )
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled || isBusy)
    }
}

/// A side-to-side shake for a wrong entry — nothing more is said about it.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 10
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = travel * sin(animatableData * .pi * shakes * 2)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
