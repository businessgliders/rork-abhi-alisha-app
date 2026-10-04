import WidgetKit
import SwiftUI

@main
struct AbhiAlishaWatchWidgetBundle: WidgetBundle {
    init() {
        // The complications draw in the couple's own typefaces, bundled here too.
        WatchTheme.registerFontsIfNeeded()
    }

    var body: some Widget {
        WeddingComplications()
    }
}
