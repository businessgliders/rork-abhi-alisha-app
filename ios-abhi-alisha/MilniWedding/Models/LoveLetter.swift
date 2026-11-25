import Foundation

/// The couple's letter to their guests. Every line is optional: anything empty
/// is left out of the layout entirely.
nonisolated struct LoveLetter: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let dateLine: String?
    let salutation: String?
    let body: String?
    let closing: String?
    let signature: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case dateLine = "date_line"
        case salutation
        case body
        case closing
        case signature
        case isActive = "is_active"
    }

    /// The body split into paragraphs on blank lines, ready to render.
    var paragraphs: [String] {
        guard let body else { return [] }
        return body
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// True when there is something worth showing.
    var hasContent: Bool {
        salutation?.nonEmpty != nil || !paragraphs.isEmpty || signature?.nonEmpty != nil
    }

    /// The first active letter with any content at all.
    static func firstActive(from letters: [LoveLetter]) -> LoveLetter? {
        letters
            .filter { $0.isActive != false }
            .first { $0.hasContent }
    }
}
