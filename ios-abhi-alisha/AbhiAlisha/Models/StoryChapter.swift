import Foundation

/// One chapter of Abhi & Alisha's story, as they've written it on their timeline.
nonisolated struct StoryChapter: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let description: String?
    let year: String?
    let imageURL: String?
    let sortOrder: Double?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case year
        case imageURL = "image_url"
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }

    var url: URL? {
        guard let imageURL, !imageURL.isEmpty else { return nil }
        return URL(string: imageURL)
    }

    /// Active chapters with something to read, in the couple's own order.
    static func timeline(from chapters: [StoryChapter]) -> [StoryChapter] {
        chapters
            .filter { $0.isActive != false }
            .filter { ($0.title?.isEmpty == false) || ($0.description?.isEmpty == false) }
            .sorted { ($0.sortOrder ?? .greatestFiniteMagnitude) < ($1.sortOrder ?? .greatestFiniteMagnitude) }
    }
}
