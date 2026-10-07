import Foundation
import UIKit

/// One photograph in the Wedding Week timeline, as stored in Supabase `event_photos`.
/// Files live in the public `event-photos` bucket: `<event_id>/<uuid>.jpg` at full size
/// and `<event_id>/<uuid>_t.jpg` as the thumbnail.
nonisolated struct WeddingPhoto: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var eventID: String
    let photoPath: String
    let thumbPath: String?
    var caption: String?
    let takenAt: Date?
    var isCover: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case photoPath = "photo_path"
        case thumbPath = "thumb_path"
        case caption
        case takenAt = "taken_at"
        case isCover = "is_cover"
        case createdAt = "created_at"
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
        eventID = (try? container.decodeIfPresent(String.self, forKey: .eventID)) ?? ""
        photoPath = (try? container.decodeIfPresent(String.self, forKey: .photoPath)) ?? ""
        thumbPath = (try? container.decodeIfPresent(String.self, forKey: .thumbPath))?.nonEmpty
        caption = (try? container.decodeIfPresent(String.self, forKey: .caption))?.nonEmpty
        takenAt = Self.date(in: container, forKey: .takenAt)
        isCover = (try? container.decodeIfPresent(Bool.self, forKey: .isCover)) ?? false
        createdAt = Self.date(in: container, forKey: .createdAt)
    }

    /// Reads a timestamp whether it arrives as Postgres text or as the number this app
    /// writes to its own cache.
    private static func date(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            return ChatJSON.parseDate(text)
        }
        if let seconds = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        return nil
    }

    /// When it was taken, or failing that, when it was added.
    var sortDate: Date { takenAt ?? createdAt ?? .distantPast }

    var fullURL: URL? { Self.publicURL(photoPath) }
    var thumbURL: URL? { thumbPath.flatMap(Self.publicURL) ?? fullURL }

    static let bucket = "event-photos"

    static func publicURL(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(ChatBackend.url.absoluteString)/storage/v1/object/public/\(bucket)/\(encoded)")
    }
}

/// A new row for `event_photos`.
nonisolated struct WeddingPhotoInsert: Encodable, Sendable {
    let event_id: String
    let photo_path: String
    let thumb_path: String
    let caption: String?
    let taken_at: String?
    let is_cover: Bool
}

/// Sets or clears a caption; a cleared caption is sent as an explicit null.
nonisolated struct WeddingCaptionChange: Encodable, Sendable {
    let caption: String?

    enum CodingKeys: String, CodingKey { case caption }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(caption, forKey: .caption)
    }
}

nonisolated struct WeddingCoverChange: Encodable, Sendable {
    let is_cover: Bool
}

nonisolated struct WeddingEventChange: Encodable, Sendable {
    let event_id: String
    let is_cover: Bool
}

/// A photo the couple has picked and the app has already resized, waiting in review.
struct PreparedWeddingPhoto: Identifiable, Equatable {
    let id: UUID
    let fullName: String
    let thumbName: String
    let preview: UIImage
    let takenAt: Date?
    var eventID: String?
    var caption: String = ""
    var isCover: Bool = false
}

/// A photo on its way up, kept on disk so it survives the app closing.
nonisolated struct WeddingUploadJob: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let eventID: String
    let caption: String?
    let isCover: Bool
    let takenAt: Date?
    let fullName: String
    let thumbName: String
    var attempts: Int = 0

    var photoPath: String { "\(eventID)/\(id.uuidString.lowercased()).jpg" }
    var thumbPath: String { "\(eventID)/\(id.uuidString.lowercased())_t.jpg" }
}
