import Foundation

/// A member of the two families.
///
/// The published data keeps the person's first name in `role` and their
/// relationship to the couple in `name`, so both are exposed under clearer names here.
nonisolated struct FamilyMember: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let role: String?
    let photo: String?
    let initials: String?
    let sortOrder: Double?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case role
        case photo
        case initials
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }

    /// The person's first name.
    var displayName: String? {
        let value = role?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// How they're related to Abhi & Alisha.
    var relationship: String? {
        let value = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    var photoURL: URL? {
        guard let photo, !photo.isEmpty else { return nil }
        return URL(string: photo)
    }

    var monogram: String {
        if let initials, !initials.isEmpty { return initials.uppercased() }
        return String(displayName?.prefix(1) ?? "·").uppercased()
    }

    static func active(from members: [FamilyMember]) -> [FamilyMember] {
        members
            .filter { $0.isActive != false }
            .filter { $0.displayName != nil || $0.relationship != nil }
            .sorted { ($0.sortOrder ?? .greatestFiniteMagnitude) < ($1.sortOrder ?? .greatestFiniteMagnitude) }
    }
}
