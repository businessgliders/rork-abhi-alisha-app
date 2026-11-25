import SwiftUI

/// The signature navigation: a drooping gold wire strung between two little planes,
/// with one hanging bulb per celebration. The selected bulb is lit.
struct StringLightsNavigation: View {
    let events: [ScheduleEvent]
    @Binding var selectedIndex: Int

    private let sag: CGFloat = 22
    private let startY: CGFloat = 10
    private let endY: CGFloat = 20
    private let horizontalInset: CGFloat = 34

    @State private var glowPhase = false

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                let width = max(proxy.size.width - horizontalInset * 2, 1)

                ZStack(alignment: .topLeading) {
                    DroopingWire(sag: sag, startY: startY, endY: endY)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    BrandPalette.gold.opacity(0.35),
                                    BrandPalette.gold.opacity(0.85),
                                    BrandPalette.gold.opacity(0.35)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round)
                        )
                        .frame(width: width)
                        .offset(x: horizontalInset)

                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        let point = bulbPoint(index: index, width: width)

                        Button {
                            select(index)
                        } label: {
                            FestoonBulb(
                                isLit: index == selectedIndex,
                                dropLength: 14,
                                size: 13,
                                glowPhase: glowPhase
                            )
                            .frame(width: 46, height: 58, alignment: .top)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(x: horizontalInset + point.x, y: point.y + 29)
                        .accessibilityLabel(event.title)
                        .accessibilityAddTraits(index == selectedIndex ? [.isButton, .isSelected] : .isButton)
                    }

                    planeMarker(systemName: "airplane.arrival", label: "ARRIVE")
                        .position(x: horizontalInset / 2 + 2, y: startY + 16)

                    planeMarker(systemName: "airplane.departure", label: "DEPART")
                        .position(x: horizontalInset + width + horizontalInset / 2 - 2, y: endY + 16)
                }
            }
            .frame(height: 88)
        }
        .animation(.calm, value: selectedIndex)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                glowPhase = true
            }
        }
    }

    private func bulbPoint(index: Int, width: CGFloat) -> CGPoint {
        let count = max(events.count, 1)
        let t: CGFloat = count == 1 ? 0.5 : (CGFloat(index) + 0.5) / CGFloat(count)
        return DroopingWire.point(t: t, width: width, startY: startY, endY: endY, sag: sag)
    }

    private func select(_ index: Int) {
        guard index != selectedIndex else { return }
        BrandHaptics.tick()
        withAnimation(.calm) {
            selectedIndex = index
        }
    }

    private func planeMarker(systemName: String, label: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(BrandPalette.gold)
            Text(label)
                .font(BrandLabel.font(size: 8.5, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(BrandPalette.gold.opacity(0.8))
                .fixedSize()
        }
        .accessibilityHidden(true)
    }
}
