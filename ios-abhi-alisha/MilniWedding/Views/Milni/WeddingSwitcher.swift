import SwiftUI

// MARK: - Switcher capsule

/// Home's top-left capsule: the wedding's monogram and title. Opens the switcher.
struct WeddingSwitcherCapsule: View {
    private let context = WeddingContext.shared
    @State private var isPresented = false

    var body: some View {
        Button {
            BrandHaptics.tick()
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                MilniMonogram(
                    initials: context.snapshot.initials,
                    size: 26,
                    ring: Color(hex: 0xE6CF9A),
                    textColor: .white
                )
                Text(context.snapshot.coupleNames)
                    .font(Milni.inter(13, weight: 600))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .frame(height: 36)
            .background { glass }
            .contentShape(Capsule())
        }
        .buttonStyle(MilniPressStyle())
        .frame(minHeight: 44)
        .accessibilityLabel("\(context.snapshot.coupleNames). Switch wedding")
        .sheet(isPresented: $isPresented) {
            WeddingSwitcherSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

extension WeddingSwitcherCapsule {
    @ViewBuilder
    fileprivate var glass: some View {
        if #available(iOS 26.0, *) {
            Capsule().fill(Color.clear)
                .glassEffect(.regular.tint(Color.black.opacity(0.18)), in: .capsule)
        } else {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.black.opacity(0.2)))
        }
    }
}

// MARK: - Switcher sheet

struct WeddingSwitcherSheet: View {
    private let context = WeddingContext.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rows already left on this phone, hidden before the server list catches up.
    @State private var gone: Set<String> = []
    @State private var leaving: WeddingSummary?
    @State private var busyID: String?
    @State private var share: HostSharePayload?
    @State private var error: String?
    @State private var photoReports = PhotoReportStore.shared

    private var weddings: [WeddingSummary] {
        context.myWeddings.filter { !gone.contains($0.id.lowercased()) }
    }

    private var fade: Animation { reduceMotion ? .easeInOut(duration: 0.25) : .calm }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR WEDDINGS")
                        .font(Milni.inter(11, weight: 600))
                        .tracking(2.4)
                        .foregroundStyle(BrandPalette.goldDeep)
                    Text("Switch wedding")
                        .font(Milni.cormorant(36))
                        .foregroundStyle(BrandPalette.ink)
                    if let error {
                        Text(error)
                            .font(Milni.inter(13))
                            .foregroundStyle(BrandPalette.overdue)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                            .transition(.opacity)
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 12)
                .plainRow()

                if context.isSample {
                    row(
                        initials: context.snapshot.initials,
                        title: context.snapshot.coupleNames,
                        detail: "Sample wedding",
                        badge: nil,
                        selected: true
                    ) {}
                    .plainRow()
                }
                ForEach(weddings) { wedding in
                    row(
                        initials: wedding.initials,
                        title: wedding.title,
                        detail: wedding.dateRange ?? "Dates to come",
                        badge: badge(for: wedding),
                        selected: !context.isSample && wedding.id.lowercased() == context.weddingID.lowercased(),
                        isBusy: busyID == wedding.id
                    ) {
                        BrandHaptics.soft()
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            context.switchTo(wedding)
                        }
                    }
                    .plainRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        trailingActions(wedding)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        leadingActions(wedding)
                    }
                }
                if weddings.isEmpty, !context.isSample {
                    row(
                        initials: context.snapshot.initials,
                        title: context.snapshot.coupleNames,
                        detail: context.snapshot.placeLine ?? "",
                        badge: nil,
                        selected: true
                    ) {}
                    .plainRow()
                }

                if !weddings.isEmpty {
                    Text("Swipe a wedding for more")
                        .font(Milni.inter(12))
                        .foregroundStyle(BrandPalette.body.opacity(0.75))
                        .padding(.top, 10)
                        .plainRow()
                }

                VStack(spacing: 10) {
                    Button {
                        open(.joinCode)
                    } label: {
                        Label("Join another wedding", systemImage: "envelope.open")
                    }
                    .buttonStyle(MilniButtonStyle(kind: .primary, ink: BrandPalette.ink, paper: BrandPalette.background))

                    Button {
                        open(.create)
                    } label: {
                        Label("Create a wedding", systemImage: "plus")
                    }
                    .buttonStyle(MilniButtonStyle(kind: .secondary, ink: BrandPalette.ink, paper: BrandPalette.background))
                }
                .padding(.top, 22)
                .plainRow()

                // The host's area, without a swipe needed.
                if let current = currentWedding, canManageCurrent {
                    Button {
                        openCoupleArea(current, route: nil)
                    } label: {
                        HStack(spacing: 8) {
                            Label("Manage this wedding", systemImage: "key.horizontal")
                                .font(Milni.inter(14, weight: 500))
                                .foregroundStyle(BrandPalette.goldDeep)
                            if photoReports.openCount > 0 {
                                OpenReportsBadge(count: photoReports.openCount)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                    .plainRow()
                    .task { await photoReports.refresh() }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .animation(fade, value: weddings.map(\.id))
        .animation(fade, value: error)
        .task { await context.refreshMyWeddings() }
        .sheet(item: $share) { payload in
            HostShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .alert(
            leaveTitle,
            isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } })
        ) {
            Button(isPending(leaving) ? "Cancel request" : "Leave", role: .destructive) {
                if let wedding = leaving { Task { await leave(wedding) } }
            }
            Button(isPending(leaving) ? "Keep request" : "Stay", role: .cancel) { leaving = nil }
        } message: {
            Text(isPending(leaving)
                 ? "The couple won't see your request any more. You can ask again with the code."
                 : "You'll need the code to rejoin.")
        }
    }

    // MARK: Roles

    private func isHost(_ wedding: WeddingSummary) -> Bool { wedding.role?.lowercased() == "host" }
    private func isCohost(_ wedding: WeddingSummary) -> Bool { wedding.roleBadge == "Co-host" }
    private func isPending(_ wedding: WeddingSummary?) -> Bool { wedding?.status?.lowercased() == "pending" }

    private var currentWedding: WeddingSummary? {
        guard !context.isSample else { return nil }
        return context.myWeddings.first { $0.id.lowercased() == context.weddingID.lowercased() }
    }

    private var canManageCurrent: Bool {
        guard let wedding = currentWedding else { return false }
        return (isHost(wedding) || isCohost(wedding)) && !isPending(wedding)
    }

    private func badge(for wedding: WeddingSummary) -> RowBadge {
        if isPending(wedding) { return RowBadge(text: "Pending", muted: true) }
        if isHost(wedding) { return RowBadge(text: "Host", muted: false) }
        if isCohost(wedding) { return RowBadge(text: "Co-host", muted: false) }
        return RowBadge(text: "Guest", muted: true)
    }

    private var leaveTitle: String {
        guard let wedding = leaving else { return "" }
        return isPending(wedding)
            ? "Cancel your request to join \(wedding.coupleNames)?"
            : "Leave \(wedding.coupleNames)?"
    }

    // MARK: Swipe actions

    @ViewBuilder
    private func trailingActions(_ wedding: WeddingSummary) -> some View {
        if isHost(wedding) && !isPending(wedding) {
            Button {
                openCoupleArea(wedding, route: .guests)
            } label: {
                Label("Manage", systemImage: "person.2")
            }
            .tint(BrandPalette.goldDeep)
        } else {
            Button {
                BrandHaptics.tick()
                leaving = wedding
            } label: {
                if isPending(wedding) {
                    Label("Cancel request", systemImage: "xmark")
                } else {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .tint(.red)
        }
    }

    @ViewBuilder
    private func leadingActions(_ wedding: WeddingSummary) -> some View {
        if !isPending(wedding) {
            if isHost(wedding) || isCohost(wedding) {
                Button {
                    openCoupleArea(wedding, route: nil)
                } label: {
                    Label("Couple's area", systemImage: "key.horizontal")
                }
                .tint(BrandPalette.goldDeep)
            } else {
                Button {
                    Task { await shareInvite(wedding) }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .tint(BrandPalette.gold)
            }
        }
    }

    // MARK: Actions

    private func open(_ entry: WeddingContext.OnboardingEntry) {
        BrandHaptics.tick()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            context.presentFlow(entry)
        }
    }

    /// Switches to the wedding if needed, then opens its couple's area.
    private func openCoupleArea(_ wedding: WeddingSummary, route: CoupleRoute?) {
        BrandHaptics.soft()
        let isCurrent = !context.isSample && wedding.id.lowercased() == context.weddingID.lowercased()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if !isCurrent { context.switchTo(wedding) }
            DispatchQueue.main.asyncAfter(deadline: .now() + (isCurrent ? 0 : 0.7)) {
                AdminSession.request.open(route)
            }
        }
    }

    private func leave(_ wedding: WeddingSummary) async {
        leaving = nil
        busyID = wedding.id
        defer { busyID = nil }
        let wasCurrent = !context.isSample && wedding.id.lowercased() == context.weddingID.lowercased()
        do {
            try await HostAPI.shared.leaveWedding(weddingID: wedding.id)
            BrandHaptics.tick()
            withAnimation(fade) {
                _ = gone.insert(wedding.id.lowercased())
                error = nil
            }
            if wasCurrent {
                dismiss()
                try? await Task.sleep(for: .milliseconds(350))
                await context.didLeaveCurrentWedding()
            } else {
                await context.refreshMyWeddings()
            }
        } catch {
            withAnimation(fade) {
                self.error = isPending(wedding)
                    ? "We couldn't cancel your request. Check your connection and try again."
                    : "We couldn't take you out of this wedding. Check your connection and try again."
            }
        }
    }

    private func shareInvite(_ wedding: WeddingSummary) async {
        BrandHaptics.tick()
        busyID = wedding.id
        defer { busyID = nil }
        let code = try? await HostAPI.shared.joinCode(weddingID: wedding.id)
        if let code, !code.isEmpty {
            share = HostSharePayload(items: [
                "Join \(wedding.coupleNames)'s wedding on Milni: https://milniapp.com/j/\(code)"
            ])
        } else {
            withAnimation(fade) { error = "The invitation link isn't available right now. Ask the couple for their code." }
        }
    }

    // MARK: Row

    struct RowBadge {
        let text: String
        let muted: Bool
    }

    private func row(
        initials: String,
        title: String,
        detail: String,
        badge: RowBadge?,
        selected: Bool,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                MilniMonogram(initials: initials, size: 44, ring: BrandPalette.gold, textColor: BrandPalette.ink)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(Milni.cormorant(22, weight: 500))
                            .foregroundStyle(BrandPalette.ink)
                            .lineLimit(1)
                        if let badge {
                            Text(badge.text.uppercased())
                                .font(Milni.inter(9, weight: 600))
                                .tracking(1.4)
                                .foregroundStyle(badge.muted ? BrandPalette.body : BrandPalette.goldDeep)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(badge.muted ? BrandPalette.hairline.opacity(0.6) : Color.clear))
                                .overlay(Capsule().strokeBorder(
                                    badge.muted ? Color.clear : BrandPalette.gold.opacity(0.6),
                                    lineWidth: 0.8
                                ))
                                .fixedSize()
                        }
                    }
                    if !detail.isEmpty {
                        Text(detail)
                            .font(Milni.inter(13))
                            .foregroundStyle(BrandPalette.body)
                    }
                }
                Spacer(minLength: 8)
                if isBusy {
                    ProgressView()
                } else if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandPalette.goldDeep)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(BrandPalette.hairline).frame(height: 0.5)
            }
        }
        .buttonStyle(MilniPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension View {
    /// A List row that looks like the sheet's own paper, edge to edge.
    func plainRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
            .listRowBackground(BrandPalette.background)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Sample mode

/// A thin line across the top while browsing the sample wedding.
struct SampleWeddingBanner: View {
    var body: some View {
        Button {
            BrandHaptics.tick()
            WeddingContext.shared.goToOnboarding(.choose)
        } label: {
            HStack(spacing: 6) {
                Text("Sample wedding")
                    .foregroundStyle(Milni.champagneLight)
                Text("·").foregroundStyle(Milni.champagneLight.opacity(0.6))
                Text("Join yours")
                    .foregroundStyle(Color(hex: 0xF4EBDC))
                    .underline()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xF4EBDC))
            }
            .font(Milni.inter(12, weight: 500))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(Milni.midnight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("You're browsing a sample wedding. Join yours.")
    }
}

/// Shown in place of Chat and My Outfits while browsing the sample.
struct SampleJoinCard: View {
    var symbol = "bubble.left.and.bubble.right"

    var body: some View {
        VStack(spacing: 18) {
            MilniRings(color: BrandPalette.gold, lineWidth: 1, duration: 1.6, showsOuter: false, breathes: false)
                .frame(width: 64, height: 64)
            Text("Join a wedding to chat and plan outfits")
                .font(Milni.cormorant(32))
                .foregroundStyle(BrandPalette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("The sample shows how a wedding week looks. Conversations and outfits are for the guests of each wedding.")
                .font(Milni.inter(15))
                .lineSpacing(4)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Join a wedding") {
                BrandHaptics.tick()
                WeddingContext.shared.goToOnboarding(.choose)
            }
            .buttonStyle(MilniButtonStyle(kind: .primary, ink: BrandPalette.ink, paper: BrandPalette.background))
            .padding(.top, 8)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandPalette.background.ignoresSafeArea())
    }
}

// MARK: - Empty schedule

/// Before the couple adds events: their monogram and a quiet line.
struct WeddingEmptyState: View {
    var title = "Your schedule will appear here"
    var message = "Each ceremony, with its time, place and dress code, shows up as soon as it's added."

    var body: some View {
        VStack(spacing: 16) {
            MilniMonogram(initials: ActiveWedding.snapshot.initials, size: 72, ring: BrandPalette.gold, textColor: BrandPalette.ink)
            Text(title)
                .font(Milni.cormorant(28))
                .foregroundStyle(BrandPalette.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Milni.inter(14))
                .lineSpacing(4)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}
