import AppIntents
import SwiftUI

// MARK: - What's next

struct NextEventIntent: AppIntent {
    static let title: LocalizedStringResource = "What's next at the wedding"
    static let description = IntentDescription("Tells you the next celebration, when it starts, where, and what to wear.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let event = IntentSchedule.focus() else {
            return .result(
                dialog: IntentDialog(stringLiteral: String(localized: "There's nothing else on the schedule. Open the app to see the whole week.")),
                view: EventSnippetView(event: nil)
            )
        }
        let now = Date()
        let isNow = (event.startsAt ?? .distantFuture) <= now
        var sentence = isNow
            ? String(localized: "\(event.title) is happening now")
            : String(localized: "Next is \(event.title)")
        if !isNow, let when = IntentSchedule.whenLine(event.startsAt) {
            sentence += String(localized: ", \(when)")
        }
        if let venue = event.locationName, !venue.isEmpty {
            sentence += String(localized: " at \(venue)")
        }
        sentence += "."
        if let code = event.dressCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            sentence += " " + String(localized: "Dress code: \(code).")
        }
        return .result(dialog: IntentDialog(stringLiteral: sentence), view: EventSnippetView(event: event))
    }
}

// MARK: - Dress code

struct DressCodeTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "What's the dress code today"
    static let description = IntentDescription("Tells you what to wear for today's celebration.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let event = IntentSchedule.today() else {
            return .result(
                dialog: IntentDialog(stringLiteral: String(localized: "There's nothing on the schedule to dress for.")),
                view: EventSnippetView(event: nil)
            )
        }
        let code = event.dressCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sentence = code.isEmpty
            ? String(localized: "\(event.title) has no dress code set yet. Wear what feels festive.")
            : String(localized: "For \(event.title), the dress code is \(code).")
        return .result(dialog: IntentDialog(stringLiteral: sentence), view: EventSnippetView(event: event))
    }
}

// MARK: - Open the schedule

struct OpenScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "Open the schedule"
    static let description = IntentDescription("Opens the wedding schedule.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.open(.tab(.schedule))
        return .result()
    }
}

// MARK: - My outfit

struct ShowOutfitIntent: AppIntent {
    static let title: LocalizedStringResource = "Show my outfit"
    static let description = IntentDescription("Opens your saved look for a celebration.")
    static let openAppWhenRun = true

    @Parameter(title: "Event")
    var event: EventEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Show my outfit for \(\.$event)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.pendingOutfitEventID = event.id
        return .result()
    }
}

// MARK: - Open one event (Spotlight's entity and the snippet's tap)

struct OpenEventIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open wedding event"
    static let openAppWhenRun = true

    @Parameter(title: "Event")
    var target: EventEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.pendingEventID = target.id
        DeepLinkRouter.shared.open(.tab(.schedule))
        return .result()
    }
}

// MARK: - Shortcuts

struct MilniShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextEventIntent(),
            phrases: [
                "What's next at the wedding in \(.applicationName)",
                "What's next in \(.applicationName)",
                "Ask \(.applicationName) what's next"
            ],
            shortTitle: "What's next",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: DressCodeTodayIntent(),
            phrases: [
                "What's the dress code tonight in \(.applicationName)",
                "What should I wear today in \(.applicationName)",
                "Ask \(.applicationName) about the dress code"
            ],
            shortTitle: "Dress code",
            systemImageName: "tshirt"
        )
        AppShortcut(
            intent: OpenScheduleIntent(),
            phrases: [
                "Open the schedule in \(.applicationName)",
                "Show the \(.applicationName) schedule"
            ],
            shortTitle: "Schedule",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: ShowOutfitIntent(),
            phrases: [
                "Show my outfit for \(\.$event) in \(.applicationName)",
                "Show my \(.applicationName) outfit for \(\.$event)",
                "Show my outfit in \(.applicationName)"
            ],
            shortTitle: "My outfit",
            systemImageName: "hanger"
        )
    }
}

// MARK: - Snippet

/// Siri's card: the celebration in the wedding's own colours.
struct EventSnippetView: View {
    let event: ScheduleEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ActiveWedding.snapshot.coupleNames)
                .font(BrandLabel.font(size: 10, weight: .semibold))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(BrandPalette.goldDeep)

            if let event {
                Text(event.title)
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.ink)

                Rectangle()
                    .fill(BrandPalette.gold.opacity(0.6))
                    .frame(width: 34, height: 1)

                if let when = IntentSchedule.whenLine(event.startsAt) {
                    row("clock", when)
                }
                if let venue = event.locationName, !venue.isEmpty {
                    row("mappin", venue)
                }
                if let code = event.dressCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
                    row("tshirt", code)
                }
            } else {
                Text("Nothing else on the schedule")
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(BrandPalette.background)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(BrandPalette.goldDeep)
                .frame(width: 16)
            Text(text)
                .brandFont(.bodySmall)
                .foregroundStyle(BrandPalette.ink)
        }
    }
}
