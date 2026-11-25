import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Shared models (plain, so drafts and lists save without the AI framework)

nonisolated struct ToastText: Codable, Hashable, Sendable {
    var title: String
    var opening: String
    var body: String
    var closing: String

    static let empty = ToastText(title: "", opening: "", body: "", closing: "")

    var isEmpty: Bool { [title, opening, body, closing].allSatisfy { $0.isEmpty } }

    /// The toast as one piece of text, for Copy and Share.
    var plainText: String {
        [title, opening, body, closing]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

nonisolated enum ToastRelationship: String, Codable, CaseIterable, Identifiable, Sendable {
    case sibling, cousin, friend, parent, coworker, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sibling: return String(localized: "Sibling")
        case .cousin: return String(localized: "Cousin")
        case .friend: return String(localized: "Friend")
        case .parent: return String(localized: "Parent")
        case .coworker: return String(localized: "Co-worker")
        case .other: return String(localized: "Other")
        }
    }
}

nonisolated enum ToastTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case heartfelt, funny, short, poetic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .heartfelt: return String(localized: "Heartfelt")
        case .funny: return String(localized: "Funny")
        case .short: return String(localized: "Short & sweet")
        case .poetic: return String(localized: "Poetic")
        }
    }
}

nonisolated enum ToastLength: String, Codable, CaseIterable, Identifiable, Sendable {
    case thirty, minute, twoMinutes
    var id: String { rawValue }
    var label: String {
        switch self {
        case .thirty: return String(localized: "30 sec")
        case .minute: return String(localized: "1 min")
        case .twoMinutes: return String(localized: "2 min")
        }
    }
    /// Roughly 130 spoken words a minute.
    var words: Int {
        switch self {
        case .thirty: return 70
        case .minute: return 130
        case .twoMinutes: return 260
        }
    }
}

nonisolated struct ToastInput: Codable, Hashable, Sendable {
    var name = ""
    var relationship: ToastRelationship = .friend
    var tone: ToastTone = .heartfelt
    var length: ToastLength = .minute
    var memories = ""
    var languageMix = ""
}

/// What the wedding tells the writer.
nonisolated struct ToastContext: Hashable, Sendable {
    var partnerOne: String
    var partnerTwo: String
    var eventTitle: String?
    var city: String?
    var storyTitles: [String]

    var couple: String {
        [partnerOne, partnerTwo].filter { !$0.isEmpty }.joined(separator: " & ")
    }
}

nonisolated enum ToastAdjustment: Sendable {
    case shorter, funnier
}

// Packing

nonisolated enum PackingSectionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case outfits, shoes, weather, documents, toiletries, ceremonies, extras
    var id: String { rawValue }
    var title: String {
        switch self {
        case .outfits: return String(localized: "Outfits by event")
        case .shoes: return String(localized: "Shoes & accessories")
        case .weather: return String(localized: "Weather")
        case .documents: return String(localized: "Travel documents")
        case .toiletries: return String(localized: "Toiletries")
        case .ceremonies: return String(localized: "For the ceremonies")
        case .extras: return String(localized: "Extras")
        }
    }
    var symbol: String {
        switch self {
        case .outfits: return "hanger"
        case .shoes: return "shoe"
        case .weather: return "sun.max"
        case .documents: return "doc.text"
        case .toiletries: return "drop"
        case .ceremonies: return "sparkles"
        case .extras: return "bag"
        }
    }
}

nonisolated struct PackingItem: Codable, Hashable, Identifiable, Sendable {
    var id = UUID().uuidString
    var text: String
    var isChecked = false
}

nonisolated struct PackingSection: Codable, Hashable, Identifiable, Sendable {
    var kind: PackingSectionKind
    var items: [PackingItem]
    var id: String { kind.rawValue }
}

nonisolated enum PackingBag: String, Codable, CaseIterable, Identifiable, Sendable {
    case checked, carryOn
    var id: String { rawValue }
    var label: String {
        switch self {
        case .checked: return String(localized: "Checked bag")
        case .carryOn: return String(localized: "Carry-on only")
        }
    }
}

nonisolated struct PackingEvent: Hashable, Sendable {
    var title: String
    var dressCode: String?
    var isOutdoor: Bool
    var weather: String?
    var savedLook: String?
}

nonisolated struct PackingContext: Hashable, Sendable {
    var city: String?
    var country: String?
    var nights: Int
    var temperature: Int?
    var weatherSummary: String?
    var events: [PackingEvent]
    var withKids: Bool
    var bag: PackingBag

    var destination: String {
        [city, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - The writer

/// Writes toasts and packing lists with Apple's on-device model when this iPhone has it,
/// otherwise from templates. Nothing leaves the phone, and nothing here ever surfaces an
/// error: any failure falls back to the template.
@MainActor
enum OnDeviceWriter {
    static var isModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    // MARK: Toast

    /// Streams the toast as it's written. Each value is the whole draft so far.
    static func streamToast(
        _ input: ToastInput,
        context: ToastContext,
        adjusting previous: ToastText? = nil,
        adjustment: ToastAdjustment? = nil
    ) -> AsyncStream<ToastText> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                var produced = false
                #if canImport(FoundationModels)
                if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
                    do {
                        let session = LanguageModelSession(instructions: toastInstructions)
                        let prompt = toastPrompt(input, context: context, previous: previous, adjustment: adjustment)
                        let stream = session.streamResponse(
                            to: prompt,
                            generating: GeneratedToast.self,
                            options: GenerationOptions(temperature: adjustment == nil ? 0.8 : 0.6)
                        )
                        for try await snapshot in stream {
                            let partial = snapshot.content
                            let text = ToastText(
                                title: partial.title ?? "",
                                opening: partial.opening ?? "",
                                body: partial.body ?? "",
                                closing: partial.closing ?? ""
                            )
                            if !text.isEmpty { produced = true }
                            continuation.yield(text)
                        }
                    } catch {
                        produced = false
                    }
                }
                #endif
                if !produced, !Task.isCancelled {
                    let template = templateToast(input, context: context, previous: previous, adjustment: adjustment)
                    // A gentle reveal so the template reads like the real thing.
                    var shown = ToastText.empty
                    for keyPath in [\ToastText.title, \.opening, \.body, \.closing] {
                        shown[keyPath: keyPath] = template[keyPath: keyPath]
                        continuation.yield(shown)
                        try? await Task.sleep(for: .milliseconds(180))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static let toastInstructions = """
    You help a wedding guest write a short toast to read aloud at an Indian or multicultural wedding celebration.
    Keep it warm, family-safe and respectful: no swearing, no innuendo, no jokes about exes, money, weight, religion or drinking, and nothing embarrassing about the couple.
    Write in the first person as the guest. Use only the memories the guest gives; never invent names, places or events.
    Write plain spoken sentences with no hashtags, emojis, stage directions or markdown.
    """

    private static func toastPrompt(_ input: ToastInput, context: ToastContext, previous: ToastText?, adjustment: ToastAdjustment?) -> String {
        var lines: [String] = []
        if let previous, let adjustment {
            lines.append("Here is a toast draft:")
            lines.append(previous.plainText)
            switch adjustment {
            case .shorter: lines.append("Rewrite it about half as long, keeping the best line and the same voice.")
            case .funnier: lines.append("Rewrite it a little funnier with gentle, kind humour that the couple's grandparents would enjoy. Keep the same length.")
            }
            return lines.joined(separator: "\n")
        }
        lines.append("The couple: \(context.couple).")
        if let event = context.eventTitle { lines.append("The toast is for the \(event).") }
        if let city = context.city { lines.append("The wedding is in \(city).") }
        if !context.storyTitles.isEmpty {
            lines.append("Chapters of their story, for colour only: \(context.storyTitles.prefix(5).joined(separator: "; ")).")
        }
        let speaker = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("The guest\(speaker.isEmpty ? "" : " is \(speaker) and") is the couple's \(input.relationship.label.lowercased()).")
        lines.append("Tone: \(input.tone.label). Length: about \(input.length.words) words in total.")
        let memories = input.memories.trimmingCharacters(in: .whitespacesAndNewlines)
        if !memories.isEmpty { lines.append("Memories to draw from: \(memories)") }
        let mix = input.languageMix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mix.isEmpty { lines.append("Mix in a few simple words or a short blessing in \(mix), written in the Latin alphabet.") }
        lines.append("End by asking everyone to raise a glass to the couple.")
        return lines.joined(separator: "\n")
    }

    /// The fallback: a template that still uses every input.
    static func templateToast(_ input: ToastInput, context: ToastContext, previous: ToastText? = nil, adjustment: ToastAdjustment? = nil) -> ToastText {
        let couple = context.couple.isEmpty ? String(localized: "the happy couple") : context.couple
        let speaker = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let intro = speaker.isEmpty
            ? String(localized: "Good evening, everyone.")
            : String(localized: "Good evening, everyone. For those I haven't met, I'm \(speaker).")
        let role: String = {
            switch input.relationship {
            case .sibling: return String(localized: "I've had a front-row seat to one half of this love story my whole life")
            case .cousin: return String(localized: "Being family means I've seen every chapter of this, from cousins' sleepovers to tonight")
            case .friend: return String(localized: "As a friend, I've watched this love story unfold one late-night phone call at a time")
            case .parent: return String(localized: "As a parent, there is no prouder seat in the room than this one")
            case .coworker: return String(localized: "I know one of you from long days at work, and I've never seen anyone light up like this")
            case .other: return String(localized: "I'm so grateful to be part of this celebration")
            }
        }()
        let memory = input.memories.trimmingCharacters(in: .whitespacesAndNewlines)
        let memoryLine = memory.isEmpty ? "" : String(localized: " I keep thinking about this: \(memory)")
        let event = context.eventTitle.map { String(localized: " at the \($0)") } ?? ""
        let place = context.city.map { String(localized: " here in \($0)") } ?? ""

        var body: String
        switch input.tone {
        case .heartfelt:
            body = String(localized: "\(role).\(memoryLine) What I love most is how you make each other more yourselves, never less.")
        case .funny:
            body = String(localized: "\(role).\(memoryLine) I'm told the secret to a long marriage is two words: \"you're right\". Practise them daily, and say them to each other's mothers.")
        case .short:
            body = String(localized: "\(role).\(memoryLine)")
        case .poetic:
            body = String(localized: "\(role).\(memoryLine) Two families, two stories, one thread of gold running through them both, tied tonight\(place).")
        }
        let mix = input.languageMix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mix.isEmpty, input.tone != .short {
            body += String(localized: " And in \(mix), from all of us: every blessing on this new home.")
        }
        if adjustment == .shorter || input.length == .thirty {
            body = role + "." + memoryLine
        } else if adjustment == .funnier, input.tone != .funny {
            body += String(localized: " May your Wi-Fi be strong, your arguments short, and your aunties always on your side.")
        }

        return ToastText(
            title: input.tone == .poetic ? String(localized: "A thread of gold") : String(localized: "To \(couple)"),
            opening: "\(intro) " + String(localized: "It's an honour to say a few words\(event)\(place)."),
            body: body,
            closing: String(localized: "So please, raise your glasses to \(couple). To love, laughter and a lifetime of it.")
        )
    }

    // MARK: Packing

    static func packingList(for context: PackingContext) async -> (sections: [PackingSection], usedModel: Bool) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                let session = LanguageModelSession(instructions: packingInstructions)
                let response = try await session.respond(
                    to: packingPrompt(context),
                    generating: GeneratedPackingList.self,
                    options: GenerationOptions(temperature: 0.4)
                )
                let list = response.content
                let raw: [(PackingSectionKind, [String])] = [
                    (.outfits, list.outfitsByEvent),
                    (.shoes, list.shoesAndAccessories),
                    (.weather, list.weather),
                    (.documents, list.travelDocuments),
                    (.toiletries, list.toiletries),
                    (.ceremonies, list.forTheCeremonies),
                    (.extras, list.extras)
                ]
                let sections = raw.map { kind, items in
                    PackingSection(kind: kind, items: tidy(items).map { PackingItem(text: $0) })
                }.filter { !$0.items.isEmpty }
                if sections.count >= 4 { return (sections, true) }
            } catch {
                // Fall through to the rules.
            }
        }
        #endif
        return (rulesPackingList(for: context), false)
    }

    private static let packingInstructions = """
    You write a concise, practical packing checklist for a guest travelling to a multi-day wedding.
    Each item is a short noun phrase of at most eight words, with no numbering, emojis or markdown.
    Only mention events and dress codes that you are given. Keep everything family-safe.
    """

    private static func packingPrompt(_ context: PackingContext) -> String {
        var lines: [String] = []
        lines.append("Destination: \(context.destination.isEmpty ? "unknown" : context.destination). Nights: \(context.nights).")
        if let temp = context.temperature { lines.append("Typical temperature: \(temp)°C. \(context.weatherSummary ?? "")") }
        lines.append(context.bag == .carryOn ? "Travelling with carry-on luggage only, so keep liquids under 100 ml and pack light." : "Travelling with a checked bag.")
        if context.withKids { lines.append("Travelling with children.") }
        lines.append("Events:")
        for event in context.events {
            var line = "- \(event.title)"
            if let code = event.dressCode { line += "; dress code: \(code)" }
            if event.isOutdoor { line += "; outdoors" }
            if let weather = event.weather { line += "; weather: \(weather)" }
            if let look = event.savedLook { line += "; the guest already planned: \(look)" }
            lines.append(line)
        }
        lines.append("In outfitsByEvent, write one item per event in the form 'Event: outfit'.")
        return lines.joined(separator: "\n")
    }

    private static func tidy(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { raw in
            let text = raw
                .trimmingCharacters(in: CharacterSet(charactersIn: "-•* ").union(.whitespacesAndNewlines))
            guard !text.isEmpty, text.count <= 90, seen.insert(text.lowercased()).inserted else { return nil }
            return text
        }
    }

    /// The fallback list, built from the same inputs with plain rules.
    static func rulesPackingList(for context: PackingContext) -> [PackingSection] {
        func items(_ texts: [String?]) -> [PackingItem] {
            tidy(texts.compactMap { $0 }).map { PackingItem(text: $0) }
        }
        let hot = (context.temperature ?? 22) >= 26
        let cool = (context.temperature ?? 22) <= 15
        let anyOutdoor = context.events.contains { $0.isOutdoor }
        let rainy = (context.weatherSummary ?? "").localizedCaseInsensitiveContains("rain")
            || (context.weatherSummary ?? "").localizedCaseInsensitiveContains("shower")
            || context.events.contains { ($0.weather ?? "").localizedCaseInsensitiveContains("umbrella") }

        let outfits = context.events.map { event -> String in
            if let look = event.savedLook { return "\(event.title): \(look)" }
            if let code = event.dressCode { return "\(event.title): \(code)" }
            return String(localized: "\(event.title): festive outfit")
        }
        let shoes: [String?] = [
            String(localized: "Dress shoes or heels"),
            String(localized: "Flat sandals or juttis for dancing"),
            anyOutdoor ? String(localized: "Block heels or wedges for grass and sand") : nil,
            String(localized: "Statement jewellery"),
            String(localized: "Clutch or small evening bag"),
            String(localized: "Bangles, cufflinks or pocket square")
        ]
        let weather: [String?] = [
            hot ? String(localized: "Sun cream, SPF 50") : nil,
            hot ? String(localized: "Sunglasses and a hat") : nil,
            hot ? String(localized: "Handheld fan") : nil,
            rainy ? String(localized: "Compact umbrella") : nil,
            cool ? String(localized: "Warm shawl or wrap") : String(localized: "Light shawl for the evenings"),
            anyOutdoor ? String(localized: "Insect repellent") : nil,
            hot || anyOutdoor ? String(localized: "Swimsuit") : nil
        ]
        let documents: [String?] = [
            String(localized: "Passport or ID"),
            String(localized: "Flight and hotel confirmations"),
            String(localized: "Travel insurance details"),
            String(localized: "Some local currency"),
            String(localized: "Travel adaptor"),
            context.withKids ? String(localized: "Children's passports and consent letters") : nil
        ]
        let toiletries: [String?] = [
            context.bag == .carryOn ? String(localized: "Liquids under 100 ml in a clear bag") : String(localized: "Full-size toiletries"),
            String(localized: "Hair styling products and pins"),
            String(localized: "Makeup and setting spray"),
            String(localized: "Blister plasters"),
            String(localized: "Any regular medicines"),
            context.withKids ? String(localized: "Children's sun cream and medicines") : nil
        ]
        let ceremonies: [String?] = [
            String(localized: "Cash envelopes for shagun"),
            String(localized: "Wedding gift or card"),
            String(localized: "Head covering for the religious ceremony"),
            String(localized: "Safety pins and fashion tape"),
            String(localized: "Mehndi aftercare: lemon and sugar")
        ]
        let extras: [String?] = [
            String(localized: "Phone charger and power bank"),
            String(localized: "Steamer or wrinkle-release spray"),
            String(localized: "Reusable water bottle"),
            context.withKids ? String(localized: "Snacks and a quiet toy for long ceremonies") : nil,
            context.withKids ? String(localized: "Ear defenders for the dance floor") : nil,
            context.nights >= 4 ? String(localized: "Laundry bag") : nil
        ]
        return [
            PackingSection(kind: .outfits, items: items(outfits)),
            PackingSection(kind: .shoes, items: items(shoes)),
            PackingSection(kind: .weather, items: items(weather)),
            PackingSection(kind: .documents, items: items(documents)),
            PackingSection(kind: .toiletries, items: items(toiletries)),
            PackingSection(kind: .ceremonies, items: items(ceremonies)),
            PackingSection(kind: .extras, items: items(extras))
        ].filter { !$0.items.isEmpty }
    }
}

// MARK: - Generable shapes (iOS 26 with Apple Intelligence)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedToast {
    @Guide(description: "A short, warm title for the toast, two to six words")
    var title: String
    @Guide(description: "One or two sentences greeting the room and introducing the speaker")
    var opening: String
    @Guide(description: "The heart of the toast: the memories and what the guest loves about the couple")
    var body: String
    @Guide(description: "One or two sentences wishing the couple well and asking everyone to raise a glass")
    var closing: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedPackingList {
    @Guide(description: "One item per event, in the form 'Event: outfit'")
    var outfitsByEvent: [String]
    @Guide(description: "Shoes, jewellery and accessories", .count(3...8))
    var shoesAndAccessories: [String]
    @Guide(description: "Items for the weather and outdoor events", .count(2...7))
    var weather: [String]
    @Guide(description: "Passports, bookings, money and travel essentials", .count(3...7))
    var travelDocuments: [String]
    @Guide(description: "Toiletries and personal care", .count(3...8))
    var toiletries: [String]
    @Guide(description: "Things needed for the wedding ceremonies, like gifts or a head covering", .count(2...6))
    var forTheCeremonies: [String]
    @Guide(description: "Anything else useful", .count(2...6))
    var extras: [String]
}
#endif
