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
    // TEMPORARY — header diagnostics, TestFlight only. Remove with the panel below
    // before the App Store submission.
    @State private var headerFrame: CGRect = .zero
    @State private var showsDiagnostics = false

    /// A snapshot of the note at the moment Send was tapped.
    private struct PendingSend: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let destination: AnnouncementDestination
    }

    private var canCompose: Bool { session.isAdmin }

    var body: some View {
        // The header is a plain sibling above the stage — never inside a scroll view
        // and never offset — so no device or pose can lift it off the top. The stage
        // below scales the easel to whatever room is left, so the page never scrolls.
        VStack(spacing: 0) {
            header
            content
        }
        .background(BrandPalette.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let toast {
                ChatToast(text: toast)
                    .padding(.top, 70)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.calm, value: toast)
        .onPreferenceChange(HeaderFrameKey.self) { headerFrame = $0 }
        .overlay { diagnosticsPanel }
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
    /// gold button to an icon-only circle instead of squeezing the words. The frame
    /// capture feeds the diagnostics panel.
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
                    // TEMPORARY diagnostics trigger — remove with the panel.
                    .onLongPressGesture(minimumDuration: 2) {
                        guard HeaderDiagnostics.isEnabled else { return }
                        BrandHaptics.soft()
                        showsDiagnostics = true
                    }
                    .accessibilityAction(named: "Show layout numbers") {
                        guard HeaderDiagnostics.isEnabled else { return }
                        showsDiagnostics = true
                    }
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
        .padding(.top, 8)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(BrandPalette.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrandPalette.hairline)
                .frame(height: 1)
        }
    }

    /// Where the header actually landed, for the diagnostics panel.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow { newAnnouncementButton }
            headerRow { compactNewAnnouncementButton }
        }
        .background {
            GeometryReader { g in
                Color.clear.preference(key: HeaderFrameKey.self, value: g.frame(in: .global))
            }
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
        // The room below the header only. The easel is fixed-ratio and scales itself
        // into whatever this measures; nothing here scrolls, so nothing can start
        // scrolled or shift after appearing.
        GeometryReader { proxy in
            Group {
                if updates.records.isEmpty {
                    emptyCard
                        .padding(.horizontal, 14)
                        .readableWidth(560)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 34)
                } else {
                    AnnouncementEasel(
                        records: updates.records,
                        events: store.events,
                        available: CGSize(
                            width: max(proxy.size.width - 32, 200),
                            height: max(proxy.size.height - FloatingTabBar.contentReserve - 16 - 14, 120)
                        ),
                        isUnread: { updates.isUnread($0) },
                        onRoute: route
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 14)
                }
            }
            .padding(.bottom, FloatingTabBar.contentReserve + 12)
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

    // MARK: - TEMPORARY header diagnostics (TestFlight only — remove before App Store)

    private var diagnosticsPanel: some View {
        Group {
            if showsDiagnostics {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { showsDiagnostics = false }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Header diagnostics")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Text(HeaderDiagnostics.readout)
                            .font(.system(size: 12, design: .monospaced))
                        Text("header x \(Int(headerFrame.minX)) y \(Int(headerFrame.minY)) w \(Int(headerFrame.width)) h \(Int(headerFrame.height))")
                            .font(.system(size: 12, design: .monospaced))
                        Text("scroll: none — page does not scroll")
                            .font(.system(size: 12, design: .monospaced))
                        Text("Tap anywhere to close")
                            .font(.system(size: 11, design: .monospaced))
                            .opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(30)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsDiagnostics)
    }
}

/// TEMPORARY — what the folding phone's window really reports. Reads the key window's
/// own safe-area insets, which is what SwiftUI's layout was given. Shows only in
/// TestFlight and sandbox builds, never an App Store build; remove entirely before
/// the App Store submission.
enum HeaderDiagnostics {
    static let isEnabled = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"

    static var readout: String {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let window else { return "No key window" }
        let inset = window.safeAreaInsets
        return """
        window \(Int(window.bounds.size.width)) \u{d7} \(Int(window.bounds.size.height))
        insets  top \(inset.top)  left \(inset.left)
                bottom \(inset.bottom)  right \(inset.right)
        """
    }
}

/// The header row's frame in global coordinates, captured where it really landed.
private struct HeaderFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        if value == .zero { value = nextValue() }
    }
}
