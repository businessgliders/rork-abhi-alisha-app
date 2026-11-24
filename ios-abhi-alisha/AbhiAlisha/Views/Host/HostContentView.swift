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
        var id: String { rawValue }

        var kind: String {
            switch self {
            case .letter: return "custom"
            case .story: return "story"
            case .family: return "family"
            case .faq: return "faq"
            }
        }
    }

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
            if tab == .letter { return section.string("key") == "letter" }
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

                if isLoading && sections.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if shown.isEmpty {
                    HostEmptyLine(text: emptyText)
                } else {
                    HostCard {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, section in
                            if index > 0 { HostHairline() }
                            Button {
                                BrandHaptics.tick()
                                editing = section
                            } label: {
                                sectionRow(section)
                            }
                            .buttonStyle(HostRowPressStyle())
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
        .navigationTitle("Story, family & FAQ")
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
        Tab.allCases.first { $0.kind == section.kind } ?? .letter
    }

    private var hint: String {
        switch tab {
        case .letter: return "The note guests read first on the Story screen."
        case .story: return "Moments from how you met, one card each."
        case .family: return "The people guests will meet, with a photo and how they're related."
        case .faq: return "Answers to the questions everyone asks."
        }
    }

    private var emptyText: String {
        switch tab {
        case .letter: return "No letter yet."
        case .story: return "No story moments yet."
        case .family: return "No family added yet."
        case .faq: return "No questions yet."
        }
    }

    private var addTitle: String {
        switch tab {
        case .letter: return "Write the letter"
        case .story: return "Add a moment"
        case .family: return "Add a family member"
        case .faq: return "Add a question"
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
                if !section.body.isEmpty {
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
        if tab == .faq { data["section"] = .string("general") }
        let sort = (shown.map(\.sort).max() ?? -1) + 1
        return HostSection(id: "", kind: tab.kind, title: "", body: "", data: data, sort: sort)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sections = try await HostAPI.shared.sections(weddingID: weddingID, kinds: Tab.allCases.map(\.kind))
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
