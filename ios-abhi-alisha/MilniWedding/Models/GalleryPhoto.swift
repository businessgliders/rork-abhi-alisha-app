import Foundation

/// A photograph from the couple's gallery. Hero photographs feed the Home slideshow.
nonisolated struct GalleryPhoto: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let imageURL: String?
    let videoURL: String?
    let youtubeURL: String?
    let caption: String?
    let category: String?
    let mediaType: String?
    let isHero: Bool?
    let heroSortOrder: Double?
    let sortOrder: Double?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case imageURL = "image_url"
        case videoURL = "video_url"
        case youtubeURL = "youtube_url"
        case caption
        case category
        case mediaType = "media_type"
        case isHero = "is_hero"
        case heroSortOrder = "hero_sort_order"
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }

    /// What this entry actually is, whatever the couple typed in `media_type`.
    enum Kind: String, Sendable {
        case image
        case video
        case youtube
    }

    var kind: Kind {
        if let mediaType, let kind = Kind(rawValue: mediaType.lowercased()) { return kind }
        if youtubeURL?.nonEmpty != nil { return .youtube }
        if videoURL?.nonEmpty != nil { return .video }
        return .image
    }

    var url: URL? {
        guard let imageURL, !imageURL.isEmpty else { return nil }
        return URL(string: imageURL)
    }

    var movieURL: URL? {
        guard let videoURL = videoURL?.nonEmpty else { return nil }
        return URL(string: videoURL)
    }

    var youtubeWatchURL: URL? {
        guard let youtubeURL = youtubeURL?.nonEmpty else { return nil }
        return URL(string: youtubeURL)
    }

    /// The eleven-character YouTube id, pulled from either link shape.
    var youtubeID: String? {
        guard let youtubeWatchURL,
              let components = URLComponents(url: youtubeWatchURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if let value = components.queryItems?.first(where: { $0.name == "v" })?.value?.nonEmpty {
            return value
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? nil : path
    }

    /// YouTube's own poster frame, used when the couple hasn't uploaded one.
    var posterURL: URL? {
        if let url { return url }
        guard let youtubeID else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(youtubeID)/hqdefault.jpg")
    }

    var trimmedCaption: String? { caption?.nonEmpty }

    /// True when there is something to open or play.
    var isPlayable: Bool {
        switch kind {
        case .image: return false
        case .video: return movieURL != nil
        case .youtube: return youtubeWatchURL != nil
        }
    }

    /// Active entries for the gallery grid, in the couple's order. Anything with
    /// nothing to show — no poster and nothing to play — is left out.
    static func gallerySequence(from photos: [GalleryPhoto]) -> [GalleryPhoto] {
        photos
            .filter { $0.isActive != false }
            .filter { $0.posterURL != nil || $0.isPlayable }
            .sorted { ($0.sortOrder ?? .greatestFiniteMagnitude) < ($1.sortOrder ?? .greatestFiniteMagnitude) }
    }

    /// Photographs of the resort itself, whenever the couple files any under a resort category.
    static func resortSequence(from photos: [GalleryPhoto]) -> [GalleryPhoto] {
        let resortCategories: Set<String> = ["resort", "venue", "ava", "hotel"]
        return photos
            .filter { $0.isActive != false }
            .filter { ($0.mediaType ?? "image") == "image" }
            .filter { resortCategories.contains(($0.category ?? "").lowercased()) }
            .filter { $0.url != nil }
            .sorted { ($0.sortOrder ?? .greatestFiniteMagnitude) < ($1.sortOrder ?? .greatestFiniteMagnitude) }
    }

    /// Active, hero-flagged still photographs in the order the couple arranged them.
    static func heroSequence(from photos: [GalleryPhoto]) -> [GalleryPhoto] {
        photos
            .filter { $0.isActive != false }
            .filter { $0.isHero == true }
            .filter { ($0.mediaType ?? "image") == "image" }
            .filter { $0.url != nil }
            .sorted { ($0.heroSortOrder ?? .greatestFiniteMagnitude) < ($1.heroSortOrder ?? .greatestFiniteMagnitude) }
    }
}
