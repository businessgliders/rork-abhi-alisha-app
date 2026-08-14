import Foundation

/// The six line-art motifs bundled with the app, drawn in `LineArtIcon`.
nonisolated enum EventIconKey: String, CaseIterable, Sendable {
    case flutes
    case paisley
    case arch
    case mandap
    case sparkle
    case sun

    /// Keyword inference used only when `icon_key` is empty.
    static func inferred(fromTitle title: String) -> EventIconKey {
        let text = title.lowercased()
        let rules: [(keywords: [String], key: EventIconKey)] = [
            (["mehndi", "sangeet", "haldi"], .paisley),
            (["anand karaj", "sikh", "gurdwara"], .arch),
            (["phera", "mandap", "hindu", "baraat"], .mandap),
            (["reception"], .sparkle),
            (["welcome", "cocktail", "party"], .flutes),
            (["brunch", "farewell", "thank you", "rest"], .sun)
        ]
        for rule in rules where rule.keywords.contains(where: text.contains) {
            return rule.key
        }
        return .sparkle
    }
}
