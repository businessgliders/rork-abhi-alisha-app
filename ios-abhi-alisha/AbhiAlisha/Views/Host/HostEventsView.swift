import MapKit
import PhotosUI
import SwiftUI

// MARK: - Events list

/// Every celebration, in the order guests see them. Drag to reorder, tap to edit.
struct HostEventsView: View {
    @Environment(ScheduleStore.self) private var schedule

    @State private var events: [HostEvent] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var editing: HostEvent?

    private var weddingID: String { WeddingContext.shared.weddingID }

    var body: some View {
        List {
            if let error {
                HostErrorLine(message: error)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if isLoading && events.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if events.isEmpty {
                VStack(spacing: 14) {
                    HostEmptyLine(text: "No celebrations yet.")
                    Button("Add your first celebration") { editing = .blank(sort: 0) }
                        .buttonStyle(.milniPrimary)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(events) { event in
                        Button {
                            BrandHaptics.tick()
                            editing = event
                        } label: {
                            HostEventRow(event: event)
                        }
                        .listRowBackground(HostStyle.card)
                    }
                    .onMove(perform: move)
                } footer: {
                    Text("Hold and drag a celebration to change its place in the schedule.")
                        .font(Milni.inter(12))
                        .foregroundStyle(HostStyle.muted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(HostPaper())
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New event", systemImage: "plus") { editing = .blank(sort: events.count) }
                    Button("Sort by date and time", systemImage: "clock") { Task { await sortByTime() } }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(HostStyle.ink)
                }
                .accessibilityLabel("Add or sort")
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $editing) { event in
            HostEventEditor(event: event) { saved in
                if let saved {
                    if let index = events.firstIndex(where: { $0.id == saved.id }) {
                        events[index] = saved
                    } else {
                        events.append(saved)
                    }
                } else {
                    events.removeAll { $0.id == event.id }
                }
                Task { await schedule.refresh() }
            }
            .interactiveDismissDisabled()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await HostAPI.shared.events(weddingID: weddingID)
            withAnimation(.calm) {
                events = loaded.sorted { ($0.sort, $0.startsAt ?? .distantFuture) < ($1.sort, $1.startsAt ?? .distantFuture) }
            }
            error = nil
        } catch {
            self.error = error.hostMessage
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        events.move(fromOffsets: source, toOffset: destination)
        BrandHaptics.tick()
        Task { await saveOrder() }
    }

    private func sortByTime() async {
        withAnimation(.calm) {
            events.sort { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
        }
        await saveOrder()
    }

    private func saveOrder() async {
        do {
            try await HostAPI.shared.reorder(events)
            for index in events.indices { events[index].sort = index }
            error = nil
            await schedule.refresh()
        } catch {
            self.error = error.hostMessage
        }
    }
}

private struct HostEventRow: View {
    let event: HostEvent

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 1) {
                if let start = event.startsAt {
                    Text(dayNumber(start))
                        .font(Milni.cormorant(24, weight: 500))
                    Text(month(start).uppercased())
                        .font(Milni.inter(9, weight: 600))
                        .tracking(1.2)
                } else {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 16))
                }
            }
            .foregroundStyle(HostStyle.goldText)
            .frame(width: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .font(Milni.cormorant(21, weight: 500))
                    .foregroundStyle(HostStyle.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(Milni.inter(12))
                    .foregroundStyle(HostStyle.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if event.isOutdoor {
                Image(systemName: "sun.max")
                    .font(.system(size: 13))
                    .foregroundStyle(HostStyle.gold)
                    .accessibilityLabel("Outdoors")
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts: [String] = []
        if let start = event.startsAt { parts.append(HostTime.time(start)) } else { parts.append("Date to be set") }
        if !event.venueName.isEmpty { parts.append(event.venueName) }
        return parts.joined(separator: " · ")
    }

    private func dayNumber(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.day()
        style.timeZone = HostTime.zone
        return date.formatted(style)
    }

    private func month(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated)
        style.timeZone = HostTime.zone
        return date.formatted(style)
    }
}

// MARK: - Editor

/// One celebration, edited in a sheet. `done` gets the saved event, or nil after a delete.
struct HostEventEditor: View {
    @State var event: HostEvent
    let done: (HostEvent?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var hasDate: Bool
    @State private var hasEnd: Bool
    @State private var day: Date
    @State private var start: Date
    @State private var end: Date
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var outfitPicks: [PhotosPickerItem] = []
    @State private var uploading = 0
    @State private var venueQuery = ""
    @State private var venueResults: [MKMapItem] = []
    @State private var isSearching = false

    private var weddingID: String { WeddingContext.shared.weddingID }

    static let kinds: [(id: String, title: String, symbol: String)] = [
        ("welcome", "Welcome", "hand.wave"),
        ("mehndi", "Mehndi", "hand.raised"),
        ("haldi", "Haldi", "sun.max"),
        ("sangeet", "Sangeet", "music.note"),
        ("ceremony", "Ceremony", "heart"),
        ("reception", "Reception", "wineglass"),
        ("brunch", "Brunch", "cup.and.saucer"),
        ("custom", "Other", "sparkles"),
    ]

    init(event: HostEvent, done: @escaping (HostEvent?) -> Void) {
        _event = State(initialValue: event)
        self.done = done
        let fallback = Self.defaultStart()
        let start = event.startsAt ?? fallback
        _hasDate = State(initialValue: event.startsAt != nil)
        _hasEnd = State(initialValue: event.endsAt != nil)
        _day = State(initialValue: start)
        _start = State(initialValue: start)
        _end = State(initialValue: event.endsAt ?? start.addingTimeInterval(3 * 3600))
        _venueQuery = State(initialValue: event.venueName)
    }

    private static func defaultStart() -> Date {
        let snapshot = WeddingContext.shared.snapshot
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = HostTime.zone
        if let text = snapshot.startDate {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = HostTime.zone
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: text), let six = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date) {
                return six
            }
        }
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
    }

    var body: some View {
        VStack(spacing: 0) {
            HostSheetBar(
                title: "Event",
                canSave: !event.title.hostTrimmed.isEmpty && uploading == 0,
                isSaving: isSaving,
                cancel: { dismiss() },
                save: { Task { await save() } }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HostTitleField(placeholder: "Event name", text: $event.title, size: 40)
                        .padding(.top, 10)

                    kindPicker
                    whenSection
                    venueSection

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $event.isOutdoor.animation(.calm)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Outdoors")
                                    .font(Milni.inter(16, weight: 500))
                                    .foregroundStyle(HostStyle.ink)
                                Text(event.isOutdoor ? "Outdoors · forecast on" : "Guests see the forecast for outdoor events")
                                    .font(Milni.inter(12))
                                    .foregroundStyle(event.isOutdoor ? HostStyle.goldText : HostStyle.muted)
                                    .contentTransition(.opacity)
                            }
                        }
                        .tint(HostStyle.gold)
                    }

                    HostField(label: "Dress code", text: $event.dressCode, placeholder: "Garden formal, pastels welcome")

                    outfitSection

                    HostField(label: "About", text: $event.description, placeholder: "What guests should know about this celebration", multiline: true)

                    faqSection

                    HostErrorLine(message: error)

                    if !event.isNew {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Text("Delete this event")
                                .font(Milni.inter(15, weight: 500))
                                .foregroundStyle(HostStyle.danger)
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .confirmationDialog("Delete \(event.title.isEmpty ? "this event" : event.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete event", role: .destructive) { Task { await delete() } }
                        } message: {
                            Text("Guests will no longer see it in the schedule. This can't be undone.")
                        }
                    }
                }
                .padding(.horizontal, HostStyle.side)
                .padding(.bottom, 60)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(HostPaper())
        .environment(\.colorScheme, .light)
        .onChange(of: outfitPicks) { _, picks in
            guard !picks.isEmpty else { return }
            outfitPicks = []
            Task { await upload(picks) }
        }
    }

    // MARK: Sections

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HostCaps("Kind", color: HostStyle.muted)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.kinds, id: \.id) { kind in
                        HostChip(title: kind.title, symbol: kind.symbol, isOn: event.kind == kind.id) {
                            event.kind = kind.id
                        }
                    }
                }
                .padding(.horizontal, HostStyle.side)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -HostStyle.side)
        }
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HostCaps("When", color: HostStyle.muted)
            VStack(spacing: 0) {
                Toggle("Date is set", isOn: $hasDate.animation(.calm))
                    .font(Milni.inter(16))
                    .tint(HostStyle.gold)
                    .padding(.vertical, 10)
                if hasDate {
                    Divider()
                    DatePicker("Date", selection: $day, displayedComponents: .date)
                        .padding(.vertical, 6)
                    Divider()
                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                        .padding(.vertical, 6)
                    Divider()
                    Toggle("Has an end time", isOn: $hasEnd.animation(.calm))
                        .tint(HostStyle.gold)
                        .padding(.vertical, 10)
                    if hasEnd {
                        Divider()
                        DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                            .padding(.vertical, 6)
                    }
                }
            }
            .font(Milni.inter(16))
            .foregroundStyle(HostStyle.ink)
            .environment(\.timeZone, HostTime.zone)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(HostStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(HostStyle.hairline, lineWidth: 1))
            Text("Times are in the wedding's time zone (\(HostTime.zone.identifier.replacingOccurrences(of: "_", with: " "))).")
                .font(Milni.inter(12))
                .foregroundStyle(HostStyle.muted)
        }
    }

    private var venueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HostCaps("Venue", color: HostStyle.muted)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(HostStyle.muted)
                TextField("", text: $venueQuery, prompt: Text("Search for a place").foregroundStyle(HostStyle.muted.opacity(0.5)))
                    .font(Milni.inter(16))
                    .foregroundStyle(HostStyle.ink)
                    .submitLabel(.search)
                    .onSubmit { Task { await searchVenue() } }
                if isSearching { ProgressView() }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HostStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(HostStyle.hairline, lineWidth: 1))

            if !venueResults.isEmpty {
                HostCard {
                    ForEach(Array(venueResults.prefix(5).enumerated()), id: \.offset) { index, item in
                        if index > 0 { HostHairline() }
                        Button {
                            choose(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Place")
                                    .font(Milni.inter(15, weight: 600))
                                    .foregroundStyle(HostStyle.ink)
                                Text(Self.address(of: item))
                                    .font(Milni.inter(12))
                                    .foregroundStyle(HostStyle.muted)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HostRowPressStyle())
                    }
                }
                .transition(.opacity)
            }

            if let lat = event.lat, let lng = event.lng {
                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 900, longitudinalMeters: 900))) {
                    Marker(event.venueName.isEmpty ? "Venue" : event.venueName, coordinate: coordinate)
                        .tint(HostStyle.ink)
                }
                .id("\(lat),\(lng)")
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            HostField(label: "Venue name", text: $event.venueName, placeholder: "The Terrace")
            HostField(label: "Address", text: $event.address, placeholder: "Street, city")
        }
        .animation(.calm, value: venueResults.count)
    }

    private var outfitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HostCaps("Outfit inspiration", color: HostStyle.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(event.outfitImages) { tile in
                    RemoteImage(url: URL(string: tile.imageURL), contentMode: .fill) {
                        HostStyle.hairline
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            BrandHaptics.tick()
                            withAnimation(.calm) { event.outfitImages.removeAll { $0.id == tile.id } }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(.black.opacity(0.55)))
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Remove photo")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
                ForEach(0..<uploading, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(HostStyle.hairline.opacity(0.6))
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .overlay(ProgressView())
                }
                PhotosPicker(selection: $outfitPicks, maxSelectionCount: 6, matching: .images) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(HostStyle.gold.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "plus").font(.system(size: 18, weight: .light))
                                Text("Add").font(Milni.inter(12, weight: 500))
                            }
                            .foregroundStyle(HostStyle.goldText)
                        }
                }
                .accessibilityLabel("Add outfit photos")
            }
            .animation(.calm, value: event.outfitImages.count)
        }
    }

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HostCaps("Questions guests ask", color: HostStyle.muted)
            ForEach($event.faqs) { $faq in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        TextField("", text: $faq.question, prompt: Text("Question").foregroundStyle(HostStyle.muted.opacity(0.5)), axis: .vertical)
                            .font(Milni.cormorant(20, weight: 600))
                        Button {
                            BrandHaptics.tick()
                            withAnimation(.calm) { event.faqs.removeAll { $0.id == faq.id } }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(HostStyle.muted)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Remove question")
                    }
                    TextField("", text: $faq.answer, prompt: Text("Answer").foregroundStyle(HostStyle.muted.opacity(0.5)), axis: .vertical)
                        .font(Milni.inter(15))
                        .lineLimit(1...8)
                }
                .foregroundStyle(HostStyle.ink)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(HostStyle.card))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(HostStyle.hairline, lineWidth: 1))
                .transition(.opacity)
            }
            Button {
                BrandHaptics.tick()
                withAnimation(.calm) { event.faqs.append(.init(question: "", answer: "")) }
            } label: {
                Label("Add a question", systemImage: "plus")
                    .font(Milni.inter(15, weight: 600))
                    .foregroundStyle(HostStyle.goldText)
                    .frame(minHeight: 44)
            }
        }
    }

    // MARK: Actions

    private func combined(_ day: Date, _ time: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = HostTime.zone
        let d = calendar.dateComponents([.year, .month, .day], from: day)
        let t = calendar.dateComponents([.hour, .minute], from: time)
        var parts = DateComponents()
        parts.year = d.year; parts.month = d.month; parts.day = d.day
        parts.hour = t.hour; parts.minute = t.minute
        return calendar.date(from: parts) ?? day
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var draft = event
        draft.title = draft.title.hostTrimmed
        if hasDate {
            let startsAt = combined(day, start)
            draft.startsAt = startsAt
            if hasEnd {
                var endsAt = combined(day, end)
                if endsAt <= startsAt { endsAt = endsAt.addingTimeInterval(24 * 3600) }
                draft.endsAt = endsAt
            } else {
                draft.endsAt = nil
            }
        } else {
            draft.startsAt = nil
            draft.endsAt = nil
        }
        do {
            let saved = try await HostAPI.shared.save(draft, weddingID: weddingID)
            BrandHaptics.soft()
            done(saved)
            dismiss()
        } catch {
            withAnimation(.calm) { self.error = error.hostMessage }
        }
    }

    private func delete() async {
        do {
            try await HostAPI.shared.delete(eventID: event.id)
            done(nil)
            dismiss()
        } catch {
            withAnimation(.calm) { self.error = error.hostMessage }
        }
    }

    private func upload(_ picks: [PhotosPickerItem]) async {
        uploading += picks.count
        for item in picks {
            defer { uploading -= 1 }
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                error = "One photo couldn't be read. Try another."
                continue
            }
            do {
                let path = "\(weddingID.lowercased())/events/\(UUID().uuidString.lowercased()).jpg"
                let url = try await HostAPI.shared.uploadPhoto(image, path: path, maxSide: 1600)
                withAnimation(.calm) { event.outfitImages.append(.init(imageURL: url, lightboxURL: url, caption: nil)) }
            } catch {
                self.error = error.hostMessage
            }
        }
    }

    private func searchVenue() async {
        let query = venueQuery.hostTrimmed
        guard !query.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let lat = WeddingContext.shared.snapshot.latitude, let lng = WeddingContext.shared.snapshot.longitude {
            request.region = MKCoordinateRegion(center: .init(latitude: lat, longitude: lng), latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        }
        do {
            venueResults = try await MKLocalSearch(request: request).start().mapItems
            if venueResults.isEmpty { error = "No places found for that search." } else { error = nil }
        } catch {
            venueResults = []
            self.error = "Couldn't search the map right now. You can type the venue below."
        }
    }

    private func choose(_ item: MKMapItem) {
        BrandHaptics.soft()
        withAnimation(.calm) {
            event.venueName = item.name ?? event.venueName
            event.address = Self.address(of: item)
            event.lat = item.placemark.coordinate.latitude
            event.lng = item.placemark.coordinate.longitude
            venueQuery = item.name ?? venueQuery
            venueResults = []
        }
    }

    static func address(of item: MKMapItem) -> String {
        let mark = item.placemark
        let parts = [
            [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " "),
            mark.locality ?? "",
            mark.country ?? "",
        ]
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
