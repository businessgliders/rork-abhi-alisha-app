import SwiftUI

/// Shown when someone who hosts weddings tries to delete their account.
/// Lists the weddings and jumps to the couple's area so they can hand one over.
struct HostWeddingsSheet: View {
    @State private var account = AccountDeletion.shared
    @State private var isBusy = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "heart.text.square")
                    .symbolVariant(.none)
                    .font(.system(size: 24, weight: .ultraLight))
                    .foregroundStyle(BrandPalette.goldDeep)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(BrandPalette.card))
                    .overlay(Circle().stroke(BrandPalette.gold.opacity(0.55), lineWidth: 1))
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("You're still hosting")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(BrandPalette.ink)
                        .multilineTextAlignment(.center)
                    Text("An account that hosts a wedding can't be deleted. Hand over hosting to a co-host, or delete the wedding first.")
                        .brandFont(.bodyText)
                        .foregroundStyle(BrandPalette.body)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    ForEach(account.hostingWeddings) { wedding in
                        MatteCard(cornerRadius: 18) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(wedding.title)
                                    .font(.headline)
                                    .foregroundStyle(BrandPalette.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                GoldActionButton(
                                    title: "Open couple's area",
                                    systemImage: "arrow.right.circle",
                                    isBusy: isBusy
                                ) {
                                    openCoupleArea(wedding)
                                }
                            }
                        }
                    }
                }

                ChatOutlineButton(title: "Not now", systemImage: "xmark") {
                    dismiss()
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
            .readableWidth(480)
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }

    /// Mirrors the switcher: dismiss the sheet, let the tab settle, then open the couple's area.
    private func openCoupleArea(_ wedding: HostedWedding) {
        isBusy = true
        BrandHaptics.soft()
        let context = WeddingContext.shared
        let summary = context.myWeddings.first { $0.id.lowercased() == wedding.id.lowercased() }
        let isCurrent = !context.isSample && wedding.id.lowercased() == context.weddingID.lowercased()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if !isCurrent {
                if let summary {
                    context.switchTo(summary)
                } else {
                    Task { try? await context.open(weddingID: wedding.id) }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (isCurrent ? 0 : 0.7)) {
                AdminSession.request.open(.guests)
            }
        }
    }
}

/// The last confirmation for Apple accounts, with the Apple copy at the step it happens.
struct DeleteAccountConfirmSheet: View {
    let isAppleAccount: Bool
    @State private var account = AccountDeletion.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "trash")
                    .symbolVariant(.none)
                    .font(.system(size: 24, weight: .ultraLight))
                    .foregroundStyle(BrandPalette.overdue)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(BrandPalette.card))
                    .overlay(Circle().stroke(BrandPalette.overdue.opacity(0.4), lineWidth: 1))
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Delete your account?")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(BrandPalette.ink)
                        .multilineTextAlignment(.center)
                    Text("Your name, your messages and everything you've added are removed for good. This can't be undone.")
                        .brandFont(.bodyText)
                        .foregroundStyle(BrandPalette.body)
                        .multilineTextAlignment(.center)
                }

                if isAppleAccount {
                    MatteCard(cornerRadius: 18) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 16, weight: .light))
                                .foregroundStyle(BrandPalette.goldDeep)
                                .padding(.top, 2)
                            Text("To finish, confirm with Apple. This disconnects Milni from your Apple ID.")
                                .brandFont(.bodyText)
                                .foregroundStyle(BrandPalette.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GoldActionButton(
                    title: isAppleAccount ? "Confirm with Apple" : "Delete my account",
                    systemImage: "trash",
                    isBusy: account.isDeleting
                ) {
                    dismiss()
                    Task { await AccountDeletion.shared.start() }
                }
                ChatOutlineButton(title: "Keep my account", systemImage: "heart") {
                    dismiss()
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
            .readableWidth(480)
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(account.isDeleting)
    }
}

/// A brief line on the welcome screen after an account is deleted.
struct AccountDeletionToast: View {
    @State private var account = AccountDeletion.shared

    var body: some View {
        Group {
            if let notice = account.deletionNotice {
                Text(notice)
                    .brandFont(.chatName)
                    .foregroundStyle(BrandPalette.background)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(BrandPalette.ink.opacity(0.92)))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.softFade, value: account.deletionNotice)
        .padding(.top, 8)
        .allowsHitTesting(false)
    }
}
