import SwiftUI
import UIKit

/// Saved toast drafts, on this phone only, per wedding.
@MainActor
enum ToastDraftStore {
    struct Draft: Codable, Identifiable, Hashable {
        var id = UUID().uuidString
        var savedAt = Date()
        var input: ToastInput
        var text: ToastText
    }

    private static var key: String { "toast-drafts." + ActiveWedding.snapshot.id.lowercased() }
    private static var inputKey: String { "toast-input." + ActiveWedding.snapshot.id.lowercased() }

    static func load() -> [Draft] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let drafts = try? JSONDecoder().decode([Draft].self, from: data) else { return [] }
        return drafts
    }

    static func save(_ drafts: [Draft]) {
        if let data = try? JSONEncoder().encode(Array(drafts.prefix(8))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func lastInput() -> ToastInput? {
        guard let data = UserDefaults.standard.data(forKey: inputKey) else { return nil }
        return try? JSONDecoder().decode(ToastInput.self, from: data)
    }

    static func remember(_ input: ToastInput) {
        if let data = try? JSONEncoder().encode(input) {
            UserDefaults.standard.set(data, forKey: inputKey)
        }
    }
}

/// "Write a toast": a few choices, then a draft written on the phone, streamed into a
/// card as it's written.
struct ToastWriterView: View {
    /// The celebration the toast is for; the reception (else the main ceremony) when nil.
    var eventID: String? = nil

    @Environment(ScheduleStore.self) private var schedule
    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var input = ToastDraftStore.lastInput() ?? ToastInput()
    @State private var text = ToastText.empty
    @State private var isWriting = false
    @State private var drafts = ToastDraftStore.load()
    @State private var didCopy = false
    @State private var writing: Task<Void, Never>?
    @FocusState private var focused: Field?

    private enum Field { case name, memories, language }

    private let usesModel = OnDeviceWriter.isModelAvailable

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        form
                        WriterPrimaryButton(
                            title: text.isEmpty ? String(localized: "Write my toast") : String(localized: "Regenerate"),
                            symbol: "sparkles",
                            isBusy: isWriting
                        ) {
                            focused = nil
                            write(adjustment: nil)
                            withAnimation(.calm) { proxy.scrollTo("draft", anchor: .top) }
                        }

                        if !text.isEmpty || isWriting {
                            draftCard
                                .id("draft")
                                .transition(.opacity)
                            if !isWriting {
                                actions
                                    .transition(.opacity)
                            }
                        }

                        if !drafts.isEmpty {
                            savedDrafts
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                    .readableWidth()
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(BrandPalette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(BrandPalette.goldDeep)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
            .animation(.softFade, value: isWriting)
            .animation(.softFade, value: text.isEmpty)
        }
        .onDisappear { writing?.cancel() }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: String(localized: "For \(ActiveWedding.couple)"))
            Text("Write a toast")
                .brandFont(.screenTitle)
                .foregroundStyle(BrandPalette.ink)
            GoldRule(width: 58, alignment: .leading)
                .padding(.top, 2)
            Text(usesModel
                 ? "Written by Apple Intelligence on your iPhone. Nothing you type leaves your phone."
                 : "Built from a template on your iPhone. Nothing you type leaves your phone.")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 22) {
            field(String(localized: "Your name")) {
                TextField("First name", text: $input.name)
                    .textContentType(.givenName)
                    .focused($focused, equals: .name)
                    .brandFont(.bodyText)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(inputBackground)
            }

            field(String(localized: "You are their…")) {
                ChipFlow(items: ToastRelationship.allCases, selection: input.relationship, label: \.label) {
                    input.relationship = $0
                }
            }

            field(String(localized: "Tone")) {
                ChipFlow(items: ToastTone.allCases, selection: input.tone, label: \.label) {
                    input.tone = $0
                }
            }

            field(String(localized: "Length")) {
                ChipFlow(items: ToastLength.allCases, selection: input.length, label: \.label) {
                    input.length = $0
                }
            }

            field(String(localized: "A memory or two")) {
                VStack(alignment: .trailing, spacing: 6) {
                    TextField("How you met, a trip, a moment you'll never forget…", text: $input.memories, axis: .vertical)
                        .lineLimit(3...7)
                        .focused($focused, equals: .memories)
                        .brandFont(.bodyText)
                        .padding(14)
                        .background(inputBackground)
                        .onChange(of: input.memories) { _, value in
                            if value.count > 300 { input.memories = String(value.prefix(300)) }
                        }
                    Text("\(input.memories.count)/300")
                        .font(BrandLabel.font(size: 10, weight: .medium))
                        .foregroundStyle(BrandPalette.body.opacity(0.7))
                        .accessibilityLabel(Text("\(input.memories.count) of 300 characters"))
                }
            }

            field(String(localized: "Mix in another language (optional)")) {
                TextField("e.g. Punjabi, Hindi, Spanish", text: $input.languageMix)
                    .focused($focused, equals: .language)
                    .brandFont(.bodyText)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(inputBackground)
            }
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(BrandPalette.card)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title, size: 10.5)
            content()
        }
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PrivateBadge()

            if !text.title.isEmpty {
                Text(text.title)
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.ink)
            }

            ForEach([text.opening, text.body, text.closing].filter { !$0.isEmpty }, id: \.self) { paragraph in
                Text(paragraph)
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isWriting {
                GoldCaret(isAnimated: !reduceMotion)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isWriting ? String(localized: "Writing your toast. \(text.plainText)") : text.plainText))
    }

    private var actions: some View {
        WrapLayout(spacing: 10) {
            WriterSecondaryButton(title: String(localized: "Make it shorter"), symbol: "arrow.down.right.and.arrow.up.left") {
                write(adjustment: .shorter)
            }
            WriterSecondaryButton(title: String(localized: "Make it funnier"), symbol: "face.smiling") {
                write(adjustment: .funnier)
            }
            WriterSecondaryButton(title: didCopy ? String(localized: "Copied") : String(localized: "Copy"), symbol: didCopy ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = text.plainText
                withAnimation(.softFade) { didCopy = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.softFade) { didCopy = false }
                }
            }
            ShareLink(item: text.plainText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(BrandLabel.font(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(BrandPalette.goldDeep)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .overlay(Capsule().stroke(BrandPalette.gold.opacity(0.6), lineWidth: 1))
            }
        }
    }

    private var savedDrafts: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(text: String(localized: "Your drafts"))
            ForEach(drafts) { draft in
                Button {
                    BrandHaptics.tick()
                    writing?.cancel()
                    withAnimation(.softFade) {
                        input = draft.input
                        text = draft.text
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.text.title.isEmpty ? String(localized: "Untitled toast") : draft.text.title)
                                .brandFont(.bodyText)
                                .foregroundStyle(BrandPalette.ink)
                            Text("\(draft.input.tone.label) · \(draft.input.length.label) · \(draft.savedAt.formatted(date: .abbreviated, time: .shortened))")
                                .brandFont(.bodySmall)
                                .foregroundStyle(BrandPalette.body)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(BrandPalette.gold)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .contextMenu {
                    Button("Delete draft", systemImage: "trash", role: .destructive) {
                        withAnimation(.softFade) { drafts.removeAll { $0.id == draft.id } }
                        ToastDraftStore.save(drafts)
                    }
                }
            }
        }
    }

    // MARK: Writing

    private var context: ToastContext {
        let wedding = ActiveWedding.snapshot
        let event: ScheduleEvent? = {
            if let eventID, let match = schedule.events.first(where: { $0.id == eventID }) { return match }
            return schedule.events.first { $0.title.localizedCaseInsensitiveContains("reception") } ?? schedule.mainCeremony
        }()
        return ToastContext(
            partnerOne: wedding.partnerOne,
            partnerTwo: wedding.partnerTwo,
            eventTitle: event?.title,
            city: wedding.city,
            storyTitles: content.storyChapters.compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        )
    }

    private func write(adjustment: ToastAdjustment?) {
        writing?.cancel()
        ToastDraftStore.remember(input)
        let previous = adjustment == nil ? nil : text
        let request = input
        let context = context
        isWriting = true
        if adjustment == nil { text = .empty }
        writing = Task {
            var latest = ToastText.empty
            for await partial in OnDeviceWriter.streamToast(request, context: context, adjusting: previous, adjustment: adjustment) {
                guard !Task.isCancelled else { break }
                latest = partial
                if reduceMotion {
                    text = partial
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { text = partial }
                }
            }
            guard !Task.isCancelled else { return }
            isWriting = false
            if !latest.isEmpty {
                text = latest
                BrandHaptics.soft()
                drafts.insert(ToastDraftStore.Draft(input: request, text: latest), at: 0)
                drafts = Array(drafts.prefix(8))
                ToastDraftStore.save(drafts)
            }
        }
    }
}

/// The blinking gold caret at the end of a draft being written.
private struct GoldCaret: View {
    let isAnimated: Bool
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(BrandPalette.gold)
            .frame(width: 2, height: 20)
            .opacity(visible ? 1 : 0.15)
            .onAppear {
                guard isAnimated else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { visible = false }
            }
            .accessibilityHidden(true)
    }
}
