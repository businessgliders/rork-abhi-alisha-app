import SwiftUI
import UIKit

/// Write one note to every guest, see it as they will on their Lock Screen, and send it
/// only after a second, deliberate tap. Past notes are listed below — never any tokens
/// or guest names.
struct AdminSendView: View {
    @Binding var draft: NotificationDraft

    @Environment(AdminSession.self) private var session

    @State private var phase: Phase = .composing
    @State private var history: [NotificationRecord] = []
    @State private var historyFailed = false
    /// Set while the app itself clears the note, so that clearing doesn't wipe the result.
    @State private var isClearingDraft = false
    @FocusState private var focusedField: Field?

    private enum Field { case title, body }

    private enum Phase: Equatable {
        case composing
        case confirming
        case sending
        case sent(Int?)
        case failed
    }

    private static let titleLimit = 60
    private static let bodyLimit = 240

    private var canSend: Bool {
        draft.title.nonEmpty != nil && draft.body.nonEmpty != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AdminHeader(eyebrow: "For every guest", title: "Send a Note")

                fields
                    .padding(.top, 26)

                Eyebrow(text: "On their Lock Screen", size: 9.5)
                    .padding(.top, 28)

                LockScreenPreview(title: draft.title, message: draft.body)
                    .padding(.top, 10)

                action
                    .padding(.top, 22)

                historySection
                    .padding(.top, 40)

                AdminLockFooter()
                    .padding(.top, 30)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, FloatingTabBar.contentReserve + 20)
            .readableWidth()
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(BrandPalette.background.ignoresSafeArea())
        .animation(.calm, value: phase)
        .onChange(of: draft) { _, _ in
            if isClearingDraft {
                isClearingDraft = false
                return
            }
            // Any edit after a result, or mid-confirmation, starts the note afresh.
            if phase != .composing, phase != .sending {
                phase = .composing
            }
        }
        .task {
            if history.isEmpty {
                history = AdminService.shared.cachedNotificationHistory()
            }
            await loadHistory()
        }
        .refreshable {
            await loadHistory()
        }
    }

    // MARK: - Compose

    private var fields: some View {
        VStack(alignment: .leading, spacing: 18) {
            AdminField(label: "Title", hint: counter(draft.title, Self.titleLimit)) {
                TextField("Shuttle to the Sangeet", text: limited(\.title, Self.titleLimit))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .title)
                    .onSubmit { focusedField = .body }
            }

            AdminField(label: "Message", hint: counter(draft.body, Self.bodyLimit)) {
                TextField(
                    "Shuttles leave the main lobby at 6:30 PM. See you there!",
                    text: limited(\.body, Self.bodyLimit),
                    axis: .vertical
                )
                .lineLimit(3...7)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .body)
            }
        }
    }

    private func counter(_ text: String, _ limit: Int) -> String? {
        text.isEmpty ? nil : "\(text.count)/\(limit)"
    }

    private func limited(_ keyPath: WritableKeyPath<NotificationDraft, String>, _ limit: Int) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = String($0.prefix(limit)) }
        )
    }

    // MARK: - Send

    @ViewBuilder
    private var action: some View {
        switch phase {
        case .composing:
            GoldActionButton(title: "Send", systemImage: "paperplane", isEnabled: canSend) {
                focusedField = nil
                phase = .confirming
            }
            .transition(.opacity)

        case .confirming, .sending:
            confirmation
                .transition(.opacity.combined(with: .move(edge: .bottom)))

        case .sent(let count):
            ResultCard(
                symbol: "checkmark",
                title: "Sent",
                detail: count.map { $0 == 1 ? "Delivered to 1 phone." : "Delivered to \($0) phones." }
                    ?? "Your note is on its way to every guest."
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))

        case .failed:
            VStack(spacing: 14) {
                ResultCard(
                    symbol: "arrow.clockwise",
                    title: "Couldn't send",
                    detail: "Nothing went out. Check your connection and try again."
                )
                GoldActionButton(title: "Try again", isEnabled: canSend) {
                    phase = .confirming
                }
            }
            .transition(.opacity)
        }
    }

    private var confirmation: some View {
        MatteCard(cornerRadius: 22) {
            VStack(spacing: 0) {
                Image(systemName: "person.3")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(BrandPalette.goldDeep)

                Text("This will notify all guests")
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                Text("It can't be taken back once it's sent.")
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                GoldActionButton(
                    title: "Send to all guests",
                    isBusy: phase == .sending
                ) {
                    send()
                }
                .padding(.top, 20)

                Button("Cancel") {
                    BrandHaptics.tick()
                    phase = .composing
                }
                .font(BrandLabel.font(size: 12, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.body)
                .frame(minHeight: 44)
                .padding(.top, 4)
                .disabled(phase == .sending)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
        }
    }

    private func send() {
        guard let code = session.code,
              let title = draft.title.nonEmpty,
              let body = draft.body.nonEmpty,
              phase != .sending else { return }
        phase = .sending

        Task {
            do {
                let receipt = try await AdminService.shared.sendToAll(title: title, body: body, code: code)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isClearingDraft = true
                draft = NotificationDraft()
                phase = .sent(receipt.deliveredCount)
                try? await Task.sleep(for: .seconds(1.2))
                await loadHistory()
            } catch AdminError.unauthorized {
                session.invalidate()
            } catch {
                phase = .failed
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "Sent notes")

            if history.isEmpty {
                AdminNote(
                    text: historyFailed
                        ? "Past notes will appear here once you're back online."
                        : "Nothing sent yet. Your first note will appear here.",
                    symbol: "envelope"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(history) { record in
                        HistoryRow(record: record)
                    }
                }
            }
        }
    }

    private func loadHistory() async {
        do {
            let records = try await AdminService.shared.notificationHistory()
            withAnimation(.calm) { history = records }
            historyFailed = false
        } catch {
            historyFailed = true
        }
    }
}

// MARK: - Pieces

private struct ResultCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        MatteCard(cornerRadius: 22) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BrandPalette.goldDeep)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(BrandPalette.gold.opacity(0.55), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .brandFont(.eventTitleSmall)
                        .foregroundStyle(BrandPalette.ink)
                    Text(detail)
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryRow: View {
    let record: NotificationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

            if !meta.isEmpty {
                Text(meta.joined(separator: "  ·  "))
                    .font(BrandLabel.font(size: 10, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(BrandPalette.gold)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BrandPalette.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var meta: [String] {
        var parts: [String] = []
        if let sentAt = record.sentAt {
            parts.append(sentAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
        }
        if let count = record.deliveredCount {
            parts.append(count == 1 ? "1 phone" : "\(count) phones")
        }
        return parts
    }
}

/// How the note will look arriving on a guest's iPhone.
struct LockScreenPreview: View {
    let title: String
    let message: String

    var body: some View {
        Color(hex: 0x1B211F)
            .frame(height: 320)
            .overlay {
                Image("tropical_ocean_dusk")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            }
            .overlay {
                LinearGradient(
                    colors: [Color.black.opacity(0.28), Color.black.opacity(0.04), Color.black.opacity(0.38)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .overlay(alignment: .top) { clock.padding(.top, 24) }
            .overlay(alignment: .bottom) { banner.padding(10) }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(BrandPalette.hairline, lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Lock Screen preview")
    }

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 0) {
                Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 15, weight: .semibold))
                Text(context.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                    .font(.system(size: 66, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.white.opacity(0.9))
            .shadow(color: Color.black.opacity(0.2), radius: 8)
        }
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

                Text(title.nonEmpty ?? "Your title")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(title.nonEmpty == nil ? 0.3 : 0.88))
                    .lineLimit(1)

                Text(message.nonEmpty ?? "Your message will appear here.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black.opacity(message.nonEmpty == nil ? 0.3 : 0.8))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.74))
        )
        .animation(.softFade, value: title.isEmpty)
        .animation(.softFade, value: message.isEmpty)
    }
}
