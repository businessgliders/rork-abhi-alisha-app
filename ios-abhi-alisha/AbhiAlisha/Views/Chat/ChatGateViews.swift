import AuthenticationServices
import SwiftUI

/// Below the two shared channels: the invitation into the family chat. For a name-only
/// guest, signing in with Apple joins their existing account, so nothing is lost.
struct FamilyInviteCard: View {
    @State private var session = ChatSession.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            CrestWatermark(width: 72, finish: .pressed(BrandPalette.card))

            Eyebrow(text: "The family table")
                .padding(.top, 18)

            Text("Sign in with Apple to join the family chat")
                .brandFont(.eventTitleSmall)
                .foregroundStyle(BrandPalette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            GoldRule(width: 40)
                .padding(.top, 14)

            Text(session.isAnonymous
                 ? "Your name and messages come with you. Abhi & Alisha welcome each family member in."
                 : "A private place for the family, small groups and one-to-one chats. Abhi & Alisha welcome each family member in.")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            SignInWithAppleButton(.signIn) { request in
                session.prepare(request)
            } onCompletion: { result in
                Task { await session.complete(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .frame(maxWidth: 360)
            .clipShape(.rect(cornerRadius: 15, style: .continuous))
            .opacity(session.isSigningIn ? 0.5 : 1)
            .disabled(session.isSigningIn)
            .padding(.top, 22)
            .id(colorScheme)

            if let error = session.signInError {
                Text(error)
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(BrandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(BrandPalette.gold.opacity(0.3), lineWidth: 1))
        .animation(.softFade, value: session.signInError)
    }
}

/// The family chat's in-between states, shown in place under the shared channels:
/// opening, waiting to be welcomed in, or unavailable.
struct FamilyGateCard: View {
    enum Kind {
        case opening
        case waiting
        case unavailable
    }

    let kind: Kind

    @State private var session = ChatSession.shared

    var body: some View {
        VStack(spacing: 0) {
            switch kind {
            case .opening:
                BreathingCrest(width: 64)
                Text("Opening the family chat")
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
                    .padding(.top, 16)

            case .waiting:
                BreathingCrest(width: 72)
                Eyebrow(text: "Almost there")
                    .padding(.top, 18)
                Text("Abhi & Alisha will welcome you in shortly")
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                GoldRule(width: 40)
                    .padding(.top, 14)
                Text(waitingLine)
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

            case .unavailable:
                Text("The family chat isn't available")
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.center)
                GoldRule(width: 36)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(BrandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var waitingLine: String {
        if let name = session.me?.displayName.flatMap(ChatJSON.clean) {
            return "Thank you, \(name). The family chat will open right here the moment you're in. Questions & Chat is open now."
        }
        return "The family chat will open right here the moment you're in. Questions & Chat is open now."
    }
}

/// "What should everyone call you?" — the only thing a guest needs for Questions & Chat.
struct GuestNameSheet: View {
    var eyebrow: String = "Questions & Chat"
    var detail: String = "Your name appears beside your messages. That's all we need, no account or password."
    var actionTitle: String = "Join the chat"
    /// Called once the guest is in, before the sheet closes.
    let onJoined: () -> Void

    @State private var session = ChatSession.shared
    @State private var name = ""
    @State private var didFail = false
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: eyebrow)

                Text("What should everyone call you?")
                    .brandFont(.eventTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                GoldRule(width: 44, alignment: .leading)
                    .padding(.top, 14)

                Text(detail)
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                ChatNameField(name: $name, isFocused: $isFocused, onSubmit: join)
                    .padding(.top, 24)

                if didFail {
                    Text("We couldn't connect just now. Please check your connection and try again.")
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                        .padding(.top, 12)
                        .transition(.opacity)
                }

                GoldActionButton(
                    title: actionTitle,
                    isBusy: session.isJoiningAsGuest,
                    isEnabled: ChatJSON.clean(name) != nil,
                    action: join
                )
                .padding(.top, 20)

                Button("Not now") { dismiss() }
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
        .interactiveDismissDisabled(session.isJoiningAsGuest)
        .onAppear { isFocused = true }
    }

    private func join() {
        guard ChatJSON.clean(name) != nil, !session.isJoiningAsGuest else { return }
        didFail = false
        Task {
            if await session.joinAsGuest(name: name) {
                BrandHaptics.tick()
                onJoined()
                dismiss()
            } else {
                didFail = true
            }
        }
    }
}

/// "What should the family call you?" — asked once, after the first sign-in, and from
/// "Change my name".
struct ChatNameSheet: View {
    @State private var session = ChatSession.shared
    @State private var name = ""
    @State private var isSaving = false
    @State private var didFail = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: session.me?.hasName == true ? "Your name" : "Welcome")

                Text(session.isAnonymous ? "What should everyone call you?" : "What should the family call you?")
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

                ChatNameField(name: $name, isFocused: $isFocused, onSubmit: save)
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

/// The cream name well shared by both name sheets.
private struct ChatNameField: View {
    @Binding var name: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        TextField("Your name", text: $name)
            .textContentType(.name)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit(onSubmit)
            .focused(isFocused)
            .brandFont(.bodyText)
            .foregroundStyle(BrandPalette.ink)
            .tint(BrandPalette.goldDeep)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BrandPalette.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BrandPalette.gold.opacity(0.3), lineWidth: 1))
    }
}
