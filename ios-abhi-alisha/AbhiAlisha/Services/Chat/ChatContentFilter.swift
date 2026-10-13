import Foundation

/// A first filter at the chat's door: obvious profanity, slurs and abuse are held back
/// before anything is published to a shared channel. Reporting, blocking and organizer
/// removal still cover everything else after the fact — this simply catches what should
/// never go up in the first place.
nonisolated enum ChatContentFilter {
    /// Whole-word matches only. The list is deliberately short and unambiguous, so
    /// ordinary words never trip it; common look-alike characters are normalised away.
    private static let banned: Set<String> = [
        // English
        "fuck", "fucker", "fucking", "motherfucker", "shit", "bullshit", "bitch",
        "asshole", "bastard", "cunt", "dick", "dickhead", "prick", "twat",
        "whore", "slut", "wanker", "bollocks",
        // Slurs — never acceptable in any form
        "nigger", "nigga", "faggot", "fag", "retard", "kike", "spic", "chink",
        "tranny", "paki", "gook", "wetback", "raghead", "towelhead",
        // Transliterated Hindi / Punjabi
        "madarchod", "madarchodh", "behenchod", "behenchodh", "bhosdike",
        "bhosdiwale", "chutiya", "chutiye", "randi", "haramzade", "gandu", "lund",
        // Sexual explicitness
        "porn", "pornhub", "blowjob", "handjob"
    ]

    /// True when a word in the message is on the banned list.
    static func isObjectionable(_ text: String) -> Bool {
        let normalized = normalize(text)
        for word in normalized.split(whereSeparator: \.isWhitespace) {
            let token = word.trimmingCharacters(in: .punctuationCharacters)
            guard token.count >= 3 else { continue }
            if banned.contains(token) { return true }
        }
        return false
    }

    /// Lowercases and undoes common look-alike swaps, so "b!tch" and "sh1t" still match.
    private static func normalize(_ text: String) -> String {
        let swaps: [(Character, Character)] =
            [("0", "o"), ("1", "i"), ("3", "e"), ("4", "a"), ("5", "s"),
             ("7", "t"), ("@", "a"), ("$", "s"), ("!", "i")]
        var lowered = text.lowercased()
        for (from, to) in swaps where lowered.contains(from) {
            lowered = lowered.replacingOccurrences(of: String(from), with: String(to))
        }
        return lowered
    }
}
