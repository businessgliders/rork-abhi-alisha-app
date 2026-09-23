import SwiftUI

/// The couple's private area: Send, Checklist and Timeline beneath their own glass bar.
/// All three stay alive, so switching between them never loses a half-written note.
struct AdminRootView: View {
    @Environment(AdminSession.self) private var session

    @State private var selection: AdminTab = .send
    @State private var draft = NotificationDraft()

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
        case .send:
            AdminSendView(draft: $draft)
        case .checklist:
            AdminChecklistView()
        case .timeline:
            AdminTimelineView(onNotify: prepareChangeNotice)
        }
    }

    /// After a timeline edit: a note is written for them, ready to review and send.
    private func prepareChangeNotice(for eventName: String) {
        let name = eventName.nonEmpty ?? "the schedule"
        draft = NotificationDraft(
            title: "Update: \(name)",
            body: "We've updated the details for \(name). Open the app to see the latest."
        )
        withAnimation(.calm) { selection = .send }
    }
}
