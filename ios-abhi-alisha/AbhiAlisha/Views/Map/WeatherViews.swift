import SwiftUI

/// The forecast for an outdoor celebration: Apple Weather's symbol, temperature and
/// condition, with a one-line tip when the forecast calls for one.
struct WeatherForecastCard: View {
    let weather: DayWeather

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: weather.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 22, weight: .light))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(BrandPalette.gold.opacity(0.45), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(weather.pillText)
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tipLine)
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BrandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Weather: \(weather.accessibilityText)"))
    }

    private var tipLine: String {
        if let hint = weather.hint { return hint }
        return weather.isSeasonalAverage
            ? String(localized: "Typical for this date. The forecast arrives ten days out.")
            : String(localized: "Forecast for when it starts.")
    }
}

/// Apple Weather's mark and its legal link, required wherever its data shows.
struct WeatherAttributionFooter: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var credit: WeatherCredit?

    var body: some View {
        HStack(spacing: 10) {
            if let credit {
                AsyncImage(url: colorScheme == .dark ? credit.darkMarkURL : credit.lightMarkURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(credit.serviceName)
                        .font(BrandLabel.font(size: 10, weight: .medium))
                        .foregroundStyle(BrandPalette.body)
                }
                .frame(height: 12)
                .accessibilityLabel(Text(credit.serviceName))

                Link(destination: credit.legalURL) {
                    Text("Legal attribution")
                        .font(BrandLabel.font(size: 10, weight: .medium))
                        .underline()
                        .foregroundStyle(BrandPalette.body)
                }
                .accessibilityHint("Opens Apple Weather's data sources")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 16)
        .task {
            if credit == nil { credit = await WeddingWeather.shared.attribution() }
        }
    }
}
