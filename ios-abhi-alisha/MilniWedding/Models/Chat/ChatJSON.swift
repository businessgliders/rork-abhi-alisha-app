import Foundation

/// The one JSON dialect the chat speaks, for PostgREST rows and Realtime records alike.
///
/// Postgres hands back timestamps with up to six fractional digits and a `+00:00`
/// offset (sometimes a space instead of the `T`), which Foundation's ISO parser won't
/// take as-is, so every date goes through `parseDate` first.
nonisolated enum ChatJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ChatJSON.parseDate(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unreadable date")
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ChatJSON.isoString(date))
        }
        return encoder
    }()

    /// Reads any of the timestamp shapes Postgres and Realtime produce.
    static func parseDate(_ raw: String) -> Date? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.count >= 11, text[text.index(text.startIndex, offsetBy: 10)] == " " {
            text.replaceSubrange(
                text.index(text.startIndex, offsetBy: 10)...text.index(text.startIndex, offsetBy: 10),
                with: "T"
            )
        }
        guard let tIndex = text.firstIndex(of: "T") else {
            return dateOnly(text)
        }

        var zone = "Z"
        var main = text
        if text.hasSuffix("Z") || text.hasSuffix("z") {
            main = String(text.dropLast())
        } else if let range = text[tIndex...].range(of: "[+-]\\d{2}(:?\\d{2})?$", options: .regularExpression) {
            var offset = String(text[range])
            if offset.count == 3 {
                offset += ":00"
            } else if !offset.contains(":") {
                offset.insert(":", at: offset.index(offset.startIndex, offsetBy: 3))
            }
            zone = offset
            main = String(text[..<range.lowerBound])
        }

        var fraction = ""
        if let dot = main.firstIndex(of: ".") {
            let digits = String(main[main.index(after: dot)...])
            fraction = "." + String((digits + "000").prefix(3))
            main = String(main[..<dot])
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fraction.isEmpty
            ? [.withInternetDateTime]
            : [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: main + fraction + zone)
    }

    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func dateOnly(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: text)
    }

    /// Trims and drops empty strings so blank values never reach the screen.
    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// One or two capital letters for a name, for the gold-ringed avatars.
    static func initials(for name: String?) -> String {
        guard let name = clean(name) else { return "·" }
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" }).filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap { $0.first.map(String.init) }
        let joined = letters.joined().uppercased()
        return joined.isEmpty ? "·" : joined
    }
}
