import SwiftUI

/// Every announcement the couple have sent, as a notice board: the newest pinned to a
/// gold easel, the earlier ones listed beneath it. Guests read;
/// an admin (profile role = admin) gets a gold "+ New announcement" button in the
/// header, which opens a full sheet to write in before the send is confirmed.
/// Opens instantly from the saved copy, then refreshes quietly.
struct AnnouncementsView: View {
    @State private var updates = NotificationsStore.shared
    @State private var session = ChatSession.shared
    @State private var draft = AnnouncementDraft.shared
    @Environment(ScheduleStore.self) private var store
    @State private var pendingSend: PendingSend?
    @State private var isComposing = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    /// A snapshot of the note at the moment Send was tapped.
    private struct PendingSend: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let destination: AnnouncementDestination
    }

    private var canCompose: Bool { session.isAdmin }

    var body: some View {
        content
            // The header lives in the safe area itself, so on the folding iPhone's
            // outer screen — where the sensor housing takes an edge and the top inset
            // is small — it can never rise above the visible area. The background
            // still runs under the status bar; the content does not.
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .background(BrandPalette.background.ignoresSafeArea())
            .overlay(alignment: .top) {
                if let toast {
                    ChatToast(text: toast)
                    // The header now counts as safe area, so the toast sits just
                    // beneath it without a hard-coded status-bar height.
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.calm, value: toast)
        .sheet(isPresented: $isComposing) {
            NewAnnouncementSheet(events: store.events) { title, message, destination in
                isComposing = false
                BrandHaptics.soft()
                pendingSend = PendingSend(title: title, message: message, destination: destination)
            }
        }
        .sheet(item: $pendingSend) { pending in
            AnnouncementSendSheet(
                title: pending.title,
                message: pending.message,
                destination: pending.destination
            ) { count in
                didSend(pending, count: count)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // The composer bar is gone; the floating tab bar never needs to step aside.
            draft.isComposerOnScreen = false
        }
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

    /// Narrow windows (the closed folding iPhone, a Split View pane) collapse the
    /// gold button to an icon-only circle instead of squeezing the words.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow { newAnnouncementButton }
            headerRow { compactNewAnnouncementButton }
        }
    }

    private func headerRow<Compose: View>(@ViewBuilder compose: () -> Compose) -> some View {
        HStack(spacing: 10) {
            ChatBackButton()

            ChannelBadge(kind: .announcements, size: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("Announcements")
                    .brandFont(.chatName)
                    .foregroundStyle(BrandPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                Text("From \(ActiveWedding.couple)")
                    .font(BrandLabel.font(size: 11, weight: .medium))
                    .foregroundStyle(BrandPalette.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            if canCompose {
                compose()
            }
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

    private var newAnnouncementButton: some View {
        Button {
            BrandHaptics.soft()
            isComposing = true
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New announcement")
                        .font(BrandLabel.font(size: 11, weight: .semibold))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .fixedSize()
                }
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New")
                        .font(BrandLabel.font(size: 11, weight: .semibold))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .fixedSize()
                }
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color(hex: 0xFFFBF1))
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [BrandPalette.gold, BrandPalette.goldDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("New announcement")
    }

    /// The same action as a 44 pt circle, for widths too narrow for the words.
    private var compactNewAnnouncementButton: some View {
        Button {
            BrandHaptics.soft()
            isComposing = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFFFBF1))
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [BrandPalette.gold, BrandPalette.goldDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("New announcement")
    }

    // MARK: - The deck

    private var content: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if updates.records.isEmpty {
                        emptyCard
                            .padding(.top, 34)
                            .padding(.horizontal, 14)
                            .readableWidth(560)
                    } else {
                        // One composition sized to the room between the header and the tab bar.
                        AnnouncementEasel(
                            records: updates.records,
                            events: store.events,
                            available: CGSize(
                                width: max(proxy.size.width - 32, 200),
                                height: max(proxy.size.height - FloatingTabBar.contentReserve - 16 - 14, 260)
                            ),
                            isUnread: { updates.isUnread($0) },
                            onRoute: route
                        )
                        .padding(.top, 14)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, FloatingTabBar.contentReserve + 16)
            }
            .scrollIndicators(.hidden)
            .refreshable { await updates.refresh() }
            .animation(.calm, value: updates.records)
        }
    }

    /// Following an announcement's link goes exactly where tapping its notification would.
    private func route(_ destination: AnnouncementDestination) {
        BrandHaptics.soft()
        let landing = DeepLinkRouter.landing(forScreen: destination.screen, eventID: destination.eventID)
        DeepLinkRouter.shared.open(landing)
    }

    // MARK: - Sending

    private func didSend(_ pending: PendingSend, count: Int?) {
        draft.clear()
        updates.addJustSent(title: pending.title, body: pending.message, destination: pending.destination)
        if let count {
            showToast(count == 1 ? "Sent to 1 guest" : "Sent to \(count) guests")
        } else {
            showToast("Sent to every guest")
        }
        Task { await updates.refreshAfterSend() }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    // MARK: - Empty

    private var emptyCard: some View {
        VStack(spacing: 14) {
            IconWatermark(key: .sparkle, size: 64, opacity: 0.3)
            Text("Announcements from \(ActiveWedding.couple) will appear here")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .padding(.horizontal, 20)
        .announcementPaper(cornerRadius: 22, isLatest: false)
    }
}
