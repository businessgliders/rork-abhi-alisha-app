//
//  AbhiAlishaApp.swift
//  AbhiAlisha
//
//  Created by Rork on August 13, 2026.
//

import SwiftUI

@main
struct AbhiAlishaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        BrandFont.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
