import SwiftUI

/// Where an announcement is written: a full sheet with the title, the message, where it
/// opens, and a live preview of exactly how the front card will look, in its colour.
/// Nothing goes out here — Send hands the note to the one-line confirmation.
struct NewAnnouncementSheet: View {
    let events: [ScheduleEvent]
    /// Hands the finished note up to the confirmation step.
    let onCompose: (String, String, AnnouncementDestination) -> Void

    @State private var draft = AnnouncementDraft.shared
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    private enum Field { case title, body }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Announcement", size: 10)
                        .padding(.top, 24)

                    Text("Write to every guest")
                        .brandFont(.eventTitleSmall)
                        .foregroundStyle(BrandPalette.ink)
                        .padding(.top, 8)

                    GoldRule(width: 40)
                        .padding(.top, 12)

                    fields
                        .padding(.top, 22)

                    HStack(spacing: 10) {
                        Text("OPENS TO")
                            .font(BrandLabel.font(size: 8.5, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(BrandPalette.body.opacity(0.8))
                        AnnouncementOpensToMenu()
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 16)

                    preview
                        .padding(.top, 26)

                    GoldActionButton(title: "Send", systemImage: "paperplane", isEnabled: draft.canSend) {
                        send()
                    }
                    .padding(.top, 26)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
                .readableWidth(640)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(BrandPalette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        BrandHaptics.tick()
                        dismiss()
                    }
                    .foregroundStyle(BrandPalette.goldDeep)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: draft.title) { _, _ in draft.redetect(events: events) }
        .onChange(of: draft.body) { _, _ in draft.redetect(events: events) }
        .onChange(of: events.count) { _, _ in draft.redetect(events: events) }
    }

    // MARK: - Fields

    private var fields: some View {
        @Bindable var draft = draft
        return VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $draft.title, prompt: AdminExample.prompt("Shuttle to the Sangeet"))
                .brandFont(.chatName)
                .foregroundStyle(BrandPalette.ink)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
                .focused($focus, equals: .title)
                .onSubmit { focus = .body }
                .padding(14)
                .background(paper(focused: focus == .title))

            TextField(
                "Message",
                text: $draft.body,
                prompt: AdminExample.prompt("Shuttles leave the main lobby at 6:30 PM."),
                axis: .vertical
            )
            .lineLimit(3...10)
            .brandFont(.bodyText)
            .foregroundStyle(BrandPalette.ink)
            .textInputAutocapitalization(.sentences)
            .focused($focus, equals: .body)
            .padding(14)
            .background(paper(focused: focus == .body))
        }
        .tint(BrandPalette.goldDeep)
    }

    private func paper(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(BrandPalette.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(focused ? BrandPalette.gold.opacity(0.55) : BrandPalette.hairline, lineWidth: 1)
            )
    }

    // MARK: - Preview

    /// Exactly how the front card will look — same stock, same button rules.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "How the front card looks", size: 9.5)
            AnnouncementCard(
                content: previewContent,
                onOpen: previewDestination == nil ? nil : {}
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The destination as the deck will read it back from the saved screen value, so the
    /// preview matches card-for-card — including when no button will show.
    private var previewDestination: AnnouncementDestination? {
        AnnouncementDestination.resolve(
            screen: draft.destination.screen,
            eventID: draft.destination.eventID,
            events: events
        )
    }

    private var previewContent: AnnouncementCardContent {
        AnnouncementCardContent(
            title: draft.title.nonEmpty ?? "Your headline goes here",
            message: draft.body.nonEmpty ?? "The news for every guest, written in full.",
            sentAt: Date(),
            isLatest: true,
            isNew: false,
            destination: previewDestination
        )
    }

    private func send() {
        guard draft.canSend else { return }
        focus = nil
        onCompose(draft.title, draft.body, draft.destination)
    }
}
