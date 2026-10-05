import SwiftUI

/// The family's conversations: the family room pinned at the top, then whatever spoke
/// most recently. Opens from the phone's saved copy, then refreshes quietly.
struct ConversationListView: View {
    @Binding var path: [ChatRoute]

    @State private var store = ChatStore.shared
    @State private var session = ChatSession.shared
    @State private var isComposing = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if session.isAdmin, !store.pendingPeople.isEmpty {
                    waitingBanner
                        .padding(.top, 22)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                newMessageButton
                    .padding(.top, 22)

                list
                    .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, ScreenChrome.contentReserve)
            .padding(.bottom, FloatingTabBar.contentReserve + 24)
            .readableWidth()
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refreshAll() }
        .background(BrandPalette.background.ignoresSafeArea())
        .animation(.calm, value: store.pendingPeople.count)
        .sheet(isPresented: $isComposing) {
            NewMessageSheet { id in
                isComposing = false
                path.append(.thread(id))
            }
        }
        .chatAccountDialogs(isConfirmingSignOut: $isConfirmingSignOut, isConfirmingDelete: $isConfirmingDelete)
        .task { await store.refreshAll() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ChatPageHeader(eyebrow: "The family table", title: "Chat")
            Spacer(minLength: 0)
            menu
                .padding(.top, 4)
        }
    }

    private var menu: some View {
        Menu {
            if session.isAdmin {
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

                if session.isAdmin, !store.pendingPeople.isEmpty {
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
        .accessibilityLabel(session.isAdmin && !store.pendingPeople.isEmpty
            ? "Chat menu, \(store.pendingPeople.count) waiting to join"
            : "Chat menu")
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

    // MARK: - New message

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

    // MARK: - List

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
                .padding(.top, 60)
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
