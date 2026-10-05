import SwiftUI

/// The admin's composer at the foot of the Announcements chat: a title, a message that
/// grows to five lines, the "Opens to" pill above Send, and a gold send arrow.
struct AnnouncementComposer: View {
    let onSend: () -> Void

    @State private var draft = AnnouncementDraft.shared
    @Environment(ScheduleStore.self) private var store
    @FocusState private var focus: Field?

    private enum Field { case title, body }

    var body: some View {
        @Bindable var draft = draft

        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 10) {
                if let counter {
                    Text(counter)
                        .font(BrandLabel.font(size: 10, weight: .medium))
                        .foregroundStyle(BrandPalette.body.opacity(0.7))
                        .monospacedDigit()
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                AnnouncementOpensToMenu()
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    TextField(
                        "Title",
                        text: $draft.title,
                        prompt: AdminExample.prompt("Shuttle to the Sangeet")
                    )
                    .brandFont(.chatName)
                    .foregroundStyle(BrandPalette.ink)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .focused($focus, equals: .title)
                    .onSubmit { focus = .body }
                    .padding(.vertical, 9)

                    Rectangle()
                        .fill(BrandPalette.hairline)
                        .frame(height: 1)

                    TextField(
                        "Message",
                        text: $draft.body,
                        prompt: AdminExample.prompt("Shuttles leave the main lobby at 6:30 PM."),
                        axis: .vertical
                    )
                    .lineLimit(1...5)
                    .brandFont(.chatMessage)
                    .foregroundStyle(BrandPalette.ink)
                    .textInputAutocapitalization(.sentences)
                    .focused($focus, equals: .body)
                    .padding(.vertical, 9)
                }
                .tint(BrandPalette.goldDeep)
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(BrandPalette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(focus != nil ? BrandPalette.gold.opacity(0.55) : BrandPalette.hairline, lineWidth: 1)
                )
                .animation(.calm, value: focus)

                Button {
                    focus = nil
                    onSend()
                } label: {
                    Image(systemName: "paperplane")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFFFBF1))
                        .frame(width: 46, height: 46)
                        .background(
                            Circle().fill(
                                LinearGradient(
                                    colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        )
                        .overlay(Circle().stroke(Color(hex: 0xE0C982).opacity(0.5), lineWidth: 0.75))
                        .opacity(draft.canSend ? 1 : 0.4)
                        .scaleEffect(draft.canSend ? 1 : 0.92)
                        .animation(.calm, value: draft.canSend)
                }
                .buttonStyle(PressableStyle())
                .disabled(!draft.canSend)
                .accessibilityLabel("Send announcement")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .readableWidth(720)
        .background(
            BrandPalette.background
                .overlay(alignment: .top) {
                    Rectangle().fill(BrandPalette.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.softFade, value: counter)
        .onChange(of: draft.title) { _, _ in draft.redetect(events: store.events) }
        .onChange(of: draft.body) { _, _ in draft.redetect(events: store.events) }
        .onChange(of: store.events.count) { _, _ in draft.redetect(events: store.events) }
    }

    /// How much room is left in the field being typed in.
    private var counter: String? {
        switch focus {
        case .title:
            return draft.title.isEmpty ? nil : "\(draft.title.count)/\(AnnouncementDraft.titleLimit)"
        case .body:
            return draft.body.isEmpty ? nil : "\(draft.body.count)/\(AnnouncementDraft.bodyLimit)"
        case nil:
            return nil
        }
    }
}

/// The small "Opens to" pill: where a tap on the notification takes guests. It follows
/// the words until the admin picks a place, and says "Auto" while it does.
struct AnnouncementOpensToMenu: View {
    @State private var draft = AnnouncementDraft.shared
    @Environment(ScheduleStore.self) private var store

    private var events: [ScheduleEvent] {
        store.events.filter { $0.isActive != false }
    }

    var body: some View {
        Menu {
            Section {
                ForEach(AnnouncementDestination.screens, id: \.self) { option($0) }
            }
            if !events.isEmpty {
                Section("A celebration") {
                    ForEach(events) { event in
                        option(.event(id: event.id, title: event.title.trimmed))
                    }
                }
            }
            Section {
                ForEach(AnnouncementDestination.more, id: \.self) { option($0) }
            }
            if !draft.isAuto {
                Section {
                    Button {
                        BrandHaptics.tick()
                        draft.resumeAuto(events: store.events)
                    } label: {
                        Label("Choose automatically", systemImage: "wand.and.stars")
                    }
                }
            }
        } label: {
            pill
        }
        .accessibilityLabel("Opens to \(draft.destination.label)\(draft.isAuto ? ", chosen automatically" : "")")
    }

    private var pill: some View {
        HStack(spacing: 6) {
            Text("OPENS")
                .font(BrandLabel.font(size: 8.5, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.body.opacity(0.8))

            Image(systemName: draft.destination.symbolName)
                .font(.system(size: 10.5, weight: .medium))

            Text(draft.destination.label)
                .font(BrandLabel.font(size: 11.5, weight: .semibold))
                .lineLimit(1)

            if draft.isAuto {
                Text("AUTO")
                    .font(BrandLabel.font(size: 7.5, weight: .bold))
                    .tracking(0.9)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(BrandPalette.gold.opacity(0.2)))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(BrandPalette.body.opacity(0.7))
        }
        .foregroundStyle(BrandPalette.goldDeep)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .frame(maxWidth: 280)
        .background(Capsule(style: .continuous).fill(BrandPalette.card))
        .overlay(Capsule(style: .continuous).stroke(BrandPalette.gold.opacity(0.45), lineWidth: 1))
        .contentShape(Capsule(style: .continuous))
        .animation(.calm, value: draft.destination)
        .animation(.calm, value: draft.isAuto)
    }

    private func option(_ destination: AnnouncementDestination) -> some View {
        let current = draft.destination
        let isSelected = destination.screen == current.screen && destination.eventID == current.eventID
        return Button {
            BrandHaptics.tick()
            draft.choose(destination)
        } label: {
            Label(destination.label, systemImage: isSelected ? "checkmark" : destination.symbolName)
        }
    }
}
