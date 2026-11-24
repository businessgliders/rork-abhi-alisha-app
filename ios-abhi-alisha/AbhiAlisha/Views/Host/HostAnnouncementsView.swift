import Supabase
import SwiftUI

/// Announcements already sent, newest first, and the button to write a new one.
struct HostAnnouncementsView: View {
    @State private var sent: [SentAnnouncement] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var isComposing = false

    struct SentAnnouncement: Identifiable, Decodable {
        let id: String
        let title: String?
        let body: String?
        let screen: String?
        let sent_at: String?
        let delivered_count: Int?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button {
                    BrandHaptics.soft()
                    isComposing = true
                } label: {
                    Label("New announcement", systemImage: "square.and.pencil")
                }
                .buttonStyle(.milniPrimary)
                .padding(.top, 12)

                HostErrorLine(message: error)

                HostCaps("Sent")
                    .padding(.top, 10)

                if isLoading && sent.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                } else if sent.isEmpty {
                    HostEmptyLine(text: "Nothing sent yet.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(sent) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(when(item))
                                        .font(Milni.inter(11, weight: 600))
                                        .tracking(1)
                                        .foregroundStyle(HostStyle.goldText)
                                    Spacer()
                                    if let count = item.delivered_count {
                                        Label("\(count)", systemImage: "bell")
                                            .font(Milni.inter(11))
                                            .foregroundStyle(HostStyle.muted)
                                            .accessibilityLabel("Delivered to \(count)")
                                    }
                                }
                                Text(item.title ?? "")
                                    .font(Milni.cormorant(22, weight: 600))
                                    .foregroundStyle(HostStyle.ink)
                                if let body = item.body, !body.isEmpty {
                                    Text(body)
                                        .font(Milni.inter(14))
                                        .foregroundStyle(HostStyle.muted)
                                        .lineLimit(3)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(HostStyle.card))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(HostStyle.hairline, lineWidth: 1))
                        }
                    }
                }
            }
            .padding(.horizontal, HostStyle.side)
            .padding(.bottom, 40)
        }
        .background(HostPaper())
        .navigationTitle("Announcements")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $isComposing, onDismiss: { Task { await load() } }) {
            HostAnnouncementComposer()
                .interactiveDismissDisabled()
        }
    }

    private func when(_ item: SentAnnouncement) -> String {
        guard let text = item.sent_at, let date = HostAPI.parseDate(text) else { return "SENT" }
        return "\(HostTime.day(date)) · \(HostTime.time(date))".uppercased()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await ChatBackend.client.from("announcements")
                .select("id,title,body,screen,sent_at,delivered_count")
                .eq("wedding_id", value: WeddingContext.shared.weddingID)
                .order("sent_at", ascending: false)
                .limit(40)
                .execute()
            sent = (try? JSONDecoder().decode([SentAnnouncement].self, from: response.data)) ?? []
            error = nil
        } catch {
            self.error = error.hostMessage
        }
    }
}

// MARK: - Composer

/// Write an announcement, choose where its notification opens, see it as guests will.
struct HostAnnouncementComposer: View {
    @Environment(ScheduleStore.self) private var schedule
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var title = ""
    @State private var message = ""
    @State private var destination: AnnouncementDestination = .announcements
    @State private var pickedByHand = false
    @State private var guestCount: Int?
    @State private var isSending = false
    @State private var error: String?
    @State private var sentCount: Int??

    private var events: [ScheduleEvent] {
        schedule.events.filter { $0.isActive != false }
    }

    private var options: [AnnouncementDestination] {
        [.announcements, .schedule] + events.map { .event(id: $0.id, title: $0.title) } + [.chat, .gallery]
    }

    private var suggestion: AnnouncementDestination {
        Self.suggest(title: title, body: message, events: events)
    }

    private var canSend: Bool { !title.hostTrimmed.isEmpty && !message.hostTrimmed.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HostSheetBar(
                title: "Announcement",
                saveTitle: "Send",
                canSave: canSend && sentCount == nil,
                isSaving: isSending,
                cancel: { dismiss() },
                save: { Task { await send() } }
            )

            if let sentCount {
                sentState(sentCount)
            } else {
                form
            }
        }
        .background(HostPaper())
        .environment(\.colorScheme, .light)
        .task {
            guestCount = await HostAPI.shared.count(
                table: "wedding_members",
                weddingID: WeddingContext.shared.weddingID,
                filter: ("status", "approved")
            )
        }
        .onChange(of: suggestion) { _, new in
            guard !pickedByHand else { return }
            withAnimation(.calm) { destination = new }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HostTitleField(placeholder: "Title", text: $title, size: 32)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 8) {
                    HostCaps("Message", color: HostStyle.muted)
                    TextField("", text: $message, prompt: Text("The shuttle to the ceremony leaves at 4:30 from the lobby.").foregroundStyle(HostStyle.muted.opacity(0.5)), axis: .vertical)
                        .font(Milni.inter(17))
                        .foregroundStyle(HostStyle.ink)
                        .lineLimit(3...10)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HostCaps("Opens to", color: HostStyle.muted)
                        Spacer()
                        if !pickedByHand, destination == suggestion, canSend || !message.isEmpty {
                            Label("Suggested from your message", systemImage: "sparkles")
                                .font(Milni.inter(11, weight: 500))
                                .foregroundStyle(HostStyle.goldText)
                                .transition(.opacity)
                        }
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(options, id: \.self) { option in
                                HostChip(
                                    title: option == .gallery ? "Photos" : option.label,
                                    symbol: option.symbolName,
                                    isOn: option == destination
                                ) {
                                    pickedByHand = true
                                    destination = option
                                }
                            }
                        }
                        .padding(.horizontal, HostStyle.side)
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, -HostStyle.side)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HostCaps("Guests will see", color: HostStyle.muted)
                    notificationPreview
                }

                HostErrorLine(message: error)

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().tint(HostStyle.paper)
                    } else if let guestCount {
                        Text("Send to all \(guestCount) \(guestCount == 1 ? "guest" : "guests")")
                    } else {
                        Text("Send to all guests")
                    }
                }
                .buttonStyle(.milniPrimary)
                .disabled(!canSend || isSending)
            }
            .padding(.horizontal, HostStyle.side)
            .padding(.bottom, 50)
            .animation(.calm, value: destination)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var notificationPreview: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Milni.midnight)
                MilniRings(color: Milni.champagne, lineWidth: 1, duration: 0.01, showsOuter: false, breathes: false)
                    .padding(7)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title.hostTrimmed.isEmpty ? "Title" : title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("now")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Text(message.hostTrimmed.isEmpty ? "Your message appears here." : message)
                    .font(.system(size: 15))
                    .lineLimit(4)
                Text("Opens \(destination.previewLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Color.black.opacity(0.88))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        }
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Milni.midnight.opacity(0.85), Color(hex: 0x3A4266)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(-10)
        }
        .padding(10)
        .accessibilityElement(children: .combine)
    }

    private func sentState(_ count: Int?) -> some View {
        VStack(spacing: 18) {
            Spacer()
            MilniRings(color: HostStyle.gold, lineWidth: 1.2, duration: reduceMotion ? 0.01 : 1.4, showsOuter: true, breathes: false)
                .frame(width: 90, height: 90)
            Text("Sent.")
                .font(Milni.cormorant(44, weight: 500, italic: true))
                .foregroundStyle(HostStyle.ink)
            Text(count.map { "Delivered to \($0) \($0 == 1 ? "phone" : "phones")." } ?? "It's on its way to your guests.")
                .font(Milni.inter(15))
                .foregroundStyle(HostStyle.muted)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.milniPrimary)
                .padding(.horizontal, HostStyle.side)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    private func send() async {
        guard canSend, !isSending else { return }
        isSending = true
        defer { isSending = false }
        let outcome = await AnnouncementService.shared.send(
            title: title.hostTrimmed,
            body: message.hostTrimmed,
            destination: destination
        )
        switch outcome {
        case .sent(let count):
            BrandHaptics.soft()
            withAnimation(.calm) { sentCount = .some(count) }
        case .forbidden:
            withAnimation(.calm) { error = "Only the hosts of this wedding can send announcements." }
        case .failed:
            withAnimation(.calm) { error = "That didn't send. Please check your connection and try again." }
        }
    }

    /// Guesses where a message should open from the words in it.
    static func suggest(title: String, body: String, events: [ScheduleEvent]) -> AnnouncementDestination {
        let text = (title + " " + body).lowercased()
        guard !text.hostTrimmed.isEmpty else { return .announcements }
        if let event = events.first(where: { event in
            let name = event.title.lowercased()
            return !name.isEmpty && text.contains(name)
        }) {
            return .event(id: event.id, title: event.title)
        }
        let photoWords = ["photo", "picture", "pics", "upload", "album", "gallery"]
        if photoWords.contains(where: text.contains) { return .gallery }
        let chatWords = ["chat", "say hi", "message us", "group thread"]
        if chatWords.contains(where: text.contains) { return .chat }
        let scheduleWords = ["schedule", "shuttle", "bus", "moved", "starts", "start time", "pm", "am ", "o'clock", "running late", "delayed", "tonight", "tomorrow"]
        if scheduleWords.contains(where: text.contains) { return .schedule }
        return .announcements
    }
}
