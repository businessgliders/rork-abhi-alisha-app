#if DEBUG && targetEnvironment(simulator)

import Foundation
import SwiftUI

/// Screenshot mode for the App Store captures (`rork sim record --scenario app-store`).
///
/// Everything in this file compiles out of release builds: the scenario is read from
/// the launch arguments inside this guard and never persisted. It seeds fictional,
/// local-only sample data (no real guests, no real messages, no production calls) and
/// routes straight to each capture target, so the recorder never has to tap through
/// onboarding or sign-in.
enum ScreenshotFixture {
    /// Read only from the launch inputs (`-RORK_SCREENSHOT_SCENARIO app-store`).
    static let scenario = UserDefaults.standard.string(forKey: "RORK_SCREENSHOT_SCENARIO")
    /// `-RORK_SCREENSHOT_TARGET <target>`, one capture screen per launch.
    static let target = UserDefaults.standard.string(forKey: "RORK_SCREENSHOT_TARGET")

    static var isActive: Bool { scenario == "app-store" }
    /// Stores check this before any network call during a capture: a seed must never
    /// be undone by a refresh, and the capture must never touch the real backend.
    static var suspendNetwork: Bool { isActive }

    // MARK: - The two weddings in the store story

    /// The second wedding in the story: a fictional couple, shown the way the couple's
    /// flow would create one. Lake Como, blush theme.
    static let mayaArjun = WeddingSnapshot(
        id: "b7d2c4a6-3f18-4e5c-9a0d-6f21c8b4e7d3",
        slug: "maya-arjun",
        title: "Maya & Arjun",
        partnerOne: "Maya",
        partnerTwo: "Arjun",
        venueName: "Villa Serena sul Lago",
        city: "Lenno",
        country: "Italy",
        timezone: "Europe/Rome",
        startDate: "2027-09-12",
        endDate: "2027-09-15",
        preset: "blush",
        mainEventRef: "maya-varmala",
        rsvpURL: nil,
        latitude: 45.9830,
        longitude: 9.2370
    )

    /// The couple's draft for the create-flow capture, pre-filled so the mood step
    /// shows the live invitation card.
    static let moodDraft: CoupleDraft = {
        var draft = CoupleDraft()
        draft.partnerOne = "Maya"
        draft.partnerTwo = "Arjun"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        if let start = calendar.date(from: DateComponents(year: 2027, month: 9, day: 12)) {
            draft.start = start
        }
        if let end = calendar.date(from: DateComponents(year: 2027, month: 9, day: 15)) {
            draft.end = end
        }
        draft.preset = "blush"
        return draft
    }()

    // MARK: - Entry point (called from the app's init, before any view mounts)

    static func apply() {
        guard isActive else { return }
        let mayaTargets: Set<String> = ["create-mood", "gallery", "couples-area", "toast"]
        let isMaya = target.map { mayaTargets.contains($0) } ?? false
        let snapshot = isMaya ? mayaArjun : WeddingSnapshot.sample

        // Seeds first (caches read the wedding that was just saved), then people,
        // then the wedding itself, then the route.
        seedWedding(
            snapshot,
            events: isMaya ? ScreenshotEvents.maya : ScreenshotEvents.abhiAlisha,
            announcements: isMaya ? nil : ScreenshotAnnouncements.abhiAlisha,
            gallery: isMaya ? ScreenshotGallery.maya : nil,
            chat: isMaya ? nil : ScreenshotChat.abhiAlisha
        )
        ChatSession.shared.adoptFixtureUser()
        WeddingContext.shared.adoptFixtureWedding(
            snapshot,
            role: target == "couples-area" ? "host" : "guest",
            status: "approved"
        )
        route()
    }

    private static func seedWedding(
        _ snapshot: WeddingSnapshot,
        events: Data,
        announcements: Data?,
        gallery: Data?,
        chat: ChatListSnapshot?
    ) {
        ActiveWedding.save(snapshot)

        let defaults = UserDefaults.standard
        let id = snapshot.id.lowercased()
        defaults.set(id, forKey: "milni.currentWeddingId")
        defaults.set(true, forKey: "milni.hasSeenIntro")
        defaults.set(false, forKey: "couple.faceid.\(id)")

        ScheduleCache.shared.save(rawData: events)
        if let announcements {
            JSONDiskCache(filename: "wedding-updates.json").save(announcements)
        }
        if let gallery {
            JSONDiskCache(filename: "gallery-photos.json").save(gallery)
        }
        if let chat, let user = chatFixtureUserID {
            ChatCache.save(chat, named: ChatCache.listName(for: user))
        }
        if target == "toast" {
            // The toast composer opens with the last input on this phone, so the
            // capture shows it mid-thought.
            let input = """
            {"name":"Rohan","relationship":"friend","tone":"heartfelt","length":"minute",\
            "memories":"The way Arjun practiced saying ciao in Italian for a month before Maya's parents arrived in Lenno","languageMix":""}
            """.data(using: .utf8)!
            defaults.set(input, forKey: "toast-input.\(id)")
        }
    }

    /// The chat person the fixtures are written for; nil when the snapshot is malformed.
    private static var chatFixtureUserID: UUID? { ChatSession.fixtureUserID }

    private static func route() {
        let router = DeepLinkRouter.shared
        let context = WeddingContext.shared
        switch target {
        case "schedule":
            router.pending = .tab(.schedule)
        case "event-where":
            // The ceremony sheet, opened by the recorder, scrolled to "Where".
            router.pendingEventID = "69effcf9de6c7e34fc4616a4"
            router.pending = .tab(.schedule)
        case "announcements":
            router.pendingAnnouncements = true
            router.pending = .tab(.chat)
        case "chat":
            router.pending = .tab(.chat)
        case "gallery":
            router.pendingStoryGallery = true
            router.pending = .tab(.story)
        case "couples-area":
            // No router landing: the shell's own request path opens the couple's area.
            AdminSession.request.open(nil)
        case "create-mood":
            context.flowRequest = WeddingContext.FlowRequest(entry: .create)
        case "toast":
            router.pending = .tab(.resort)
        case "siri":
            break // the shell overlays the Siri composite itself
        default:
            break // home
        }
    }
}

// MARK: - Capture markers

/// The ready and target markers the capture tool waits for. Two clear 2×2 elements,
/// always on screen, holding the screen's content nowhere.
struct ScreenshotFixtureMarkers: View {
    var body: some View {
        Color.clear.frame(width: 8, height: 8)
            .accessibilityElement()
            .accessibilityIdentifier("rork.screenshot.ready.app-store")
        Color.clear.frame(width: 8, height: 8)
            .accessibilityElement()
            .accessibilityLabel("rork.screenshot.target.\(ScreenshotFixture.target ?? "")")
    }
}

extension View {
    /// Adds the capture markers over this view. Compiles to a no-op in release builds
    /// (see the stub at the bottom of this file).
    func screenshotFixtureMarkers() -> some View {
        overlay(alignment: .topLeading) { ScreenshotFixtureMarkers() }
    }
}

// MARK: - Sample events

/// Fictional celebrations for both weddings, written as raw server-shaped JSON so
/// `ScheduleCache` stores exactly what a real wedding would have saved.
private enum ScreenshotEvents {
    /// Abhi & Alisha, AVA Resort Cancún, 30 January – 3 February 2027 (EST, −05:00).
    /// The ceremony keeps the wedding's real `main_event_ref` so the countdown runs to it.
    static let abhiAlisha: Data = {
        let events: [[String: Any]] = [
            event(
                id: "aa-welcome", title: "Welcome Fiesta", date: "Saturday, January 30, 2027",
                time: "7:00 PM", startsAt: "2027-01-30T19:00:00-05:00",
                locationName: "Pool Deck", address: "AVA Resort Cancún, Puerto Morelos, Mexico",
                dressCode: "Resort chic — linens and light colours",
                description: "Cocktails by the pool as the weekend begins. dinner and dancing under the palms.",
                sortOrder: 1
            ),
            event(
                id: "aa-haldi", title: "Haldi", date: "Sunday, January 31, 2027",
                time: "10:00 AM", startsAt: "2027-01-31T10:00:00-05:00",
                locationName: "Garden Lawn", address: "AVA Resort Cancún, Puerto Morelos, Mexico",
                dressCode: "Casual whites — turmeric stays behind",
                isOutdoor: true,
                description: "Turmeric, marigolds and blessings from the elders.",
                sortOrder: 2
            ),
            event(
                id: "aa-mehndi", title: "Mehndi", date: "Sunday, January 31, 2027",
                time: "4:00 PM", startsAt: "2027-01-31T16:00:00-05:00",
                locationName: "Palm Terrace", address: "AVA Resort Cancún, Puerto Morelos, Mexico",
                dressCode: "Bright and breezy",
                description: "Henna for every hand, with music and mocktails.",
                sortOrder: 3
            ),
            event(
                id: "aa-sangeet", title: "Sangeet Night", date: "Monday, February 1, 2027",
                time: "7:30 PM", startsAt: "2027-02-01T19:30:00-05:00",
                locationName: "Grand Ballroom", address: "AVA Resort Cancún, Puerto Morelos, Mexico",
                dressCode: "Sparkling Indian formal",
                description: "Both families take the stage — come ready to dance.",
                sortOrder: 4
            ),
            event(
                id: "69effcf9de6c7e34fc4616a4", title: "Wedding Ceremony", date: "Tuesday, February 2, 2027",
                time: "9:30 AM", startsAt: "2027-02-02T09:30:00-05:00",
                locationName: "Oceanfront Lawn", address: "AVA Resort Cancún, Puerto Morelos, Mexico",
                dressCode: "Indian formal in soft pastels",
                isOutdoor: true,
                latitude: 21.0419, longitude: -86.7841,
                description: "The pheras on the lawn facing the water.",
                faqs: [(
                    question: "Will the ceremony be outdoors?",
                    answer: "Yes — the lawn faces the ocean. Shawls will be provided for the sea breeze."
                )],
                sortOrder: 5
            ),
            event(
                id: "aa-reception", title: "Reception", date: "Tuesday, February 2, 2027",
                time: "7:00 PM", startsAt: "2027-02-02T19:00:00-05:00",
                locationName: "Grand Ballroom", address: "AVA Resort Cancún, Puerto Morelos, Mexico",
                dressCode: "Black tie optional",
                description: "Dinner, toasts and a very full dance floor.",
                sortOrder: 6
            ),
            event(
                id: "aa-brunch", title: "Farewell Brunch", date: "Wednesday, February 3, 2027",
                time: "10:00 AM", startsAt: "2027-02-03T10:00:00-05:00",
                locationName: "Beach Club", address: "AVA Resort Cancún, Puerto Morelos, Mexico",
                dressCode: "Come as you are",
                description: "One last slow morning by the sea before we say goodbye.",
                sortOrder: 7
            ),
        ]
        return jsonData(events)
    }()

    /// Maya & Arjun, Villa Serena sul Lago, Lenno, 12–15 September 2027 (CEST, +02:00).
    static let maya: Data = {
        let events: [[String: Any]] = [
            event(
                id: "maya-welcome", title: "Lakeside Welcome Dinner", date: "Sunday, September 12, 2027",
                time: "7:00 PM", startsAt: "2027-09-12T19:00:00+02:00",
                locationName: "Limone Terrace", address: "Villa Serena sul Lago, Via Regina 14, Lenno, Italy",
                dressCode: "Smart casual",
                description: "Long tables, candlelight and the lake at dusk.",
                sortOrder: 1
            ),
            event(
                id: "maya-mehndi", title: "Mehndi by the Lake", date: "Monday, September 13, 2027",
                time: "3:00 PM", startsAt: "2027-09-13T15:00:00+02:00",
                locationName: "Rose Garden", address: "Villa Serena sul Lago, Via Regina 14, Lenno, Italy",
                dressCode: "Garden party pastels",
                isOutdoor: true,
                description: "Henna, iced tea and the shade of the lemon trees.",
                sortOrder: 2
            ),
            event(
                id: "maya-varmala", title: "Baraat & Varmala", date: "Tuesday, September 14, 2027",
                time: "10:00 AM", startsAt: "2027-09-14T10:00:00+02:00",
                locationName: "Lakeside Lawn", address: "Villa Serena sul Lago, Via Regina 14, Lenno, Italy",
                dressCode: "Ivory and gold",
                isOutdoor: true,
                latitude: 45.9830, longitude: 9.2370,
                description: "The baraat arrives by the jetty; the varmala follows on the lawn.",
                faqs: [(
                    question: "Will the ceremony be outdoors?",
                    answer: "Yes — on the lawn by the water. The villa keeps parasols and water on hand."
                )],
                sortOrder: 3
            ),
            event(
                id: "maya-reception", title: "Reception under the Stars", date: "Tuesday, September 14, 2027",
                time: "7:30 PM", startsAt: "2027-09-14T19:30:00+02:00",
                locationName: "The Orangery", address: "Villa Serena sul Lago, Via Regina 14, Lenno, Italy",
                dressCode: "Evening elegance",
                description: "Dinner, toasts and dancing with the lake behind us.",
                sortOrder: 4
            ),
            event(
                id: "maya-brunch", title: "Farewell Brunch", date: "Wednesday, September 15, 2027",
                time: "10:30 AM", startsAt: "2027-09-15T10:30:00+02:00",
                locationName: "Limone Terrace", address: "Villa Serena sul Lago, Via Regina 14, Lenno, Italy",
                dressCode: "Come as you are",
                description: "A slow last morning — coffee, cornetti and goodbyes.",
                sortOrder: 5
            ),
        ]
        return jsonData(events)
    }()

    private static func event(
        id: String,
        title: String,
        date: String,
        time: String,
        startsAt: String,
        locationName: String,
        address: String,
        dressCode: String,
        isOutdoor: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil,
        description: String,
        faqs: [(question: String, answer: String)] = [],
        sortOrder: Double
    ) -> [String: Any] {
        var row: [String: Any] = [
            "id": id,
            "title": title,
            "date": date,
            "time": time,
            "starts_at": startsAt,
            "location_name": locationName,
            "location_address": address,
            "dress_code": dressCode,
            "is_outdoor": isOutdoor,
            "is_active": true,
            "sort_order": sortOrder,
            "description": description,
        ]
        if let latitude, let longitude {
            row["latitude"] = latitude
            row["longitude"] = longitude
        }
        if !faqs.isEmpty {
            row["faqs"] = faqs.map { ["question": $0.question, "answer": $0.answer] }
        }
        return row
    }

    private static func jsonData(_ rows: [[String: Any]]) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: rows) else {
            return Data("[]".utf8)
        }
        return data
    }
}

// MARK: - Sample announcements (Abhi & Alisha)

private enum ScreenshotAnnouncements {
    /// Written by hand because `NotificationRecord` is decode-only; the dates are in
    /// the past, so the newest card lights the unread dot like a real feed would.
    static let abhiAlisha: Data = """
    [
      {"id": "ann-gift",
       "title": "Your welcome gift awaits",
       "body": "Stop by the concierge desk any time on Friday to pick up your welcome basket — sunscreen, hangover kit and a note from us.",
       "sent_at": "2026-11-18T15:00:00Z", "delivered_count": 86,
       "screen": "schedule", "event_id": "aa-welcome"},
      {"id": "ann-mehndi",
       "title": "Mehndi has a new spot",
       "body": "Join us on the Palm Terrace instead of the garden lawn — same time, more shade, better views.",
       "sent_at": "2026-11-12T18:30:00Z", "delivered_count": 84,
       "screen": "event", "event_id": "aa-mehndi"},
      {"id": "ann-schedule",
       "title": "The schedule is live",
       "body": "Every celebration, dress code and map is now in the app. Have a look before you pack.",
       "sent_at": "2026-10-30T09:00:00Z", "delivered_count": 90,
       "screen": "schedule"}
    ]
    """.data(using: .utf8)!
}

// MARK: - Sample gallery (Maya & Arjun)

private enum ScreenshotGallery {
    /// Fictional photos of the couple's lakeside weekend, hosted by Rork so the grid
    /// fills without touching anyone's real account.
    static let maya: Data = {
        let urls = ScreenshotGalleryURLs.all
        let photos: [[String: Any]] = urls.enumerated().map { index, url in
            [
                "id": "maya-photo-\(index + 1)",
                "image_url": url,
                "caption": galleryCaptions[index],
                "media_type": "image",
                "is_active": true,
                "sort_order": Double(index + 1),
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: photos) else {
            return Data("[]".utf8)
        }
        return data
    }()

    private static let galleryCaptions = [
        "Golden hour on the jetty",
        "The long table at dusk",
        "Their first dance",
        "The baraat arrives",
        "Mandap at sunrise",
        "Sparklers over the lake",
    ]
}

/// Filled with the hosted URLs printed by `rork ai assets info` after generation.
private enum ScreenshotGalleryURLs {
    static let all: [String] = [
        "https://z6akv7onms9gcj3bblx69.rork.app/~assets/img/c00c0598-a649-43a3-b82b-3cad989b6313.png",
        "https://z6akv7onms9gcj3bblx69.rork.app/~assets/img/adf3f15a-cc8a-440a-b7fc-8dc66d5849db.png",
        "https://z6akv7onms9gcj3bblx69.rork.app/~assets/img/cc3b365d-19a8-4d08-9f2e-6220d7e0e663.png",
        "https://z6akv7onms9gcj3bblx69.rork.app/~assets/img/1b60001e-29e7-4377-89fb-e2d7f4c38155.png",
        "https://z6akv7onms9gcj3bblx69.rork.app/~assets/img/6b31b96c-732b-4cee-833f-8ded891c9af7.png",
        "https://z6akv7onms9gcj3bblx69.rork.app/~assets/img/11461686-9572-40cb-9e45-b0317f6d59a8.png",
    ]
}

// MARK: - Sample chat (Abhi & Alisha)

private enum ScreenshotChat {
    /// This phone's person and everyone they'd see. Fictional names only.
    static let abhiAlisha: ChatListSnapshot = {
        let me = ChatSession.fixtureUserID
        let priya = UUID(uuidString: "AA0A0A0A-0000-4000-8000-00000000A0B1")!
        let meera = UUID(uuidString: "AA0A0A0A-0000-4000-8000-00000000A0B2")!
        let vikram = UUID(uuidString: "AA0A0A0A-0000-4000-8000-00000000A0B3")!
        let open = UUID(uuidString: "AA0A0A0A-0000-4000-8000-00000000A0C1")!
        let family = UUID(uuidString: "AA0A0A0A-0000-4000-8000-00000000A0C2")!
        let direct = UUID(uuidString: "AA0A0A0A-0000-4000-8000-00000000A0C3")!

        func profile(_ id: UUID, _ name: String, role: String? = nil) -> ChatProfile {
            ChatProfile(
                id: id, displayName: name, status: "approved", role: role,
                avatarURL: nil, createdAt: Date(timeIntervalSinceNow: -8_640_000),
                isAnonymous: false
            )
        }

        func message(_ conversation: UUID, _ sender: UUID, _ body: String, minutesAgo: Double) -> ChatMessage {
            ChatMessage(
                id: UUID(),
                conversationID: conversation,
                senderID: sender,
                body: body,
                clientID: nil,
                createdAt: Date(timeIntervalSinceNow: -minutesAgo * 60),
                deletedAt: nil,
                editedAt: nil
            )
        }

        return ChatListSnapshot(
            conversations: [
                ChatConversation(
                    id: open, title: "Questions & Chat", kind: "open",
                    createdBy: priya, createdAt: Date(timeIntervalSinceNow: -8_640_000 * 4),
                    lastMessageAt: Date(timeIntervalSinceNow: -42 * 60),
                    weddingID: UUID(uuidString: ActiveWedding.sampleID)
                ),
                ChatConversation(
                    id: family, title: "The Family Room", kind: "family",
                    createdBy: vikram, createdAt: Date(timeIntervalSinceNow: -8_640_000 * 9),
                    lastMessageAt: Date(timeIntervalSinceNow: -3 * 3600),
                    weddingID: UUID(uuidString: ActiveWedding.sampleID)
                ),
                ChatConversation(
                    id: direct, title: "Priya Sharma", kind: "direct",
                    createdBy: priya, createdAt: Date(timeIntervalSinceNow: -8_640_000 * 2),
                    lastMessageAt: Date(timeIntervalSinceNow: -26 * 3600),
                    weddingID: UUID(uuidString: ActiveWedding.sampleID)
                ),
            ],
            members: [
                ChatMember(conversationID: open, userID: me, lastReadAt: Date(timeIntervalSinceNow: -50 * 60), joinedAt: nil, muted: nil),
                ChatMember(conversationID: open, userID: priya, lastReadAt: nil, joinedAt: nil, muted: nil),
                ChatMember(conversationID: open, userID: meera, lastReadAt: nil, joinedAt: nil, muted: nil),
                ChatMember(conversationID: open, userID: vikram, lastReadAt: nil, joinedAt: nil, muted: nil),
                ChatMember(conversationID: family, userID: me, lastReadAt: Date(timeIntervalSinceNow: -4 * 3600), joinedAt: nil, muted: nil),
                ChatMember(conversationID: family, userID: vikram, lastReadAt: nil, joinedAt: nil, muted: nil),
                ChatMember(conversationID: family, userID: meera, lastReadAt: nil, joinedAt: nil, muted: nil),
                ChatMember(conversationID: direct, userID: me, lastReadAt: Date(timeIntervalSinceNow: -27 * 3600), joinedAt: nil, muted: nil),
                ChatMember(conversationID: direct, userID: priya, lastReadAt: nil, joinedAt: nil, muted: nil),
            ],
            profiles: [
                profile(me, "Rohan", role: "guest"),
                profile(priya, "Priya Sharma"),
                profile(meera, "Meera Sharma"),
                profile(vikram, "Vikram Sharma", role: "admin"),
            ],
            previews: [
                message(open, meera, "Has anyone found a good cab company from the airport? The link in the resort page didn't work for me.", minutesAgo: 42),
                message(family, vikram, "Final headcount for the ballroom goes to the resort tonight — if you haven't RSVP'd, now is the moment.", minutesAgo: 180),
                message(direct, priya, "Rohan! Are you still deciding between the haldi and the spa slot on Sunday morning?", minutesAgo: 26 * 60),
            ],
            blocked: []
        )
    }()
}

// MARK: - Siri / Spotlight composite (a capture-only screen)

/// A stand-in for the Siri and Spotlight moment: a search for the wedding raises the
/// same snippet the app hands to App Intents, over the results it can answer.
/// Exists only in DEBUG simulator builds.
struct ScreenshotFixtureSiriScreen: View {
    private var ceremony: ScheduleEvent? {
        (try? ScheduleDecoder.decode(ScreenshotEvents.abhiAlisha))?.first { $0.id == "69effcf9de6c7e34fc4616a4" }
    }

    var body: some View {
        ZStack {
            // The system search backdrop: the app dimmed under the search glass.
            Color(white: 0.06).opacity(0.94).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("Where is the ceremony?")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Siri")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

                HStack {
                    EventSnippetView(event: ceremony)
                        .padding(14)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    Spacer()
                }
                .padding(.horizontal, 8)

                VStack(spacing: 0) {
                    resultRow("calendar", "Open the schedule")
                    Divider().overlay(.white.opacity(0.08))
                    resultRow("figure.2.and.list", "Questions & Chat")
                    Divider().overlay(.white.opacity(0.08))
                    resultRow("mappin.and.ellipse", "Directions to the lawn")
                }
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

                Spacer()
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }

    private func resultRow(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.tint)
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#else

// The marker modifier compiles to a no-op outside capture builds; nothing else in
// this file exists in release.
#if !(DEBUG && targetEnvironment(simulator))
extension View {
    func screenshotFixtureMarkers() -> some View { self }
}
#endif

#endif
