import SwiftUI

/// A slim gold line on Home while a celebration is underway, or within the hour before
/// one starts. It checks the clock every minute and steps away the rest of the time.
struct HappeningNowBanner: View {
    let events: [ScheduleEvent]

    @State private var detailEvent: ScheduleEvent?
    @State private var glow = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let state = Self.state(in: events, at: context.date) {
                banner(state)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.calm, value: events.count)
        .sheet(item: $detailEvent) { event in
            EventDetailSheet(event: event)
        }
    }

    // MARK: - State

    enum Moment: Equatable {
        case now
        case upNext(minutes: Int)
    }

    struct State: Equatable {
        let event: ScheduleEvent
        let moment: Moment
    }

    /// Happening now wins; otherwise the next start within 60 minutes. Nothing at all
    /// outside the wedding dates, since no celebration is then near.
    static func state(in events: [ScheduleEvent], at now: Date) -> State? {
        let timed = events.filter { $0.isActive != false && $0.startsAt != nil && !$0.isTimeToBeAnnounced }
        if let live = timed.first(where: { $0.isHappening(at: now) }) {
            return State(event: live, moment: .now)
        }
        let soon = timed
            .filter { ($0.startsAt ?? .distantPast) > now }
            .min { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
        guard let soon, let start = soon.startsAt else { return nil }
        let seconds = start.timeIntervalSince(now)
        guard seconds <= 3600 else { return nil }
        return State(event: soon, moment: .upNext(minutes: max(1, Int((seconds / 60).rounded(.up)))))
    }

    // MARK: - Drawing

    private func banner(_ state: State) -> some View {
        Button {
            BrandHaptics.soft()
            detailEvent = state.event
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0xFFF3CF).opacity(0.45))
                        .frame(width: 14, height: 14)
                        .scaleEffect(glow ? 1.25 : 0.7)
                        .opacity(glow ? 0 : 0.9)
                    Circle()
                        .fill(Color(hex: 0xFFFBF1))
                        .frame(width: 6, height: 6)
                }
                .frame(width: 14, height: 14)

                Text(line(state))
                    .font(BrandLabel.font(size: 12, weight: .semibold))
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color(hex: 0xFFFBF1))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color(hex: 0xE0C982).opacity(0.5), lineWidth: 0.75)
            )
        }
        .buttonStyle(PressableStyle())
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { glow = true }
        }
        .accessibilityLabel(line(state))
        .accessibilityHint("Opens the celebration")
    }

    private func line(_ state: State) -> String {
        switch state.moment {
        case .now:
            let parts = ["Happening now", state.event.title, state.event.locationName].compactMap { $0 }
            return parts.joined(separator: " · ")
        case .upNext(let minutes):
            return "Up next in \(Self.duration(minutes)) · \(state.event.title)"
        }
    }

    private static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "1 hr" : "\(minutes) min"
    }
}
