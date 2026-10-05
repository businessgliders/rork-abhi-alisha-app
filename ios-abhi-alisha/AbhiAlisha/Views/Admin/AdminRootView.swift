import SwiftUI

/// The couple's private area: Checklist and Timeline beneath their own glass bar.
/// Announcements are written in the Announcements chat instead. Both rooms stay alive,
/// so switching between them never loses anything half-done.
struct AdminRootView: View {
    @Environment(AdminSession.self) private var session

    @State private var selection: AdminTab = .checklist

    var body: some View {
        ZStack(alignment: .bottom) {
            BrandPalette.background.ignoresSafeArea()

            ZStack {
                ForEach(AdminTab.allCases) { tab in
                    screen(for: tab)
                        .opacity(selection == tab ? 1 : 0)
                        .allowsHitTesting(selection == tab)
                        .accessibilityHidden(selection != tab)
                }
            }
            .animation(.softFade, value: selection)

            AdminTabBar(selection: $selection) {
                session.isAdminPresented = false
            }
        }
        .tint(BrandPalette.goldDeep)
    }

    @ViewBuilder
    private func screen(for tab: AdminTab) -> some View {
        switch tab {
        case .checklist:
            AdminChecklistView()
        case .timeline:
            AdminTimelineView(onNotify: prepareChangeNotice)
        }
    }

    /// After a timeline edit: a note is written for them, already pointed at that
    /// celebration, waiting in the Announcements composer to review and send.
    private func prepareChangeNotice(for entry: TimelineEntry) {
        let name = entry.title?.nonEmpty ?? "the schedule"
        let destination: AnnouncementDestination = entry.title?.nonEmpty.map {
            .event(id: entry.id, title: $0)
        } ?? .schedule
        AnnouncementDraft.shared.prefill(
            title: "Update: \(name)",
            body: "We've updated the details for \(name). Open the app to see the latest.",
            destination: destination
        )
        DeepLinkRouter.shared.open(.announcementsComposer)
    }
}
