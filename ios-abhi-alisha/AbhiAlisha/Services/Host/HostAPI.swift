import Foundation
import Supabase
import UIKit

/// One person in the wedding, as the host sees them.
nonisolated struct HostMember: Identifiable, Hashable, Sendable {
    let userID: String
    var displayName: String
    var role: String
    var status: String
    var joinedAt: Date?

    var id: String { userID }

    var isCohost: Bool { ["host", "cohost", "co-host", "co_host"].contains(role.lowercased()) }
    var isOwner: Bool { role.lowercased() == "host" }
}

/// An event row as the host edits it.
nonisolated struct HostEvent: Identifiable, Hashable, Sendable {
    var id: String
    var ref: String?
    var title: String
    var kind: String
    var startsAt: Date?
    var endsAt: Date?
    var venueName: String
    var address: String
    var lat: Double?
    var lng: Double?
    var isOutdoor: Bool
    var dressCode: String
    var description: String
    var outfitImages: [OutfitTile]
    var faqs: [FAQ]
    var details: [String: AnyJSON]
    var sort: Int

    nonisolated struct OutfitTile: Hashable, Sendable, Identifiable {
        var imageURL: String
        var lightboxURL: String?
        var caption: String?
        var id: String { imageURL }
    }

    nonisolated struct FAQ: Hashable, Sendable, Identifiable {
        var id = UUID()
        var question: String
        var answer: String
    }

    static func blank(sort: Int) -> HostEvent {
        HostEvent(
            id: "", ref: nil, title: "", kind: "custom", startsAt: nil, endsAt: nil,
            venueName: "", address: "", lat: nil, lng: nil, isOutdoor: false, dressCode: "",
            description: "", outfitImages: [], faqs: [], details: [:], sort: sort
        )
    }

    var isNew: Bool { id.isEmpty }
}

/// A `content_sections` row as the host edits it.
nonisolated struct HostSection: Identifiable, Hashable, Sendable {
    var id: String
    var kind: String
    var title: String
    var body: String
    var data: [String: AnyJSON]
    var sort: Int

    var isNew: Bool { id.isEmpty }

    func string(_ key: String) -> String {
        if case .string(let value)? = data[key] { return value }
        return ""
    }
}

/// Everything the Host area reads and writes. RLS on the server decides what a
/// signed-in host or co-host may change; this only shapes the calls.
final class HostAPI {
    static let shared = HostAPI()

    private var client: SupabaseClient { ChatBackend.client }

    // MARK: - Members

    func members(weddingID: String) async throws -> [HostMember] {
        let response = try await client.from("wedding_members")
            .select()
            .eq("wedding_id", value: weddingID)
            .execute()
        let rows = MilniJSON.rows(response.data)
        let ids = rows.compactMap { MilniJSON.string($0["user_id"]) }
        var names: [String: String] = [:]
        if !ids.isEmpty {
            if let profiles = try? await client.from("profiles")
                .select()
                .in("id", values: ids)
                .execute() {
                for row in MilniJSON.rows(profiles.data) {
                    guard let id = MilniJSON.string(row["id"]) else { continue }
                    names[id.lowercased()] = MilniJSON.string(row["display_name"])
                        ?? MilniJSON.string(row["full_name"])
                        ?? MilniJSON.string(row["name"])
                }
            }
        }
        return rows.compactMap { row in
            guard let userID = MilniJSON.string(row["user_id"]) else { return nil }
            let name = MilniJSON.string(row["display_name"])
                ?? names[userID.lowercased()]
                ?? "Guest"
            return HostMember(
                userID: userID,
                displayName: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Guest" : name,
                role: MilniJSON.string(row["role"]) ?? "guest",
                status: MilniJSON.string(row["status"]) ?? "pending",
                joinedAt: MilniJSON.string(row["joined_at"]).flatMap(Self.parseDate)
                    ?? MilniJSON.string(row["created_at"]).flatMap(Self.parseDate)
            )
        }
        .sorted { ($0.joinedAt ?? .distantPast) > ($1.joinedAt ?? .distantPast) }
    }

    func setStatus(weddingID: String, userID: String, status: String) async throws {
        try await client.rpc("set_member_status", params: [
            "p_wedding": weddingID, "p_user": userID, "p_status": status
        ]).execute()
    }

    func setRole(weddingID: String, userID: String, role: String) async throws {
        try await client.rpc("set_member_role", params: [
            "p_wedding": weddingID, "p_user": userID, "p_role": role
        ]).execute()
    }

    func remove(weddingID: String, userID: String) async throws {
        try await client.rpc("remove_member", params: [
            "p_wedding": weddingID, "p_user": userID
        ]).execute()
    }

    func createCohostInvite(weddingID: String) async throws -> String {
        let response = try await client.rpc("create_cohost_invite", params: ["p_wedding": weddingID]).execute()
        guard let code = Self.firstString(response.data, keys: ["code", "invite_code", "create_cohost_invite"]) else {
            throw HostError.message("We couldn't make an invite just now. Please try again.")
        }
        return code
    }

    func acceptCohostInvite(code: String) async throws -> String? {
        let response = try await client.rpc("accept_cohost_invite", params: ["p_code": code]).execute()
        return Self.firstString(response.data, keys: ["wedding_id", "id", "accept_cohost_invite"])
    }

    func regenerateJoinCode(weddingID: String) async throws -> String {
        let response = try await client.rpc("regenerate_join_code", params: ["p_wedding": weddingID]).execute()
        guard let code = Self.firstString(response.data, keys: ["join_code", "code", "regenerate_join_code"]) else {
            throw HostError.message("We couldn't make a new code just now. Please try again.")
        }
        return code
    }

    func joinCode(weddingID: String) async throws -> String? {
        // The live code lives in wedding_codes; older weddings may only have it on the row.
        if let codes = try? await client.from("wedding_codes")
            .select("join_code")
            .eq("wedding_id", value: weddingID)
            .limit(1)
            .execute(),
           let code = MilniJSON.rows(codes.data).first.flatMap({ MilniJSON.string($0["join_code"]) }),
           !code.isEmpty {
            return code
        }
        let response = try await client.from("weddings")
            .select("join_code")
            .eq("id", value: weddingID)
            .limit(1)
            .execute()
        return MilniJSON.rows(response.data).first.flatMap { MilniJSON.string($0["join_code"]) }
    }

    // MARK: - Events

    func events(weddingID: String) async throws -> [HostEvent] {
        let response = try await client.from("events")
            .select()
            .eq("wedding_id", value: weddingID)
            .order("sort")
            .execute()
        return MilniJSON.rows(response.data).compactMap(Self.event(from:))
    }

    func save(_ event: HostEvent, weddingID: String) async throws -> HostEvent {
        var row: [String: AnyJSON] = [
            "wedding_id": .string(weddingID),
            "title": .string(event.title),
            "kind": .string(event.kind),
            "starts_at": event.startsAt.map { .string(Self.iso($0)) } ?? .null,
            "ends_at": event.endsAt.map { .string(Self.iso($0)) } ?? .null,
            "venue_name": event.venueName.isEmpty ? .null : .string(event.venueName),
            "address": event.address.isEmpty ? .null : .string(event.address),
            "lat": event.lat.map { .double($0) } ?? .null,
            "lng": event.lng.map { .double($0) } ?? .null,
            "is_outdoor": .bool(event.isOutdoor),
            "dress_code": event.dressCode.isEmpty ? .null : .string(event.dressCode),
            "description": event.description.isEmpty ? .null : .string(event.description),
            "sort": .integer(event.sort)
        ]
        row["outfit_images"] = .array(event.outfitImages.map { tile in
            var object: [String: AnyJSON] = ["image_url": .string(tile.imageURL)]
            object["lightbox_url"] = .string(tile.lightboxURL ?? tile.imageURL)
            if let caption = tile.caption, !caption.isEmpty { object["caption"] = .string(caption) }
            return .object(object)
        })
        var details = event.details
        details["faqs"] = .array(event.faqs
            .filter { !$0.question.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { .object(["q": .string($0.question), "a": .string($0.answer)]) })
        row["details"] = .object(details)

        let response: PostgrestResponse<Void>
        if event.isNew {
            response = try await client.from("events").insert(row, returning: .representation).execute()
        } else {
            response = try await client.from("events").update(row, returning: .representation)
                .eq("id", value: event.id).execute()
        }
        guard let saved = MilniJSON.rows(response.data).first.flatMap(Self.event(from:)) else {
            throw HostError.message("That didn't save. Please check your connection and try again.")
        }
        return saved
    }

    func delete(eventID: String) async throws {
        try await client.from("events").delete().eq("id", value: eventID).execute()
    }

    func reorder(_ events: [HostEvent]) async throws {
        for (index, event) in events.enumerated() where event.sort != index {
            try await client.from("events").update(["sort": AnyJSON.integer(index)]).eq("id", value: event.id).execute()
        }
    }

    /// One row per chosen celebration, right after a wedding is created.
    func insertStarterEvents(weddingID: String, events: [(title: String, kind: String)]) async throws {
        guard !events.isEmpty else { return }
        let rows: [[String: AnyJSON]] = events.enumerated().map { index, event in
            [
                "wedding_id": .string(weddingID),
                "title": .string(event.title),
                "kind": .string(event.kind),
                "sort": .integer(index),
                "starts_at": .null
            ]
        }
        try await client.from("events").insert(rows).execute()
    }

    // MARK: - Content sections

    func sections(weddingID: String, kinds: [String]) async throws -> [HostSection] {
        let response = try await client.from("content_sections")
            .select()
            .eq("wedding_id", value: weddingID)
            .in("kind", values: kinds)
            .order("sort")
            .execute()
        let decoded = (try? JSONDecoder().decode([RawSection].self, from: response.data)) ?? []
        return decoded.map {
            HostSection(
                id: $0.id, kind: $0.kind, title: $0.title ?? "", body: $0.body ?? "",
                data: $0.data ?? [:], sort: $0.sort ?? 0
            )
        }
    }

    @discardableResult
    func save(_ section: HostSection, weddingID: String) async throws -> String {
        let row: [String: AnyJSON] = [
            "wedding_id": .string(weddingID),
            "kind": .string(section.kind),
            "title": .string(section.title),
            "body": section.body.isEmpty ? .null : .string(section.body),
            "data": .object(section.data),
            "sort": .integer(section.sort)
        ]
        if section.isNew {
            let response = try await client.from("content_sections").insert(row, returning: .representation).execute()
            return MilniJSON.rows(response.data).first.flatMap { MilniJSON.string($0["id"]) } ?? ""
        }
        try await client.from("content_sections").update(row).eq("id", value: section.id).execute()
        return section.id
    }

    func delete(sectionID: String) async throws {
        try await client.from("content_sections").delete().eq("id", value: sectionID).execute()
    }

    // MARK: - Wedding row

    func updateWedding(weddingID: String, fields: [String: AnyJSON]) async throws {
        try await client.from("weddings").update(fields).eq("id", value: weddingID).execute()
    }

    func weddingRow(weddingID: String) async throws -> [String: Any] {
        let response = try await client.from("weddings").select().eq("id", value: weddingID).limit(1).execute()
        return MilniJSON.rows(response.data).first ?? [:]
    }

    // MARK: - Counts

    func count(table: String, weddingID: String, filter: (String, String)? = nil) async -> Int {
        var query = client.from(table).select("id", head: true, count: .exact).eq("wedding_id", value: weddingID)
        if let filter { query = query.eq(filter.0, value: filter.1) }
        return (try? await query.execute().count) ?? 0
    }

    // MARK: - Storage

    static let assetsBucket = "wedding-assets"

    /// Uploads and returns the public address of the file.
    func upload(_ data: Data, bucket: String = HostAPI.assetsBucket, path: String, contentType: String) async throws -> String {
        try await client.storage.from(bucket)
            .upload(path, data: data, options: FileOptions(contentType: contentType, upsert: true))
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return "\(ChatBackend.url.absoluteString)/storage/v1/object/public/\(bucket)/\(encoded)"
    }

    /// Resizes and uploads a photo as JPEG.
    func uploadPhoto(_ image: UIImage, path: String, maxSide: CGFloat = 2048) async throws -> String {
        guard let data = Self.jpeg(image, maxSide: maxSide) else {
            throw HostError.message("That photo couldn't be read. Please pick another.")
        }
        return try await upload(data, path: path, contentType: "image/jpeg")
    }

    static func jpeg(_ image: UIImage, maxSide: CGFloat) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.84)
    }

    // MARK: - Helpers

    /// Any JSONSerialization-style value as Supabase's AnyJSON.
    nonisolated static func anyJSON(_ object: Any) -> AnyJSON {
        switch object {
        case let value as AnyJSON: return value
        case is NSNull: return .null
        case let value as String: return .string(value)
        case let value as Bool: return .bool(value)
        case let value as Int: return .integer(value)
        case let value as Double: return .double(value)
        case let value as [String: Any]: return .object(value.mapValues { anyJSON($0) })
        case let value as [Any]: return .array(value.map { anyJSON($0) })
        default: return .null
        }
    }

    private nonisolated struct RawSection: Decodable {
        let id: String
        let kind: String
        let title: String?
        let body: String?
        let data: [String: AnyJSON]?
        let sort: Int?
    }

    private static func event(from row: [String: Any]) -> HostEvent? {
        guard let id = MilniJSON.string(row["id"]) else { return nil }
        let details = (row["details"] as? [String: Any]) ?? [:]
        let detailsJSON = (try? JSONSerialization.data(withJSONObject: details))
            .flatMap { try? JSONDecoder().decode([String: AnyJSON].self, from: $0) } ?? [:]
        let faqs = ((details["faqs"] as? [[String: Any]]) ?? []).map {
            HostEvent.FAQ(
                question: MilniJSON.string($0["q"]) ?? MilniJSON.string($0["question"]) ?? "",
                answer: MilniJSON.string($0["a"]) ?? MilniJSON.string($0["answer"]) ?? ""
            )
        }
        let outfits = ((row["outfit_images"] as? [[String: Any]]) ?? []).compactMap { item -> HostEvent.OutfitTile? in
            guard let url = MilniJSON.string(item["image_url"]) else { return nil }
            return HostEvent.OutfitTile(
                imageURL: url,
                lightboxURL: MilniJSON.string(item["lightbox_url"]),
                caption: MilniJSON.string(item["caption"])
            )
        }
        return HostEvent(
            id: id,
            ref: MilniJSON.string(row["ref"]),
            title: MilniJSON.string(row["title"]) ?? "",
            kind: MilniJSON.string(row["kind"]) ?? "custom",
            startsAt: MilniJSON.string(row["starts_at"]).flatMap(parseDate),
            endsAt: MilniJSON.string(row["ends_at"]).flatMap(parseDate),
            venueName: MilniJSON.string(row["venue_name"]) ?? "",
            address: MilniJSON.string(row["address"]) ?? "",
            lat: MilniJSON.double(row["lat"]),
            lng: MilniJSON.double(row["lng"]),
            isOutdoor: (row["is_outdoor"] as? Bool) ?? false,
            dressCode: MilniJSON.string(row["dress_code"]) ?? "",
            description: MilniJSON.string(row["description"]) ?? "",
            outfitImages: outfits,
            faqs: faqs,
            details: detailsJSON,
            sort: Int(MilniJSON.double(row["sort"]) ?? 0)
        )
    }

    static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        // Postgres sometimes sends "2027-01-30 18:00:00+00".
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ssX", "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd HH:mm:ss.SSSSSSX"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func firstString(_ data: Data, keys: [String]) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        if let text = object as? String { return text }
        if let dict = object as? [String: Any] {
            for key in keys { if let value = MilniJSON.string(dict[key]) { return value } }
        }
        if let list = object as? [[String: Any]], let first = list.first {
            for key in keys { if let value = MilniJSON.string(first[key]) { return value } }
        }
        if let list = object as? [Any], let first = list.first as? String { return first }
        return nil
    }
}

enum HostError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

extension Error {
    /// Plain words for anything the host might see.
    var hostMessage: String {
        if let host = self as? HostError, let text = host.errorDescription { return text }
        let text = String(describing: self).lowercased()
        if text.contains("offline") || text.contains("network") || text.contains("internet") {
            return "You're offline. Try again when you have a connection."
        }
        if text.contains("42501") || text.contains("permission") || text.contains("not allowed") {
            return "Only the couple can change that."
        }
        return "Something went wrong. Please try again."
    }
}
