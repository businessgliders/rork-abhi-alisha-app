import Foundation
import Observation

/// The announcement an admin is writing in the Announcements chat. Shared, so a
/// Timeline edit in the couple's area can hand over a prepared note, and so a
/// half-written one survives leaving the screen.
@Observable
final class AnnouncementDraft {
    static let shared = AnnouncementDraft()

    static let titleLimit = 120
    static let bodyLimit = 1000

    var title: String = "" {
        didSet {
            if title.count > Self.titleLimit { title = String(title.prefix(Self.titleLimit)) }
        }
    }

    var body: String = "" {
        didSet {
            if body.count > Self.bodyLimit { body = String(body.prefix(Self.bodyLimit)) }
        }
    }

    private(set) var destination: AnnouncementDestination = .announcements
    /// True until the admin picks a destination themselves.
    private(set) var isAuto = true
    /// The Announcements chat is on screen with the composer showing.
    var isComposerOnScreen = false

    var canSend: Bool { title.nonEmpty != nil && body.nonEmpty != nil }

    /// Re-reads the words and picks a destination, unless the admin already chose one.
    func redetect(events: [ScheduleEvent]) {
        guard isAuto else { return }
        let detected = AnnouncementRouteDetector.detect(title: title, message: body, events: events)
        if detected != destination { destination = detected }
    }

    func choose(_ destination: AnnouncementDestination) {
        isAuto = false
        self.destination = destination
    }

    /// Hands the choice back to auto-detection.
    func resumeAuto(events: [ScheduleEvent]) {
        isAuto = true
        redetect(events: events)
    }

    /// A note prepared elsewhere, already pointed where it should go.
    func prefill(title: String, body: String, destination: AnnouncementDestination) {
        self.title = title
        self.body = body
        isAuto = false
        self.destination = destination
    }

    func clear() {
        title = ""
        body = ""
        isAuto = true
        destination = .announcements
    }
}
