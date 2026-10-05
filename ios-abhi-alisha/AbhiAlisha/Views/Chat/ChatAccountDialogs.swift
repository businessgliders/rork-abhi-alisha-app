import SwiftUI

/// The confirmations behind "Sign out" and "Delete account", shared by every chat screen
/// that offers them, plus the calm note if a deletion couldn't go through.
private struct ChatAccountDialogs: ViewModifier {
    @Binding var isConfirmingSignOut: Bool
    @Binding var isConfirmingDelete: Bool

    @State private var session = ChatSession.shared

    func body(content: Content) -> some View {
        @Bindable var session = session

        content
            .alert(session.isAnonymous ? "Leave Questions & Chat?" : "Sign out of the chat?", isPresented: $isConfirmingSignOut) {
                Button("Sign Out", role: .destructive) {
                    Task { await session.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(session.isAnonymous
                     ? "You joined with just a name, so this phone won't be able to come back as you. Your messages stay in the chat. You can join again with a name any time."
                     : "Your messages stay with the family. You can sign in again any time.")
            }
            .alert("Delete your account?", isPresented: $isConfirmingDelete) {
                Button("Delete Account", role: .destructive) {
                    Task { await session.deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes your name and all of your messages from the chat. It can't be undone.")
            }
            .alert("Nothing was deleted", isPresented: $session.didDeleteFail) {
                Button("Try Again") {
                    Task { await session.deleteAccount() }
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("We couldn't reach the chat just now, so your account is exactly as it was. Please try again in a moment.")
            }
            .overlay {
                if session.isDeletingAccount {
                    ZStack {
                        BrandPalette.background.opacity(0.88).ignoresSafeArea()
                        VStack(spacing: 18) {
                            BreathingCrest(width: 92)
                            Text("Deleting your account")
                                .brandFont(.bodyItalic)
                                .foregroundStyle(BrandPalette.body)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.softFade, value: session.isDeletingAccount)
    }
}

extension View {
    /// Attaches the sign-out and delete-account confirmations.
    func chatAccountDialogs(isConfirmingSignOut: Binding<Bool>, isConfirmingDelete: Binding<Bool>) -> some View {
        modifier(ChatAccountDialogs(isConfirmingSignOut: isConfirmingSignOut, isConfirmingDelete: isConfirmingDelete))
    }
}

/// The pressed crest, slowly breathing, for moments of waiting.
struct BreathingCrest: View {
    var width: CGFloat = 120

    @State private var isBreathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CrestWatermark(width: width, finish: .pressed(BrandPalette.background))
            .scaleEffect(isBreathing ? 1.035 : 0.975)
            .opacity(isBreathing ? 1 : 0.78)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }
}
