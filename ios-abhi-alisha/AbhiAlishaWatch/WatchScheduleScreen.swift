import SwiftUI

/// How a row sits in the evening: underway, still to come, or already past.
enum WatchRowState {
    case current
    case upcoming
    case past
}

/// The whole watch app on one screen: today's (or the next day's) celebrations in a
/// vertical list, the one happening now glowing gold, past ones dimmed. The schedule
/// is on screen from the first moment — the bundled copy until a refresh lands.
struct WatchScheduleScreen: View {
    @State private var store = WatchScheduleStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var didScrollToCurrent = false
    @State private var didChime = false

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = WatchScheduleScreen.dayZone
        return calendar
    }

    /// Celebrations are Cancún time, written with their offset — days are grouped there
    /// too, so the list matches the resort whatever timezone the guest last left home in.
    private static let dayZone = TimeZone(identifier: "America/Cancun") ?? .current

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        header

                        if let group = focusGroup {
                            ForEach(group.events) { event in
                                row(for: event)
                            }
                        } else {
                            emptyState
                        }

                        guideRow
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                }
                .onChange(of: store.events.count) { _, _ in
                    scrollToCurrentIfNeeded(proxy)
                }
                .onAppear {
                    scrollToCurrentIfNeeded(proxy)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            await store.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // Back at the wrist: quietly check for changes.
            if phase == .active {
                Task { await store.refresh() }
            }
        }
        .sensoryFeedback(.selection, trigger: didChime)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 3) {
            Image("crest")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20)
                .foregroundStyle(WatchTheme.gold.opacity(0.7))
                .accessibilityHidden(true)

            Text("THE CELEBRATIONS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(WatchTheme.gold.opacity(0.75))

            if let group = focusGroup {
                Text(dayTitle(for: group))
                    .font(.watchPlayfair(16, weight: .medium))
                    .foregroundStyle(WatchTheme.cream)
            }
        }
        .padding(.bottom, 4)
    }

    private func row(for event: WatchEvent) -> some View {
        NavigationLink {
            WatchEventDetailScreen(event: event)
        } label: {
            WatchEventRow(event: event, state: state(for: event))
        }
        .buttonStyle(.plain)
        .id(event.id)
    }

    private var emptyState: some View {
        Text("The schedule will appear here soon.")
            .font(.watchCormorant(14))
            .foregroundStyle(WatchTheme.creamDim)
            .padding(.top, 20)
    }

    /// A quiet way in: the guide for dressing an Apple face in the wedding's gold.
    private var guideRow: some View {
        NavigationLink {
            WatchFaceGuideScreen()
        } label: {
            HStack(spacing: 6) {
                Image("crest")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11)
                    .foregroundStyle(WatchTheme.gold.opacity(0.55))
                    .accessibilityHidden(true)

                Text("MAKE YOUR WEDDING FACE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(WatchTheme.gold.opacity(0.7))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Days

    private struct DayGroup: Identifiable {
        let day: Date
        var events: [WatchEvent]

        var id: Date { day }
    }

    /// Celebrations grouped by their Cancún day, in schedule order. A celebration with
    /// no start time sits with the day before it, the way it reads on paper.
    private var dayGroups: [DayGroup] {
        var groups: [DayGroup] = []
        for event in store.events {
            guard let startsAt = event.startsAt else {
                if !groups.isEmpty {
                    groups[groups.count - 1].events.append(event)
                }
                continue
            }
            let day = calendar.startOfDay(for: startsAt)
            if let index = groups.lastIndex(where: { $0.day == day }) {
                groups[index].events.append(event)
            } else {
                groups.append(DayGroup(day: day, events: [event]))
            }
        }
        return groups
    }

    /// Today when it has celebrations, otherwise the next day that does — the last
    /// one once the weekend has passed.
    private var focusGroup: DayGroup? {
        let groups = dayGroups
        guard !groups.isEmpty else { return nil }
        let today = calendar.startOfDay(for: Date())
        if let group = groups.first(where: { $0.day == today }) {
            return group
        }
        return groups.first(where: { $0.day > today }) ?? groups.last
    }

    private func dayTitle(for group: DayGroup) -> String {
        if calendar.isDateInToday(group.day) { return "Today" }
        if calendar.isDateInTomorrow(group.day) { return "Tomorrow" }
        return group.day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    // MARK: - The current celebration

    /// Whatever is happening now, else what's next, else the last one — the same
    /// rule the phone's schedule follows.
    private var currentEvent: WatchEvent? {
        let now = Date()
        return store.events.first(where: { $0.isHappening(at: now) })
            ?? store.events.first(where: { ($0.startsAt ?? .distantFuture) > now })
            ?? store.events.last
    }

    private func state(for event: WatchEvent) -> WatchRowState {
        let now = Date()
        if event.isHappening(at: now) { return .current }
        if event.end < now { return .past }
        return .upcoming
    }

    private func scrollToCurrentIfNeeded(_ proxy: ScrollViewProxy) {
        guard !didScrollToCurrent, let current = currentEvent else { return }
        didScrollToCurrent = true
        withAnimation(.easeOut(duration: 0.5)) {
            proxy.scrollTo(current.id, anchor: .center)
        }
        // One soft tick once the current celebration has come into view.
        Task {
            try? await Task.sleep(for: .seconds(0.55))
            didChime = true
        }
    }
}

/// One celebration in the list: line-art mark, name in Playfair, time in Cormorant.
/// The one underway is outlined in gold with a soft glow and a gentle breathing pulse.
struct WatchEventRow: View {
    let event: WatchEvent
    let state: WatchRowState

    @State private var isBreathing = false

    var body: some View {
        HStack(spacing: 10) {
            WatchLineArtIcon(key: event.iconKey)
                .stroke(
                    state == .current ? WatchTheme.gold : WatchTheme.creamDim,
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.watchPlayfair(15, weight: .semibold))
                    .foregroundStyle(state == .past ? WatchTheme.creamDim : WatchTheme.cream)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let time = event.displayTime {
                    Text(time)
                        .font(.watchCormorant(13))
                        .foregroundStyle(state == .current ? WatchTheme.gold : WatchTheme.creamDim)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(state == .current ? WatchTheme.gold.opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    state == .current ? WatchTheme.gold.opacity(0.8) : WatchTheme.hairline,
                    lineWidth: state == .current ? 1.2 : 1
                )
        )
        .shadow(color: state == .current ? WatchTheme.gold.opacity(0.35) : .clear, radius: 9)
        .opacity(state == .past ? 0.45 : 1)
        .scaleEffect(state == .current && isBreathing ? 1.015 : 1)
        .onAppear {
            guard state == .current, !isBreathing else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(state == .current ? "Happening now" : "")
    }
}
