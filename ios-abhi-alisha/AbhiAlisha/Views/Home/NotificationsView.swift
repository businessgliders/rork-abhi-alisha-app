import SwiftUI

/// Every note the couple has sent, newest first — where a tapped wedding update
/// lands. Opens instantly from the disk cache; a quiet refresh follows behind.
struct NotificationsView: View {
    @Environment(NotificationsStore.self) private var updates
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            BrandPalette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    content
                        .padding(.top, 26)
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 44)
                .readableWidth()
            }
            .scrollIndicators(.hidden)
            .animation(.calm, value: updates.records)

            closeButton
                .padding(.trailing, 16)
        }
        .task {
            await updates.refreshIfNeeded()
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "From Abhi & Alisha")

            Text("Updates")
                .brandFont(.screenTitle)
                .foregroundStyle(BrandPalette.ink)

            GoldRule(width: 58, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 48)
    }

    @ViewBuilder
    private var content: some View {
        if updates.records.isEmpty {
            emptyState
        } else {
            VStack(spacing: 14) {
                ForEach(updates.records) { record in
                    UpdateCard(record: record)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            IconWatermark(key: .sparkle, size: 92, opacity: 0.3)

            Text("No updates yet.")
                .brandFont(.bodyText)
                .foregroundStyle(BrandPalette.ink)

            Text("The moment there's news, it will arrive here — and on your lock screen.")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    private var closeButton: some View {
        Button {
            BrandHaptics.soft()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BrandPalette.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(BrandPalette.card))
                .overlay(Circle().stroke(BrandPalette.hairline, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.06), radius: 10, y: 3)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Close")
    }
}

/// One note, matte and unhurried — the news first, then when it went out.
private struct UpdateCard: View {
    let record: NotificationRecord

    var body: some View {
        MatteCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                if let sentAt = record.sentAt {
                    Text(sentAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .font(BrandLabel.font(size: 10, weight: .medium))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(BrandPalette.gold)
                }

                if let title = record.title {
                    Text(title)
                        .brandFont(.bodyText)
                        .foregroundStyle(BrandPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let body = record.body {
                    Text(body)
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NotificationsView()
        .environment(NotificationsStore())
}
