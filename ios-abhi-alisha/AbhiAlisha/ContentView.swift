import SwiftUI

/// Root shell: the five sections stay alive behind a floating Liquid Glass tab bar,
/// so content scrolls beneath the glass and each screen keeps its own state.
/// Home's crest is held here, lit over the photograph; every other screen carries its
/// own crest inside the page, so it moves with the header rather than over it.
///
/// Light and dark are left entirely to iOS: nothing here forces a colour scheme, so
/// the palette follows the phone's own setting the moment it changes.
struct WeddingShell: View {
    @State private var store = ScheduleStore()
    @State private var content = ContentStore()
    @State private var updates = NotificationsStore.shared
    @State private var router = DeepLinkRouter.shared
    @State private var push = PushRegistrar.shared
    @State private var chat = ChatStore.shared
    @State private var announcementDraft = AnnouncementDraft.shared
    @State private var admin = AdminSession()
    @State private var areaRequest = AdminSession.request
    @State private var selection: AppTab = .home

    @Environment(\.scenePhase) private var scenePhase

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
            // Pinned to the window, so a screen that runs taller on a short wide window
            // (the folding iPhone's inner screen) can never push the chrome or the tab
            // bar outside the safe area.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)

            if !isReadingThread {
                FloatingTabBar(selection: $selection)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.calm, value: isReadingThread)
        .overlay(alignment: .top) {
            ScreenChrome(showsCrest: selection == .home, onHost: { admin.requestEntry() })
        }
        .sheet(isPresented: $push.isExplainerPresented) {
            NotificationExplainerSheet()
                .environment(push)
        }
        .fullScreenCover(isPresented: $admin.isAdminPresented) {
            CoupleAreaView()
                .environment(store)
                .environment(content)
                .environment(admin)
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
            // Join links are handled by the root gate.
            guard WeddingContext.joinCode(from: url) == nil,
                  WeddingContext.cohostCode(from: url) == nil else { return }
            // Where a tap on a widget, or on the Live Activity, lands.
            guard let tab = router.handle(url) else { return }
            withAnimation(.calm) { selection = tab }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if WeddingContext.shared.isSample {
                SampleWeddingBanner()
            }
        }
        .onChange(of: router.pending) { _, _ in
            openPendingLanding()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                push.applicationDidBecomeActive()
                ChatSession.shared.applicationDidBecomeActive()
                WeddingPhotoStore.shared.resumeUploads()
            }
        }
        .onAppear(perform: openPendingLanding)
        .onAppear { admin.consumeRequest() }
        .onChange(of: areaRequest.pending) { _, pending in
            guard pending != nil else { return }
            admin.consumeRequest()
        }
        .task {
            store.startClock()
            NotificationsStore.shared.startListening()
            LiveActivityRegistrar.shared.start()
            WeddingPhotoStore.shared.resumeUploads()
            Task { await push.offerIfNeeded(isSample: WeddingContext.shared.isSample) }
            await content.refreshIfNeeded()
            await StayMigration.runIfNeeded(content: content)
        }
    }

    /// A notification tap asked for a landing; it is only acted on once this root view
    /// is alive, so a tap that wakes the app waits for it to finish loading. Any open
    /// couple's area steps aside for it.
    private func openPendingLanding() {
        guard let landing = router.pending else { return }
        router.pending = nil
        admin.isAdminPresented = false

        switch landing {
        case .tab(let tab):
            router.isNotificationsPresented = false
            withAnimation(.calm) { selection = tab }
        case .announcementsComposer:
            router.isNotificationsPresented = false
            router.pendingAnnouncements = true
            withAnimation(.calm) { selection = .chat }
        case .notifications:
            // Already open? Then the tap simply keeps it where it is.
            router.isNotificationsPresented = true
        }
    }

    /// A conversation, or the admin's announcement composer, fills the screen to the
    /// bottom edge, so the bar steps aside.
    private var isReadingThread: Bool {
        selection == .chat && (chat.activeThreadID != nil || announcementDraft.isComposerOnScreen)
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView()
        case .schedule:
            ScheduleView(isActive: selection == .schedule)
        case .chat:
            ChatRootView(isActive: selection == .chat)
        case .story:
            StoryView()
        case .resort:
            ExperienceView(isActive: selection == .resort)
        }
    }
}

/// The app's root: the splash while the saved wedding loads, onboarding when there
/// is no wedding yet, otherwise the wedding itself. Switching weddings rebuilds the
/// wedding screens with a cross-fade into the new colours.
struct ContentView: View {
    private let context = WeddingContext.shared

    var body: some View {
        ZStack {
            switch context.stage {
            case .launching:
                MilniSplashView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingFlow()
                    .transition(.opacity)
            case .wedding:
                WeddingShell()
                    .id(context.shellKey)
                    .preferredColorScheme(context.colorScheme)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.7), value: context.stage)
        .animation(.easeInOut(duration: 0.7), value: context.shellKey)
        .fullScreenCover(item: Bindable(context).flowRequest) { request in
            OnboardingFlow(entry: request.entry) {
                context.closeFlow()
            }
        }
        .sheet(item: Bindable(context).pendingCohostInvite) { invite in
            CohostAcceptView(invite: invite)
        }
        .onOpenURL { url in
            if !context.handleCohostLink(url) { _ = context.handleJoinLink(url) }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            if !context.handleCohostLink(url) { _ = context.handleJoinLink(url) }
        }
        .task {
            ChatSession.shared.start()
            await context.bootstrap()
        }
    }
}

#Preview {
    ContentView()
}
