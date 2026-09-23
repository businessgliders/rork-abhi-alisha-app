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
    @State private var router = DeepLinkRouter.shared
    @State private var push = PushRegistrar.shared
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

            FloatingTabBar(selection: $selection)
        }
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
        .tint(BrandPalette.goldDeep)
        .environment(store)
        .environment(content)
        .environment(router)
        .environment(push)
        .environment(admin)
        .onOpenURL { url in
            // Where a tap on a widget, or on the Live Activity, lands.
            guard let tab = router.handle(url) else { return }
            withAnimation(.calm) { selection = tab }
        }
        .onChange(of: router.pendingTab) { _, _ in
            openPendingTab()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                push.applicationDidBecomeActive()
            }
        }
        .onAppear(perform: openPendingTab)
        .task {
            store.startClock()
            await content.refreshIfNeeded()
        }
    }

    /// A notification tap asked for a tab; any open couple's area steps aside for it.
    private func openPendingTab() {
        guard let tab = router.pendingTab else { return }
        router.pendingTab = nil
        admin.isPromptPresented = false
        admin.isAdminPresented = false
        withAnimation(.calm) { selection = tab }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView()
        case .schedule:
            ScheduleView()
        case .story:
            StoryView()
        case .gallery:
            GalleryView()
        case .resort:
            ResortView()
        }
    }
}

#Preview {
    ContentView()
}
