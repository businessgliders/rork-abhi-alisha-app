import Foundation

/// The "Where we're staying" section, read from the wedding's `content_sections` row of
/// kind `stay` that carries photos, maps and amenities (room-type rows are skipped).
nonisolated struct StayInfo: Codable, Hashable, Sendable {
    nonisolated struct Amenity: Codable, Hashable, Sendable, Identifiable {
        var title: String
        var subtitle: String?
        var icon: String?

        var id: String { title }
    }

    var id: String?
    var title: String
    var photos: [String]
    var resortMapURL: String?
    var wingMapURL: String?
    var pdfURL: String?
    var amenities: [Amenity]

    enum CodingKeys: String, CodingKey {
        case id, title, photos, amenities
        case resortMapURL = "resort_map_url"
        case wingMapURL = "wing_map_url"
        case pdfURL = "pdf_url"
    }

    var photoURLs: [URL] { photos.compactMap(URL.init(string:)) }
    var resortMap: URL? { resortMapURL.flatMap(URL.init(string:)) }
    var wingMap: URL? { wingMapURL.flatMap(URL.init(string:)) }
    var pdf: URL? { pdfURL.flatMap(URL.init(string:)) }

    /// Whether a `stay` row describes the place (as opposed to one room type).
    static func isPlaceRow(_ data: [String: Any]) -> Bool {
        data["photos"] != nil || data["resort_map_url"] != nil || data["amenities"] != nil
            || data["pdf_url"] != nil || data["wing_map_url"] != nil
    }

    /// Builds the JSON object the shaper hands to the store.
    static func shapedRow(id: String, title: String?, data: [String: Any]) -> [String: Any] {
        var row: [String: Any] = ["id": id, "title": title ?? "Where we're staying"]
        row["photos"] = (data["photos"] as? [Any])?.compactMap { $0 as? String } ?? []
        row["resort_map_url"] = data["resort_map_url"] as? String
        row["wing_map_url"] = data["wing_map_url"] as? String
        row["pdf_url"] = data["pdf_url"] as? String
        let amenities = (data["amenities"] as? [[String: Any]]) ?? []
        row["amenities"] = amenities.compactMap { item -> [String: Any]? in
            guard let title = item["title"] as? String, !title.isEmpty else { return nil }
            var out: [String: Any] = ["title": title]
            out["subtitle"] = item["subtitle"] as? String
            out["icon"] = item["icon"] as? String
            return out
        }
        return row.compactMapValues { $0 }
    }

    /// The content A&A shipped with, used until their stay row exists.
    @MainActor static var abhiAlishaBundled: StayInfo {
        StayInfo(
            id: nil,
            title: "AVA Resort Cancún",
            photos: ResortMedia.photos.map(\.absoluteString),
            resortMapURL: nil,
            wingMapURL: nil,
            pdfURL: WingMapArtwork.pdfURL?.absoluteString,
            amenities: ResortAmenity.all.map {
                Amenity(title: $0.name, subtitle: $0.note, icon: $0.symbolName)
            }
        )
    }

    @MainActor var resortAmenities: [ResortAmenity] {
        amenities.map {
            ResortAmenity(
                id: $0.title,
                name: $0.title,
                note: $0.subtitle ?? "",
                symbolName: $0.icon.flatMap { $0.isEmpty ? nil : $0 } ?? "sparkles"
            )
        }
    }
}
