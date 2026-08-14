import Foundation

/// The sections the couple files their questions under.
nonisolated enum FaqSection: String, CaseIterable, Identifiable, Sendable {
    case payment
    case transfer
    case cancellation
    case resort
    case general
    case important

    var id: String { rawValue }

    /// Small gold heading shown above the group.
    var heading: String {
        switch self {
        case .payment: return "Deposits & Payment"
        case .transfer: return "Airport Transfers"
        case .cancellation: return "Cancellation Policy"
        case .resort: return "At the Resort"
        case .general: return "Before You Travel"
        case .important: return "Booking Essentials"
        }
    }
}

/// One question and answer, published by the couple.
nonisolated struct Faq: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let section: String?
    let question: String?
    let answer: String?
    let sortOrder: Double?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case section
        case question
        case answer
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }

    var sectionKey: FaqSection? {
        guard let section else { return nil }
        return FaqSection(rawValue: section)
    }

    /// Answered, active entries for one section, in the couple's order.
    static func group(_ faqs: [Faq], section: FaqSection) -> [Faq] {
        faqs
            .filter { $0.isActive != false }
            .filter { $0.sectionKey == section }
            .filter { ($0.question?.isEmpty == false) && ($0.answer?.isEmpty == false) }
            .sorted { ($0.sortOrder ?? .greatestFiniteMagnitude) < ($1.sortOrder ?? .greatestFiniteMagnitude) }
    }
}
