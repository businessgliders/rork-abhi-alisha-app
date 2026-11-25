//
//  MilniWeddingApp.swift
//  MilniWedding
//
//  Created by Rork on August 13, 2026.
//

import SwiftUI

@main
struct MilniWeddingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        BrandFont.registerIfNeeded()
#if DEBUG && targetEnvironment(simulator)
        ScreenshotFixture.apply()
#endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
