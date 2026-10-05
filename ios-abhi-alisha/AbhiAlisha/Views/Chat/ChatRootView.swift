import SwiftUI

/// The Chat tab. Who you are decides what you see: an invitation to sign in, a calm
/// waiting room, a closed door, or the family's conversations.
struct ChatRootView: View {
    /// Whether the Chat tab is the one on screen; the name sheet only rises here.
    var isActive: Bool = true

    @State private var session = ChatSession.shared
    @State private var path: [ChatRoute] = []
    @Environment(DeepLinkRouter.self) private var router

    var body: some View {
        @Bindable var session = session

        NavigationStack(path: $path) {
            Group {
                switch session.phase {
                case .loading:
                    ChatGateView(kind: .opening)
                case .signedOut:
                    ChatSignedOutView()
                case .pending:
                    ChatGateView(kind: .waiting)
                case .blocked:
                    ChatGateView(kind: .unavailable)
                case .approved:
                    ConversationListView(path: $path)
                }
            }
            .transition(.opacity)
            .animation(.softFade, value: session.phase)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ChatRoute.self) { route in
                switch route {
                case .thread(let id):
                    ChatThreadView(conversationID: id)
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
            if phase != .approved { path = [] }
            openPendingConversation()
        }
        .onChange(of: router.pendingConversationID) { _, _ in
            openPendingConversation()
        }
        .onAppear(perform: openPendingConversation)
    }

    /// A chat notification tap opens its conversation, once the person is allowed in.
    private func openPendingConversation() {
        guard session.phase == .approved, let id = router.pendingConversationID else { return }
        router.pendingConversationID = nil
        if case .thread(let current) = path.last, current == id { return }
        path = [.thread(id)]
    }
}
