import Foundation

/// TEMPORARY — switched on only while capturing the App Store screenshots.
/// It forces the happening-now ribbon on Home to read "Happening now" and keeps the
/// first-open notification card out of the captures. Revert to `false` when the
/// captures are done.
enum ScreenshotCapture {
    static let isActive = false
}
