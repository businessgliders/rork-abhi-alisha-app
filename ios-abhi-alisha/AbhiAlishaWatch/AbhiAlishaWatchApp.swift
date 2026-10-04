import SwiftUI

@main
struct AbhiAlishaWatchApp: App {
    init() {
        WatchTheme.registerFontsIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            WatchScheduleScreen()
        }
    }
}
