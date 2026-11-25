import SwiftUI

/// The confirmations behind "Sign out" and "Delete account", shared by every chat screen
/// that offers them, plus the calm note if a deletion couldn't go through.
private struct ChatAccountDialogs: ViewModifier {
    @Binding var isConfirmingSignOut: Bool
    @Binding var isConfirmingDelete: Bool

    @State private var session = ChatSession.shared
    @State private var account = AccountDeletion.shared

    func body(content: Content) -> some View {
        @Bindable var session = session
        @Bindable var account = account

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
                    // Apple accounts get one more themed step, with the Apple copy,
                    // before the Apple sheet appears. Guests delete straight away.
                    if session.isSignedIn && !session.isAnonymous {
                        account.isConfirmSheetPresented = true
                    } else {
                        Task { await AccountDeletion.shared.start() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes your name and all of your messages from the chat. It can't be undone.")
            }
            .sheet(isPresented: $account.isConfirmSheetPresented) {
                DeleteAccountConfirmSheet(isAppleAccount: session.isSignedIn && !session.isAnonymous)
            }
            .sheet(isPresented: $account.isHostingSheetPresented) {
                HostWeddingsSheet()
            }
            .alert("Nothing was deleted", isPresented: $account.didFail) {
                Button("Try Again") {
                    Task { await AccountDeletion.shared.start() }
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("We couldn't reach the chat just now, so your account is exactly as it was. Please try again in a moment.")
            }
            .overlay {
                if account.isDeleting {
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
            .animation(.softFade, value: account.isDeleting)
            .onChange(of: account.didFinishDeletion) {
                // The account is gone: leave Settings and land on the welcome screen.
                if account.didFinishDeletion { dismiss() }
            }
    }

    @Environment(\.dismiss) private var dismiss
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
