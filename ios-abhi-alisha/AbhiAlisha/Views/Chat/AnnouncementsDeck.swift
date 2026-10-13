import SwiftUI

/// The Announcements deck: a fixed stack with the oldest note at the back (top) and the
/// newest at the front (bottom). The latest is open by default. Tapping an older strip
/// opens it right where it sits — the newer cards slide down to make room and the latest
/// folds to a strip. Tapping the open card (or its chevron) folds it and the latest opens
/// again. With Reduce Motion, the change crossfades instead of sliding.
struct AnnouncementDeck: View {
    /// How many announcements the deck holds before the rest live in the archive.
    static let deckSize = 6

    let records: [NotificationRecord]
    let events: [ScheduleEvent]
    let isUnread: (NotificationRecord) -> Bool
    let onRoute: (AnnouncementDestination) -> Void

    /// The older note that's open; nil means the default — the latest open.
    @State private var openID: String?
    @State private var isArchiveOpen = false
    @State private var deckOpacity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Newest first, as stored.
    private var visible: [NotificationRecord] { Array(records.prefix(Self.deckSize)) }
    private var latestID: String? { visible.first?.id }
    private var effectiveOpenID: String? { openID ?? latestID }

    private static let spring: Animation = .spring(duration: 0.35, bounce: 0.14)

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 8) {
                // Oldest at the top/back, newest at the bottom/front — never reordered.
                ForEach(Array(visible.enumerated().reversed()), id: \.element.id) { index, record in
                    row(record, index: index, proxy: proxy)
                        .id(record.id)
                }

                if records.count > Self.deckSize {
                    seeAllStrip
                        .padding(.top, 4)
                }
            }
            .opacity(deckOpacity)
        }
        .onChange(of: latestID) { _, _ in
            // A new announcement arrives at the front, open; anything else folds.
            openID = nil
        }
        .sheet(isPresented: $isArchiveOpen) {
            AnnouncementArchiveSheet(records: records, events: events)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ record: NotificationRecord, index: Int, proxy: ScrollViewProxy) -> some View {
        let isLatest = record.id == latestID
        let isOpen = record.id == effectiveOpenID
        // Folded older strips step back a little for depth, measured from the front.
        let scale: CGFloat = (isOpen || isLatest) ? 1 : max(0.98 - CGFloat(index - 1) * 0.02, 0.9)

        VStack(alignment: .leading, spacing: 0) {
            if isOpen {
                AnnouncementCardBody(
                    content: .init(record: record, events: events, isLatest: isLatest, isNew: isUnread(record)),
                    showsChevron: !isLatest,
                    onCollapse: { select(nil, proxy: proxy) },
                    onOpen: openAction(for: record)
                )
                .padding(20)
                .transition(.opacity)
            } else {
                AnnouncementStripRow(
                    record: record,
                    isLatest: isLatest,
                    isNew: isLatest && isUnread(record)
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .announcementPaper(cornerRadius: 20, isLatest: isLatest, isLifted: isOpen)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            if isOpen {
                if !isLatest { select(nil, proxy: proxy) }
            } else {
                select(isLatest ? nil : record.id, proxy: proxy)
            }
        }
        .scaleEffect(scale, anchor: .bottom)
        .accessibilityElement(children: isOpen ? .contain : .combine)
        .accessibilityAddTraits(isOpen ? [] : .isButton)
        .accessibilityHint(isOpen ? (isLatest ? "" : "Double-tap to fold") : "Opens this announcement in place")
    }

    private func openAction(for record: NotificationRecord) -> (() -> Void)? {
        guard let destination = record.destination(events: events) else { return nil }
        return { onRoute(destination) }
    }

    /// Opens one card (nil = back to the latest). Only one is ever open.
    private func select(_ id: String?, proxy: ScrollViewProxy) {
        guard id != openID else { return }
        BrandHaptics.soft()
        let target = id ?? latestID

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.12)) { deckOpacity = 0 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) {
                    openID = id
                    if let target { proxy.scrollTo(target, anchor: nil) }
                }
                withAnimation(.easeIn(duration: 0.16)) { deckOpacity = 1 }
            }
            return
        }

        withAnimation(Self.spring) { openID = id }
        Task { @MainActor in
            // Let the cards settle, then nudge the page only as far as needed.
            try? await Task.sleep(for: .milliseconds(200))
            guard let target else { return }
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: nil) }
        }
    }

    private var seeAllStrip: some View {
        Button {
            BrandHaptics.tick()
            isArchiveOpen = true
        } label: {
            HStack(spacing: 7) {
                Text("See all \(records.count) announcements")
                    .font(BrandLabel.font(size: 11, weight: .semibold))
                    .tracking(1.3)
                    .textCase(.uppercase)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(BrandPalette.goldDeep)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BrandPalette.card.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BrandPalette.gold.opacity(0.4), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens every announcement as a list")
    }
}

// MARK: - Card content

/// Everything a card shows, held separately so the compose sheet can preview a note
/// that doesn't exist yet.
struct AnnouncementCardContent {
    let title: String
    let message: String
    let sentAt: Date?
    let isLatest: Bool
    let isNew: Bool
    let destination: AnnouncementDestination?

    init(
        title: String,
        message: String,
        sentAt: Date?,
        isLatest: Bool,
        isNew: Bool,
        destination: AnnouncementDestination?
    ) {
        self.title = title
        self.message = message
        self.sentAt = sentAt
        self.isLatest = isLatest
        self.isNew = isNew
        self.destination = destination
    }

    /// Straight from a saved announcement.
    init(record: NotificationRecord, events: [ScheduleEvent], isLatest: Bool, isNew: Bool) {
        self.init(
            title: record.title ?? "",
            message: record.body ?? "",
            sentAt: record.sentAt,
            isLatest: isLatest,
            isNew: isNew,
            destination: record.destination(events: events)
        )
    }
}

/// A standalone announcement on cream paper — used by the compose preview and the archive.
/// The latest gets the gold border and glow.
struct AnnouncementCard: View {
    let content: AnnouncementCardContent
    /// Where the card's button goes; nil shows no button at all.
    var onOpen: (() -> Void)?

    var body: some View {
        AnnouncementCardBody(content: content, showsChevron: false, onCollapse: nil, onOpen: onOpen)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .announcementPaper(cornerRadius: 20, isLatest: content.isLatest)
    }
}

/// The words of an open card: label row, Playfair italic headline, Cormorant message,
/// an optional "View … →" button and the sign-off.
struct AnnouncementCardBody: View {
    let content: AnnouncementCardContent
    let showsChevron: Bool
    let onCollapse: (() -> Void)?
    let onOpen: (() -> Void)?

    private let stock = AnnouncementTint.cream

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if content.isLatest {
                    Text("Latest")
                        .font(BrandLabel.font(size: 9.5, weight: .semibold))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(BrandPalette.goldDeep)
                    if content.sentAt != nil {
                        Text("·")
                            .font(BrandLabel.font(size: 9.5, weight: .semibold))
                            .foregroundStyle(BrandPalette.goldDeep)
                    }
                }

                if let sentAt = content.sentAt {
                    Text(content.isLatest ? ChatTime.ago(sentAt) : sentAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(BrandLabel.font(size: 9.5, weight: content.isLatest ? .semibold : .medium))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(content.isLatest ? BrandPalette.goldDeep : stock.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 6)

                if content.isNew {
                    UnreadDot()
                        .accessibilityLabel("New")
                }

                if showsChevron, let onCollapse {
                    Button(action: onCollapse) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(stock.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.vertical, -14)
                    .padding(.trailing, -12)
                    .accessibilityLabel("Fold announcement")
                }
            }
            .accessibilityElement(children: .combine)

            if content.title.nonEmpty != nil {
                Text(content.title)
                    .brandFont(.announcementHeadline)
                    .foregroundStyle(stock.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            if content.message.nonEmpty != nil {
                Text(content.message)
                    .brandFont(.bodyText)
                    .foregroundStyle(stock.ink.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            if let onOpen, let destination = content.destination {
                Button(action: onOpen) {
                    HStack(spacing: 6) {
                        Text("View \(destination.label)")
                            .font(BrandLabel.font(size: 11.5, weight: .semibold))
                            .tracking(1.3)
                            .textCase(.uppercase)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(stock.ink.opacity(0.9))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Capsule(style: .continuous).fill(stock.paper.opacity(0.5)))
                    .overlay(Capsule(style: .continuous).stroke(BrandPalette.gold.opacity(0.5), lineWidth: 1))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 16)
                .accessibilityHint("Opens \(destination.label), the same place the notification goes")
            }

            if let sentAt = content.sentAt {
                Text("From Abhi & Alisha · \(sentAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                    .font(BrandLabel.font(size: 9.5, weight: .medium))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(stock.secondary)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Strip

/// A folded note: the date in gold small caps, the title on one line, and a ⌄ chevron.
/// The latest keeps its "Latest" label (and its gold border, from the paper) when folded.
struct AnnouncementStripRow: View {
    let record: NotificationRecord
    let isLatest: Bool
    let isNew: Bool

    private let stock = AnnouncementTint.cream

    var body: some View {
        HStack(spacing: 10) {
            if isLatest {
                Text("Latest")
                    .font(BrandLabel.font(size: 9.5, weight: .semibold))
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(BrandPalette.goldDeep)
            } else if let sentAt = record.sentAt {
                Text(sentAt.formatted(.dateTime.month(.abbreviated).day()))
                    .font(BrandLabel.font(size: 9.5, weight: .semibold))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(BrandPalette.goldDeep)
                    .monospacedDigit()
            }

            Text(record.title?.nonEmpty ?? record.body?.nonEmpty ?? "An announcement")
                .brandFont(.chatName)
                .foregroundStyle(stock.ink)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isNew {
                UnreadDot()
                    .accessibilityLabel("New")
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(stock.secondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .accessibilityLabel("\(isLatest ? "Latest announcement" : "Announcement"): \(record.title ?? "from Abhi & Alisha")")
    }
}

// MARK: - Archive

/// Every announcement, newest first: a quiet list where a row expands in place.
private struct AnnouncementArchiveSheet: View {
    let records: [NotificationRecord]
    let events: [ScheduleEvent]

    @Environment(\.dismiss) private var dismiss
    @State private var expandedID: String?

    private let stock = AnnouncementTint.cream

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(records) { record in
                        row(record)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .readableWidth(680)
            }
            .scrollIndicators(.hidden)
            .background(BrandPalette.background.ignoresSafeArea())
            .navigationTitle("All announcements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(BrandPalette.goldDeep)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func row(_ record: NotificationRecord) -> some View {
        let isOpen = expandedID == record.id

        VStack(alignment: .leading, spacing: 0) {
            Button {
                BrandHaptics.tick()
                withAnimation(.calm) { expandedID = isOpen ? nil : record.id }
            } label: {
                HStack(spacing: 10) {
                    if let sentAt = record.sentAt {
                        Text(sentAt.formatted(.dateTime.month(.abbreviated).day()))
                            .font(BrandLabel.font(size: 9.5, weight: .semibold))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .foregroundStyle(BrandPalette.goldDeep)
                            .monospacedDigit()
                    }

                    Text(record.title ?? record.body ?? "An announcement")
                        .brandFont(.chatName)
                        .foregroundStyle(stock.ink)
                        .lineLimit(isOpen ? 2 : 1)

                    Spacer(minLength: 0)

                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(stock.secondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            if isOpen, record.body?.nonEmpty != nil {
                AnnouncementCardBody(
                    content: .init(record: record, events: events, isLatest: false, isNew: false),
                    showsChevron: false,
                    onCollapse: nil,
                    onOpen: nil
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
        .announcementPaper(cornerRadius: 18, isLatest: false, isLifted: false)
    }
}
