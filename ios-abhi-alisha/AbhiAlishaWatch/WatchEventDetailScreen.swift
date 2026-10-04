import SwiftUI

/// One celebration, at reading distance: name in Playfair italic, its line-art mark in
/// gold, then the time, the place and the dress code — whatever is known. Anything
/// missing is simply left out.
struct WatchEventDetailScreen: View {
    let event: WatchEvent

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchLineArtIcon(key: event.iconKey)
                    .stroke(
                        WatchTheme.gold,
                        style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 40, height: 40)
                    .padding(.top, 6)
                    .accessibilityHidden(true)

                Text(event.title)
                    .font(.watchPlayfair(18, weight: .semibold))
                    .foregroundStyle(WatchTheme.cream)
                    .multilineTextAlignment(.center)

                Rectangle()
                    .fill(WatchTheme.gold.opacity(0.6))
                    .frame(width: 34, height: 1)

                detailRow(
                    eyebrow: "When",
                    value: [event.displayDate, event.displayTime].compactMap { $0 }.joined(separator: "  ·  ")
                )
                detailRow(eyebrow: "Where", value: event.locationName)
                detailRow(eyebrow: "Dress", value: event.dressCode)

                if let description = event.description {
                    Text(description)
                        .font(.watchCormorant(13.5))
                        .foregroundStyle(WatchTheme.creamDim)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("")
    }

    @ViewBuilder
    private func detailRow(eyebrow: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(spacing: 2) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(WatchTheme.gold.opacity(0.8))

                Text(value)
                    .font(.watchCormorant(14))
                    .foregroundStyle(WatchTheme.cream)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
