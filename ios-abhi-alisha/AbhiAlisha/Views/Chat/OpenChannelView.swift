import SwiftUI

/// Questions & Chat: finds the open conversation this person was added to, then shows
/// it as an ordinary thread. Someone who has been removed sees only a quiet note.
struct OpenChannelView: View {
    @State private var session = ChatSession.shared
    @State private var store = ChatStore.shared
    @State private var didGiveUp = false

    var body: some View {
        Group {
            if session.phase == .blocked {
                note(
                    title: "You've been removed from this chat",
                    line: nil
                )
            } else if let conversation = store.openConversation {
                ChatThreadView(conversationID: conversation.id)
            } else if didGiveUp {
                note(
                    title: "Questions & Chat isn't open just yet",
                    line: "Pull down on Chat to check again in a moment."
                )
            } else {
                opening
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.softFade, value: store.openConversation?.id)
        .task { await find() }
    }

    /// A brand-new guest is added by the server a beat after their account exists, so
    /// the list is asked again a few times before saying so.
    private func find() async {
        let delays: [Duration] = [.zero, .milliseconds(800), .seconds(1.5), .seconds(2.5), .seconds(4)]
        for delay in delays {
            guard store.openConversation == nil, session.phase != .blocked else { return }
            if delay > .zero { try? await Task.sleep(for: delay) }
            if Task.isCancelled { return }
            await store.refreshAll()
        }
        if store.openConversation == nil { didGiveUp = true }
    }

    private var opening: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            VStack(spacing: 18) {
                BreathingCrest(width: 84)
                Text("Opening Questions & Chat")
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
            }
            Spacer(minLength: 0)
        }
        .background(BrandPalette.background.ignoresSafeArea())
    }

    private func note(title: String, line: String?) -> some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                IconWatermark(key: .paisley, size: 70, opacity: 0.3)
                Text(title)
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                GoldRule(width: 36)
                if let line {
                    Text(line)
                        .brandFont(.bodyItalic)
                        .foregroundStyle(BrandPalette.body)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .background(BrandPalette.background.ignoresSafeArea())
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            ChatBackButton()
            ChannelBadge(kind: .questions, size: 36)
            Text("Questions & Chat")
                .brandFont(.chatName)
                .foregroundStyle(BrandPalette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BrandPalette.hairline).frame(height: 1)
        }
    }
}
