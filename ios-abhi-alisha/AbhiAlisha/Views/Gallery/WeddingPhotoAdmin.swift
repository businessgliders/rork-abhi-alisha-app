import PhotosUI
import SwiftUI
import UIKit

/// Where the couple's next Wedding Week photos come from.
enum WeddingAddSource: String, Identifiable {
    case library
    case camera

    var id: String { rawValue }
}

// MARK: - Add button

/// "+ Add photos": a small menu for the library (up to 50) or the camera.
struct AddWeddingPhotosButton: View {
    @Binding var source: WeddingAddSource?

    var body: some View {
        Menu {
            Button("Choose from Library", systemImage: "photo.on.rectangle") {
                source = .library
            }
            Button("Take Photo", systemImage: "camera") {
                source = .camera
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("Add photos")
                    .font(BrandLabel.font(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Color(hex: 0xFFFBF1))
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .simultaneousGesture(TapGesture().onEnded { BrandHaptics.tick() })
        .accessibilityLabel("Add wedding week photos")
    }
}

// MARK: - Upload progress

/// "Uploading 12 of 23", with a gold bar; it waits quietly while offline.
struct WeddingUploadProgress: View {
    @State private var store = WeddingPhotoStore.shared

    var body: some View {
        if store.isUploadingAnything {
            let total = max(store.runTotal, store.queue.count)
            let done = store.uploadedInRun
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: store.isOnline ? "arrow.up.circle" : "wifi.slash")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(BrandPalette.goldDeep)
                    Text(store.isOnline
                         ? "Uploading \(min(done + 1, total)) of \(total)"
                         : "Waiting for a connection · \(done) of \(total) uploaded")
                        .font(BrandLabel.font(size: 11.5, weight: .semibold))
                        .foregroundStyle(BrandPalette.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(BrandPalette.hairline)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [BrandPalette.goldPale, BrandPalette.gold, BrandPalette.goldDeep],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, proxy.size.width * CGFloat(done) / CGFloat(max(total, 1))))
                    }
                }
                .frame(height: 5)
                .animation(.calm, value: done)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BrandPalette.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BrandPalette.gold.opacity(0.35), lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Picking and reviewing

extension View {
    /// Library picker, camera, preparation and the review sheet, for the couple.
    func weddingPhotoAdder(source: Binding<WeddingAddSource?>, originEventID: String?) -> some View {
        modifier(WeddingPhotoAdder(source: source, originEventID: originEventID))
    }

    /// The couple's press-and-hold actions on a photo.
    func weddingPhotoActions(photo: WeddingPhoto, events: [ScheduleEvent], isEnabled: Bool) -> some View {
        modifier(WeddingPhotoActions(photo: photo, events: events, isEnabled: isEnabled))
    }
}

private struct WeddingPhotoAdder: ViewModifier {
    @Binding var source: WeddingAddSource?
    let originEventID: String?

    @Environment(ScheduleStore.self) private var schedule
    @State private var picks: [PhotosPickerItem] = []
    @State private var prepared: [PreparedWeddingPhoto] = []
    @State private var isReviewing = false
    @State private var preparing: (done: Int, total: Int)?
    @State private var didSkip = false

    private var libraryBinding: Binding<Bool> {
        Binding(get: { source == .library }, set: { if !$0, source == .library { source = nil } })
    }

    private var cameraBinding: Binding<Bool> {
        Binding(get: { source == .camera }, set: { if !$0, source == .camera { source = nil } })
    }

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: libraryBinding,
                selection: $picks,
                maxSelectionCount: 50,
                selectionBehavior: .ordered,
                matching: .images,
                preferredItemEncoding: .current
            )
            .onChange(of: picks) { _, items in
                guard !items.isEmpty else { return }
                prepareLibrary(items)
            }
            .fullScreenCover(isPresented: cameraBinding) {
                OutfitCameraView { image in
                    prepareCamera(image)
                }
            }
            .sheet(isPresented: $isReviewing, onDismiss: discardUnsent) {
                WeddingReviewSheet(
                    items: $prepared,
                    events: WeddingWeek.events(from: schedule.events),
                    didSkip: didSkip
                ) {
                    WeddingPhotoStore.shared.enqueue(prepared)
                    prepared = []
                    isReviewing = false
                }
            }
            .overlay {
                if let preparing {
                    PreparingOverlay(done: preparing.done, total: preparing.total)
                        .transition(.opacity)
                }
            }
            .animation(.softFade, value: preparing?.done)
    }

    private func prepareLibrary(_ items: [PhotosPickerItem]) {
        picks = []
        let events = WeddingWeek.events(from: schedule.events)
        preparing = (0, items.count)
        Task {
            var results: [PreparedWeddingPhoto] = []
            var skipped = 0
            for (offset, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ready = await make(data, fallback: nil, events: events) {
                    results.append(ready)
                } else {
                    skipped += 1
                }
                preparing = (offset + 1, items.count)
            }
            preparing = nil
            present(results, skipped: skipped)
        }
    }

    private func prepareCamera(_ image: UIImage) {
        let events = WeddingWeek.events(from: schedule.events)
        preparing = (0, 1)
        Task {
            // Give the camera a moment to close before the review rises.
            try? await Task.sleep(for: .milliseconds(450))
            var results: [PreparedWeddingPhoto] = []
            if let data = image.jpegData(compressionQuality: 0.95),
               let ready = await make(data, fallback: Date(), events: events) {
                results.append(ready)
            }
            preparing = nil
            present(results, skipped: results.isEmpty ? 1 : 0)
        }
    }

    private func make(_ data: Data, fallback: Date?, events: [ScheduleEvent]) async -> PreparedWeddingPhoto? {
        guard let output = await WeddingPhotoProcessor.prepare(data, fallbackDate: fallback),
              let preview = UIImage(data: output.thumbData) else { return nil }
        let eventID = WeddingPhotoTagger.eventID(
            for: output.takenAt,
            in: events,
            now: Date(),
            origin: originEventID
        )
        return PreparedWeddingPhoto(
            id: UUID(),
            fullName: output.fullName,
            thumbName: output.thumbName,
            preview: preview,
            takenAt: output.takenAt,
            eventID: eventID
        )
    }

    private func present(_ results: [PreparedWeddingPhoto], skipped: Int) {
        guard !results.isEmpty else {
            WeddingPhotoStore.shared.notice = "Those photos couldn't be opened. Please try others."
            return
        }
        prepared = results
        didSkip = skipped > 0
        isReviewing = true
    }

    /// Closing the review without uploading clears the staged files.
    private func discardUnsent() {
        guard !prepared.isEmpty else { return }
        WeddingPhotoProcessor.discard(prepared.flatMap { [$0.fullName, $0.thumbName] })
        prepared = []
    }
}

private struct PreparingOverlay: View {
    let done: Int
    let total: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(BrandPalette.goldDeep)
                Text(total > 1 ? "Preparing \(done) of \(total)" : "Preparing your photo")
                    .font(BrandLabel.font(size: 12, weight: .semibold))
                    .foregroundStyle(BrandPalette.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BrandPalette.card))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Photos grouped by the celebration they were matched to. Each group can be moved to
/// another event, each photo can take a caption, and a star chooses the cover.
private struct WeddingReviewSheet: View {
    @Binding var items: [PreparedWeddingPhoto]
    let events: [ScheduleEvent]
    let didSkip: Bool
    let onUpload: () -> Void

    @Environment(\.dismiss) private var dismiss

    private struct Group: Identifiable {
        let eventID: String?
        let ids: [UUID]
        var id: String { eventID ?? "unassigned" }
    }

    /// Unmatched photos first (they need a choice), then the celebrations in order.
    private var groups: [Group] {
        var result: [Group] = []
        let unassigned = items.filter { $0.eventID == nil }.map(\.id)
        if !unassigned.isEmpty { result.append(Group(eventID: nil, ids: unassigned)) }
        for event in events {
            let ids = items.filter { $0.eventID == event.id }.map(\.id)
            if !ids.isEmpty { result.append(Group(eventID: event.id, ids: ids)) }
        }
        // Anything matched to a celebration that has since left the schedule.
        let known = Set(events.map(\.id))
        let orphans = items.filter { $0.eventID.map { !known.contains($0) } ?? false }.map(\.id)
        if !orphans.isEmpty { result.append(Group(eventID: "__other", ids: orphans)) }
        return result
    }

    private var canUpload: Bool {
        let known = Set(events.map(\.id))
        return !items.isEmpty && items.allSatisfy { $0.eventID.map(known.contains) ?? false }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Each photo was matched to the celebration it was taken at. Change a group's event if needed, add captions, and star a cover.")
                        .brandFont(.bodyItalic)
                        .foregroundStyle(BrandPalette.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if didSkip {
                        Text("A few photos couldn't be opened and were left out.")
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.overdue)
                            .padding(.top, 10)
                    }

                    ForEach(groups) { group in
                        groupView(group)
                            .padding(.top, 28)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
                .readableWidth(720)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(BrandPalette.background.ignoresSafeArea())
            .navigationTitle("Review photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(BrandPalette.goldDeep)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GoldActionButton(
                    title: items.count == 1 ? "Upload 1 photo" : "Upload \(items.count) photos",
                    systemImage: "arrow.up",
                    isEnabled: canUpload
                ) {
                    BrandHaptics.soft()
                    onUpload()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .readableWidth(560)
                .background(BrandPalette.background.opacity(0.96).ignoresSafeArea())
            }
        }
        .presentationDetents([.large])
        .presentationSizing(.page)
        .interactiveDismissDisabled()
    }

    private func groupView(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: group.ids.count == 1 ? "1 photo" : "\(group.ids.count) photos", size: 9.5)
                    Text(title(for: group.eventID))
                        .brandFont(.eventTitleSmall)
                        .foregroundStyle(group.eventID == nil ? BrandPalette.overdue : BrandPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Menu {
                    ForEach(events) { event in
                        Button(event.title) { assign(group.ids, to: event.id) }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(group.eventID == nil ? "Choose event" : "Change")
                            .font(BrandLabel.font(size: 10.5, weight: .semibold))
                            .tracking(1.1)
                            .textCase(.uppercase)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(BrandPalette.goldDeep)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .overlay(Capsule().stroke(BrandPalette.gold.opacity(0.55), lineWidth: 1))
                    .contentShape(Capsule())
                }
            }

            VStack(spacing: 10) {
                ForEach(group.ids, id: \.self) { id in
                    if let index = items.firstIndex(where: { $0.id == id }) {
                        ReviewRow(
                            item: $items[index],
                            canBeCover: group.eventID != nil,
                            onStar: { toggleCover(id) },
                            onRemove: { remove(id) }
                        )
                    }
                }
            }
        }
    }

    private func title(for eventID: String?) -> String {
        guard let eventID else { return "Choose a celebration" }
        return events.first { $0.id == eventID }?.title ?? "No longer on the schedule"
    }

    private func assign(_ ids: [UUID], to eventID: String) {
        BrandHaptics.tick()
        withAnimation(.calm) {
            let hasCover = items.contains { $0.eventID == eventID && $0.isCover && !ids.contains($0.id) }
            for index in items.indices where ids.contains(items[index].id) {
                items[index].eventID = eventID
                // Joining a group that already has a cover keeps that one.
                if hasCover { items[index].isCover = false }
            }
            // At most one cover per celebration.
            var seenCover = false
            for index in items.indices where items[index].eventID == eventID && items[index].isCover {
                if seenCover { items[index].isCover = false }
                seenCover = true
            }
        }
    }

    private func toggleCover(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        BrandHaptics.tick()
        let eventID = items[index].eventID
        let turningOn = !items[index].isCover
        withAnimation(.calm) {
            for other in items.indices where items[other].eventID == eventID {
                items[other].isCover = false
            }
            items[index].isCover = turningOn
        }
    }

    private func remove(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        BrandHaptics.tick()
        WeddingPhotoProcessor.discard([item.fullName, item.thumbName])
        withAnimation(.calm) { items.removeAll { $0.id == id } }
        if items.isEmpty { dismiss() }
    }
}

private struct ReviewRow: View {
    @Binding var item: PreparedWeddingPhoto
    let canBeCover: Bool
    let onStar: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Color(BrandPalette.hairline)
                .frame(width: 72, height: 72)
                .overlay {
                    Image(uiImage: item.preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Add a caption", text: $item.caption, axis: .vertical)
                    .lineLimit(1...3)
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.ink)
                    .tint(BrandPalette.goldDeep)
                    .onChange(of: item.caption) { _, value in
                        if value.count > 200 { item.caption = String(value.prefix(200)) }
                    }
                if let takenAt = item.takenAt {
                    Text(takenAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .font(BrandLabel.font(size: 10, weight: .medium))
                        .foregroundStyle(BrandPalette.body.opacity(0.75))
                }
            }

            Spacer(minLength: 0)

            if canBeCover {
                Button(action: onStar) {
                    Image(systemName: item.isCover ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(item.isCover ? BrandPalette.goldDeep : BrandPalette.body.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .symbolEffect(.bounce, value: item.isCover)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isCover ? "Cover photo" : "Make cover photo")
            }

            Menu {
                Button("Remove from upload", systemImage: "xmark", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BrandPalette.body)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BrandPalette.card))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(item.isCover ? BrandPalette.gold.opacity(0.6) : BrandPalette.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Managing a photo

private struct WeddingPhotoActions: ViewModifier {
    let photo: WeddingPhoto
    let events: [ScheduleEvent]
    let isEnabled: Bool

    @State private var store = WeddingPhotoStore.shared
    @State private var isEditingCaption = false
    @State private var captionDraft = ""
    @State private var isConfirmingDelete = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contextMenu {
                    Button("Edit Caption", systemImage: "text.quote") {
                        captionDraft = photo.caption ?? ""
                        isEditingCaption = true
                    }
                    Menu("Move to Another Event", systemImage: "arrow.right.square") {
                        ForEach(events.filter { $0.id != photo.eventID }) { event in
                            Button(event.title) {
                                Task { await store.move(photo, to: event.id) }
                            }
                        }
                    }
                    if !photo.isCover {
                        Button("Make Cover", systemImage: "star") {
                            Task { await store.makeCover(photo) }
                        }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
                .alert("Caption", isPresented: $isEditingCaption) {
                    TextField("Add a caption", text: $captionDraft)
                    Button("Save") {
                        let text = String(captionDraft.prefix(200))
                        Task { _ = await store.setCaption(text, for: photo) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .confirmationDialog("Delete this photo?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete for Everyone", role: .destructive) {
                        Task { await store.delete(photo) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("It will be removed from Wedding Week for every guest.")
                }
        } else {
            content
        }
    }
}
