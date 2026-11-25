import AuthenticationServices
import SwiftUI

/// Opened from a co-host link: sign in with Apple if needed, then accept.
struct CohostAcceptView: View {
    let invite: WeddingContext.CohostInvite

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let session = ChatSession.shared
    private let context = WeddingContext.shared

    @State private var isAccepting = false
    @State private var accepted = false
    @State private var error: String?

    private var isReady: Bool { session.isSignedIn && !session.isAnonymous && !session.isSigningIn }

    var body: some View {
        ZStack {
            Milni.midnight.ignoresSafeArea()
            MilniSpecks(count: 24, color: Milni.champagne)
                .opacity(0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xF4EBDC))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close")
                }

                Spacer(minLength: 16)

                MilniRings(color: Milni.champagne, lineWidth: 1, duration: reduceMotion ? 0.01 : 1.8, showsOuter: true, breathes: !reduceMotion)
                    .frame(width: 78, height: 78)
                    .milniEntrance(0)

                HostCaps(accepted ? "Welcome to the team" : "You're invited", color: Milni.champagne)
                    .padding(.top, 28)
                    .milniEntrance(1)

                Text(accepted ? "You're a co-host." : "Help host the wedding.")
                    .font(Milni.cormorant(44, weight: 500, italic: true))
                    .milniFoil()
                    .environment(\.colorScheme, .dark)
                    .padding(.top, 10)
                    .milniEntrance(2)

                Text(accepted
                     ? "Look for the Host button on Home. From there you can let guests in, edit events and send announcements."
                     : "As a co-host you can let guests in, edit the schedule and send announcements. Sign in with Apple so the couple knows it's you.")
                    .font(Milni.inter(16))
                    .foregroundStyle(Color(hex: 0xC9BFAE))
                    .lineSpacing(3)
                    .padding(.top, 14)
                    .milniEntrance(3)

                Spacer(minLength: 28)

                if let error {
                    Text(error)
                        .font(Milni.inter(14))
                        .foregroundStyle(Color(hex: 0xE8A291))
                        .padding(.bottom, 14)
                        .transition(.opacity)
                } else if let signInError = session.signInError, !isReady {
                    Text(signInError)
                        .font(Milni.inter(14))
                        .foregroundStyle(Color(hex: 0xE8A291))
                        .padding(.bottom, 14)
                }

                Group {
                    if accepted {
                        Button("Open the wedding") { dismiss() }
                            .buttonStyle(MilniButtonStyle(kind: .primary, ink: Milni.champagne, paper: Milni.midnight))
                    } else if isReady {
                        Button {
                            Task { await accept() }
                        } label: {
                            if isAccepting { ProgressView().tint(Milni.midnight) } else { Text("Accept and co-host") }
                        }
                        .buttonStyle(MilniButtonStyle(kind: .primary, ink: Milni.champagne, paper: Milni.midnight))
                        .disabled(isAccepting)
                    } else {
                        SignInWithAppleButton(.continue) { request in
                            session.prepare(request)
                        } onCompletion: { result in
                            Task { await session.complete(result) }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 56)
                        .clipShape(Capsule())
                        .opacity(session.isSigningIn ? 0.5 : 1)
                        .disabled(session.isSigningIn)
                    }
                }
                .padding(.bottom, 8)
                .milniEntrance(4)
                .animation(.calm, value: isReady)
                .animation(.calm, value: accepted)
            }
            .milniSides()
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: isReady) { _, ready in
            if ready, !accepted, !isAccepting { Task { await accept() } }
        }
    }

    private func accept() async {
        isAccepting = true
        defer { isAccepting = false }
        do {
            try await context.acceptCohost(code: invite.code)
            BrandHaptics.soft()
            withAnimation(.calm) {
                accepted = true
                error = nil
            }
        } catch {
            withAnimation(.calm) {
                self.error = "This invite didn't work. It may have been used already or replaced. Ask the couple for a new link."
            }
        }
    }
}
