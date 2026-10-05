import SwiftUI

/// "The Celebrations" — a single-screen view: fixed header, string-lights navigation,
/// one flexible event card, and the arrow stepper. Nothing scrolls except long copy
/// inside the card itself.
struct ScheduleView: View {
    /// True while the Schedule tab is the one on screen.
    var isActive = true

    @Environment(ScheduleStore.self) private var store
    @Environment(DeepLinkRouter.self) private var router

    @State private var selectedIndex = 0
    @State private var didSyncToCurrent = false
    @State private var lastCurrentIndex: Int?
    @State private var weatherByEvent: [String: DayWeather] = [:]
    @State private var dragOffset: CGFloat = 0
    @State private var isMovingForward = true
    @State private var detailEvent: ScheduleEvent?
    @State private var calendar = CalendarService.shared
    @State private var phase = WeddingPhase.shared
    @State private var calendarMessage: String?
    @State private var messageTask: Task<Void, Never>?
    @State private var isShowingCalendarTip = false
    @AppStorage("schedule.calendarTipSeen") private var hasSeenCalendarTip = false

    /// After the wedding the Schedule reads as a keepsake: muted, nothing to add.
    private var isPast: Bool { phase.isThankYou(at: store.now) }

    private var events: [ScheduleEvent] { store.events }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, ScreenChrome.contentReserve)

            if events.isEmpty {
                emptyState
                    .frame(maxHeight: .infinity)
            } else {
                StringLightsNavigation(events: events, selectedIndex: $selectedIndex)
                    .padding(.top, 16)
                    .saturation(isPast ? 0.25 : 1)
                    .opacity(isPast ? 0.7 : 1)

                if !isPast {
                    calendarControl
                        .padding(.top, 10)
                        .overlay(alignment: .bottom) {
                            if isShowingCalendarTip {
                                CalendarTip(onDismiss: dismissCalendarTip)
                                    .alignmentGuide(.bottom) { $0[.top] - 4 }
                                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                                    .zIndex(5)
                            }
                        }
                        .zIndex(5)
                }

                cardCarousel
                    .padding(.top, 10)
                    .frame(maxHeight: .infinity)
                    .saturation(isPast ? 0.35 : 1)
                    .opacity(isPast ? 0.82 : 1)

                stepper
                    .padding(.top, 14)

                if store.isShowingOfflineData {
                    Text("Showing your saved schedule")
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body.opacity(0.75))
                        .padding(.top, 8)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, FloatingTabBar.contentReserve)
        .readableWidth()
        .crestCorner()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandPalette.background.ignoresSafeArea())
        .sheet(item: $detailEvent) { event in
            EventDetailSheet(event: event, weather: weatherByEvent[event.id])
        }
        .task {
            syncToCurrentIfNeeded()
            await prefetchWeather()
            await store.refresh()
        }
        .onChange(of: store.now) { _, _ in
            advanceWithTheEvening()
        }
        .onChange(of: events.count) { _, _ in
            clampSelection()
            syncToCurrentIfNeeded()
            openPendingEventIfNeeded()
        }
        .onChange(of: router.pendingEventID) { _, _ in
            openPendingEventIfNeeded()
        }
        .onAppear(perform: openPendingEventIfNeeded)
        .task(id: isActive) {
            await showCalendarTipIfNeeded()
        }
        .task(id: selectedEvent?.id) {
            await loadWeatherForSelection()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: isPast ? "The celebrations · Past" : "The Celebrations")

            Text("Schedule")
                .brandFont(.screenTitle)
                .foregroundStyle(BrandPalette.ink)

            GoldRule(width: 58, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One tap puts every celebration in the guest's calendar; a second tap only updates.
    private var calendarControl: some View {
        let isAdded = calendar.hasAddedAll(events)

        return VStack(spacing: 6) {
            Button {
                addAllToCalendar()
            } label: {
                HStack(spacing: 8) {
                    if calendar.isAddingAll {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(isAdded ? Color(hex: 0xFFFBF1) : BrandPalette.goldDeep)
                    } else {
                        Image(systemName: isAdded ? "checkmark" : "calendar.badge.plus")
                            .font(.system(size: 12, weight: .regular))
                    }
                    Text(isAdded ? "Added to Calendar" : "Add all to Calendar")
                        .font(BrandLabel.font(size: 11, weight: .semibold))
                        .tracking(1.3)
                        .textCase(.uppercase)
                }
                .foregroundStyle(isAdded ? Color(hex: 0xFFFBF1) : BrandPalette.goldDeep)
                .padding(.horizontal, 18)
                .frame(minHeight: 40)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isAdded
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                : AnyShapeStyle(BrandPalette.card)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(BrandPalette.gold.opacity(isAdded ? 0.3 : 0.55), lineWidth: 1)
                )
            }
            .buttonStyle(PressableStyle())
            .disabled(calendar.isAddingAll)
            .accessibilityHint(isAdded ? "Tap to update your calendar" : "Adds every celebration with an alert an hour before")

            if let calendarMessage {
                Text(calendarMessage)
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            } else if isAdded {
                Text("Tap to update")
                    .font(BrandLabel.font(size: 9.5, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(BrandPalette.body.opacity(0.6))
                    .transition(.opacity)
            }
        }
        .animation(.calm, value: isAdded)
        .animation(.softFade, value: calendarMessage)
    }

    /// The first time the guest lands on Schedule, a small note points at the button.
    private func showCalendarTipIfNeeded() async {
        guard isActive, !hasSeenCalendarTip, !isPast, !events.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled, !hasSeenCalendarTip else { return }
        hasSeenCalendarTip = true
        withAnimation(.calm) { isShowingCalendarTip = true }
        try? await Task.sleep(for: .seconds(6))
        guard !Task.isCancelled else { return }
        withAnimation(.softFade) { isShowingCalendarTip = false }
    }

    private func dismissCalendarTip() {
        BrandHaptics.tick()
        withAnimation(.softFade) { isShowingCalendarTip = false }
    }

    private func addAllToCalendar() {
        if isShowingCalendarTip { withAnimation(.softFade) { isShowingCalendarTip = false } }
        BrandHaptics.soft()
        Task {
            let outcome = await calendar.addAll(events)
            if case .done = outcome { BrandHaptics.tick() }
            calendarMessage = outcome.message
            messageTask?.cancel()
            messageTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                calendarMessage = nil
            }
        }
    }

    private var cardCarousel: some View {
        ZStack {
            if let event = selectedEvent {
                StackedPaperBacking(
                    sheetsBehind: min(2, max(events.count - selectedIndex - 1, 0))
                )

                EventCard(
                    event: event,
                    weather: weatherByEvent[event.id],
                    fillsHeight: true,
                    onOpenDetails: { detailEvent = event }
                )
                .id(event.id)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: isMovingForward ? .trailing : .leading)
                            .combined(with: .opacity),
                        removal: .opacity
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragOffset = value.translation.width * 0.28
                }
                .onEnded { value in
                    let threshold: CGFloat = 56
                    withAnimation(.calm) { dragOffset = 0 }
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < -threshold {
                        step(by: 1)
                    } else if value.translation.width > threshold {
                        step(by: -1)
                    }
                }
        )
    }

    private var stepper: some View {
        HStack(spacing: 22) {
            stepButton(systemName: "chevron.left", enabled: selectedIndex > 0) {
                step(by: -1)
            }

            Text("\(selectedIndex + 1) / \(events.count)")
                .brandFont(.bodyText)
                .foregroundStyle(BrandPalette.body)
                .tracking(1.2)
                .contentTransition(.numericText())
                .frame(minWidth: 66)

            stepButton(systemName: "chevron.right", enabled: selectedIndex < events.count - 1) {
                step(by: 1)
            }
        }
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(BrandPalette.goldDeep)
                .frame(width: 46, height: 46)
                .background(
                    Circle().fill(Color.clear)
                )
                .overlay(
                    Circle().stroke(BrandPalette.gold.opacity(enabled ? 0.6 : 0.22), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
        .accessibilityLabel(systemName == "chevron.left" ? "Previous celebration" : "Next celebration")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            IconWatermark(key: .sparkle, size: 76, opacity: 0.4)
            Text("The schedule will appear here soon.")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Selection

    private var selectedEvent: ScheduleEvent? {
        guard events.indices.contains(selectedIndex) else { return events.first }
        return events[selectedIndex]
    }

    private func step(by delta: Int) {
        let target = selectedIndex + delta
        guard events.indices.contains(target) else { return }
        isMovingForward = delta > 0
        BrandHaptics.soft()
        withAnimation(.calm) {
            selectedIndex = target
        }
    }

    private func clampSelection() {
        guard !events.isEmpty else { return }
        selectedIndex = min(max(selectedIndex, 0), events.count - 1)
    }

    /// Arrives on the celebration a widget or the Live Activity was pointing at.
    private func openPendingEventIfNeeded() {
        guard let id = router.pendingEventID else { return }
        guard let target = events.firstIndex(where: { $0.id == id }) else { return }
        router.pendingEventID = nil
        didSyncToCurrent = true
        guard target != selectedIndex else { return }
        isMovingForward = target > selectedIndex
        withAnimation(.calm) {
            selectedIndex = target
        }
    }

    private func syncToCurrentIfNeeded() {
        guard !didSyncToCurrent, let current = store.currentIndex() else { return }
        didSyncToCurrent = true
        lastCurrentIndex = current
        selectedIndex = current
    }

    /// Re-evaluated on every clock tick so the lit bulb advances on its own.
    private func advanceWithTheEvening() {
        guard let current = store.currentIndex() else { return }
        guard current != lastCurrentIndex else { return }
        lastCurrentIndex = current
        guard current != selectedIndex else { return }
        isMovingForward = current > selectedIndex
        BrandHaptics.tick()
        withAnimation(.calmSlow) {
            selectedIndex = current
        }
    }

    /// Warms every day's weather up front so stepping between cards never shows a gap.
    private func prefetchWeather() async {
        for event in events {
            guard let date = event.startsAt, weatherByEvent[event.id] == nil else { continue }
            let weather = await WeatherService.shared.weather(for: date)
            withAnimation(.softFade) {
                weatherByEvent[event.id] = weather
            }
        }
    }

    private func loadWeatherForSelection() async {
        guard let event = selectedEvent, let date = event.startsAt else { return }
        guard weatherByEvent[event.id] == nil else { return }
        let weather = await WeatherService.shared.weather(for: date)
        withAnimation(.softFade) {
            weatherByEvent[event.id] = weather
        }
    }
}
