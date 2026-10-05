import Foundation

/// The four parts of a guest's look for one celebration.
nonisolated enum OutfitCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case outfit
    case jewelry
    case shoes
    case accessories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outfit: return "Outfit"
        case .jewelry: return "Jewellery"
        case .shoes: return "Shoes"
        case .accessories: return "Accessories"
        }
    }

    var symbolName: String {
        switch self {
        case .outfit: return "tshirt"
        case .jewelry: return "sparkles"
        case .shoes: return "shoe"
        case .accessories: return "handbag"
        }
    }
}

/// One photograph in a guest's own look, as stored in Supabase `outfit_items`.
/// The id is read whether the table hands back a uuid or a number.
nonisolated struct OutfitItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let eventID: String
    let category: String
    var photoPath: String
    var note: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case category
        case photoPath = "photo_path"
        case note
        case createdAt = "created_at"
    }

    init(id: String, eventID: String, category: OutfitCategory, photoPath: String, note: String? = nil) {
        self.id = id
        self.eventID = eventID
        self.category = category.rawValue
        self.photoPath = photoPath
        self.note = note
        self.createdAt = Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .id) {
            id = text
        } else if let number = try? container.decode(Int.self, forKey: .id) {
            id = String(number)
        } else {
            id = UUID().uuidString
        }
        eventID = try container.decodeIfPresent(String.self, forKey: .eventID) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? OutfitCategory.outfit.rawValue
        photoPath = try container.decodeIfPresent(String.self, forKey: .photoPath) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note)?.nonEmpty
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    var kind: OutfitCategory? { OutfitCategory(rawValue: category) }
}

/// A new row for `outfit_items`; `user_id` is filled in by the server.
nonisolated struct OutfitItemInsert: Encodable, Sendable {
    let event_id: String
    let category: String
    let photo_path: String
    let note: String?
}

/// Sets or clears a note. A cleared note is sent as an explicit null.
nonisolated struct OutfitNoteChange: Encodable, Sendable {
    let note: String?

    enum CodingKeys: String, CodingKey { case note }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(note, forKey: .note)
    }
}

nonisolated struct OutfitPathChange: Encodable, Sendable {
    let photo_path: String
}
