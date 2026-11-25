import Foundation

/// switched on while the App Store screenshots are captured (`--scenario app-store`).
/// It forces the happening-now ribbon on Home to read "Happening now" and keeps the
/// first-open notification card out of the captures. Release builds always read false.
enum ScreenshotCapture {
#if DEBUG && targetEnvironment(simulator)
    static var isActive: Bool { ScreenshotFixture.isActive }
#else
    static let isActive = false
#endif
}
