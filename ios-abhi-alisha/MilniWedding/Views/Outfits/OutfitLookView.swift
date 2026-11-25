import PhotosUI
import SwiftUI
import UIKit

/// One celebration's look: the couple's suggestion, the guest's own four slots, and a
/// "Don't forget" list for packing.
struct OutfitLookView: View {
    let eventID: String

    @Environment(ScheduleStore.self) private var schedule
    @State private var outfits = OutfitStore.shared
    @State private var session = ChatSession.shared

    /// What the next photo is for: a new one in a slot, or in place of an existing one.
    private enum PhotoTarget: Equatable {
        case add(OutfitCategory)
        case replace(OutfitItem)
    }

    @State private var target: PhotoTarget?
    @State private var isChoosingSource = false
    @State private var isShowingCamera = false
    @State private var isShowingLibrary = false
    @State private var libraryPicks: [PhotosPickerItem] = []
    @State private var isAskingName = false
    @State private var queuedAfterName: OutfitCategory?
    @State private var noteItem: OutfitItem?
    @State private var viewingItem: OutfitItem?
    @State private var deletingItem: OutfitItem?
    @State private var suggestionPhoto: OutfitPhoto?

    private var event: ScheduleEvent? {
        schedule.events.first { $0.id == eventID }
    }

    var body: some View {
        ScrollView {
            if let event {
                content(for: event)
            } else {
                AdminNote(text: "This celebration isn't on the schedule any more.", symbol: "sparkles")
                    .padding(.top, 80)
            }
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(
            isPresented: $isShowingLibrary,
            selection: $libraryPicks,
            maxSelectionCount: isReplacing ? 1 : 6,
            matching: .images,
            preferredItemEncoding: .compatible
        )
        .onChange(of: libraryPicks) { _, picks in
            guard !picks.isEmpty else { return }
            importLibraryPicks(picks)
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            OutfitCameraView { image in
                use([image])
            }
        }
        .fullScreenCover(item: $suggestionPhoto) { photo in
            OutfitLightbox(photo: photo)
        }
        .fullScreenCover(item: $viewingItem) { item in
            MyOutfitPhotoViewer(item: item)
        }
        .sheet(item: $noteItem) { item in
            OutfitNoteSheet(item: item)
        }
        .sheet(isPresented: $isAskingName) {
            GuestNameSheet(
                eyebrow: "My Outfits",
                detail: "Your outfit photos are saved to your name so they're here on any visit. Only you can see them.",
                actionTitle: "Continue"
            ) {
                if let category = queuedAfterName {
                    queuedAfterName = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        startAdding(to: category)
                    }
                }
            }
        }
        .confirmationDialog("Delete this photo?", isPresented: Binding(
            get: { deletingItem != nil },
            set: { if !$0 { deletingItem = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let item = deletingItem else { return }
                deletingItem = nil
                Task { await outfits.delete(item) }
            }
            Button("Cancel", role: .cancel) { deletingItem = nil }
        }
        .alert("Not saved", isPresented: Binding(
            get: { outfits.notice != nil },
            set: { if !$0 { outfits.notice = nil } }
        )) {
            Button("OK", role: .cancel) { outfits.notice = nil }
        } message: {
            Text(outfits.notice ?? "")
        }
        .task(id: session.userID) {
            outfits.syncUser()
            await outfits.refresh(eventID: eventID)
        }
    }

    // MARK: - Content

    private func content(for event: ScheduleEvent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(event)

            suggestedLook(event)
                .padding(.top, 30)

            myLook
                .padding(.top, 38)

            if let guide = OutfitGuide.forTitle(event.title) {
                OutfitChecklistSection(eventID: eventID, guide: guide)
                    .padding(.top, 38)
            }

            OutfitPrivacyLine()
                .padding(.top, 40)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 48)
        .readableWidth()
    }

    private func header(_ event: ScheduleEvent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "My Outfit")

            Text(event.title)
                .brandFont(.eventTitle)
                .foregroundStyle(BrandPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.trailing, 60)

            if let date = event.displayDate {
                Text(date)
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.body)
                    .padding(.top, 6)
            }

            GoldRule(width: 44, alignment: .leading)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            OutfitProgressRing(filled: outfits.filledSlots(for: eventID), size: 54)
                .padding(.top, 4)
        }
    }

    // MARK: Suggested look

    @ViewBuilder
    private func suggestedLook(_ event: ScheduleEvent) -> some View {
        let photo = event.outfitPhotos?.first { $0.imageURL != nil || $0.lightboxURL != nil }

        if photo != nil || event.dressCode != nil {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "The couple's suggestion", size: 10.5)

                if let photo {
                    Button {
                        BrandHaptics.soft()
                        suggestionPhoto = photo
                    } label: {
                        RemoteImage(url: URL(string: photo.imageURL ?? photo.lightboxURL ?? ""), contentMode: .fit, aspectRatio: 4.0 / 5.0)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 20))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(BrandPalette.gold.opacity(0.3), lineWidth: 0.75)
                            )
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.black.opacity(0.35)))
                                    .padding(12)
                            }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("The couple's suggested look, full screen")
                }

                if let dressCode = event.dressCode {
                    Text(dressCode)
                        .brandFont(.dressCodeLine)
                        .foregroundStyle(BrandPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: My look

    private var myLook: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "My look", size: 10.5)
                Spacer()
                Text("Hold a photo for more")
                    .font(BrandLabel.font(size: 10, weight: .medium))
                    .foregroundStyle(BrandPalette.body.opacity(0.65))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(OutfitCategory.allCases) { category in
                    OutfitSlot(
                        category: category,
                        items: outfits.items(for: eventID, category: category),
                        uploads: outfits.uploads(for: eventID, category: category),
                        busyIDs: outfits.busyItemIDs,
                        onAdd: { startAdding(to: category) },
                        onView: { viewingItem = $0 },
                        onReplace: { item in
                            target = .replace(item)
                            isChoosingSource = true
                        },
                        onNote: { noteItem = $0 },
                        onDelete: { deletingItem = $0 }
                    )
                    // Attached to the slot itself, so on iPad the choice opens as a bubble
                    // pointing at the box that was tapped; on iPhone it rises from the bottom.
                    .confirmationDialog(sourceTitle, isPresented: sourceBinding(for: category), titleVisibility: .visible) {
                        Button("Take Photo") { isShowingCamera = true }
                        Button("Choose from Library") {
                            libraryPicks = []
                            isShowingLibrary = true
                        }
                        Button("Cancel", role: .cancel) { target = nil }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// The slot the next photo belongs to.
    private var targetCategory: OutfitCategory? {
        switch target {
        case .add(let category): return category
        case .replace(let item): return item.kind ?? .outfit
        case .none: return nil
        }
    }

    private func sourceBinding(for category: OutfitCategory) -> Binding<Bool> {
        Binding(
            get: { isChoosingSource && targetCategory == category },
            set: { if !$0 { isChoosingSource = false } }
        )
    }

    private var isReplacing: Bool {
        if case .replace = target { return true }
        return false
    }

    private var sourceTitle: String {
        switch target {
        case .add(let category): return "Add to \(category.title)"
        case .replace: return "Replace photo"
        case .none: return "Add a photo"
        }
    }

    /// A Supabase session is needed first; a guest with none gives just a name.
    private func startAdding(to category: OutfitCategory) {
        BrandHaptics.soft()
        guard session.isSignedIn else {
            queuedAfterName = category
            isAskingName = true
            return
        }
        target = .add(category)
        isChoosingSource = true
    }

    private func importLibraryPicks(_ picks: [PhotosPickerItem]) {
        Task {
            var images: [UIImage] = []
            for pick in picks {
                if let data = try? await pick.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            libraryPicks = []
            if images.isEmpty {
                outfits.notice = "That photo couldn't be opened. Please try another."
                target = nil
                return
            }
            use(images)
        }
    }

    private func use(_ images: [UIImage]) {
        guard let target else { return }
        self.target = nil
        switch target {
        case .add(let category):
            for image in images {
                Task { await outfits.add(image, eventID: eventID, category: category) }
            }
        case .replace(let item):
            guard let image = images.first else { return }
            Task { await outfits.replace(item, with: image) }
        }
    }
}

/// One of the four parts of a look: a dashed gold invitation when empty, a strip of
/// photos once something is in it.
private struct OutfitSlot: View {
    let category: OutfitCategory
    let items: [OutfitItem]
    let uploads: [PendingOutfitUpload]
    let busyIDs: Set<String>
    let onAdd: () -> Void
    let onView: (OutfitItem) -> Void
    let onReplace: (OutfitItem) -> Void
    let onNote: (OutfitItem) -> Void
    let onDelete: (OutfitItem) -> Void

    private let slotHeight: CGFloat = 196

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 11, weight: .light))
                Text(category.title.uppercased())
                    .font(BrandLabel.font(size: 10, weight: .semibold))
                    .tracking(1.4)
                Spacer(minLength: 0)
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(BrandLabel.font(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(BrandPalette.goldDeep)
                }
            }
            .foregroundStyle(isEmpty ? BrandPalette.body : BrandPalette.goldDeep)

            if isEmpty {
                emptySlot
            } else {
                strip
            }
        }
    }

    private var isEmpty: Bool { items.isEmpty && uploads.isEmpty }

    private var emptySlot: some View {
        Button(action: onAdd) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BrandPalette.gold.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(BrandPalette.gold.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                )
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .ultraLight))
                            .foregroundStyle(BrandPalette.goldDeep)
                        Text("Add")
                            .font(BrandLabel.font(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(BrandPalette.goldDeep.opacity(0.85))
                    }
                }
                .frame(height: slotHeight)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Add a photo of your \(category.title.lowercased())")
    }

    private var strip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    photo(item)
                }
                ForEach(uploads) { upload in
                    uploading(upload)
                }
                addMore
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: slotHeight)
        .clipShape(.rect(cornerRadius: 18))
    }

    private func photo(_ item: OutfitItem) -> some View {
        let isBusy = busyIDs.contains(item.id)

        return Button {
            onView(item)
        } label: {
            OutfitThumbnail(path: item.photoPath)
                .frame(width: stripWidth, height: slotHeight)
                .clipShape(.rect(cornerRadius: 18))
                .overlay(alignment: .bottomLeading) {
                    if item.note != nil {
                        Image(systemName: "text.quote")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.black.opacity(0.4)))
                            .padding(8)
                    }
                }
                .overlay {
                    if isBusy {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.3))
                            .overlay(ProgressView().tint(Color.white))
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button("Replace", systemImage: "arrow.triangle.2.circlepath.camera") { onReplace(item) }
            Button(item.note == nil ? "Add Note" : "Edit Note", systemImage: "text.quote") { onNote(item) }
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(item) }
        }
        .disabled(isBusy)
        .accessibilityLabel(item.note ?? "\(category.title) photo")
        .accessibilityHint("Hold for Replace, Add note, or Delete")
    }

    private func uploading(_ upload: PendingOutfitUpload) -> some View {
        Color(BrandPalette.hairline)
            .frame(width: stripWidth, height: slotHeight)
            .overlay {
                Image(uiImage: upload.preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            }
            .overlay(Color.black.opacity(0.28))
            .overlay(ProgressView().tint(Color.white))
            .clipShape(.rect(cornerRadius: 18))
            .accessibilityLabel("Saving photo")
    }

    private var addMore: some View {
        Button(action: onAdd) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(BrandPalette.gold.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .frame(width: 54, height: slotHeight)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(BrandPalette.goldDeep)
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Add another \(category.title.lowercased()) photo")
    }

    private var stripWidth: CGFloat {
        items.count + uploads.count > 1 ? 112 : 128
    }
}

/// "Don't forget": the couple's packing suggestions for this celebration, for men or
/// women, ticked off on this phone only.
private struct OutfitChecklistSection: View {
    let eventID: String
    let guide: OutfitGuide

    @State private var outfits = OutfitStore.shared

    var body: some View {
        @Bindable var outfits = outfits
        let items = guide.items(for: outfits.gender)
        let done = outfits.tickedCount(items, eventID: eventID)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Don't forget", size: 10.5)
                Spacer()
                Text("\(done) of \(items.count)")
                    .font(BrandLabel.font(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(done == items.count ? BrandPalette.goldDeep : BrandPalette.body.opacity(0.75))
                    .contentTransition(.numericText())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Suggestions for:")
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                OutfitGenderPicker(selection: $outfits.gender)
            }

            Text(guide.mood)
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .fixedSize(horizontal: false, vertical: true)

            MatteCard(cornerRadius: 20) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element) { index, text in
                        row(text)
                        if index < items.count - 1 {
                            Rectangle()
                                .fill(BrandPalette.hairline)
                                .frame(height: 1)
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .animation(.calm, value: outfits.gender)

            if let tip = guide.tip {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(BrandPalette.goldDeep)
                        .padding(.top, 3)
                    Text(tip)
                        .brandFont(.bodyItalic)
                        .foregroundStyle(BrandPalette.ink.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(BrandPalette.gold.opacity(0.08))
                )
            }
        }
    }

    private func row(_ text: String) -> some View {
        let isDone = outfits.isTicked(text, eventID: eventID)

        return Button {
            BrandHaptics.tick()
            withAnimation(.calm) { outfits.toggleTick(text, eventID: eventID) }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(BrandPalette.gold.opacity(isDone ? 0 : 0.6), lineWidth: 1)
                    Circle()
                        .fill(BrandPalette.gold)
                        .scaleEffect(isDone ? 1 : 0.2)
                        .opacity(isDone ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: 0xFFFBF1))
                        .opacity(isDone ? 1 : 0)
                }
                .frame(width: 22, height: 22)
                .padding(.top, 1)

                Text(text)
                    .brandFont(.bodyText)
                    .foregroundStyle(isDone ? BrandPalette.body.opacity(0.7) : BrandPalette.ink)
                    .strikethrough(isDone, color: BrandPalette.gold.opacity(0.6))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isDone ? [.isButton, .isSelected] : .isButton)
    }
}

/// A note of up to 200 characters on one photo.
private struct OutfitNoteSheet: View {
    let item: OutfitItem

    @State private var text: String
    @State private var isSaving = false
    @State private var didFail = false
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(item: OutfitItem) {
        self.item = item
        _text = State(initialValue: item.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: item.kind?.title ?? "Photo")

            Text(item.note == nil ? "Add a note" : "Edit note")
                .brandFont(.eventTitleSmall)
                .foregroundStyle(BrandPalette.ink)
                .padding(.top, 8)

            AdminField(label: "Note", hint: "\(text.count)/\(OutfitStore.noteLimit)") {
                TextField("", text: $text, prompt: AdminExample.prompt("Mum's gold jhumkas, steam the dupatta"), axis: .vertical)
                    .lineLimit(2...5)
                    .focused($isFocused)
            }
            .padding(.top, 20)
            .onChange(of: text) { _, value in
                if value.count > OutfitStore.noteLimit {
                    text = String(value.prefix(OutfitStore.noteLimit))
                }
            }

            if didFail {
                Text("That note didn't save. Please try again.")
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .padding(.top, 10)
            }

            GoldActionButton(title: "Save note", isBusy: isSaving) {
                save()
            }
            .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .background(BrandPalette.background.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear { isFocused = true }
    }

    private func save() {
        isSaving = true
        didFail = false
        Task {
            let ok = await OutfitStore.shared.setNote(text, for: item)
            isSaving = false
            if ok {
                BrandHaptics.tick()
                dismiss()
            } else {
                didFail = true
            }
        }
    }
}

/// Full-screen look at one of the guest's own photos, with its note.
private struct MyOutfitPhotoViewer: View {
    let item: OutfitItem

    @State private var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 8)
            } else {
                ProgressView().tint(BrandPalette.goldPale)
            }

            if let note = item.note {
                VStack {
                    Spacer()
                    Text(note)
                        .brandFont(.bodyItalic)
                        .foregroundStyle(Color.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 44)
                }
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(PressableStyle())
            .padding(.trailing, 18)
            .padding(.top, 12)
            .accessibilityLabel("Close photograph")
        }
        .task {
            image = OutfitPhotoCache.shared.cached(item.photoPath)
            if image == nil {
                image = await OutfitPhotoCache.shared.image(for: item.photoPath)
            }
        }
    }
}
