import SwiftUI
import UIKit

/// Every celebration, as stored. Tap one to change its details.
struct AdminTimelineView: View {
    /// Asks the couple's area to prepare a note about a changed celebration.
    let onNotify: (String) -> Void

    @State private var entries: [TimelineEntry] = []
    @State private var editing: TimelineEntry?
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AdminHeader(eyebrow: "The celebrations", title: "Timeline")

                Text("Tap a celebration to update its details. Guests see changes the next time their schedule refreshes.")
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                if entries.isEmpty {
                    AdminNote(
                        text: loadFailed
                            ? "The celebrations will appear here once you're connected."
                            : "No celebrations yet.",
                        symbol: "calendar"
                    )
                    .padding(.top, 20)
                } else {
                    VStack(spacing: 12) {
                        ForEach(entries) { entry in
                            EntryRow(entry: entry) {
                                BrandHaptics.soft()
                                editing = entry
                            }
                        }
                    }
                    .padding(.top, 24)
                }

                AdminLockFooter()
                    .padding(.top, 30)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, FloatingTabBar.contentReserve + 20)
            .readableWidth()
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .sheet(item: $editing) { entry in
            EventEditorSheet(
                entry: entry,
                onSaved: replace,
                onNotify: onNotify
            )
        }
        .task {
            if entries.isEmpty { loadLocal() }
            await refresh()
        }
        .refreshable {
            await refresh()
        }
    }

    private func replace(_ updated: TimelineEntry) {
        guard let index = entries.firstIndex(where: { $0.id == updated.id }) else { return }
        withAnimation(.calm) { entries[index] = updated }
    }

    /// The last copy seen, or the one shipped with the app.
    private func loadLocal() {
        let data = ScheduleCache.shared.loadRaw()
            ?? Bundle.main.url(forResource: "schedule_snapshot", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        guard let data, let rows = try? JSONDecoder().decode([JSONValue].self, from: data) else { return }
        entries = TimelineEntry.entries(from: rows)
    }

    private func refresh() async {
        do {
            let result = try await WeddingAPI.shared.fetch(JSONValue.self, entity: "ScheduleEvent")
            let fresh = TimelineEntry.entries(from: result.items)
            guard !fresh.isEmpty else { return }
            withAnimation(.calm) { entries = fresh }
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}

private struct EntryRow: View {
    let entry: TimelineEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MatteCard(cornerRadius: 20) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title ?? "Untitled celebration")
                            .brandFont(.eventTitleSmall)
                            .foregroundStyle(BrandPalette.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if let summary = entry.summary {
                            Text(summary)
                                .brandFont(.bodySmall)
                                .foregroundStyle(BrandPalette.body)
                        }

                        if let location = entry.locationName {
                            Text(location)
                                .brandFont(.bodyItalic)
                                .foregroundStyle(BrandPalette.goldDeep)
                        }

                        if !entry.isActive {
                            BrandPill(text: "Hidden from guests")
                                .padding(.top, 6)
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(BrandPalette.goldDeep)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(BrandPalette.gold.opacity(0.45), lineWidth: 1))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topTrailing) {
                    IconWatermark(key: entry.iconKey, size: 70, opacity: 0.1)
                        .padding(.top, 8)
                        .padding(.trailing, 56)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Edit this celebration")
    }
}

// MARK: - Editor

/// Only the eight editable fields — never ids, order, coordinates or anything else.
private struct EventEditorSheet: View {
    let entry: TimelineEntry
    let onSaved: (TimelineEntry) -> Void
    let onNotify: (String) -> Void

    @Environment(AdminSession.self) private var session
    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let original: EventDraft
    @State private var draft: EventDraft
    @State private var isConfirming = false
    @State private var isSaving = false
    @State private var didSave = false
    @State private var errorMessage: String?

    init(entry: TimelineEntry, onSaved: @escaping (TimelineEntry) -> Void, onNotify: @escaping (String) -> Void) {
        self.entry = entry
        self.onSaved = onSaved
        self.onNotify = onNotify
        let start = EventDraft(entry: entry)
        original = start
        _draft = State(initialValue: start)
    }

    private var changes: [String: JSONValue] { draft.changes(from: original) }

    var body: some View {
        ScrollView {
            Group {
                if didSave {
                    savedState
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    form
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
            .readableWidth(560)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(BrandPalette.background.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving || (!changes.isEmpty && !didSave))
        .animation(.calm, value: didSave)
        .animation(.softFade, value: errorMessage)
        .confirmationDialog(
            "Save changes to \(draft.title.nonEmpty ?? "this celebration")?",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Save changes") { save() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Guests will see the new details the next time their schedule refreshes.")
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Edit celebration")
                Text(original.title.nonEmpty ?? "Celebration")
                    .brandFont(.eventTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                GoldRule(width: 44, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(.top, 28)
            .padding(.bottom, 4)

            AdminField(label: "Title") {
                TextField("Welcome Party", text: $draft.title)
                    .textInputAutocapitalization(.words)
            }

            HStack(alignment: .top, spacing: 12) {
                AdminField(label: "Date") {
                    TextField("Saturday, January 30, 2027", text: $draft.date, axis: .vertical)
                        .lineLimit(1...2)
                }
                AdminField(label: "Time") {
                    TextField("7:00 PM", text: $draft.time)
                }
                .frame(maxWidth: 150)
            }

            Text("Date and time are shown to guests exactly as written. Start and end set the countdown, widgets and Live Activity.")
                .brandFont(.bodySmall)
                .foregroundStyle(BrandPalette.body.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            OptionalDateField(label: "Starts", date: $draft.startsAt, fallback: original.startsAt ?? Date())
            OptionalDateField(label: "Ends", date: $draft.endsAt, fallback: draft.startsAt?.addingTimeInterval(3 * 3600) ?? Date())

            AdminField(label: "Location") {
                TextField("Sunny's Patio", text: $draft.locationName)
                    .textInputAutocapitalization(.words)
            }

            AdminField(label: "Dress code") {
                TextField("Semi-formal", text: $draft.dressCode, axis: .vertical)
                    .lineLimit(1...3)
            }

            AdminField(label: "Description") {
                TextField("What guests should know", text: $draft.description, axis: .vertical)
                    .lineLimit(4...12)
            }

            if let errorMessage {
                Text(errorMessage)
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            GoldActionButton(
                title: "Save changes",
                isBusy: isSaving,
                isEnabled: !changes.isEmpty && draft.isValid
            ) {
                errorMessage = nil
                isConfirming = true
            }
            .padding(.top, 6)

            Button(changes.isEmpty ? "Close" : "Discard changes") { dismiss() }
                .font(BrandLabel.font(size: 12, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.body)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isSaving)
        }
    }

    // MARK: Saved

    private var savedState: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(BrandPalette.goldDeep)
                .frame(width: 78, height: 78)
                .background(Circle().fill(BrandPalette.card))
                .overlay(Circle().stroke(BrandPalette.gold.opacity(0.55), lineWidth: 1))
                .shadow(color: BrandPalette.gold.opacity(0.22), radius: 18)
                .padding(.top, 60)

            Text("Saved")
                .brandFont(.eventTitle)
                .foregroundStyle(BrandPalette.ink)
                .padding(.top, 22)

            GoldRule(width: 40)
                .padding(.top, 12)

            Text("Notify guests of this change?")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            GoldActionButton(title: "Notify guests", systemImage: "paperplane") {
                let name = draft.title.trimmed
                dismiss()
                onNotify(name)
            }
            .padding(.top, 30)

            Button("Not now") { dismiss() }
                .font(BrandLabel.font(size: 12, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.body)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Save

    private func save() {
        let payload = changes
        guard let code = session.code, !payload.isEmpty, !isSaving else { return }
        isSaving = true

        Task {
            do {
                let returned = try await AdminService.shared.updateEvent(id: entry.id, data: payload, code: code)
                var updated = entry
                if let returned, returned["id"] != nil {
                    updated.fields = returned
                } else {
                    for (key, value) in payload {
                        if value.isNull {
                            updated.fields.removeValue(forKey: key)
                        } else {
                            updated.fields[key] = value
                        }
                    }
                }
                onSaved(updated)
                isSaving = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                didSave = true
                // The guest schedule, widgets and Live Activity pick up the change now.
                await store.refresh()
            } catch AdminError.unauthorized {
                isSaving = false
                session.invalidate()
            } catch {
                isSaving = false
                errorMessage = "Couldn't save just now. Your edits are still here, so try again once you're connected."
            }
        }
    }
}

/// A moment in Cancún time that may be left unset.
private struct OptionalDateField: View {
    let label: String
    @Binding var date: Date?
    let fallback: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: label, size: 9.5)

            HStack(spacing: 12) {
                if let value = date {
                    DatePicker(
                        label,
                        selection: Binding(get: { value }, set: { date = $0 }),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .tint(BrandPalette.goldDeep)
                    .environment(\.timeZone, EventTime.zone)

                    Spacer(minLength: 0)

                    Button {
                        BrandHaptics.tick()
                        date = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BrandPalette.body)
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(BrandPalette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(label.lowercased()) time")
                } else {
                    Button {
                        BrandHaptics.tick()
                        date = fallback
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Set \(label.lowercased()) time")
                                .font(BrandLabel.font(size: 12, weight: .semibold))
                                .tracking(1)
                        }
                        .foregroundStyle(BrandPalette.goldDeep)
                        .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BrandPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BrandPalette.gold.opacity(0.3), lineWidth: 1)
            )

            Text("Cancún time")
                .font(BrandLabel.font(size: 9.5, weight: .medium))
                .foregroundStyle(BrandPalette.body.opacity(0.6))
        }
    }
}
