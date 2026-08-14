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
    @State private var router = DeepLinkRouter()
    @State private var selection: AppTab = .home

    var body: some View {
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
        .tint(BrandPalette.goldDeep)
        .environment(store)
        .environment(content)
        .environment(router)
        .onOpenURL { url in
            // Where a tap on a widget, or on the Live Activity, lands.
            guard let tab = router.handle(url) else { return }
            withAnimation(.calm) { selection = tab }
        }
        .task {
            store.startClock()
            await content.refreshIfNeeded()
        }
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
