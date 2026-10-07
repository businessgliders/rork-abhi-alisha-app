import SwiftUI

/// The Chat tab, guests first. Two large cards everyone shares sit at the top:
/// Announcements (read-only, no sign-in) and Questions & Chat (just a name). Below them,
/// a quiet "Start a family chat" button that asks for Sign in with Apple only when
/// tapped; or, for family, a waiting note or the family's conversations with the family
/// room pinned first. Everything opens from the phone's saved copy, then refreshes quietly.
struct ConversationListView: View {
    @Binding var path: [ChatRoute]

    @State private var store = ChatStore.shared
    @State private var session = ChatSession.shared
    @State private var updates = NotificationsStore.shared
    @State private var isComposing = false
    @State private var isAskingName = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false
    @State private var isShowingOutfits = false
    @State private var isShowingFamilySignIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if session.isFamilyMember, session.isAdmin, !store.pendingPeople.isEmpty {
                    waitingBanner
                        .padding(.top, 22)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                channels
                    .padding(.top, 22)

                familySection
                    .padding(.top, 30)
            }
            .padding(.horizontal, 20)
            .padding(.top, ScreenChrome.contentReserve)
            .padding(.bottom, FloatingTabBar.contentReserve + 24)
            .readableWidth()
        }
        .scrollIndicators(.hidden)
        .refreshable {
            async let feed: Void = updates.refresh()
            async let chats: Void = store.refreshAll()
            _ = await (feed, chats)
        }
        .background(BrandPalette.background.ignoresSafeArea())
        .animation(.calm, value: store.pendingPeople.count)
        .animation(.calm, value: session.phase)
        .animation(.calm, value: session.isAnonymous)
        .sheet(isPresented: $isComposing) {
            NewMessageSheet { id in
                isComposing = false
                path.append(.thread(id))
            }
        }
        .sheet(isPresented: $isAskingName) {
            GuestNameSheet {
                path.append(.openChannel)
            }
        }
        .sheet(isPresented: $isShowingFamilySignIn) {
            FamilySignInSheet()
        }
        .chatAccountDialogs(isConfirmingSignOut: $isConfirmingSignOut, isConfirmingDelete: $isConfirmingDelete)
        .fullScreenCover(isPresented: $isShowingOutfits) {
            MyOutfitsView()
        }
        .task {
            async let feed: Void = updates.refreshIfNeeded()
            async let chats: Void = store.refreshAll()
            _ = await (feed, chats)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ChatPageHeader(eyebrow: "The wedding table", title: "Chat")
            Spacer(minLength: 0)
            if session.isSignedIn {
                menu
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
    }

    private var menu: some View {
        Menu {
            if session.isFamilyMember, session.isAdmin {
                Section("For Abhi & Alisha") {
                    Button {
                        path.append(.approvals)
                    } label: {
                        Label(approvalsTitle, systemImage: "person.badge.clock")
                    }
                    Button {
                        path.append(.reports)
                    } label: {
                        Label(reportsTitle, systemImage: "flag")
                    }
                }
            }
            Section {
                Button {
                    isShowingOutfits = true
                } label: {
                    Label("My Outfits", systemImage: "hanger")
                }
            }
            Section {
                if session.phase != .blocked {
                    Button {
                        path.append(.blocked)
                    } label: {
                        Label("Blocked people", systemImage: "hand.raised")
                    }
                    Button {
                        session.isNamePromptPresented = true
                    } label: {
                        Label("Change my name", systemImage: "pencil")
                    }
                }
            }
            Section {
                Button {
                    isConfirmingSignOut = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete Account", systemImage: "trash")
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BrandPalette.goldDeep)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(BrandPalette.card))
                    .overlay(Circle().stroke(BrandPalette.hairline, lineWidth: 1))

                if showsAdminBadge {
                    Text("\(store.pendingPeople.count)")
                        .font(BrandLabel.font(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: 0xFFFBF1))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(BrandPalette.goldDeep))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .accessibilityLabel(showsAdminBadge
            ? "Chat menu, \(store.pendingPeople.count) waiting to join"
            : "Chat menu")
    }

    private var showsAdminBadge: Bool {
        session.isFamilyMember && session.isAdmin && !store.pendingPeople.isEmpty
    }

    private var approvalsTitle: String {
        let count = store.pendingPeople.count
        return count > 0 ? "Approvals (\(count))" : "Approvals"
    }

    private var reportsTitle: String {
        let count = store.reports.count
        return count > 0 ? "Reports (\(count))" : "Reports"
    }

    // MARK: - Admin banner

    private var waitingBanner: some View {
        let count = store.pendingPeople.count
        return Button {
            BrandHaptics.tick()
            path.append(.approvals)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.badge.clock")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(Color(hex: 0xFFFBF1))

                Text(count == 1 ? "1 person waiting to join" : "\(count) people waiting to join")
                    .font(Font(BrandFont.uiFont(.playfairItalic, size: 18, weight: 500, textStyle: .headline, maxSize: 26)))
                    .foregroundStyle(Color(hex: 0xFFFBF1))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFFFBF1).opacity(0.85))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: 0xE0C982).opacity(0.5), lineWidth: 0.75)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens Approvals")
    }

    // MARK: - Shared channels

    private var channels: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "For every guest", size: 9.5)
                .padding(.leading, 4)
                .padding(.bottom, 2)

            Button {
                BrandHaptics.tick()
                path.append(.announcements)
            } label: {
                ChannelRow(
                    badge: .announcements,
                    title: "Announcements",
                    preview: announcementPreview,
                    time: updates.latest?.sentAt,
                    isUnread: updates.hasUnread,
                    isHighlighted: true
                )
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("From Abhi & Alisha, read only")

            Button(action: openQuestions) {
                ChannelRow(
                    badge: .questions,
                    title: "Questions & Chat",
                    preview: questionsPreview,
                    time: store.openConversation.map(store.lastActivity).flatMap { $0 == .distantPast ? nil : $0 },
                    isUnread: store.openConversation.map(store.isUnread) ?? false,
                    isMuted: store.openConversation.map { store.isMuted($0.id) } ?? false,
                    isHighlighted: false
                )
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint(session.isSignedIn ? "Open to every guest" : "Asks for your name, then opens the chat")
        }
    }

    private var announcementPreview: String {
        guard let latest = updates.latest else { return "News from Abhi & Alisha will appear here" }
        return latest.title ?? latest.body ?? "A note from Abhi & Alisha"
    }

    private var questionsPreview: String {
        if !session.isSignedIn { return "Ask anything. Just your name needed" }
        if session.phase == .blocked { return "Not available" }
        guard let conversation = store.openConversation,
              store.previews[conversation.id] != nil else {
            return "Ask anything, chat with every guest"
        }
        return store.previewText(for: conversation)
    }

    private func openQuestions() {
        BrandHaptics.tick()
        if session.isSignedIn {
            path.append(.openChannel)
        } else {
            isAskingName = true
        }
    }

    // MARK: - Family chat

    @ViewBuilder
    private var familySection: some View {
        if !session.isSignedIn || session.isAnonymous {
            if session.phase == .loading && !session.isSignedIn {
                EmptyView()
            } else {
                StartFamilyChatButton { isShowingFamilySignIn = true }
                    .transition(.opacity)
            }
        } else {
            switch session.phase {
            case .loading:
                FamilyGateCard(kind: .opening)
            case .pending:
                FamilyGateCard(kind: .waiting)
            case .blocked:
                FamilyGateCard(kind: .unavailable)
            case .signedOut:
                StartFamilyChatButton { isShowingFamilySignIn = true }
            case .approved:
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "The family", size: 9.5)
                        .padding(.leading, 4)

                    newMessageButton
                        .padding(.top, 12)

                    list
                        .padding(.top, 12)
                }
                .transition(.opacity)
            }
        }
    }

    private var newMessageButton: some View {
        Button {
            BrandHaptics.soft()
            isComposing = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .regular))
                Text("New message")
                    .font(BrandLabel.font(size: 12, weight: .semibold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            .foregroundStyle(BrandPalette.goldDeep)
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BrandPalette.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BrandPalette.gold.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private var list: some View {
        let conversations = store.sortedConversations
        if conversations.isEmpty {
            if store.hasLoadedList {
                ChatEmptyNote(text: "Your conversations will gather here. Start one with “New message”.")
            } else {
                VStack(spacing: 18) {
                    BreathingCrest(width: 84)
                    Text("Gathering the family")
                        .brandFont(.bodyItalic)
                        .foregroundStyle(BrandPalette.body)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(conversations) { conversation in
                    Button {
                        BrandHaptics.tick()
                        path.append(.thread(conversation.id))
                    } label: {
                        ConversationRow(conversation: conversation)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

/// One of the two shared channels: a large card, front and centre for every guest.
private struct ChannelRow: View {
    let badge: ChannelBadge.Kind
    let title: String
    let preview: String
    let time: Date?
    let isUnread: Bool
    var isMuted: Bool = false
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ChannelBadge(kind: badge, size: 56)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .brandFont(.chatName)
                        .foregroundStyle(BrandPalette.ink)
                        .lineLimit(1)

                    if isMuted {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(BrandPalette.body.opacity(0.7))
                            .accessibilityLabel("Muted")
                    }

                    Spacer(minLength: 6)

                    if let time {
                        Text(ChatTime.listStamp(time))
                            .font(BrandLabel.font(size: 11, weight: isUnread ? .semibold : .regular))
                            .foregroundStyle(isUnread ? BrandPalette.goldDeep : BrandPalette.body.opacity(0.8))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Text(preview)
                        .brandFont(.chatPreview)
                        .foregroundStyle(isUnread ? BrandPalette.ink : BrandPalette.body)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isUnread {
                        UnreadDot()
                            .padding(.top, 6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                HStack(spacing: 6) {
                    Text(badge == .announcements ? "Read the latest" : "Open the chat")
                        .font(BrandLabel.font(size: 10.5, weight: .semibold))
                        .tracking(1.3)
                        .textCase(.uppercase)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundStyle(BrandPalette.goldDeep)
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isHighlighted ? AnyShapeStyle(BrandPalette.gold.opacity(0.1)) : AnyShapeStyle(BrandPalette.card))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BrandPalette.gold.opacity(isHighlighted ? 0.5 : 0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 6)
        .animation(.calm, value: isUnread)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? "Unread" : "")
    }
}

/// The one quiet way into the family chat for guests: a slim button and a single line.
private struct StartFamilyChatButton: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                BrandHaptics.soft()
                action()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .symbolVariant(.none)
                        .font(.system(size: 15, weight: .light))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(BrandPalette.gold.opacity(0.45), lineWidth: 1))
                    Text("Start a family chat")
                        .font(BrandLabel.font(size: 12, weight: .semibold))
                        .tracking(1.4)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .light))
                }
                .foregroundStyle(BrandPalette.goldDeep)
                .padding(.horizontal, 14)
                .frame(minHeight: 58)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BrandPalette.card))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("For family. Asks you to sign in with Apple.")

            Text("For family: a private room, small groups and one-to-one chats.")
                .brandFont(.bodySmall)
                .foregroundStyle(BrandPalette.body.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
    }
}

/// Explains that Abhi & Alisha welcome each family member in, with Sign in with Apple
/// underneath. Closes itself once the sign-in has gone through.
private struct FamilySignInSheet: View {
    @State private var session = ChatSession.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                FamilyInviteCard()

                Button("Not now") {
                    BrandHaptics.tick()
                    dismiss()
                }
                .font(BrandLabel.font(size: 11, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(BrandPalette.body.opacity(0.8))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 20)
            .readableWidth(480)
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .onChange(of: session.isAnonymous) { _, _ in closeIfSignedIn() }
        .onChange(of: session.userID) { _, _ in closeIfSignedIn() }
    }

    private func closeIfSignedIn() {
        guard session.isSignedIn, !session.isAnonymous else { return }
        BrandHaptics.tick()
        dismiss()
    }
}

/// One conversation: avatar, name, last line, time, and the unread dot.
private struct ConversationRow: View {
    let conversation: ChatConversation

    @State private var store = ChatStore.shared

    var body: some View {
        let isFamily = store.isFamily(conversation)
        let isUnread = store.isUnread(conversation)
        let activity = store.lastActivity(conversation)

        HStack(spacing: 12) {
            ChatAvatar(
                initials: store.initials(for: conversation),
                size: 48,
                showsCrest: isFamily
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.title(for: conversation))
                        .brandFont(.chatName)
                        .foregroundStyle(BrandPalette.ink)
                        .lineLimit(1)

                    if isFamily {
                        Image(systemName: "pin")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(BrandPalette.gold)
                            .accessibilityLabel("Pinned")
                    }

                    Spacer(minLength: 6)

                    if activity != .distantPast {
                        Text(ChatTime.listStamp(activity))
                            .font(BrandLabel.font(size: 11, weight: isUnread ? .semibold : .regular))
                            .foregroundStyle(isUnread ? BrandPalette.goldDeep : BrandPalette.body.opacity(0.8))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .center, spacing: 8) {
                    Text(store.previewText(for: conversation))
                        .brandFont(.chatPreview)
                        .foregroundStyle(isUnread ? BrandPalette.ink : BrandPalette.body)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isUnread {
                        UnreadDot()
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(BrandPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isFamily ? BrandPalette.gold.opacity(0.4) : BrandPalette.hairline, lineWidth: 1)
        )
        .animation(.calm, value: isUnread)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isUnread ? "Unread" : "")
    }
}
