import Foundation

/// The wedding this phone is showing right now, as the app, the widgets and the Live
/// Activity all see it. The app writes it to the App Group whenever the wedding changes;
/// the widgets only ever read it. Nothing here touches the network.
nonisolated struct WeddingSnapshot: Codable, Equatable, Sendable {
    var id: String
    var slug: String?
    var title: String
    var partnerOne: String
    var partnerTwo: String
    var venueName: String?
    var city: String?
    var country: String?
    var timezone: String
    var startDate: String?
    var endDate: String?
    var preset: String
    /// `weddings.main_event_ref`: the event the countdown runs to.
    var mainEventRef: String? = nil
    var rsvpURL: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// The full `weddings.theme`. Older saved snapshots have none and fall back to the preset.
    var theme: WeddingTheme? = nil

    /// The theme to paint with: the saved one, else the preset's built-in look.
    var resolvedTheme: WeddingTheme {
        if let theme { return theme }
        return isAbhiAlisha ? .abhiAlishaFallback : WeddingTheme.preset(preset)
    }

    /// The wedding every earlier build of this app was made for. Its caches keep their
    /// original file names, so an existing guest never loses what is already on disk.
    static let sample = WeddingSnapshot(
        id: ActiveWedding.sampleID,
        slug: "abhi-alisha",
        title: "Abhi & Alisha",
        partnerOne: "Abhi",
        partnerTwo: "Alisha",
        venueName: "AVA Resort Cancún",
        city: "Cancún",
        country: "Mexico",
        timezone: "America/Cancun",
        startDate: "2027-01-30",
        endDate: "2027-02-03",
        preset: "ivory",
        mainEventRef: "69effcf9de6c7e34fc4616a4",
        rsvpURL: nil,
        latitude: 21.0419,
        longitude: -86.7841
    )

    var isSampleWedding: Bool { id.lowercased() == ActiveWedding.sampleID }

    /// Abhi & Alisha's own wedding: AVA Resort Cancún's photos, maps, wing guide, PDF and
    /// amenities, the crest and the RSVP lookup belong to it alone, never to other couples.
    var isAbhiAlisha: Bool { slug?.lowercased() == "abhi-alisha" || isSampleWedding }

    /// "Abhi & Alisha".
    var coupleNames: String {
        let one = partnerOne.trimmingCharacters(in: .whitespacesAndNewlines)
        let two = partnerTwo.trimmingCharacters(in: .whitespacesAndNewlines)
        if one.isEmpty || two.isEmpty { return title }
        return "\(one) & \(two)"
    }

    /// "Abhi and Alisha", for VoiceOver.
    var coupleNamesSpoken: String {
        coupleNames.replacingOccurrences(of: "&", with: "and")
    }

    /// "AB" style initials for the monogram.
    var initials: String {
        let one = partnerOne.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? ""
        let two = partnerTwo.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? ""
        let joined = (one + two).uppercased()
        return joined.isEmpty ? String(title.prefix(1)).uppercased() : joined
    }

    var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .current }

    /// This snapshot, with any blank names or title filled from the last good copy of the
    /// same wedding, so a partial or failed load can never blank the couple's names.
    func keepingNames(from previous: WeddingSnapshot) -> WeddingSnapshot {
        guard previous.id.lowercased() == id.lowercased() else { return self }
        var merged = self
        if merged.partnerOne.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.partnerOne = previous.partnerOne
        }
        if merged.partnerTwo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.partnerTwo = previous.partnerTwo
        }
        if merged.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.title = previous.title
        }
        return merged
    }

    /// The venue line: "AVA Resort Cancún", else the city, else nothing.
    var placeLine: String? {
        if let venueName = venueName?.trimmingCharacters(in: .whitespacesAndNewlines), !venueName.isEmpty {
            return venueName
        }
        if let city = city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty { return city }
        return nil
    }

    /// "AVA Resort Cancún · Mexico", "Toronto · Canada", or just one of them.
    var placeWithCountry: String? {
        let parts = [placeLine, country?.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Noon on the last day, in the wedding's own time zone: when Home becomes a thank-you.
    var thankYouStart: Date {
        guard let endDate, let day = Self.day(endDate, in: timeZone) else { return .distantFuture }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? .distantFuture
    }

    var start: Date? { startDate.flatMap { Self.day($0, in: timeZone) } }
    var end: Date? { endDate.flatMap { Self.day($0, in: timeZone) } }

    static func day(_ text: String, in zone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(text.prefix(10)))
    }
}

/// Reads and writes the current wedding in the shared container.
nonisolated enum ActiveWedding {
    static let sampleID = "84faefbc-2e43-4c6c-ac61-fb38d4563679"
    private static let fileName = "current-wedding.json"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: WeddingSnapshot?

    /// The wedding on screen. Falls back to Abhi & Alisha, which is what every phone
    /// that installed an earlier build was already showing.
    static var snapshot: WeddingSnapshot {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let loaded = loadFromDisk() ?? .sample
        cached = loaded
        return loaded
    }

    static var id: String { snapshot.id }

    /// "Abhi & Alisha" for the current wedding.
    static var couple: String { snapshot.coupleNames }

    /// The venue, else the city, else a gentle fallback.
    static var place: String { snapshot.placeLine ?? "the celebration" }

    /// Forgets the in-memory copy so the next read comes from disk (widgets call this
    /// before each timeline, since the app may have switched weddings meanwhile).
    static func reload() {
        lock.lock()
        cached = nil
        lock.unlock()
    }

    /// Posted after `save`, so views that derive from the snapshot (the countdown) redraw.
    static let didSave = Notification.Name("ActiveWedding.didSave")

    static func save(_ snapshot: WeddingSnapshot) {
        lock.lock()
        cached = snapshot
        lock.unlock()
        NotificationCenter.default.post(name: didSave, object: nil)
        guard let url = WeddingGroup.fileURL(fileName),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func loadFromDisk() -> WeddingSnapshot? {
        guard let url = WeddingGroup.fileURL(fileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WeddingSnapshot.self, from: data)
    }

    /// A cache file name for the current wedding. Abhi & Alisha keep their original names,
    /// so caches written by earlier builds keep working.
    static func scopedName(_ base: String, weddingID: String? = nil) -> String {
        let id = (weddingID ?? self.id).lowercased()
        if id == sampleID { return base }
        return "w-\(id)-\(base)"
    }
}
