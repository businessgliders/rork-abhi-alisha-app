import SwiftUI
import UIKit

/// The deliberate second step: how the notification will look, where it opens, and one
/// gold Send. Nothing goes out until it's tapped.
struct AnnouncementSendSheet: View {
    let title: String
    let message: String
    let destination: AnnouncementDestination
    let onSent: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSending = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Eyebrow(text: "Announcement", size: 10)
                    .padding(.top, 30)

                Text("Send to all guests?")
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                GoldRule(width: 40)
                    .padding(.top, 12)

                Text("Every guest's phone gets this notification. It can't be taken back.")
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                PushPreview(title: title, message: message)
                    .padding(.top, 22)

                HStack(spacing: 7) {
                    Image(systemName: destination.symbolName)
                        .font(.system(size: 11, weight: .medium))
                    Text("Opens: \(destination.previewLabel)")
                        .font(BrandLabel.font(size: 10.5, weight: .semibold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(BrandPalette.goldDeep)
                .padding(.top, 14)
                .accessibilityElement(children: .combine)

                if let errorText {
                    Text(errorText)
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.overdue)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)
                        .transition(.opacity)
                }

                GoldActionButton(title: "Send", systemImage: "paperplane", isBusy: isSending) {
                    send()
                }
                .padding(.top, 24)

                Button("Cancel") {
                    BrandHaptics.tick()
                    dismiss()
                }
                .font(BrandLabel.font(size: 12, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.body)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 4)
                .disabled(isSending)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .readableWidth(560)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(BrandPalette.background)
        .interactiveDismissDisabled(isSending)
        .animation(.softFade, value: errorText)
    }

    private func send() {
        guard !isSending else { return }
        isSending = true
        errorText = nil

        Task {
            let outcome = await AnnouncementService.shared.send(
                title: title,
                body: message,
                destination: destination
            )
            isSending = false
            switch outcome {
            case .sent(let count):
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSent(count)
                dismiss()
            case .forbidden:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                errorText = "Only admins can send announcements"
            case .failed:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                errorText = "Couldn't send. Nothing went out, so check your connection and try again."
            }
        }
    }
}

/// The notification as it arrives on a guest's iPhone, over the dusk photograph.
private struct PushPreview: View {
    let title: String
    let message: String

    var body: some View {
        Color(hex: 0x1B211F)
            .frame(height: 210)
            .overlay {
                Image("tropical_ocean_dusk")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            }
            .overlay {
                LinearGradient(
                    colors: [Color.black.opacity(0.18), Color.black.opacity(0.36)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .overlay { banner.padding(12) }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(BrandPalette.hairline, lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Notification preview. \(title). \(message)")
    }

    private var banner: some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(hex: 0xFBF8F2))
                .frame(width: 38, height: 38)
                .overlay {
                    Image("crest")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(Color(hex: 0xA9873C))
                        .padding(5)
                }

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Abhi & Alisha")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                    Spacer(minLength: 6)
                    Text("now")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.black.opacity(0.45))
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .lineLimit(1)

                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black.opacity(0.8))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.78))
        )
    }
}
