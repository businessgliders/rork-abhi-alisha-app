import Foundation
import Supabase

/// A wedding as the join flow previews it, or as `my_weddings()` lists it.
nonisolated struct WeddingSummary: Identifiable, Hashable, Sendable {
    let id: String
    var slug: String?
    var title: String
    var partnerOne: String
    var partnerTwo: String
    var startDate: String?
    var endDate: String?
    var timezone: String?
    var venueName: String?
    var city: String?
    var country: String?
    var preset: String
    var theme: WeddingTheme?
    var coverURLs: [String]
    var role: String?
    var status: String?
    var mainEventRef: String?
    var rsvpURL: String?
    var latitude: Double?
    var longitude: Double?

    var coupleNames: String {
        if partnerOne.isEmpty || partnerTwo.isEmpty { return title }
        return "\(partnerOne) & \(partnerTwo)"
    }

    var initials: String {
        let one = partnerOne.first.map(String.init) ?? ""
        let two = partnerTwo.first.map(String.init) ?? ""
        let joined = (one + two).uppercased()
        return joined.isEmpty ? String(title.prefix(1)).uppercased() : joined
    }

    var roleBadge: String? {
        switch role?.lowercased() {
        case "host": return "Host"
        case "cohost", "co-host", "co_host": return "Co-host"
        default: return nil
        }
    }

    /// "CANCÚN · JAN 30 – FEB 3, 2027"
    var cityAndDates: String {
        var parts: [String] = []
        if let place = (city ?? venueName)?.trimmingCharacters(in: .whitespaces), !place.isEmpty {
            parts.append(place)
        }
        if let dates = dateRange { parts.append(dates) }
        return parts.joined(separator: " · ")
    }

    var dateRange: String? {
        let zone = TimeZone(identifier: timezone ?? "") ?? .current
        guard let startDate, let start = WeddingSnapshot.day(startDate, in: zone) else { return nil }
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = zone
        let end = endDate.flatMap { WeddingSnapshot.day($0, in: zone) }
        var yearStyle = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        yearStyle.timeZone = zone
        guard let end, end > start else { return start.formatted(yearStyle) }
        return "\(start.formatted(style)) – \(end.formatted(yearStyle))"
    }

    init(row: [String: Any]) {
        let wedding = (row["wedding"] as? [String: Any]) ?? (row["weddings"] as? [String: Any]) ?? row
        id = MilniJSON.string(wedding["id"]) ?? MilniJSON.string(row["wedding_id"]) ?? MilniJSON.string(row["id"]) ?? ""
        slug = MilniJSON.string(wedding["slug"])
        title = MilniJSON.string(wedding["title"]) ?? ""
        partnerOne = MilniJSON.string(wedding["partner_one"]) ?? ""
        partnerTwo = MilniJSON.string(wedding["partner_two"]) ?? ""
        startDate = MilniJSON.string(wedding["start_date"])
        endDate = MilniJSON.string(wedding["end_date"])
        timezone = MilniJSON.string(wedding["timezone"])
        venueName = MilniJSON.string(wedding["venue_name"])
        city = MilniJSON.string(wedding["city"])
        country = MilniJSON.string(wedding["country"])
        preset = MilniJSON.preset(wedding["theme"])
        // The join and list RPCs may send only a preset: keep the full theme only when
        // the row carried one, so a richer saved snapshot isn't replaced by a guess.
        theme = wedding["theme"] == nil || wedding["theme"] is NSNull ? nil : WeddingTheme.parse(wedding["theme"])
        coverURLs = (wedding["cover_urls"] as? [Any])?.compactMap { MilniJSON.string($0) } ?? []
        role = MilniJSON.string(row["role"]) ?? MilniJSON.string(wedding["role"])
        status = MilniJSON.string(row["status"]) ?? MilniJSON.string(wedding["status"])
        mainEventRef = MilniJSON.string(wedding["main_event_ref"])
        rsvpURL = MilniJSON.string(wedding["rsvp_url"])
        latitude = MilniJSON.double(wedding["lat"])
        longitude = MilniJSON.double(wedding["lng"])
        if title.isEmpty { title = coupleNames }
    }

    var snapshot: WeddingSnapshot {
        WeddingSnapshot(
            id: id,
            slug: slug,
            title: title,
            partnerOne: partnerOne,
            partnerTwo: partnerTwo,
            venueName: venueName,
            city: city,
            country: country,
            timezone: timezone ?? TimeZone.current.identifier,
            startDate: startDate,
            endDate: endDate,
            preset: preset,
            mainEventRef: mainEventRef,
            rsvpURL: rsvpURL,
            latitude: latitude,
            longitude: longitude,
            theme: theme
        )
    }
}

nonisolated enum MilniError: LocalizedError {
    case notFound
    case needsSignIn
    case failed

    var errorDescription: String? {
        switch self {
        case .notFound: return "We couldn't find that code."
        case .needsSignIn: return "Sign in with Apple to create a wedding."
        case .failed: return "Something went wrong. Please try again."
        }
    }
}

/// Small helpers to read loosely shaped JSON.
nonisolated enum MilniJSON {
    static func string(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    static func preset(_ theme: Any?) -> String {
        if let dict = theme as? [String: Any], let preset = string(dict["preset"]) { return preset.lowercased() }
        if let text = theme as? String,
           let data = text.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let preset = string(dict["preset"]) {
            return preset.lowercased()
        }
        return "ivory"
    }

    static func rows(_ data: Data) -> [[String: Any]] {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return [] }
        if let rows = object as? [[String: Any]] { return rows }
        if let row = object as? [String: Any] { return [row] }
        return []
    }

    static func encode(_ rows: [[String: Any]]) -> Data {
        (try? JSONSerialization.data(withJSONObject: rows)) ?? Data("[]".utf8)
    }
}

/// Every read and write the Milni platform needs from Supabase. Rows are read as loose
/// JSON so a column added on the server never breaks this build.
nonisolated struct MilniAPI: Sendable {
    static let shared = MilniAPI()

    private var client: SupabaseClient { ChatBackend.client }

    // MARK: - Weddings

    func preview(code: String) async throws -> WeddingSummary {
        let response = try await client.rpc("get_wedding_preview", params: ["p_code": code]).execute()
        guard let row = MilniJSON.rows(response.data).first else { throw MilniError.notFound }
        let summary = WeddingSummary(row: row)
        guard !summary.id.isEmpty else { throw MilniError.notFound }
        return summary
    }

    /// Adds the signed-in person to the wedding. Returns its id when the server says.
    @discardableResult
    func join(code: String) async throws -> String? {
        let response = try await client.rpc("join_wedding", params: ["p_code": code]).execute()
        if let text = String(data: response.data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n")),
           UUID(uuidString: text) != nil {
            return text.lowercased()
        }
        let row = MilniJSON.rows(response.data).first
        return MilniJSON.string(row?["wedding_id"]) ?? MilniJSON.string(row?["id"])
    }

    func myWeddings() async throws -> [WeddingSummary] {
        let response = try await client.rpc("my_weddings").execute()
        return MilniJSON.rows(response.data).map(WeddingSummary.init(row:)).filter { !$0.id.isEmpty }
    }

    func wedding(id: String) async throws -> WeddingSummary? {
        let response = try await client.from("weddings").select().eq("id", value: id).limit(1).execute()
        return MilniJSON.rows(response.data).first.map(WeddingSummary.init(row:))
    }

    func wedding(slug: String) async throws -> WeddingSummary? {
        let response = try await client.from("weddings").select().eq("slug", value: slug).limit(1).execute()
        return MilniJSON.rows(response.data).first.map(WeddingSummary.init(row:))
    }

    func coverURLs(weddingID: String) async throws -> [String] {
        let response = try await client.from("weddings").select("cover_urls").eq("id", value: weddingID).limit(1).execute()
        let row = MilniJSON.rows(response.data).first
        return (row?["cover_urls"] as? [Any])?.compactMap { MilniJSON.string($0) } ?? []
    }

    /// The signed-in person's role and status in one wedding.
    func membership(weddingID: String, userID: String) async throws -> (role: String?, status: String?)? {
        let response = try await client.from("wedding_members")
            .select("wedding_id,user_id,role,status,joined_at")
            .eq("wedding_id", value: weddingID)
            .eq("user_id", value: userID)
            .limit(1)
            .execute()
        guard let row = MilniJSON.rows(response.data).first else { return nil }
        return (MilniJSON.string(row["role"]), MilniJSON.string(row["status"]))
    }

    func code(weddingID: String) async throws -> String? {
        let response = try await client.from("wedding_codes")
            .select("wedding_id,join_code,updated_at")
            .eq("wedding_id", value: weddingID)
            .order("updated_at", ascending: false)
            .limit(1)
            .execute()
        return MilniJSON.string(MilniJSON.rows(response.data).first?["join_code"])?.uppercased()
    }

    private struct CreateParams: Encodable, Sendable {
        let p_title: String
        let p_partner_one: String
        let p_partner_two: String
        let p_start_date: String
        let p_end_date: String
        let p_timezone: String
        let p_theme: AnyJSON
    }

    func createWedding(
        partnerOne: String,
        partnerTwo: String,
        start: Date,
        end: Date,
        timezone: TimeZone,
        preset: String
    ) async throws -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let params = CreateParams(
            p_title: "\(partnerOne) & \(partnerTwo)",
            p_partner_one: partnerOne,
            p_partner_two: partnerTwo,
            p_start_date: formatter.string(from: start),
            p_end_date: formatter.string(from: end),
            p_timezone: timezone.identifier,
            p_theme: HostAPI.anyJSON(WeddingTheme.preset(preset).json)
        )
        let response = try await client.rpc("create_wedding", params: params).execute()
        if let id = ChatBackend.decodeID(response.data) { return id.lower }
        let row = MilniJSON.rows(response.data).first
        if let id = MilniJSON.string(row?["create_wedding"]) ?? MilniJSON.string(row?["wedding_id"]) { return id }
        throw MilniError.failed
    }

    // MARK: - Schedule

    /// The wedding's events, shaped like the original schedule feed so every screen,
    /// cache, widget and Live Activity keeps reading them unchanged.
    func events(weddingID: String, timezone: TimeZone) async throws -> (events: [ScheduleEvent], raw: Data) {
        let response = try await client.from("events")
            .select()
            .eq("wedding_id", value: weddingID)
            .order("starts_at")
            .execute()
        let mapped = MilniJSON.rows(response.data).map { Self.scheduleRow($0, zone: timezone) }
        let raw = MilniJSON.encode(mapped)
        let events = try ScheduleDecoder.decode(raw)
        return (events, raw)
    }

    static func scheduleRow(_ row: [String: Any], zone: TimeZone) -> [String: Any] {
        let details = (row["details"] as? [String: Any]) ?? [:]
        var out: [String: Any] = [:]
        out["id"] = MilniJSON.string(row["ref"]) ?? MilniJSON.string(row["id"]) ?? UUID().uuidString
        out["title"] = MilniJSON.string(row["title"]) ?? ""
        if let starts = MilniJSON.string(row["starts_at"]) {
            out["starts_at"] = starts
            if let date = ScheduleEvent.date(from: starts) {
                out["date"] = MilniJSON.string(details["date"]) ?? format(date, "EEEE, MMMM d, yyyy", zone)
                out["time"] = MilniJSON.string(details["time"]) ?? format(date, "h:mm a", zone)
            }
        }
        if let ends = MilniJSON.string(row["ends_at"]) { out["ends_at"] = ends }
        if let kind = MilniJSON.string(row["kind"])?.lowercased() {
            if ["sikh", "hindu"].contains(kind) { out["ceremony_type"] = kind }
            let kindIcons = [
                "welcome": "flutes", "cocktails": "flutes", "party": "flutes",
                "haldi": "paisley", "mehndi": "paisley", "sangeet": "paisley",
                "reception": "sparkle", "farewell": "sun", "brunch": "sun",
                "sikh": "arch", "hindu": "mandap"
            ]
            if let icon = MilniJSON.string(details["icon_key"]) ?? kindIcons[kind] {
                out["icon_key"] = icon
            } else if kind == "ceremony" {
                // Anand Karaj reads as the arch, pheras as the mandap; any other ceremony the mandap.
                let inferred = EventIconKey.inferred(fromTitle: MilniJSON.string(row["title"]) ?? "")
                out["icon_key"] = inferred == .arch ? EventIconKey.arch.rawValue : EventIconKey.mandap.rawValue
            } else {
                // custom and anything new: the closest line motif from the title.
                out["icon_key"] = EventIconKey.inferred(fromTitle: MilniJSON.string(row["title"]) ?? "").rawValue
            }
        }
        if let ceremony = MilniJSON.string(details["ceremony_type"]) { out["ceremony_type"] = ceremony }
        if let sort = MilniJSON.double(row["sort"]) { out["sort_order"] = sort }
        if let venue = MilniJSON.string(row["venue_name"]) { out["location_name"] = venue }
        if let address = MilniJSON.string(row["address"]) { out["location_address"] = address }
        if let lat = MilniJSON.double(row["lat"]) { out["latitude"] = lat }
        if let lng = MilniJSON.double(row["lng"]) { out["longitude"] = lng }
        if let hide = details["hide_map"] as? Bool { out["hide_map"] = hide }
        if let x = MilniJSON.double(details["resort_map_x"]) { out["resort_map_x"] = x }
        if let y = MilniJSON.double(details["resort_map_y"]) { out["resort_map_y"] = y }
        if let label = MilniJSON.string(details["resort_map_label"]) { out["resort_map_label"] = label }
        if let description = MilniJSON.string(row["description"]) { out["description"] = description }
        if let dress = MilniJSON.string(row["dress_code"]) { out["dress_code"] = dress }
        if let photos = row["outfit_images"] as? [[String: Any]] { out["outfit_photos"] = photos }
        if let faqs = details["faqs"] as? [[String: Any]] { out["faqs"] = faqs }
        out["is_active"] = (row["hidden"] as? Bool) != true
        return out
    }

    private static func format(_ date: Date, _ pattern: String, _ zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    // MARK: - Content

    /// Every content section the wedding has, already shaped per screen.
    struct Content: Sendable {
        var gallery: Data
        var categories: Data
        var faqs: Data
        var family: Data
        var story: Data
        var items: Data
        var letter: Data?
        var stay: Data?
    }

    func content(weddingID: String) async throws -> Content {
        async let sectionsResponse = client.from("content_sections")
            .select()
            .eq("wedding_id", value: weddingID)
            .order("sort")
            .execute()
        async let coversTask = coverURLs(weddingID: weddingID)
        let rows = MilniJSON.rows(try await sectionsResponse.data)
        let covers = (try? await coversTask) ?? []
        return Self.shape(rows: rows, covers: covers)
    }

    static func shape(rows: [[String: Any]], covers: [String]) -> Content {
        var gallery: [[String: Any]] = []
        var categories: [String: [String: Any]] = [:]
        var faqs: [[String: Any]] = []
        var family: [[String: Any]] = []
        var story: [[String: Any]] = []
        var items: [[String: Any]] = []
        var letter: [[String: Any]] = []
        var stay: [String: Any]?

        for (index, url) in covers.enumerated() {
            gallery.append([
                "id": "cover-\(index)",
                "image_url": url,
                "is_hero": true,
                "hero_sort_order": Double(index),
                "media_type": "image",
                "category": "cover",
                "is_active": true
            ])
        }

        for row in rows {
            let id = MilniJSON.string(row["id"]) ?? UUID().uuidString
            let data = (row["data"] as? [String: Any]) ?? [:]
            let sort = MilniJSON.double(row["sort"]) ?? 0
            let title = MilniJSON.string(row["title"])
            let body = MilniJSON.string(row["body"])
            switch MilniJSON.string(row["kind"])?.lowercased() ?? "" {
            case "gallery":
                var photo: [String: Any] = ["id": id, "sort_order": sort, "is_active": true]
                photo["image_url"] = MilniJSON.string(data["image_url"])
                photo["youtube_url"] = MilniJSON.string(data["youtube_url"])
                photo["video_url"] = MilniJSON.string(data["video_url"])
                photo["caption"] = title
                photo["category"] = MilniJSON.string(data["category"])
                photo["media_type"] = MilniJSON.string(data["media_type"]) ?? "image"
                gallery.append(photo.compactMapValues { $0 })
                if let slug = MilniJSON.string(data["category"]), categories[slug] == nil {
                    categories[slug] = [
                        "id": "category-\(slug)",
                        "name": MilniJSON.string(data["category_name"]) ?? slug.capitalized,
                        "slug": slug,
                        "sort_order": MilniJSON.double(data["category_order"]) ?? 0,
                        "is_active": true
                    ]
                }
            case "faq":
                var faq: [String: Any] = ["id": id, "sort_order": sort, "is_active": true]
                faq["section"] = MilniJSON.string(data["section"]) ?? "general"
                faq["question"] = title
                faq["answer"] = body
                faqs.append(faq)
            case "family":
                var member: [String: Any] = ["id": id, "sort_order": sort, "is_active": true]
                member["name"] = title
                member["role"] = body
                member["photo"] = MilniJSON.string(data["photo"])
                member["initials"] = MilniJSON.string(data["initials"])
                family.append(member.compactMapValues { $0 })
            case "story":
                var chapter: [String: Any] = ["id": id, "sort_order": sort, "is_active": true]
                chapter["title"] = title
                chapter["description"] = body
                chapter["year"] = MilniJSON.string(data["year"])
                chapter["image_url"] = MilniJSON.string(data["image_url"])
                story.append(chapter.compactMapValues { $0 })
            case "custom":
                let key = MilniJSON.string(data["key"])
                if key == "letter" || key == "love_letter" {
                    var entry: [String: Any] = ["id": id, "is_active": true]
                    entry["date_line"] = MilniJSON.string(data["date_line"])
                    entry["salutation"] = MilniJSON.string(data["salutation"]) ?? title
                    entry["body"] = body
                    entry["closing"] = MilniJSON.string(data["closing"])
                    entry["signature"] = MilniJSON.string(data["signature"])
                    letter.append(entry.compactMapValues { $0 })
                } else {
                    var item: [String: Any] = ["id": id, "sort_order": sort, "is_active": true]
                    item["key"] = key
                    item["title"] = title
                    item["body"] = body
                    item["image_url"] = MilniJSON.string(data["image_url"])
                    items.append(item.compactMapValues { $0 })
                }
            case "stay":
                if stay == nil, StayInfo.isPlaceRow(data) {
                    stay = StayInfo.shapedRow(id: id, title: title, data: data)
                }
            default:
                continue
            }
        }

        return Content(
            gallery: MilniJSON.encode(gallery),
            categories: MilniJSON.encode(Array(categories.values)),
            faqs: MilniJSON.encode(faqs),
            family: MilniJSON.encode(family),
            story: MilniJSON.encode(story),
            items: MilniJSON.encode(items),
            letter: letter.isEmpty ? nil : MilniJSON.encode(letter),
            stay: stay.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        )
    }

    // MARK: - Announcements

    func announcements(weddingID: String) async throws -> Data {
        let response = try await client.from("announcements")
            .select()
            .eq("wedding_id", value: weddingID)
            .order("sent_at", ascending: false)
            .execute()
        let mapped: [[String: Any]] = MilniJSON.rows(response.data).map { row in
            var out: [String: Any] = [:]
            out["id"] = MilniJSON.string(row["id"]) ?? UUID().uuidString
            out["title"] = MilniJSON.string(row["title"])
            out["body"] = MilniJSON.string(row["body"])
            out["sent_at"] = MilniJSON.string(row["sent_at"]) ?? MilniJSON.string(row["created_at"])
            out["delivered_count"] = MilniJSON.double(row["delivered_count"])
            out["screen"] = MilniJSON.string(row["screen"])
            out["event_id"] = MilniJSON.string(row["event_ref"])
            return out.compactMapValues { $0 }
        }
        return MilniJSON.encode(mapped)
    }
}

/// Decodes loose rows with a model's own decoder, dropping the ones it can't read.
nonisolated enum MilniDecode {
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    static func list<T: Decodable>(_ type: T.Type, from data: Data) -> [T] {
        ((try? JSONDecoder().decode([Lenient<T>].self, from: data)) ?? []).compactMap(\.value)
    }
}
