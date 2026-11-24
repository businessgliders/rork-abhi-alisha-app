import PhotosUI
import Supabase
import SwiftUI

/// The wedding's words: the welcome letter, the story, the family and the FAQ.
struct HostContentView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case letter = "Letter"
        case story = "Story"
        case family = "Family"
        case faq = "FAQ"
        case stay = "Stay"
        var id: String { rawValue }

        var kind: String {
            switch self {
            case .letter, .stay: return "custom"
            case .story: return "story"
            case .family: return "family"
            case .faq: return "faq"
            }
        }

        /// Which `data.key` a custom row needs to belong here.
        var customKey: String? {
            switch self {
            case .letter: return "letter"
            case .stay: return HostContentView.roomRateKey
            default: return nil
            }
        }
    }

    static let roomRateKey = "room_rate"

    @Environment(ContentStore.self) private var content

    @State private var tab: Tab = .letter
    @State private var sections: [HostSection] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var editing: HostSection?

    private var weddingID: String { WeddingContext.shared.weddingID }

    private var shown: [HostSection] {
        sections.filter { section in
            guard section.kind == tab.kind else { return false }
            if let key = tab.customKey { return section.string("key") == key }
            return true
        }
        .sorted { $0.sort < $1.sort }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 10)

                Text(hint)
                    .font(Milni.inter(13))
                    .foregroundStyle(HostStyle.muted)
                    .contentTransition(.opacity)

                HostErrorLine(message: error)

                if tab == .stay {
                    HostCaps("Room rates", color: HostStyle.muted)
                        .padding(.top, 4)
                }

                if isLoading && sections.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if shown.isEmpty {
                    HostEmptyLine(text: emptyText)
                } else {
                    HostCard {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, section in
                            if index > 0 { HostHairline() }
                            HStack(spacing: 0) {
                                Button {
                                    BrandHaptics.tick()
                                    editing = section
                                } label: {
                                    sectionRow(section)
                                }
                                .buttonStyle(HostRowPressStyle())
                                if tab == .stay, shown.count > 1 {
                                    reorderControls(index: index, count: shown.count)
                                }
                            }
                            .contextMenu {
                                if tab == .stay, shown.count > 1 {
                                    if index > 0 {
                                        Button("Move Up", systemImage: "arrow.up") { move(from: index, by: -1) }
                                    }
                                    if index < shown.count - 1 {
                                        Button("Move Down", systemImage: "arrow.down") { move(from: index, by: 1) }
                                    }
                                }
                            }
                        }
                    }
                }

                if tab != .letter || shown.isEmpty {
                    Button {
                        BrandHaptics.tick()
                        editing = blank()
                    } label: {
                        Label(addTitle, systemImage: "plus")
                            .font(Milni.inter(15, weight: 600))
                            .foregroundStyle(HostStyle.goldText)
                            .frame(minHeight: 44)
                    }
                }
            }
            .padding(.horizontal, HostStyle.side)
            .padding(.bottom, 40)
            .animation(.calm, value: tab)
        }
        .background(HostPaper())
        .navigationTitle("FAQ, travel & stay")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $editing) { section in
            HostSectionEditor(section: section, tab: tabFor(section)) { saved in
                if let saved {
                    if let index = sections.firstIndex(where: { $0.id == saved.id }) {
                        sections[index] = saved
                    } else {
                        sections.append(saved)
                    }
                } else {
                    sections.removeAll { $0.id == section.id }
                }
                content.invalidate()
                Task { await content.refreshIfNeeded() }
            }
            .interactiveDismissDisabled()
        }
    }

    private func tabFor(_ section: HostSection) -> Tab {
        if section.kind == "custom" {
            return section.string("key") == Self.roomRateKey ? .stay : .letter
        }
        return Tab.allCases.first { $0.kind == section.kind } ?? .letter
    }

    private func reorderControls(index: Int, count: Int) -> some View {
        VStack(spacing: 0) {
            Button {
                move(from: index, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 40, height: 28)
                    .contentShape(Rectangle())
            }
            .disabled(index == 0)
            .accessibilityLabel("Move up")
            Button {
                move(from: index, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 40, height: 28)
                    .contentShape(Rectangle())
            }
            .disabled(index == count - 1)
            .accessibilityLabel("Move down")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(HostStyle.goldText)
        .buttonStyle(.plain)
        .padding(.trailing, 6)
    }

    /// Swaps a row with its neighbour and saves the new order.
    private func move(from index: Int, by offset: Int) {
        var ordered = shown
        let target = index + offset
        guard ordered.indices.contains(index), ordered.indices.contains(target) else { return }
        BrandHaptics.tick()
        ordered.swapAt(index, target)
        for position in ordered.indices { ordered[position].sort = position }
        withAnimation(.calm) {
            for row in ordered {
                if let at = sections.firstIndex(where: { $0.id == row.id }) { sections[at].sort = row.sort }
            }
        }
        Task {
            do {
                try await HostAPI.shared.reorderSections(ordered)
                error = nil
                content.invalidate()
                await content.refreshIfNeeded()
            } catch {
                self.error = error.hostMessage
                await load()
            }
        }
    }

    private var hint: String {
        switch tab {
        case .letter: return "The note guests read first on the Story screen."
        case .story: return "Moments from how you met, one card each."
        case .family: return "The people guests will meet, with a photo and how they're related."
        case .faq: return "Answers to the questions everyone asks."
        case .stay: return "Each room type with its nightly rates. Guests see them under Where we're staying."
        }
    }

    private var emptyText: String {
        switch tab {
        case .letter: return "No letter yet."
        case .story: return "No story moments yet."
        case .family: return "No family added yet."
        case .faq: return "No questions yet."
        case .stay: return "No room rates yet."
        }
    }

    private var addTitle: String {
        switch tab {
        case .letter: return "Write the letter"
        case .story: return "Add a moment"
        case .family: return "Add a family member"
        case .faq: return "Add a question"
        case .stay: return "Add a room"
        }
    }

    private func sectionRow(_ section: HostSection) -> some View {
        HStack(spacing: 12) {
            if tab == .family {
                let photo = section.string("photo")
                RemoteImage(url: URL(string: photo), contentMode: .fill) {
                    Circle().fill(HostStyle.hairline)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else if tab == .story, !section.string("year").isEmpty {
                Text(section.string("year"))
                    .font(Milni.cormorant(18, weight: 600))
                    .foregroundStyle(HostStyle.goldText)
                    .frame(width: 48, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title.isEmpty ? "Untitled" : section.title)
                    .font(Milni.cormorant(20, weight: 500))
                    .foregroundStyle(HostStyle.ink)
                    .lineLimit(1)
                if tab == .stay {
                    Text(RoomRateFormat.summary(section))
                        .font(Milni.inter(13))
                        .foregroundStyle(HostStyle.muted)
                        .lineLimit(2)
                } else if !section.body.isEmpty {
                    Text(section.body)
                        .font(Milni.inter(13))
                        .foregroundStyle(HostStyle.muted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HostStyle.gold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func blank() -> HostSection {
        var data: [String: AnyJSON] = [:]
        if tab == .letter { data["key"] = .string("letter") }
        if tab == .stay {
            data["key"] = .string(Self.roomRateKey)
            data["currency"] = .string("USD")
        }
        if tab == .faq { data["section"] = .string("general") }
        let sort = (shown.map(\.sort).max() ?? -1) + 1
        return HostSection(id: "", kind: tab.kind, title: "", body: "", data: data, sort: sort)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sections = try await HostAPI.shared.sections(weddingID: weddingID, kinds: Array(Set(Tab.allCases.map(\.kind))))
            error = nil
        } catch {
            self.error = error.hostMessage
        }
    }
}

/// One letter, story moment, family member or question.
private struct HostSectionEditor: View {
    @State var section: HostSection
    let tab: HostContentView.Tab
    let done: (HostSection?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var photoPick: PhotosPickerItem?
    @State private var isUploading = false

    private var weddingID: String { WeddingContext.shared.weddingID }

    var body: some View {
        VStack(spacing: 0) {
            HostSheetBar(
                title: barTitle,
                canSave: !section.title.hostTrimmed.isEmpty && !isUploading,
                isSaving: isSaving,
                cancel: { dismiss() },
                save: { Task { await save() } }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    fields
                    HostErrorLine(message: error)
                    if !section.isNew {
                        Button {
                            confirmDelete = true
                        } label: {
                            Text("Delete")
                                .font(Milni.inter(15, weight: 500))
                                .foregroundStyle(HostStyle.danger)
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .confirmationDialog("Delete this?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) { Task { await delete() } }
                        } message: {
                            Text("Guests will no longer see it. This can't be undone.")
                        }
                    }
                }
                .padding(.horizontal, HostStyle.side)
                .padding(.top, 10)
                .padding(.bottom, 50)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(HostPaper())
        .environment(\.colorScheme, .light)
        .onChange(of: photoPick) { _, item in
            guard let item else { return }
            photoPick = nil
            Task { await upload(item) }
        }
    }

    private var barTitle: String {
        switch tab {
        case .letter: return "Letter"
        case .story: return "Story"
        case .family: return "Family"
        case .faq: return "Question"
        case .stay: return "Room"
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch tab {
        case .letter:
            HostTitleField(placeholder: "Dear family and friends,", text: $section.title, size: 32)
            HostField(label: "Letter", text: $section.body, placeholder: "We can't wait to celebrate with you…", multiline: true)
            HostField(label: "Closing", text: dataBinding("closing"), placeholder: "With love,")
            HostField(label: "Signature", text: dataBinding("signature"), placeholder: WeddingContext.shared.snapshot.coupleNames)
        case .story:
            HostTitleField(placeholder: "How we met", text: $section.title, size: 32)
            HostField(label: "Year", text: dataBinding("year"), placeholder: "2019", keyboard: .numberPad)
            HostField(label: "The story", text: $section.body, placeholder: "It started at a friend's dinner party…", multiline: true)
            photoField(key: "image_url", folder: "story", label: "Photo")
        case .family:
            HostTitleField(placeholder: "Name", text: $section.title, size: 32)
            HostField(label: "Relation", text: $section.body, placeholder: "Bride's mother")
            photoField(key: "photo", folder: "family", label: "Photo")
        case .faq:
            HostTitleField(placeholder: "Question", text: $section.title, size: 28)
            HostField(label: "Answer", text: $section.body, placeholder: "Yes! Here's what to know…", multiline: true)
            VStack(alignment: .leading, spacing: 10) {
                HostCaps("Topic", color: HostStyle.muted)
                HStack(spacing: 8) {
                    ForEach(["general", "travel", "attire", "events"], id: \.self) { topic in
                        HostChip(title: topic.capitalized, isOn: section.string("section") == topic) {
                            section.data["section"] = .string(topic)
                        }
                    }
                }
            }
        case .stay:
            HostTitleField(placeholder: "Oceanfront King", text: $section.title, size: 30)
            VStack(alignment: .leading, spacing: 10) {
                HostCaps("Currency", color: HostStyle.muted)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(RoomRateFormat.currencies, id: \.self) { code in
                            HostChip(title: code, isOn: currency == code) {
                                section.data["currency"] = .string(code)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            HStack(alignment: .top, spacing: 16) {
                HostField(label: "Sun – Wed / night", text: numberBinding("sun_wed_rate"), placeholder: "320", keyboard: .decimalPad)
                HostField(label: "Thu – Sat / night", text: numberBinding("thu_sat_rate"), placeholder: "360", keyboard: .decimalPad)
            }
            HStack(alignment: .top, spacing: 16) {
                HostField(label: "Max adults", text: numberBinding("max_adults", whole: true), placeholder: "2", keyboard: .numberPad)
                HostField(label: "Extra adult / night", text: numberBinding("extra_adult_fee"), placeholder: "80", keyboard: .decimalPad)
            }
            HostField(label: "Room code (optional)", text: dataBinding("room_key"), placeholder: RoomRateFormat.slug(section.title))
            HostField(label: "Note for guests (optional)", text: $section.body, placeholder: "Includes breakfast for two", multiline: true)
        }
    }

    private func photoField(key: String, folder: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HostCaps(label, color: HostStyle.muted)
            HStack(spacing: 16) {
                let url = section.string(key)
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(HostStyle.hairline.opacity(0.6))
                    if !url.isEmpty {
                        RemoteImage(url: URL(string: url), contentMode: .fill) { Color.clear }
                    } else {
                        Image(systemName: "photo").foregroundStyle(HostStyle.muted)
                    }
                    if isUploading { ProgressView() }
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $photoPick, matching: .images) {
                        Text(url.isEmpty ? "Choose a photo" : "Change photo")
                            .font(Milni.inter(15, weight: 600))
                            .foregroundStyle(HostStyle.goldText)
                    }
                    if !url.isEmpty {
                        Button("Remove") { section.data[key] = nil }
                            .font(Milni.inter(14))
                            .foregroundStyle(HostStyle.muted)
                    }
                }
            }
        }
    }

    private func dataBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { section.string(key) },
            set: { section.data[key] = $0.isEmpty ? nil : .string($0) }
        )
    }

    private var currency: String {
        let code = section.string("currency").uppercased()
        return code.isEmpty ? "USD" : code
    }

    /// A number in `data`, edited as text and saved back as a number.
    private func numberBinding(_ key: String, whole: Bool = false) -> Binding<String> {
        Binding(
            get: { RoomRateFormat.text(section.data[key]) },
            set: { raw in
                let clean = raw.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }
                if clean.isEmpty {
                    section.data[key] = nil
                } else if whole {
                    section.data[key] = Int(clean.split(separator: ".").first ?? "").map(AnyJSON.integer) ?? nil
                } else if let value = Double(clean) {
                    section.data[key] = value.rounded() == value && !clean.contains(".")
                        ? .integer(Int(value)) : .double(value)
                }
            }
        )
    }

    private var photoTarget: HostPhotoTarget {
        tab == .family ? HostPhotoTarget(key: "photo", folder: "family") : HostPhotoTarget(key: "image_url", folder: "story")
    }

    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        defer { isUploading = false }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            error = "That photo couldn't be read. Please pick another."
            return
        }
        let target = photoTarget
        do {
            let path = "\(weddingID.lowercased())/\(target.folder)/\(UUID().uuidString.lowercased()).jpg"
            let url = try await HostAPI.shared.uploadPhoto(image, path: path, maxSide: 1400)
            withAnimation(.calm) { section.data[target.key] = .string(url) }
            error = nil
        } catch {
            self.error = error.hostMessage
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var draft = section
        draft.title = draft.title.hostTrimmed
        draft.body = draft.body.hostTrimmed
        if tab == .stay {
            draft.data["key"] = .string(HostContentView.roomRateKey)
            if draft.string("room_key").hostTrimmed.isEmpty {
                draft.data["room_key"] = .string(RoomRateFormat.slug(draft.title))
            }
            if draft.string("currency").isEmpty { draft.data["currency"] = .string("USD") }
        }
        do {
            let id = try await HostAPI.shared.save(draft, weddingID: weddingID)
            if !id.isEmpty { draft.id = id }
            BrandHaptics.soft()
            done(draft)
            dismiss()
        } catch {
            withAnimation(.calm) { self.error = error.hostMessage }
        }
    }

    private func delete() async {
        do {
            try await HostAPI.shared.delete(sectionID: section.id)
            done(nil)
            dismiss()
        } catch {
            withAnimation(.calm) { self.error = error.hostMessage }
        }
    }
}

struct HostPhotoTarget: Equatable {
    let key: String
    let folder: String
}

/// Shared formatting for the couple's room rates.
enum RoomRateFormat {
    static let currencies = ["USD", "CAD", "MXN", "EUR", "GBP", "INR"]

    static func number(_ value: AnyJSON?) -> Double? {
        switch value {
        case .integer(let number)?: return Double(number)
        case .double(let number)?: return number
        case .string(let text)?: return Double(text)
        default: return nil
        }
    }

    static func text(_ value: AnyJSON?) -> String {
        switch value {
        case .integer(let number)?: return String(number)
        case .double(let number)?:
            return number.rounded() == number ? String(Int(number)) : String(number)
        case .string(let text)?: return text
        default: return ""
        }
    }

    static func slug(_ title: String) -> String {
        let words = title.lowercased().split { !$0.isLetter && !$0.isNumber }
        return words.isEmpty ? "room" : words.joined(separator: "_")
    }

    static func money(_ value: Double, code: String) -> String {
        let whole = value.rounded() == value
        return value.formatted(.currency(code: code).precision(.fractionLength(whole ? 0 : 2)))
    }

    /// "USD 320 Sun–Wed · 360 Thu–Sat · up to 2 adults"
    static func summary(_ section: HostSection) -> String {
        let raw = section.string("currency").uppercased()
        let code = raw.count == 3 ? raw : "USD"
        var parts: [String] = []
        if let low = number(section.data["sun_wed_rate"]) { parts.append("\(money(low, code: code)) Sun–Wed") }
        if let high = number(section.data["thu_sat_rate"]) { parts.append("\(money(high, code: code)) Thu–Sat") }
        if let adults = number(section.data["max_adults"]), adults > 0 { parts.append("up to \(Int(adults)) adults") }
        return parts.isEmpty ? "No rates yet" : parts.joined(separator: " · ")
    }
}
