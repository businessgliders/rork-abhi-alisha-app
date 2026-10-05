import SwiftUI

/// The Chat tab. Announcements and Questions & Chat are always at the top, for every
/// guest; below them the family chat shows whatever fits this person: an invitation,
/// a waiting note, or the family's conversations.
struct ChatRootView: View {
    /// Whether the Chat tab is the one on screen; the name sheet only rises here.
    var isActive: Bool = true

    @State private var session = ChatSession.shared
    @State private var store = ChatStore.shared
    @State private var path: [ChatRoute] = []
    @Environment(DeepLinkRouter.self) private var router

    var body: some View {
        @Bindable var session = session

        NavigationStack(path: $path) {
            ConversationListView(path: $path)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: ChatRoute.self) { route in
                    switch route {
                    case .announcements:
                        AnnouncementsView()
                    case .openChannel:
                        OpenChannelView()
                    case .thread(let id):
                        if store.conversation(id)?.isOpen == true {
                            OpenChannelView()
                        } else {
                            ChatThreadView(conversationID: id)
                        }
                    case .blocked:
                        BlockedPeopleView()
                    case .approvals:
                        ApprovalsView()
                    case .reports:
                        ReportsView()
                    }
                }
        }
        .tint(BrandPalette.goldDeep)
        .sheet(isPresented: Binding(
            get: { isActive && session.isNamePromptPresented },
            set: { if !$0 { session.isNamePromptPresented = false } }
        )) {
            ChatNameSheet()
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .signedOut {
                path.removeAll { route in
                    switch route {
                    case .announcements, .openChannel: return false
                    default: return true
                    }
                }
            }
            openPendingConversation()
        }
        .onChange(of: session.isFamilyMember) { _, isMember in
            // Family-only pages close if this person is no longer in the family chat.
            guard !isMember else { return }
            path.removeAll { route in
                switch route {
                case .blocked, .approvals, .reports: return true
                case .thread(let id): return store.conversation(id)?.isOpen != true
                default: return false
                }
            }
        }
        .onChange(of: router.pendingConversationID) { _, _ in
            openPendingConversation()
        }
        .onChange(of: router.pendingAnnouncements) { _, _ in
            openPendingAnnouncements()
        }
        .onChange(of: isActive) { _, active in
            guard active else { return }
            Task { await NotificationsStore.shared.refreshIfNeeded() }
        }
        .onAppear {
            openPendingConversation()
            openPendingAnnouncements()
        }
    }

    /// A chat notification tap opens its conversation, once the person is signed in.
    private func openPendingConversation() {
        guard session.isSignedIn, session.phase != .loading,
              let id = router.pendingConversationID else { return }
        router.pendingConversationID = nil
        if store.openConversation?.id == id || store.conversation(id)?.isOpen == true {
            if path.last == .openChannel { return }
            path = [.openChannel]
            return
        }
        guard session.isFamilyMember else { return }
        if case .thread(let current) = path.last, current == id { return }
        path = [.thread(id)]
    }

    /// An announcement tap opens the feed, whoever is (or isn't) signed in.
    private func openPendingAnnouncements() {
        guard router.pendingAnnouncements else { return }
        router.pendingAnnouncements = false
        if path.last == .announcements { return }
        path = [.announcements]
    }
}
