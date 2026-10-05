import SwiftUI

/// Every announcement Abhi & Alisha have sent, oldest at the top like a chat, each in
/// a gold bubble. Read-only and never muted: posting stays in the couple's area.
/// Opens instantly from the saved copy, then refreshes quietly.
struct AnnouncementsView: View {
    @State private var updates = NotificationsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            feed
        }
        .background(BrandPalette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            updates.markOpened()
            await updates.refresh()
            updates.markOpened()
        }
        .onChange(of: updates.latest?.id) { _, _ in
            updates.markOpened()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ChatBackButton()

            ChannelBadge(kind: .announcements, size: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("Announcements")
                    .brandFont(.chatName)
                    .foregroundStyle(BrandPalette.ink)
                    .lineLimit(1)
                Text("From Abhi & Alisha")
                    .font(BrandLabel.font(size: 11, weight: .medium))
                    .foregroundStyle(BrandPalette.body)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(BrandPalette.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrandPalette.hairline)
                .frame(height: 1)
        }
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let list = updates.feed
                if list.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        IconWatermark(key: .sparkle, size: 46, opacity: 0.35)
                        Text("Only Abhi & Alisha post here")
                            .brandFont(.bodyItalic)
                            .foregroundStyle(BrandPalette.body)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)

                    ForEach(Array(list.enumerated()), id: \.element.id) { index, record in
                        let previous = index > 0 ? list[index - 1] : nil
                        if showsDayHeader(record, after: previous), let sentAt = record.sentAt {
                            dayHeader(sentAt)
                        }
                        AnnouncementBubble(record: record)
                            .padding(.trailing, 44)
                            .padding(.bottom, 12)
                            .id(record.id)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, FloatingTabBar.contentReserve + 16)
            .readableWidth(720)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.bottom)
        .refreshable { await updates.refresh() }
        .animation(.calm, value: updates.records)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            IconWatermark(key: .sparkle, size: 84, opacity: 0.3)
            Text("Nothing announced yet")
                .brandFont(.eventTitleSmall)
                .foregroundStyle(BrandPalette.ink)
            Text("News from Abhi & Alisha will arrive here, and on your lock screen.")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    private func showsDayHeader(_ record: NotificationRecord, after previous: NotificationRecord?) -> Bool {
        guard let sentAt = record.sentAt else { return false }
        guard let previousDate = previous?.sentAt else { return true }
        return !Calendar.current.isDate(sentAt, inSameDayAs: previousDate)
    }

    private func dayHeader(_ date: Date) -> some View {
        Text(ChatTime.dayHeader(date).uppercased())
            .font(BrandLabel.font(size: 10, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(BrandPalette.gold)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One announcement: from "Abhi & Alisha", the title in Playfair italic, the words in
/// Cormorant, and the time beneath.
private struct AnnouncementBubble: View {
    let record: NotificationRecord

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 6,
            bottomLeadingRadius: 20,
            bottomTrailingRadius: 20,
            topTrailingRadius: 20,
            style: .continuous
        )

        VStack(alignment: .leading, spacing: 6) {
            Text("Abhi & Alisha")
                .brandFont(.chatSender)
                .foregroundStyle(BrandPalette.goldDeep)

            if let title = record.title {
                Text(title)
                    .brandFont(.announcementTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let body = record.body {
                Text(body)
                    .brandFont(.chatMessage)
                    .foregroundStyle(BrandPalette.ink.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let sentAt = record.sentAt {
                Text(ChatTime.clock(sentAt))
                    .font(BrandLabel.font(size: 9.5, weight: .medium))
                    .foregroundStyle(BrandPalette.body.opacity(0.8))
                    .monospacedDigit()
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            shape.fill(
                LinearGradient(
                    colors: [BrandPalette.gold.opacity(0.24), BrandPalette.gold.opacity(0.13)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(shape.stroke(BrandPalette.gold.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
