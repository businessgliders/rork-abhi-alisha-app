import AuthenticationServices
import SwiftUI

/// Signed out: the crest, one line of welcome, and Sign in with Apple. Nothing else.
struct ChatSignedOutView: View {
    @State private var session = ChatSession.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                CrestWatermark(width: 150, finish: .pressed(BrandPalette.background))

                Eyebrow(text: "The family table")
                    .padding(.top, 30)

                Text("A quiet place for the family to talk")
                    .brandFont(.eventTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                GoldRule(width: 44)
                    .padding(.top, 18)

                SignInWithAppleButton(.signIn) { request in
                    session.prepare(request)
                } onCompletion: { result in
                    Task { await session.complete(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .frame(maxWidth: 360)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .opacity(session.isSigningIn ? 0.5 : 1)
                .disabled(session.isSigningIn)
                .padding(.top, 34)
                .id(colorScheme)

                if let error = session.signInError {
                    Text(error)
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .transition(.opacity)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 30)
            .padding(.top, ScreenChrome.contentReserve)
            .padding(.bottom, FloatingTabBar.contentReserve + 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        }
        .background(BrandPalette.background.ignoresSafeArea())
        .animation(.softFade, value: session.signInError)
    }
}

/// The three in-between states: opening, waiting to be welcomed in, and unavailable.
struct ChatGateView: View {
    enum Kind {
        case opening
        case waiting
        case unavailable
    }

    let kind: Kind

    @State private var session = ChatSession.shared
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false

    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 40)
                content
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 32)
            .padding(.top, ScreenChrome.contentReserve)
            .padding(.bottom, FloatingTabBar.contentReserve + 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        }
        .background(BrandPalette.background.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            if kind == .waiting {
                accountMenu
                    .padding(.top, 8)
                    .padding(.trailing, 14)
            }
        }
        .chatAccountDialogs(isConfirmingSignOut: $isConfirmingSignOut, isConfirmingDelete: $isConfirmingDelete)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .opening:
            VStack(spacing: 22) {
                BreathingCrest(width: 120)
                Text("Opening the family chat")
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
            }

        case .waiting:
            VStack(spacing: 0) {
                BreathingCrest(width: 140)

                Eyebrow(text: "Almost there")
                    .padding(.top, 30)

                Text("Abhi & Alisha will welcome you in shortly")
                    .brandFont(.eventTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                GoldRule(width: 44)
                    .padding(.top, 18)

                Text(waitingLine)
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            .accessibilityElement(children: .combine)

        case .unavailable:
            VStack(spacing: 16) {
                Text("Chat isn't available")
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.center)
                GoldRule(width: 36)
            }
        }
    }

    private var waitingLine: String {
        if let name = session.me?.displayName.flatMap(ChatJSON.clean) {
            return "Thank you, \(name). The family chat will open right here the moment you're in."
        }
        return "The family chat will open right here the moment you're in."
    }

    /// Kept out of the way while waiting, but always there: Apple requires that an
    /// account can be deleted from inside the app.
    private var accountMenu: some View {
        Menu {
            Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                isConfirmingSignOut = true
            }
            Button("Delete Account", systemImage: "trash", role: .destructive) {
                isConfirmingDelete = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BrandPalette.goldDeep)
                .frame(width: 44, height: 44)
                .background(Circle().fill(BrandPalette.card))
                .overlay(Circle().stroke(BrandPalette.hairline, lineWidth: 1))
        }
        .accessibilityLabel("Account")
    }
}

/// "What should the family call you?" — asked once, after the first sign-in.
struct ChatNameSheet: View {
    @State private var session = ChatSession.shared
    @State private var name = ""
    @State private var isSaving = false
    @State private var didFail = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: "Welcome")

                Text("What should the family call you?")
                    .brandFont(.eventTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                GoldRule(width: 44, alignment: .leading)
                    .padding(.top, 14)

                Text("This is the name everyone will see beside your messages.")
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                TextField("Your name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(save)
                    .focused($isFocused)
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.ink)
                    .tint(BrandPalette.goldDeep)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BrandPalette.card))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BrandPalette.gold.opacity(0.3), lineWidth: 1))
                    .padding(.top, 24)

                if didFail {
                    Text("We couldn't save that just now. Please try again in a moment.")
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                        .padding(.top, 12)
                        .transition(.opacity)
                }

                GoldActionButton(
                    title: "Save my name",
                    isBusy: isSaving,
                    isEnabled: ChatJSON.clean(name) != nil,
                    action: save
                )
                .padding(.top, 20)

                Button("Not now") {
                    session.isNamePromptPresented = false
                }
                .font(BrandLabel.font(size: 11, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(BrandPalette.body.opacity(0.8))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 6)
            }
            .padding(.horizontal, 26)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .animation(.softFade, value: didFail)
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled()
        .onAppear {
            name = session.me?.displayName.flatMap(ChatJSON.clean) ?? session.suggestedName
            isFocused = true
        }
    }

    private func save() {
        guard ChatJSON.clean(name) != nil, !isSaving else { return }
        isSaving = true
        didFail = false
        Task {
            let saved = await session.saveName(name)
            isSaving = false
            if saved {
                BrandHaptics.tick()
            } else {
                didFail = true
            }
        }
    }
}
