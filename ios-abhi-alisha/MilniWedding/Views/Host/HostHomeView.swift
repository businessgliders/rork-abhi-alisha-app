import SwiftUI

/// Where the Host area's rows lead.
enum HostRoute: Hashable {
    case events
    case guests
    case announcements
    case photos
    case content
    case look
}

/// The Host pill beside the wedding switcher on Home. Only approved hosts and
/// co-hosts ever see it.
struct HostPill: View {
    let action: () -> Void

    var body: some View {
        Button {
            BrandHaptics.soft()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 11, weight: .bold))
                Text("Host")
                    .font(Milni.inter(13, weight: 600))
            }
            .foregroundStyle(Color(hex: 0xF4EBDC))
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background {
                Capsule().fill(Milni.midnight.opacity(0.78))
                    .overlay(Capsule().strokeBorder(Milni.champagne.opacity(0.55), lineWidth: 0.8))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(MilniPressStyle())
        .frame(minHeight: 44)
        .accessibilityLabel("Host area")
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

/// The host's home: who is waiting, and a row for everything they can change.
struct HostHomeView: View {
    /// Opens the original couple's checklist area (Abhi & Alisha only).
    var openChecklist: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let context = WeddingContext.shared

    @State private var path: [HostRoute] = []
    @State private var members: [HostMember] = []
    @State private var code: String?
    @State private var counts: [HostRoute: Int] = [:]
    @State private var isLoading = true
    @State private var error: String?
    @State private var busy: Set<String> = []
    @State private var isShareKitPresented = false

    private var weddingID: String { context.weddingID }
    private var pending: [HostMember] {
        members.filter { $0.status.lowercased() == "pending" }
            .sorted { ($0.joinedAt ?? .distantPast) > ($1.joinedAt ?? .distantPast) }
    }

    private var isMilniWedding: Bool { weddingID.lowercased() == ActiveWedding.sampleID.lowercased() }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    VStack(alignment: .leading, spacing: 0) {
                        HostErrorLine(message: error)
                            .padding(.bottom, error == nil ? 0 : 16)

                        waiting
                        rows
                            .padding(.top, 34)

                        if isMilniWedding, openChecklist != nil {
                            checklistRow
                                .padding(.top, 14)
                        }
                    }
                    .padding(.horizontal, HostStyle.side)
                    .padding(.top, 26)
                    .padding(.bottom, 48)
                }
            }
            .scrollIndicators(.hidden)
            .background(HostPaper())
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await load() }
            .navigationDestination(for: HostRoute.self) { route in
                destination(route)
                    .toolbarBackground(HostStyle.paper, for: .navigationBar)
            }
        }
        .tint(HostStyle.ink)
        .environment(\.colorScheme, .light)
        .task { await load() }
        .sheet(isPresented: $isShareKitPresented) {
            HostShareKit(code: $code)
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            Milni.midnight
            MilniSpecks(count: 22, color: Milni.champagne)
                .opacity(0.55)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HostCaps(context.role?.lowercased() == "host" ? "You're the host" : "You're a co-host", color: Milni.champagne)

                Text(context.snapshot.coupleNames)
                    .font(Milni.cormorant(46, weight: 500, italic: true))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .milniFoil()
                    .environment(\.colorScheme, .dark)
                    .padding(.top, 12)

                if !context.snapshot.cityAndDates.isEmpty {
                    Text(context.snapshot.cityAndDates)
                        .font(Milni.inter(13))
                        .foregroundStyle(Color(hex: 0xB7A98F))
                        .padding(.top, 6)
                }

                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEDDING CODE")
                            .font(Milni.inter(10, weight: 600))
                            .tracking(1.8)
                            .foregroundStyle(Color(hex: 0xB7A98F))
                        Text(code ?? "· · · · · ·")
                            .font(Milni.inter(19, weight: 600))
                            .tracking(5)
                            .foregroundStyle(Color(hex: 0xF4EBDC))
                            .contentTransition(.numericText())
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 8)
                    Button {
                        BrandHaptics.soft()
                        isShareKitPresented = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Share")
                                .font(Milni.inter(14, weight: 600))
                        }
                        .foregroundStyle(Milni.midnight)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Capsule().fill(Milni.champagne))
                    }
                    .buttonStyle(MilniPressStyle())
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, HostStyle.side + 4)
            .padding(.top, 76)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                BrandHaptics.tick()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xF4EBDC))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.12)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MilniPressStyle())
            .accessibilityLabel("Close")
            .padding(.top, 48)
            .padding(.trailing, 14)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
    }

    // MARK: Waiting

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HostCaps("Waiting for you")
                if !pending.isEmpty {
                    Text("\(pending.count)")
                        .font(Milni.inter(11, weight: 700))
                        .foregroundStyle(HostStyle.paper)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Capsule().fill(HostStyle.gold))
                        .contentTransition(.numericText())
                }
                Spacer()
            }

            if isLoading && members.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if pending.isEmpty {
                HostEmptyLine(text: "Everyone's in. Beautiful.")
                    .transition(.opacity)
            } else {
                VStack(spacing: 10) {
                    ForEach(pending) { member in
                        PendingRow(
                            member: member,
                            isBusy: busy.contains(member.id),
                            approve: { Task { await setStatus(member, "approved") } },
                            decline: { Task { await setStatus(member, "blocked") } }
                        )
                        .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }
                if pending.count > 0 {
                    Text("Swipe left to decline.")
                        .font(Milni.inter(12))
                        .foregroundStyle(HostStyle.muted.opacity(0.8))
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.86), value: pending.map(\.id))
    }

    // MARK: Rows

    private var rows: some View {
        HostCard {
            row("Events", route: .events, symbol: "calendar")
            HostHairline()
            row("Guests & co-hosts", route: .guests, symbol: "person.2")
            HostHairline()
            row("Announcements", route: .announcements, symbol: "megaphone")
            HostHairline()
            row("Wedding Week photos", route: .photos, symbol: "photo.on.rectangle")
            HostHairline()
            row("Story, family & FAQ", route: .content, symbol: "book.closed")
            HostHairline()
            row("Look & cover photos", route: .look, symbol: "paintpalette")
        }
    }

    private func row(_ title: String, route: HostRoute, symbol: String) -> some View {
        Button {
            BrandHaptics.tick()
            path.append(route)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(HostStyle.goldText)
                    .frame(width: 22)
                Text(title)
                    .font(Milni.cormorant(22, weight: 500))
                    .foregroundStyle(HostStyle.ink)
                Spacer(minLength: 8)
                if let count = counts[route] {
                    Text("\(count)")
                        .font(Milni.inter(14))
                        .foregroundStyle(HostStyle.muted)
                        .contentTransition(.numericText())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HostStyle.gold)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(HostRowPressStyle())
    }

    private var checklistRow: some View {
        Button {
            BrandHaptics.tick()
            openChecklist?()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "checklist")
                    .foregroundStyle(HostStyle.goldText)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Our checklist")
                        .font(Milni.cormorant(20, weight: 500))
                        .foregroundStyle(HostStyle.ink)
                    Text("The original couple's area")
                        .font(Milni.inter(12))
                        .foregroundStyle(HostStyle.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HostStyle.gold)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 60)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(HostStyle.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(HostRowPressStyle())
    }

    @ViewBuilder
    private func destination(_ route: HostRoute) -> some View {
        switch route {
        case .events: HostEventsView()
        case .guests: HostGuestsView(onChange: { Task { await load() } })
        case .announcements: HostAnnouncementsView()
        case .photos: HostPhotosView()
        case .content: HostContentView()
        case .look: HostLookView()
        }
    }

    // MARK: Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let membersTask = HostAPI.shared.members(weddingID: weddingID)
        async let codeTask = HostAPI.shared.joinCode(weddingID: weddingID)
        async let events = HostAPI.shared.count(table: "events", weddingID: weddingID)
        async let announcements = HostAPI.shared.count(table: "announcements", weddingID: weddingID)
        async let photos = HostAPI.shared.count(table: "event_photos", weddingID: weddingID)
        async let sections = HostAPI.shared.count(table: "content_sections", weddingID: weddingID)
        do {
            let loaded = try await membersTask
            withAnimation(.calm) { members = loaded }
            error = nil
        } catch {
            self.error = error.hostMessage
        }
        if let loadedCode = try? await codeTask {
            withAnimation(.calm) { code = loadedCode }
        }
        let approved = members.filter { $0.status.lowercased() == "approved" }.count
        let values: [HostRoute: Int] = [
            .events: await events,
            .guests: approved,
            .announcements: await announcements,
            .photos: await photos,
            .content: await sections,
        ]
        withAnimation(.calm) { counts = values }
    }

    private func setStatus(_ member: HostMember, _ status: String) async {
        busy.insert(member.id)
        defer { busy.remove(member.id) }
        do {
            try await HostAPI.shared.setStatus(weddingID: weddingID, userID: member.userID, status: status)
            status == "approved" ? BrandHaptics.soft() : BrandHaptics.tick()
            if let index = members.firstIndex(where: { $0.id == member.id }) {
                members[index].status = status
            }
            counts[.guests] = members.filter { $0.status.lowercased() == "approved" }.count
            error = nil
        } catch {
            withAnimation(.calm) { self.error = error.hostMessage }
        }
    }
}

struct HostRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(HostStyle.gold.opacity(configuration.isPressed ? 0.08 : 0))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// One person waiting to be let in: Approve, or swipe left to decline.
struct PendingRow: View {
    let member: HostMember
    let isBusy: Bool
    let approve: () -> Void
    let decline: () -> Void

    @State private var offset: CGFloat = 0
    private let threshold: CGFloat = 110

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(HostStyle.danger)
                .overlay(alignment: .trailing) {
                    Text("Decline")
                        .font(Milni.inter(14, weight: 600))
                        .foregroundStyle(.white)
                        .padding(.trailing, 20)
                        .opacity(min(1, Double(-offset / 60)))
                }
                .opacity(offset < 0 ? 1 : 0)

            HStack(spacing: 12) {
                MilniMonogram(initials: initials, size: 38, ring: HostStyle.gold, textColor: HostStyle.goldText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName)
                        .font(Milni.inter(16, weight: 600))
                        .foregroundStyle(HostStyle.ink)
                        .lineLimit(1)
                    if let joined = member.joinedAt {
                        Text("Asked \(HostTime.relative(joined))")
                            .font(Milni.inter(12))
                            .foregroundStyle(HostStyle.muted)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    approve()
                } label: {
                    ZStack {
                        Text("Approve").opacity(isBusy ? 0 : 1)
                        if isBusy { ProgressView().tint(HostStyle.paper) }
                    }
                    .font(Milni.inter(14, weight: 600))
                    .foregroundStyle(HostStyle.paper)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().fill(HostStyle.ink))
                }
                .buttonStyle(MilniPressStyle())
                .disabled(isBusy)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 66)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(HostStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(HostStyle.hairline, lineWidth: 1))
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        offset = min(0, value.translation.width)
                    }
                    .onEnded { _ in
                        if offset < -threshold {
                            BrandHaptics.tick()
                            withAnimation(.easeOut(duration: 0.2)) { offset = -500 }
                            decline()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { offset = 0 }
                        }
                    }
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Approve", approve)
        .accessibilityAction(named: "Decline", decline)
    }

    private var initials: String {
        let parts = member.displayName.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}
