import SwiftUI

/// The short gold card that rises on the very first open: one line on what updates bring,
/// "Turn on" (which shows the iPhone's own prompt) and "Not now".
struct FirstOpenUpdatesCard: View {
    @Environment(PushRegistrar.self) private var push

    @State private var isAsking = false
    @State private var bellRings = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "bell")
                    .symbolVariant(.none)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(Color(hex: 0xFFFBF1))
                    .symbolEffect(.wiggle, value: bellRings)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color(hex: 0xFFFBF1).opacity(0.14)))
                    .overlay(Circle().stroke(Color(hex: 0xFFFBF1).opacity(0.4), lineWidth: 0.75))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Get schedule updates")
                        .font(Font(BrandFont.uiFont(.playfairItalic, size: 21, weight: 500, textStyle: .headline, maxSize: 30)))
                        .foregroundStyle(Color(hex: 0xFFFBF1))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Time changes, shuttle calls and moments not to miss, straight from Abhi & Alisha.")
                        .brandFont(.bodySmall)
                        .foregroundStyle(Color(hex: 0xFFFBF1).opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button {
                    BrandHaptics.tick()
                    close()
                } label: {
                    Text("Not now")
                        .font(BrandLabel.font(size: 11.5, weight: .semibold))
                        .tracking(1.3)
                        .textCase(.uppercase)
                        .foregroundStyle(Color(hex: 0xFFFBF1).opacity(0.9))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color(hex: 0xFFFBF1).opacity(0.45), lineWidth: 1)
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(PressableStyle())

                Button(action: turnOn) {
                    HStack(spacing: 8) {
                        if isAsking {
                            ProgressView()
                                .controlSize(.small)
                                .tint(BrandPalette.goldDeep)
                        }
                        Text("Turn on")
                            .font(BrandLabel.font(size: 11.5, weight: .bold))
                            .tracking(1.3)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(Color(hex: 0x8A6C2C))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule(style: .continuous).fill(Color(hex: 0xFFFBF1)))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .disabled(isAsking)
            }
            .padding(.top, 18)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xC9AA55), Color(hex: 0xA9873C), Color(hex: 0x94742F)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(hex: 0xE9D598).opacity(0.7), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 26, x: 0, y: 14)
        .frame(maxWidth: 460)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            bellRings += 1
        }
    }

    private func turnOn() {
        BrandHaptics.soft()
        isAsking = true
        Task {
            await push.requestPermission()
            isAsking = false
            close()
        }
    }

    private func close() {
        withAnimation(.calm) { push.isFirstOpenCardPresented = false }
    }
}
