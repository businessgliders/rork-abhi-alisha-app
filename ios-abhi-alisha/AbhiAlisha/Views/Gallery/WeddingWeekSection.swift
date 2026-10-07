import SwiftUI

/// Which celebrations the Wedding Week follows, and whether it has begun.
nonisolated enum WeddingWeek {
    /// Every active celebration in order, without the closing "Thank You For Coming".
    static func events(from all: [ScheduleEvent]) -> [ScheduleEvent] {
        all.filter { !$0.isFarewell && $0.isActive != false }
    }

    /// From half an hour before the first celebration.
    static func hasBegun(_ events: [ScheduleEvent], now: Date) -> Bool {
        guard let first = events.compactMap(\.startsAt).min() else { return false }
        return now >= first.addingTimeInterval(-30 * 60)
    }
}

/// The photographs to page through, and where to start.
struct WeddingViewerContext: Identifiable {
    let photos: [WeddingPhoto]
    let index: Int

    var id: String { photos.indices.contains(index) ? photos[index].id : "wedding-viewer" }
}

/// "Wedding Week": a gold-railed timeline of the celebrations, each with its photographs
/// as they arrive. Open to every guest with no sign-in; the couple can add and manage.
struct WeddingWeekSection: View {
    @Environment(ScheduleStore.self) private var schedule
    @State private var photoStore = WeddingPhotoStore.shared
    @State private var session = ChatSession.shared
    @State private var phase = WeddingPhase.shared
    @State private var viewer: WeddingViewerContext?
    @State private var albumEvent: ScheduleEvent?
    @State private var addSource: WeddingAddSource?

    private var events: [ScheduleEvent] { WeddingWeek.events(from: schedule.events) }

    /// Before the week begins (and before anything has been added), one quiet line.
    private var isWaiting: Bool {
        photoStore.photos.isEmpty
            && !WeddingWeek.hasBegun(events, now: schedule.now)
            && !phase.isThankYou(at: schedule.now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if session.isAdmin {
                WeddingUploadProgress()
                    .padding(.top, 14)
            }

            if isWaiting || events.isEmpty {
                waitingLine
                    .padding(.top, 14)
            } else {
                timeline
                    .padding(.top, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.calm, value: photoStore.isUploadingAnything)
        .weddingPhotoAdder(source: $addSource, originEventID: nil)
        .fullScreenCover(item: $viewer) { context in
            WeddingPhotoViewer(photos: context.photos, startIndex: context.index)
        }
        .fullScreenCover(item: $albumEvent) { event in
            WeddingAlbumView(event: event)
                .environment(schedule)
        }
        .alert("Wedding Week", isPresented: Binding(
            get: { photoStore.notice != nil && session.isAdmin },
            set: { if !$0 { photoStore.notice = nil } }
        )) {
            Button("OK", role: .cancel) { photoStore.notice = nil }
        } message: {
            Text(photoStore.notice ?? "")
        }
        .task {
            await photoStore.refresh()
            photoStore.resumeUploads()
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "As it happened", size: 10)
                Text("Wedding Week")
                    .brandFont(.eventTitle)
                    .foregroundStyle(BrandPalette.ink)
            }
            Spacer(minLength: 0)
            if session.isAdmin {
                AddWeddingPhotosButton(source: $addSource)
            }
        }
    }

    private var waitingLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera")
                .symbolVariant(.none)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(BrandPalette.gold)
            Text("Photos from the wedding week will appear here")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { offset, event in
                let photos = photoStore.photos(for: event.id)
                WeddingEventBlock(
                    event: event,
                    photos: photos,
                    events: events,
                    isLast: offset == events.count - 1,
                    onOpen: { index in
                        BrandHaptics.soft()
                        viewer = WeddingViewerContext(photos: photos, index: index)
                    },
                    onSeeAll: {
                        BrandHaptics.soft()
                        albumEvent = event
                    }
                )
            }
        }
    }
}

// MARK: - One celebration

private struct WeddingEventBlock: View {
    let event: ScheduleEvent
    let photos: [WeddingPhoto]
    let events: [ScheduleEvent]
    let isLast: Bool
    let onOpen: (Int) -> Void
    let onSeeAll: () -> Void

    private static let previewLimit = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let date = event.displayDate {
                Text(date.uppercased())
                    .font(BrandLabel.font(size: 9.5, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(BrandPalette.gold)
            }

            Text(event.title)
                .brandFont(.eventTitleSmall)
                .foregroundStyle(BrandPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            content
                .padding(.top, 14)
        }
        .padding(.leading, 26)
        .padding(.bottom, isLast ? 4 : 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) { rail }
    }

    /// The gold thread down the left: a bead per celebration, filled once it has photos.
    private var rail: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(photos.isEmpty ? BrandPalette.background : BrandPalette.gold)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(BrandPalette.gold, lineWidth: 1))
                .padding(.top, 2)
            if !isLast {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [BrandPalette.gold.opacity(0.5), BrandPalette.gold.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1)
                    .padding(.top, 4)
            }
        }
        .frame(width: 11)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if photos.isEmpty {
            Text("Photos coming soon")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body.opacity(0.7))
        } else {
            let shown = Array(photos.prefix(Self.previewLimit))
            VStack(alignment: .leading, spacing: 6) {
                if let cover = shown.first, cover.isCover {
                    WeddingPhotoTile(photo: cover, aspect: 3.0 / 2.0, events: events) { onOpen(0) }
                    WeddingPhotoGrid(photos: Array(shown.dropFirst()), events: events) { onOpen($0 + 1) }
                } else {
                    WeddingPhotoGrid(photos: shown, events: events, onOpen: onOpen)
                }

                if photos.count > Self.previewLimit {
                    Button(action: onSeeAll) {
                        HStack(spacing: 6) {
                            Text("See all \(photos.count) photos")
                                .font(BrandLabel.font(size: 11, weight: .semibold))
                                .tracking(1.3)
                                .textCase(.uppercase)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(BrandPalette.goldDeep)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 4)
                }
            }
        }
    }
}

/// Three across, square thumbnails.
struct WeddingPhotoGrid: View {
    let photos: [WeddingPhoto]
    let events: [ScheduleEvent]
    let onOpen: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                WeddingPhotoTile(photo: photo, events: events) { onOpen(offset) }
            }
        }
    }
}

/// One thumbnail. For the couple, pressing and holding opens Edit caption, Move, Make
/// cover and Delete.
struct WeddingPhotoTile: View {
    let photo: WeddingPhoto
    var aspect: CGFloat = 1
    let events: [ScheduleEvent]
    let action: () -> Void

    @State private var session = ChatSession.shared
    @State private var store = WeddingPhotoStore.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        Button(action: action) {
            BrandPalette.hairline.opacity(0.7)
                .aspectRatio(aspect, contentMode: .fit)
                .overlay {
                    RemoteImage(url: photo.thumbURL, contentMode: .fill) {
                        QuietPhotoPlaceholder()
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(shape)
                .overlay {
                    if store.busyIDs.contains(photo.id) {
                        shape.fill(Color.black.opacity(0.3))
                            .overlay(ProgressView().tint(Color.white))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if photo.isCover, session.isAdmin {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xFFFBF1))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(BrandPalette.goldDeep.opacity(0.9)))
                            .padding(6)
                            .accessibilityLabel("Cover photo")
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .weddingPhotoActions(photo: photo, events: events, isEnabled: session.isAdmin)
        .accessibilityLabel(photo.caption ?? "Wedding week photograph")
        .accessibilityHint(session.isAdmin ? "Hold for Edit caption, Move, Make cover or Delete" : "Opens the photograph")
    }
}

// MARK: - Full album

/// Every photograph from one celebration.
struct WeddingAlbumView: View {
    let event: ScheduleEvent

    @Environment(ScheduleStore.self) private var schedule
    @Environment(\.dismiss) private var dismiss
    @State private var store = WeddingPhotoStore.shared
    @State private var viewer: WeddingViewerContext?

    private var photos: [WeddingPhoto] { store.photos(for: event.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let date = event.displayDate {
                            Eyebrow(text: date, size: 10)
                        }
                        Text(event.title)
                            .brandFont(.eventTitle)
                            .foregroundStyle(BrandPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(photos.count == 1 ? "1 photo" : "\(photos.count) photos")
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 12)
                    Button {
                        BrandHaptics.tick()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(BrandPalette.goldDeep)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(BrandPalette.card))
                            .overlay(Circle().stroke(BrandPalette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Close album")
                }

                WeddingPhotoGrid(photos: photos, events: WeddingWeek.events(from: schedule.events)) { index in
                    BrandHaptics.soft()
                    viewer = WeddingViewerContext(photos: photos, index: index)
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .readableWidth(820)
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .fullScreenCover(item: $viewer) { context in
            WeddingPhotoViewer(photos: context.photos, startIndex: context.index)
        }
        .onChange(of: photos.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }
}
