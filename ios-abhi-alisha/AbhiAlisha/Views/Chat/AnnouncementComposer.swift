import SwiftUI

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
