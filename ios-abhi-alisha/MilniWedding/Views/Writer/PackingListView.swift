import SwiftUI

/// The packing list, saved on this phone per guest per wedding.
@MainActor
enum PackingStore {
    struct Saved: Codable {
        var sections: [PackingSection]
        var withKids: Bool
        var bag: PackingBag
        var temperature: Int?
        var usedModel: Bool
        var madeAt: Date
    }

    private static var key: String {
        let user = ChatSession.shared.userID?.uuidString.lowercased() ?? "guest"
        return "packing.\(user).\(ActiveWedding.snapshot.id.lowercased())"
    }

    static func load() -> Saved? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    static func save(_ saved: Saved) {
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// "Packing list": made from the guest's events, dress codes, the forecast and their saved
/// looks, then ticked off item by item.
struct PackingListView: View {
    @Environment(ScheduleStore.self) private var schedule
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sections: [PackingSection] = []
    @State private var withKids = false
    @State private var bag: PackingBag = .checked
    @State private var temperature: Int?
    @State private var usedModel = false
    @State private var isMaking = false
    @State private var didLoad = false

    private var total: Int { sections.reduce(0) { $0 + $1.items.count } }
    private var done: Int { sections.reduce(0) { $0 + $1.items.filter(\.isChecked).count } }
    private var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    options

                    WriterPrimaryButton(
                        title: sections.isEmpty ? String(localized: "Make my list") : String(localized: "Regenerate"),
                        symbol: "sparkles",
                        isBusy: isMaking
                    ) {
                        Task { await make() }
                    }

                    if !sections.isEmpty {
                        HStack {
                            PrivateBadge()
                            Spacer()
                            if !usedModel {
                                Text("From our checklist")
                                    .font(BrandLabel.font(size: 9.5, weight: .medium))
                                    .foregroundStyle(BrandPalette.body.opacity(0.75))
                            }
                        }
                        ForEach($sections) { $section in
                            sectionCard($section)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .readableWidth()
                .frame(maxWidth: .infinity)
            }
            .background(BrandPalette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(BrandPalette.goldDeep)
                }
            }
            .animation(.softFade, value: sections.isEmpty)
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            if let saved = PackingStore.load() {
                sections = saved.sections
                withKids = saved.withKids
                bag = saved.bag
                temperature = saved.temperature
                usedModel = saved.usedModel
            } else {
                temperature = await weddingTemperature()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: String(localized: "Your wedding week"))
                Text("Packing list")
                    .brandFont(.screenTitle)
                    .foregroundStyle(BrandPalette.ink)
                GoldRule(width: 58, alignment: .leading)
                    .padding(.top, 2)
                Text(summaryLine)
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
            ProgressRing(progress: progress, done: done, total: total)
                .frame(width: 66, height: 66)
        }
    }

    private var summaryLine: String {
        var parts: [String] = []
        let place = [ActiveWedding.snapshot.city, ActiveWedding.snapshot.country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        if !place.isEmpty { parts.append(place) }
        let nights = self.nights
        parts.append(nights == 1 ? String(localized: "1 night") : String(localized: "\(nights) nights"))
        if let temperature { parts.append("\(temperature)°") }
        return parts.joined(separator: " · ")
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: String(localized: "Travelling with kids?"), size: 10.5)
                HStack(spacing: 8) {
                    ChoiceChip(title: String(localized: "No"), isSelected: !withKids) { withKids = false }
                    ChoiceChip(title: String(localized: "Yes"), isSelected: withKids) { withKids = true }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: String(localized: "Luggage"), size: 10.5)
                ChipFlow(items: PackingBag.allCases, selection: bag, label: \.label) { bag = $0 }
            }
        }
    }

    // MARK: Sections

    private func sectionCard(_ section: Binding<PackingSection>) -> some View {
        let kind = section.wrappedValue.kind
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(BrandPalette.goldDeep)
                Eyebrow(text: kind.title, size: 10.5)
                Spacer()
                Text("\(section.wrappedValue.items.filter(\.isChecked).count)/\(section.wrappedValue.items.count)")
                    .font(BrandLabel.font(size: 10, weight: .medium))
                    .foregroundStyle(BrandPalette.body.opacity(0.75))
            }
            .padding(.bottom, 8)

            ForEach(section.items) { $item in
                Button {
                    BrandHaptics.tick()
                    withAnimation(reduceMotion ? .linear(duration: 0.15) : .calm) { item.isChecked.toggle() }
                    persist()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(BrandPalette.gold, lineWidth: 1.2)
                            if item.isChecked {
                                Circle().fill(BrandPalette.gold)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.white)
                            }
                        }
                        .frame(width: 20, height: 20)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }

                        Text(item.text)
                            .brandFont(.bodyText)
                            .strikethrough(item.isChecked, color: BrandPalette.gold)
                            .foregroundStyle(BrandPalette.ink)
                            .opacity(item.isChecked ? 0.45 : 1)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(item.text))
                .accessibilityValue(Text(item.isChecked ? String(localized: "Packed") : String(localized: "Not packed")))
                .accessibilityAddTraits(.isToggle)

                if item.id != section.wrappedValue.items.last?.id {
                    Rectangle().fill(BrandPalette.hairline).frame(height: 1)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BrandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
    }

    // MARK: Making the list

    private var nights: Int {
        let wedding = ActiveWedding.snapshot
        guard let start = wedding.start, let end = wedding.end else { return max(schedule.events.count > 3 ? 4 : 2, 1) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = wedding.timeZone
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 1
        return max(days + 1, 1)
    }

    private func weddingTemperature() async -> Int? {
        guard let place = WeatherPlace.forWedding(),
              let date = schedule.mainCeremony?.startsAt ?? ActiveWedding.snapshot.start else { return nil }
        let weather = await WeddingWeather.shared.weather(key: "wedding-" + ActiveWedding.snapshot.id, for: date, at: place)
        return weather.map { Int($0.highCelsius.rounded()) }
    }

    private func make() async {
        guard !isMaking else { return }
        isMaking = true
        defer { isMaking = false }

        let wedding = ActiveWedding.snapshot
        let outfits = OutfitStore.shared
        var weddingWeather: DayWeather?
        if let place = WeatherPlace.forWedding(), let date = schedule.mainCeremony?.startsAt ?? wedding.start {
            weddingWeather = await WeddingWeather.shared.weather(key: "wedding-" + wedding.id, for: date, at: place)
        }

        var events: [PackingEvent] = []
        for event in schedule.events.filter({ $0.isActive != false }) {
            let isOutdoor = event.isOutdoor == true
            let weather = isOutdoor ? await ScheduleView.weather(for: event) : nil
            let notes = OutfitCategory.allCases
                .flatMap { outfits.items(for: event.id, category: $0) }
                .compactMap { $0.note?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let filled = outfits.filledSlots(for: event.id)
            let look: String? = notes.isEmpty
                ? (filled > 0 ? String(localized: "the outfit saved in My Outfits") : nil)
                : notes.prefix(3).joined(separator: ", ")
            let code = event.dressCode?.trimmingCharacters(in: .whitespacesAndNewlines)
            events.append(PackingEvent(
                title: event.title,
                dressCode: (code?.isEmpty ?? true) ? nil : code,
                isOutdoor: isOutdoor,
                weather: weather.map { [$0.pillText, $0.hint].compactMap { $0 }.joined(separator: ", ") },
                savedLook: look
            ))
        }

        let temp = weddingWeather.map { Int($0.highCelsius.rounded()) } ?? temperature
        let context = PackingContext(
            city: wedding.city,
            country: wedding.country,
            nights: nights,
            temperature: temp,
            weatherSummary: weddingWeather?.summary,
            events: events,
            withKids: withKids,
            bag: bag
        )

        let result = await OnDeviceWriter.packingList(for: context)
        let merged = keepingChecked(result.sections, from: sections)
        withAnimation(.softFade) {
            sections = merged
            usedModel = result.usedModel
            temperature = temp
        }
        BrandHaptics.soft()
        persist()
    }

    /// Regenerating never loses what's already packed: ticked items stay ticked, and any
    /// the new list dropped are put back in their section.
    private func keepingChecked(_ fresh: [PackingSection], from old: [PackingSection]) -> [PackingSection] {
        var result = fresh
        for oldSection in old {
            for item in oldSection.items where item.isChecked {
                let key = item.text.lowercased()
                var found = false
                for s in result.indices {
                    if let i = result[s].items.firstIndex(where: { $0.text.lowercased() == key }) {
                        result[s].items[i].isChecked = true
                        found = true
                        break
                    }
                }
                if !found {
                    if let s = result.firstIndex(where: { $0.kind == oldSection.kind }) {
                        result[s].items.append(item)
                    } else {
                        result.append(PackingSection(kind: oldSection.kind, items: [item]))
                    }
                }
            }
        }
        let order = PackingSectionKind.allCases
        return result.sorted { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }
    }

    private func persist() {
        PackingStore.save(PackingStore.Saved(
            sections: sections,
            withKids: withKids,
            bag: bag,
            temperature: temperature,
            usedModel: usedModel,
            madeAt: Date()
        ))
    }
}

/// The gold ring in the header: how much is packed.
private struct ProgressRing: View {
    let progress: Double
    let done: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle().stroke(BrandPalette.gold.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(BrandPalette.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.calm, value: progress)
            VStack(spacing: 0) {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(Milni.cormorant(18, weight: 500))
                    .foregroundStyle(BrandPalette.ink)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Packed \(done) of \(total)"))
    }
}
