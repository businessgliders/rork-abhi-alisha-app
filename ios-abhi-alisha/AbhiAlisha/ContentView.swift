import SwiftUI

/// Root shell: the five sections stay alive behind a floating Liquid Glass tab bar,
/// so content scrolls beneath the glass and each screen keeps its own state.
/// Home's crest is held here, lit over the photograph; every other screen carries its
/// own crest inside the page, so it moves with the header rather than over it.
///
/// Light and dark are left entirely to iOS: nothing here forces a colour scheme, so
/// the palette follows the phone's own setting the moment it changes.
struct ContentView: View {
    @State private var store = ScheduleStore()
    @State private var content = ContentStore()
    @State private var updates = NotificationsStore()
    @State private var router = DeepLinkRouter.shared
    @State private var push = PushRegistrar.shared
    @State private var chat = ChatStore.shared
    @State private var admin: AdminSession
    @State private var checklist: ChecklistStore
    @State private var selection: AppTab = .home

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let session = AdminSession()
        _admin = State(initialValue: session)
        _checklist = State(initialValue: ChecklistStore(session: session))
    }

    var body: some View {
        @Bindable var push = push
        @Bindable var admin = admin

        ZStack(alignment: .bottom) {
            BrandPalette.background.ignoresSafeArea()

            ZStack {
                ForEach(AppTab.allCases) { tab in
                    screen(for: tab)
                        .opacity(selection == tab ? 1 : 0)
                        .allowsHitTesting(selection == tab)
                        .accessibilityHidden(selection != tab)
                }
            }
            .animation(.softFade, value: selection)

            if !isReadingThread {
                FloatingTabBar(selection: $selection)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.calm, value: isReadingThread)
        .overlay(alignment: .top) {
            ScreenChrome(showsCrest: selection == .home)
        }
        .overlay {
            if admin.isPromptPresented {
                CouplePasscodePrompt()
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.calm, value: admin.isPromptPresented)
        .sheet(isPresented: $push.isExplainerPresented) {
            NotificationExplainerSheet()
                .environment(push)
        }
        .fullScreenCover(isPresented: $admin.isAdminPresented) {
            AdminRootView()
                .environment(store)
                .environment(admin)
                .environment(checklist)
        }
        .fullScreenCover(isPresented: $router.isNotificationsPresented) {
            NotificationsView()
                .environment(updates)
        }
        .tint(BrandPalette.goldDeep)
        .environment(store)
        .environment(content)
        .environment(updates)
        .environment(router)
        .environment(push)
        .environment(admin)
        .onOpenURL { url in
            // Where a tap on a widget, or on the Live Activity, lands.
            guard let tab = router.handle(url) else { return }
            withAnimation(.calm) { selection = tab }
        }
        .onChange(of: router.pending) { _, _ in
            openPendingLanding()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                push.applicationDidBecomeActive()
                ChatSession.shared.applicationDidBecomeActive()
            }
        }
        .onAppear(perform: openPendingLanding)
        .task {
            ChatSession.shared.start()
            store.startClock()
            await content.refreshIfNeeded()
        }
    }

    /// A notification tap asked for a landing; it is only acted on once this root view
    /// is alive, so a tap that wakes the app waits for it to finish loading. Any open
    /// couple's area steps aside for it.
    private func openPendingLanding() {
        guard let landing = router.pending else { return }
        router.pending = nil
        admin.isPromptPresented = false
        admin.isAdminPresented = false

        switch landing {
        case .tab(let tab):
            router.isNotificationsPresented = false
            withAnimation(.calm) { selection = tab }
        case .notifications:
            // Already open? Then the tap simply keeps it where it is.
            router.isNotificationsPresented = true
        }
    }

    /// A conversation fills the screen, composer and all, so the bar steps aside.
    private var isReadingThread: Bool {
        selection == .chat && chat.activeThreadID != nil
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView()
        case .schedule:
            ScheduleView()
        case .chat:
            ChatRootView(isActive: selection == .chat)
        case .story:
            StoryView()
        case .resort:
            ResortView()
        }
    }
}

#Preview {
    ContentView()
}
