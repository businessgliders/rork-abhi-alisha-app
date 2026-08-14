import Foundation

/// A tab in the gallery's filter row, as published by the couple.
nonisolated struct GalleryCategory: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let slug: String?
    let sortOrder: Double?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }

    /// Active, named categories in the couple's order.
    static func active(from categories: [GalleryCategory]) -> [GalleryCategory] {
        categories
            .filter { $0.isActive != false }
            .filter { ($0.name?.isEmpty == false) && ($0.slug?.isEmpty == false) }
            .sorted { ($0.sortOrder ?? .greatestFiniteMagnitude) < ($1.sortOrder ?? .greatestFiniteMagnitude) }
    }
}
