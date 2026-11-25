import CoreSpotlight
import SwiftUI
import UniformTypeIdentifiers
import AppIntents

/// Puts the open wedding's celebrations, answered questions and latest announcements
/// into Spotlight, under one domain per wedding so leaving a wedding takes them all out.
/// Identifiers read `milni:<wedding>:<kind>:<id>`; a tap opens that item, switching
/// wedding first when needed.
@MainActor
enum SpotlightIndexer {
    enum Kind: String {
        case event, faq, announcement
    }

    struct Target: Equatable {
        let weddingID: String
        let kind: Kind
        let itemID: String
    }

    private static var lastFingerprint: [String: Int] = [:]
    private static var pending: Task<Void, Never>?

    static func identifier(wedding: String, kind: Kind, id: String) -> String {
        "milni:\(wedding.lowercased()):\(kind.rawValue):\(id)"
    }

    static func target(from identifier: String) -> Target? {
        let parts = identifier.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "milni", let kind = Kind(rawValue: parts[2]), !parts[3].isEmpty else { return nil }
        return Target(weddingID: parts[1], kind: kind, itemID: parts[3])
    }

    /// Re-indexes the open wedding. Cheap to call often: identical content is skipped and
    /// rapid changes are coalesced.
    static func reindex(events: [ScheduleEvent], faqs: [Faq], announcements: [NotificationRecord]) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let wedding = ActiveWedding.snapshot
        guard !wedding.id.isEmpty, !WeddingContext.shared.isSample else { return }
        let weddingID = wedding.id.lowercased()

        let latest = Array(
            announcements
                .filter { ($0.title?.isEmpty == false) || ($0.body?.isEmpty == false) }
                .sorted { ($0.sentAt ?? .distantPast) > ($1.sentAt ?? .distantPast) }
                .prefix(10)
        )
        let answered = faqs.filter { $0.isActive != false && ($0.question?.isEmpty == false) }

        var hasher = Hasher()
        hasher.combine(wedding.coupleNames)
        for event in events {
            hasher.combine(event.id); hasher.combine(event.title); hasher.combine(event.startsAt)
            hasher.combine(event.locationName); hasher.combine(event.dressCode)
        }
        for faq in answered { hasher.combine(faq.id); hasher.combine(faq.question); hasher.combine(faq.answer) }
        for note in latest { hasher.combine(note.id); hasher.combine(note.title); hasher.combine(note.body) }
        let fingerprint = hasher.finalize()
        guard lastFingerprint[weddingID] != fingerprint else { return }
        lastFingerprint[weddingID] = fingerprint

        let thumbnail = monogram(for: wedding)
        let couple = wedding.coupleNames
        let timeZone = wedding.timeZone
        var items: [CSSearchableItem] = []

        for event in events {
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = event.title
            attributes.contentDescription = [
                event.startsAt.map { formatted($0, in: timeZone) },
                event.locationName,
                event.dressCode.map { String(localized: "Dress code: \($0)") }
            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            attributes.startDate = event.startsAt
            attributes.endDate = event.endsAt
            attributes.namedLocation = event.locationName
            if let lat = event.latitude, let lng = event.longitude {
                attributes.latitude = NSNumber(value: lat)
                attributes.longitude = NSNumber(value: lng)
            }
            attributes.keywords = [couple, String(localized: "wedding"), event.dressCode].compactMap { $0 }
            attributes.thumbnailData = thumbnail
            if #available(iOS 18, *) {
                attributes.associateAppEntity(EventEntity(event: event), priority: 1)
            }
            items.append(CSSearchableItem(
                uniqueIdentifier: identifier(wedding: weddingID, kind: .event, id: event.id),
                domainIdentifier: weddingID,
                attributeSet: attributes
            ))
        }

        for faq in answered {
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = faq.question
            attributes.contentDescription = faq.answer
            attributes.keywords = [couple, String(localized: "question"), faq.section].compactMap { $0 }
            attributes.thumbnailData = thumbnail
            items.append(CSSearchableItem(
                uniqueIdentifier: identifier(wedding: weddingID, kind: .faq, id: faq.id),
                domainIdentifier: weddingID,
                attributeSet: attributes
            ))
        }

        for note in latest {
            let attributes = CSSearchableItemAttributeSet(contentType: .message)
            attributes.title = note.title?.isEmpty == false ? note.title : String(localized: "Announcement from \(couple)")
            attributes.contentDescription = note.body
            attributes.contentCreationDate = note.sentAt
            attributes.keywords = [couple, String(localized: "announcement")]
            attributes.thumbnailData = thumbnail
            items.append(CSSearchableItem(
                uniqueIdentifier: identifier(wedding: weddingID, kind: .announcement, id: note.id),
                domainIdentifier: weddingID,
                attributeSet: attributes
            ))
        }

        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let index = CSSearchableIndex.default()
            // Replace the whole domain so deleted events and questions disappear too.
            try? await index.deleteSearchableItems(withDomainIdentifiers: [weddingID])
            guard !items.isEmpty else { return }
            try? await index.indexSearchableItems(items)
        }
    }

    /// Takes one wedding out of Spotlight (left or deleted).
    static func removeWedding(_ weddingID: String) {
        let id = weddingID.lowercased()
        lastFingerprint[id] = nil
        Task { try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [id]) }
    }

    /// Clears everything (sign-out or account deletion).
    static func removeAll() {
        lastFingerprint.removeAll()
        pending?.cancel()
        Task { try? await CSSearchableIndex.default().deleteAllSearchableItems() }
    }

    /// Opens what a Spotlight tap points at, switching wedding first when it belongs to
    /// another one of the guest's weddings.
    static func open(_ target: Target) async {
        let context = WeddingContext.shared
        if ActiveWedding.snapshot.id.lowercased() != target.weddingID {
            do {
                try await context.open(weddingID: target.weddingID)
            } catch {
                // That wedding is gone: drop its stale results quietly.
                removeWedding(target.weddingID)
                return
            }
        }
        let router = DeepLinkRouter.shared
        switch target.kind {
        case .event:
            router.pendingEventID = target.itemID
            router.open(.tab(.schedule))
        case .faq:
            router.pendingResortSection = .questions
            router.open(.tab(.resort))
        case .announcement:
            router.pendingAnnouncements = true
            router.open(.tab(.chat))
        }
    }

    // MARK: - Helpers

    private static func formatted(_ date: Date, in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    private static var monogramCache: [String: Data] = [:]

    /// The couple's initials in a gold ring, as Spotlight's thumbnail.
    private static func monogram(for wedding: WeddingSnapshot) -> Data? {
        if let cached = monogramCache[wedding.id] { return cached }
        let initials = wedding.initials
        let label = initials.count == 2 ? "\(initials.prefix(1))&\(initials.suffix(1))" : initials
        let view = ZStack {
            Circle().fill(Color(hex: 0x1C2033))
            Circle().strokeBorder(Color(hex: 0xC9A96E), lineWidth: 3).padding(6)
            Text(label)
                .font(.system(size: 44, weight: .regular, design: .serif).italic())
                .foregroundStyle(Color(hex: 0xE3C98F))
        }
        .frame(width: 160, height: 160)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let data = renderer.uiImage?.pngData()
        if let data { monogramCache[wedding.id] = data }
        return data
    }
}
