import SwiftUI
import WidgetKit

@main
struct AbhiAlishaWidgetBundle: WidgetBundle {
    init() {
        // The widgets draw in the couple's own typefaces, which live in this extension's
        // bundle as well as the app's.
        BrandFont.registerIfNeeded()
    }

    var body: some Widget {
        CountdownWidget()
        NextEventWidget()
        EventFollowLiveActivity()
    }
}
