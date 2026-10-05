import Foundation

/// Whose suggestions the "Don't forget" list shows.
nonisolated enum OutfitGender: String, CaseIterable, Identifiable, Sendable {
    case men
    case women

    var id: String { rawValue }

    var title: String {
        switch self {
        case .men: return "Men"
        case .women: return "Women"
        }
    }
}

/// What to bring for one celebration, matched from its title.
nonisolated struct OutfitGuide: Sendable {
    /// A short read of the occasion, e.g. "All black, semi-formal, outdoor evening".
    let mood: String
    let everyone: [String]
    let men: [String]
    let women: [String]
    let tip: String?

    func items(for gender: OutfitGender) -> [String] {
        everyone + (gender == .men ? men : women)
    }

    /// The first guide whose keyword appears in the title.
    static func forTitle(_ title: String) -> OutfitGuide? {
        let text = title.lowercased()
        if ["welcome"].contains(where: text.contains) { return welcome }
        if ["haldi", "choora"].contains(where: text.contains) { return haldi }
        if ["sangeet", "jaggo"].contains(where: text.contains) { return sangeet }
        if ["anand karaj", "sikh", "gurdwara"].contains(where: text.contains) { return anandKaraj }
        if ["hindu", "phera", "mandap"].contains(where: text.contains) { return hindu }
        if ["reception"].contains(where: text.contains) { return reception }
        return nil
    }

    static let welcome = OutfitGuide(
        mood: "All black, semi-formal, outdoor evening",
        everyone: [],
        men: [
            "Black linen or dress shirt",
            "Black chinos or trousers",
            "Loafers or clean leather sneakers",
            "Watch",
            "A light layer for the breeze"
        ],
        women: [
            "Black midi or maxi dress, or a jumpsuit",
            "Block heels or dressy flat sandals for the patio",
            "Statement earrings",
            "Clutch",
            "A light wrap"
        ],
        tip: nil
    )

    static let haldi = OutfitGuide(
        mood: "Pastels, daytime, and turmeric gets messy",
        everyone: [],
        men: [
            "Pastel kurta pajama or linen shirt",
            "Mojaris, juttis or sandals",
            "Sunglasses",
            "An outfit you don't mind getting stained"
        ],
        women: [
            "Pastel sharara, anarkali, light lehenga or sundress",
            "Flats or juttis",
            "Floral or light jewellery",
            "Sunscreen",
            "Something you don't mind getting stained"
        ],
        tip: nil
    )

    static let sangeet = OutfitGuide(
        mood: "Colourful, festive, and made for dancing",
        everyone: [],
        men: [
            "Bright kurta with a Nehru jacket",
            "Juttis or mojaris",
            "Brooch or pocket square",
            "Something comfortable for dancing"
        ],
        women: [
            "Colourful lehenga, sharara or saree",
            "Jhumkas",
            "Bangles",
            "Potli bag",
            "Dance-friendly heels or juttis"
        ],
        tip: nil
    )

    static let anandKaraj = OutfitGuide(
        mood: "Formal Indian, for the Sikh ceremony",
        everyone: [
            "A head covering, required inside the ceremony",
            "Easy slip-on shoes, as shoes come off",
            "An outfit you can sit cross-legged in, as seating may be on the floor"
        ],
        men: [
            "Sherwani or kurta with a jacket",
            "Turban, patka or a rumal or bandana"
        ],
        women: [
            "Salwar suit, lehenga or saree",
            "Dupatta to cover your head"
        ],
        tip: "Leave bridal red to the bride."
    )

    static let hindu = OutfitGuide(
        mood: "Formal Indian, the same afternoon",
        everyone: [],
        men: [
            "Sherwani, bandhgala or kurta set",
            "Safa or turban, if you like",
            "Mojaris"
        ],
        women: [
            "Saree or lehenga",
            "Statement jewellery",
            "Bangles",
            "Comfortable heels or juttis"
        ],
        tip: "It's the same day as the Anand Karaj, so change outfits or keep one, and plan the swap."
    )

    static let reception = OutfitGuide(
        mood: "Formal, Indian or English",
        everyone: [],
        men: [
            "Suit, tux or bandhgala",
            "Dress shoes",
            "Cufflinks",
            "Watch"
        ],
        women: [
            "Gown, saree or lehenga",
            "Statement jewellery",
            "Heels",
            "Clutch"
        ],
        tip: nil
    )
}

extension ScheduleEvent {
    /// The closing "Thank You For Coming" morning, which has no outfit and no calendar entry.
    nonisolated var isFarewell: Bool {
        title.lowercased().contains("thank you")
    }
}
