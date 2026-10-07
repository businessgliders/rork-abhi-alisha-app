import SwiftUI
import UIKit

/// One line in a thread: a confirmed message, or one still on its way.
private enum ThreadItem: Identifiable, Equatable {
    case sent(ChatMessage)
    case pending(PendingMessage)

    var id: String {
        switch self {
        case .sent(let message): return message.id.uuidString
        case .pending(let pending): return "pending-" + pending.clientID.uuidString
        }
    }

    var senderID: UUID {
        switch self {
        case .sent(let message): return message.senderID
        case .pending(let pending): return pending.senderID
        }
    }

    var createdAt: Date {
        switch self {
        case .sent(let message): return message.createdAt
        case .pending(let pending): return pending.createdAt
        }
    }
}

/// A conversation. The newest fifty messages, older ones as you scroll up, new ones live.
struct ChatThreadView: View {
    let conversationID: UUID

    @State private var store = ChatStore.shared
    @State private var outbox = ChatOutbox.shared
    @State private var session = ChatSession.shared
    @State private var draft = ""
    @State private var toast: String?
    @State private var confirmingBlock: ChatMessage?
    @State private var confirmingRemoval: ChatMessage?
    @State private var isChangingMute = false
    @State private var confirmingDelete: ChatMessage?
    @State private var isConfirmingLeave = false
    @State private var isShowingMembers = false
    @State private var sendTick = 0
    @State private var isShowingGuidelines = false
    @FocusState private var isComposerFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var conversation: ChatConversation? { store.conversation(conversationID) }

    private var isGroupLike: Bool {
        guard let conversation else { return true }
        return !store.isDirect(conversation)
    }

    /// Questions & Chat, open to every guest.
    private var isOpenChannel: Bool { conversation?.isOpen == true }

    private var canLeave: Bool {
        guard let conversation else { return false }
        return store.isGroup(conversation)
    }

    private var items: [ThreadItem] {
        let sent = store.messages(in: conversationID)
        let delivered = Set(sent.compactMap(\.clientID))
        let pending = outbox.pending(in: conversationID).filter { !delivered.contains($0.clientID) }
        return sent.map(ThreadItem.sent) + pending.map(ThreadItem.pending)
    }

    private var thread: ChatThreadState? { store.threads[conversationID] }

    var body: some View {
        VStack(spacing: 0) {
            header
            messagesView
        }
        .background(BrandPalette.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if let toast {
                ChatToast(text: toast)
                    .padding(.top, 70)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.calm, value: toast)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: sendTick)
        .onAppear { store.openThread(conversationID) }
        .onDisappear { store.closeThread(conversationID) }
        .confirmationDialog(
            "Block \(confirmingBlock.map { store.name(of: $0.senderID) } ?? "this person")?",
            isPresented: Binding(get: { confirmingBlock != nil }, set: { if !$0 { confirmingBlock = nil } }),
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                if let message = confirmingBlock { block(message.senderID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see their messages anywhere in the chat. You can unblock them from Blocked people.")
        }
        .confirmationDialog(
            "Remove \(confirmingRemoval.map { store.name(of: $0.senderID) } ?? "this person") from the chat?",
            isPresented: Binding(get: { confirmingRemoval != nil }, set: { if !$0 { confirmingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove from Chat", role: .destructive) {
                if let message = confirmingRemoval { remove(message.senderID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll no longer be able to read or post in Questions & Chat, or the family chat.")
        }
        .confirmationDialog(
            "Delete this message?",
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete for Everyone", role: .destructive) {
                if let message = confirmingDelete { delete(message) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will read “Message deleted” for everyone.")
        }
        .confirmationDialog("Leave this group?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button("Leave Group", role: .destructive, action: leave)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop receiving its messages. Someone in the group can add you again.")
        }
        .sheet(isPresented: $isShowingMembers) {
            GroupMembersSheet(conversationID: conversationID)
        }
        .sheet(isPresented: $isShowingGuidelines) {
            CommunityGuidelinesSheet {
                send()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                BrandHaptics.tick()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(BrandPalette.goldDeep)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Chat")

            if let conversation {
                if conversation.isOpen {
                    ChannelBadge(kind: .questions, size: 36)
                } else {
                    ChatAvatar(
                        initials: store.initials(for: conversation),
                        size: 36,
                        showsCrest: store.isFamily(conversation)
                    )
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.title(for: conversation))
                        .brandFont(.chatName)
                        .foregroundStyle(BrandPalette.ink)
                        .lineLimit(1)

                    if isGroupLike {
                        Text(memberLine)
                            .font(BrandLabel.font(size: 11, weight: .medium))
                            .foregroundStyle(BrandPalette.body)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 0)

            if isOpenChannel {
                muteButton
            } else if isGroupLike {
                Menu {
                    Button {
                        isShowingMembers = true
                    } label: {
                        Label("Who's here", systemImage: "person.2")
                    }
                    if canLeave {
                        Button(role: .destructive) {
                            isConfirmingLeave = true
                        } label: {
                            Label("Leave Group", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(BrandPalette.goldDeep)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Group options")
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

    private var memberLine: String {
        if isOpenChannel {
            return store.isMuted(conversationID) ? "Open to every guest · Muted" : "Open to every guest"
        }
        let count = store.memberIDs(of: conversationID).count
        return count == 1 ? "1 person" : "\(count) people"
    }

    /// Mutes or unmutes pushes for this chat only. Announcements are never muted.
    private var muteButton: some View {
        let isMuted = store.isMuted(conversationID)
        return Button {
            guard !isChangingMute else { return }
            BrandHaptics.tick()
            isChangingMute = true
            Task {
                let done = await store.setMuted(!isMuted, in: conversationID)
                isChangingMute = false
                if done {
                    showToast(isMuted ? "Notifications on for this chat" : "Muted. Announcements still come through.")
                } else {
                    showToast("That couldn't be changed just now.")
                }
            }
        } label: {
            Image(systemName: isMuted ? "bell.slash" : "bell")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isMuted ? BrandPalette.body : BrandPalette.goldDeep)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMuted ? "Unmute this chat" : "Mute this chat")
    }

    // MARK: - Messages

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    topOfThread

                    let list = items
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        let previous = index > 0 ? list[index - 1] : nil
                        let next = index + 1 < list.count ? list[index + 1] : nil

                        if showsDayHeader(item, after: previous) {
                            dayHeader(item.createdAt)
                        }

                        row(for: item, previous: previous, next: next)
                            .id(item.id)
                    }

                    Color.clear
                        .frame(height: 8)
                        .id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .readableWidth(720)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: items.last?.id) { _, _ in
                withAnimation(.calm) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: isComposerFocused) { _, focused in
                guard focused else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(.calm) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .environment(\.chatScrollToItem, { id in
                proxy.scrollTo(id, anchor: .top)
            })
        }
    }

    /// The top of the thread: a quiet loader for older messages, or the beginning.
    @ViewBuilder
    private var topOfThread: some View {
        if let thread, thread.hasMore, !(thread.messages.isEmpty) {
            OlderMessagesLoader(conversationID: conversationID, oldestID: items.first?.id)
        } else if thread?.didLoad == true || !items.isEmpty {
            VStack(spacing: 10) {
                IconWatermark(key: .paisley, size: 46, opacity: 0.35)
                Text(items.isEmpty ? "Say hello to start the conversation." : "The beginning of the conversation")
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            BreathingCrest(width: 60)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
        }
    }

    private func showsDayHeader(_ item: ThreadItem, after previous: ThreadItem?) -> Bool {
        guard let previous else { return true }
        return !Calendar.current.isDate(item.createdAt, inSameDayAs: previous.createdAt)
    }

    private func dayHeader(_ date: Date) -> some View {
        Text(ChatTime.dayHeader(date).uppercased())
            .font(BrandLabel.font(size: 10, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(BrandPalette.gold)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func row(for item: ThreadItem, previous: ThreadItem?, next: ThreadItem?) -> some View {
        let isMine = item.senderID == store.me
        let startsRun = previous?.senderID != item.senderID || showsDayHeader(item, after: previous)
        let endsRun = next?.senderID != item.senderID || (next.map { showsDayHeader($0, after: item) } ?? true)
        let showsName = isGroupLike && !isMine && startsRun

        VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
            if showsName {
                Text(store.name(of: item.senderID))
                    .brandFont(.chatSender)
                    .foregroundStyle(BrandPalette.goldDeep)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            switch item {
            case .sent(let message):
                MessageBubble(
                    text: message.displayText,
                    time: message.createdAt,
                    isMine: isMine,
                    isDeleted: message.isDeleted,
                    status: nil
                )
                .contextMenu {
                    menu(for: message, isMine: isMine)
                }

            case .pending(let pending):
                MessageBubble(
                    text: pending.body,
                    time: pending.createdAt,
                    isMine: true,
                    isDeleted: false,
                    status: pending.state
                )
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = pending.body
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    if pending.state == .failed {
                        Button {
                            outbox.retry(pending.clientID)
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                        }
                        Button(role: .destructive) {
                            outbox.discard(pending.clientID)
                        } label: {
                            Label("Don't Send", systemImage: "trash")
                        }
                    }
                }
                .onTapGesture {
                    guard pending.state == .failed else { return }
                    BrandHaptics.tick()
                    outbox.retry(pending.clientID)
                }

                if pending.state == .failed {
                    Button {
                        BrandHaptics.tick()
                        outbox.retry(pending.clientID)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.circle")
                            Text("Not sent · Tap to retry")
                        }
                        .font(BrandLabel.font(size: 11, weight: .semibold))
                        .foregroundStyle(BrandPalette.overdue)
                        .frame(minHeight: 30)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(isMine ? .leading : .trailing, 54)
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .padding(.bottom, endsRun ? 10 : 3)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity
        ))
    }

    @ViewBuilder
    private func menu(for message: ChatMessage, isMine: Bool) -> some View {
        if !message.isDeleted {
            Button {
                UIPasteboard.general.string = message.displayText
                showToast("Copied")
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if isMine {
                Button(role: .destructive) {
                    confirmingDelete = message
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button {
                    report(message)
                } label: {
                    Label("Report", systemImage: "flag")
                }
                Button(role: .destructive) {
                    confirmingBlock = message
                } label: {
                    Label("Block \(store.firstName(of: message.senderID))", systemImage: "hand.raised")
                }
            }
        }

        if isOpenChannel, session.isAdmin, !isMine {
            Divider()
            Button(role: .destructive) {
                confirmingRemoval = message
            } label: {
                Label("Remove from Chat", systemImage: "person.crop.circle.badge.xmark")
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 6) {
            if !outbox.isOnline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                    Text("You're offline. Messages will send when you're back.")
                }
                .font(BrandLabel.font(size: 11, weight: .medium))
                .foregroundStyle(BrandPalette.body)
                .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($isComposerFocused)
                    .brandFont(.chatMessage)
                    .foregroundStyle(BrandPalette.ink)
                    .tint(BrandPalette.goldDeep)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .fill(BrandPalette.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .stroke(isComposerFocused ? BrandPalette.gold.opacity(0.55) : BrandPalette.hairline, lineWidth: 1)
                    )
                    .animation(.calm, value: isComposerFocused)

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFFFBF1))
                        .frame(width: 46, height: 46)
                        .background(
                            Circle().fill(
                                LinearGradient(
                                    colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        )
                        .overlay(Circle().stroke(Color(hex: 0xE0C982).opacity(0.5), lineWidth: 0.75))
                        .opacity(canSend ? 1 : 0.4)
                        .scaleEffect(canSend ? 1 : 0.92)
                        .animation(.calm, value: canSend)
                }
                .buttonStyle(PressableStyle())
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .readableWidth(720)
        .background(
            BrandPalette.background
                .overlay(alignment: .top) {
                    Rectangle().fill(BrandPalette.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.softFade, value: outbox.isOnline)
    }

    private var canSend: Bool { ChatJSON.clean(draft) != nil }

    // MARK: - Actions

    private func send() {
        guard let text = ChatJSON.clean(draft) else { return }
        // The first post on this phone waits for the guidelines; the draft stays put.
        guard CommunityGuidelines.isAccepted else {
            isComposerFocused = false
            isShowingGuidelines = true
            return
        }
        sendTick += 1
        draft = ""
        withAnimation(.calm) {
            outbox.enqueue(text, in: conversationID)
        }
    }

    private func delete(_ message: ChatMessage) {
        Task {
            let done = await store.delete(message)
            if !done { showToast("That message couldn't be deleted just now.") }
        }
    }

    private func report(_ message: ChatMessage) {
        BrandHaptics.soft()
        Task {
            let done = await store.report(message)
            showToast(done ? "Thanks — the organizers will review this within 24 hours." : "That report couldn't be sent just now.")
        }
    }

    private func block(_ person: UUID) {
        Task {
            let done = await store.block(person)
            showToast(done ? "Blocked. You can undo this in Blocked people." : "That couldn't be saved just now.")
        }
    }

    private func remove(_ person: UUID) {
        Task {
            let done = await store.removeFromChat(person)
            showToast(done ? "Removed from the chat." : "That couldn't be done just now.")
        }
    }

    private func leave() {
        Task {
            if await store.leave(conversationID) {
                dismiss()
            } else {
                showToast("You couldn't leave just now. Please try again.")
            }
        }
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if toast == text { toast = nil }
        }
    }
}

// MARK: - Bubble

/// One message: soft gold on the right for mine, white with a hairline on the left for
/// everyone else's. Cormorant for the words, tiny SF Pro for the time.
private struct MessageBubble: View {
    let text: String
    let time: Date
    let isMine: Bool
    let isDeleted: Bool
    let status: PendingMessage.State?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)

        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .brandFont(isDeleted ? .chatMessageItalic : .chatMessage)
                .foregroundStyle(isDeleted ? BrandPalette.body : BrandPalette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Text(ChatTime.clock(time))
                if let status {
                    switch status {
                    case .queued, .sending:
                        Image(systemName: "clock")
                            .accessibilityLabel("Waiting to send")
                    case .failed:
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(BrandPalette.overdue)
                            .accessibilityLabel("Not sent")
                    }
                }
            }
            .font(BrandLabel.font(size: 9.5, weight: .medium))
            .foregroundStyle(BrandPalette.body.opacity(0.75))
            .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .background(shape.fill(isMine ? BrandPalette.gold.opacity(0.17) : BrandPalette.card))
        .overlay(shape.stroke(isMine ? BrandPalette.gold.opacity(0.35) : BrandPalette.hairline, lineWidth: 1))
        .contentShape(.contextMenuPreview, shape)
        .opacity(status == .sending || status == .queued ? 0.82 : 1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Older messages

extension EnvironmentValues {
    /// Lets the older-messages loader keep the reader's place after a page arrives.
    @Entry var chatScrollToItem: (String) -> Void = { _ in }
}

/// Appears at the top of the thread; when scrolled into view it fetches the previous
/// page, then puts the reader back on the message they were looking at.
private struct OlderMessagesLoader: View {
    let conversationID: UUID
    let oldestID: String?

    @Environment(\.chatScrollToItem) private var scrollToItem
    @State private var store = ChatStore.shared

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(BrandPalette.gold)
            Text("Earlier messages")
                .font(BrandLabel.font(size: 10, weight: .semibold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(BrandPalette.body)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .onAppear(perform: load)
    }

    private func load() {
        let anchor = oldestID
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await store.loadOlder(conversationID)
            if let anchor {
                scrollToItem(anchor)
            }
        }
    }
}

// MARK: - Members

/// Who is in a group, in alphabetical order.
private struct GroupMembersSheet: View {
    let conversationID: UUID

    @State private var store = ChatStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ChatPageHeader(eyebrow: "In this conversation", title: "Who's here")
                    Button("Done") { dismiss() }
                        .font(BrandLabel.font(size: 13, weight: .medium))
                        .foregroundStyle(BrandPalette.goldDeep)
                        .frame(minHeight: 44)
                }

                VStack(spacing: 8) {
                    ForEach(store.memberIDs(of: conversationID), id: \.self) { id in
                        HStack(spacing: 12) {
                            ChatAvatar(initials: store.profile(id)?.initials ?? "·", size: 40)
                            Text(store.name(of: id))
                                .brandFont(.chatName)
                                .foregroundStyle(BrandPalette.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BrandPalette.card))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
    }
}
