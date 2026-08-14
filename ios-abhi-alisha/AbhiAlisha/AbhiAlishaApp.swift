//
//  AbhiAlishaApp.swift
//  AbhiAlisha
//
//  Created by Rork on August 13, 2026.
//

import SwiftUI

@main
struct AbhiAlishaApp: App {
    init() {
        BrandFont.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
