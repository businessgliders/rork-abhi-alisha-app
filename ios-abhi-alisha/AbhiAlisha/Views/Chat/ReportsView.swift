import SwiftUI

/// For Abhi & Alisha: every open report, with the message it's about and a Resolve button.
struct ReportsView: View {
    @State private var store = ChatStore.shared
    @State private var working: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ChatPageHeader(eyebrow: "For Abhi & Alisha", title: "Reports")

                if store.reports.isEmpty {
                    ChatEmptyNote(text: "Nothing has been reported. All is calm.", icon: .sun)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(store.reports) { report in
                            card(for: report)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }
                    .padding(.top, 22)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, FloatingTabBar.contentReserve + 24)
            .readableWidth()
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refreshAdmin() }
        .background(BrandPalette.background.ignoresSafeArea())
        .chatPageNavigation()
        .animation(.calm, value: store.reports.map(\.id))
        .task { await store.refreshAdmin() }
    }

    private func card(for report: ChatReport) -> some View {
        let message = store.reportedMessages[report.messageID]

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ChatAvatar(initials: message.flatMap { store.profile($0.senderID)?.initials } ?? "·", size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.map { store.name(of: $0.senderID) } ?? "Unknown sender")
                        .brandFont(.chatName)
                        .foregroundStyle(BrandPalette.ink)
                        .lineLimit(1)
                    if let message {
                        Text("Sent " + ChatTime.relative(message.createdAt))
                            .font(BrandLabel.font(size: 11, weight: .medium))
                            .foregroundStyle(BrandPalette.body)
                    }
                }
                Spacer(minLength: 0)
            }

            Text(message.map { $0.displayText.isEmpty ? "(no text)" : $0.displayText } ?? "This message is no longer available.")
                .brandFont(message?.isDeleted == false ? .chatMessage : .chatMessageItalic)
                .foregroundStyle(message?.isDeleted == false ? BrandPalette.ink : BrandPalette.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BrandPalette.background))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reported by " + (report.reporterID.map { store.name(of: $0) } ?? "a family member"))
                        .font(BrandLabel.font(size: 11, weight: .semibold))
                        .foregroundStyle(BrandPalette.goldDeep)
                    if let created = report.createdAt {
                        Text(ChatTime.relative(created))
                            .font(BrandLabel.font(size: 11, weight: .regular))
                            .foregroundStyle(BrandPalette.body)
                    }
                }
                Spacer(minLength: 8)
                ChatOutlineButton(title: working == report.id ? "…" : "Resolve", systemImage: "checkmark") {
                    resolve(report)
                }
                .disabled(working != nil)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BrandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
    }

    private func resolve(_ report: ChatReport) {
        working = report.id
        Task {
            if await store.resolve(report) { BrandHaptics.tick() }
            working = nil
        }
    }
}
