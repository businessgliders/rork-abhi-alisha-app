import Foundation

/// A loose piece of published content, keyed by the couple — the resort map, for example.
nonisolated struct WeddingContentItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let key: String?
    let section: String?
    let title: String?
    let subtitle: String?
    let body: String?
    let imageURL: String?
    let sortOrder: Double?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case section
        case title
        case subtitle
        case body
        case imageURL = "image_url"
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }

    var url: URL? {
        guard let imageURL, !imageURL.isEmpty else { return nil }
        return URL(string: imageURL)
    }

    static func active(from items: [WeddingContentItem]) -> [WeddingContentItem] {
        items
            .filter { $0.isActive != false }
            .sorted { ($0.sortOrder ?? .greatestFiniteMagnitude) < ($1.sortOrder ?? .greatestFiniteMagnitude) }
    }
}
