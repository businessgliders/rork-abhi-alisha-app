import SwiftUI

/// Announcements as a notice board: the shown notice stands on a thin gold easel, and up
/// to three earlier sheets lean behind it on the left, their dates written up the edge.
/// Tapping a sheet lifts it onto the easel and the one it replaces goes back into the
/// stack; swiping right steps to older notices, left to newer. The whole board is one
/// composition scaled to the space between the header and the tab bar.
/// With Reduce Motion, every change is a plain crossfade.
struct AnnouncementEasel: View {
    /// Newest first, as stored.
    let records: [NotificationRecord]
    let events: [ScheduleEvent]
    /// The room the board may use: width already inset from the screen edges, height
    /// from under the header to above the tab bar.
    let available: CGSize
    let isUnread: (NotificationRecord) -> Bool
    let onRoute: (AnnouncementDestination) -> Void

    /// An earlier notice put on the easel by hand; nil means the latest stands there.
    @State private var pinnedID: String?
    /// +1 when stepping to an older notice, -1 to a newer one; decides the slide direction.
    @State private var direction: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let design = CGSize(width: 320, height: 420)
    private static let navigatorHeight: CGFloat = 76

    private var index: Int {
        guard let pinnedID, let found = records.firstIndex(where: { $0.id == pinnedID }) else { return 0 }
        return found
    }

    private var current: NotificationRecord? {
        records.indices.contains(index) ? records[index] : nil
    }

    /// Older notices nearest first, then newer ones, so the sign that was just replaced
    /// always has a place in the stack.
    private var leaning: [NotificationRecord] {
        let older = records.indices.filter { $0 > index }.map { records[$0] }
        let newer = records.indices.filter { $0 < index }.reversed().map { records[$0] }
        return Array((older + newer).prefix(3))
    }

    private var olderCount: Int { max(0, records.count - 1 - index) }

    private var scale: CGFloat {
        let width = available.width / Self.design.width
        let height = (available.height - Self.navigatorHeight) / Self.design.height
        return min(max(min(width, height), 0.5), 1.35)
    }

    private var motion: Animation { reduceMotion ? .softFade : .calm }

    var body: some View {
        VStack(spacing: 0) {
            if let current {
                stage(current)
                    .frame(width: Self.design.width, height: Self.design.height)
                    .scaleEffect(scale)
                    .frame(width: Self.design.width * scale, height: Self.design.height * scale)
                    .contentShape(Rectangle())
                    .simultaneousGesture(swipe)
                    .accessibilityElement(children: .contain)
                    .accessibilityAdjustableAction { action in
                        switch action {
                        case .increment: step(by: -1)
                        case .decrement: step(by: 1)
                        @unknown default: break
                        }
                    }

                EaselNavigator(
                    count: records.count,
                    index: index,
                    olderCount: olderCount,
                    onOlder: { step(by: 1) },
                    onNewer: { step(by: -1) }
                )
                .frame(maxWidth: min(available.width, 420))
                .frame(height: Self.navigatorHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(motion, value: index)
        .onChange(of: records.first?.id) { _, _ in
            // A brand-new announcement always takes the easel.
            pinnedID = nil
        }
    }

    // MARK: Stage

    /// Positions in the 320 × 420 design space.
    private static let sign = CGRect(x: 80, y: 40, width: 224, height: 326)
    /// Where every leaning sheet's bottom-right corner rests, hidden behind the sign.
    private static let lean = CGPoint(x: 222, y: 340)

    private func stage(_ record: NotificationRecord) -> some View {
        let sign = Self.sign
        return ZStack(alignment: .topLeading) {
            EaselFrame()
                .frame(width: sign.width + 56, height: Self.design.height - 14)
                .position(x: sign.midX, y: 14 + (Self.design.height - 14) / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            ForEach(Array(leaning.enumerated()).reversed(), id: \.element.id) { depth, sheet in
                LeaningSheet(record: sheet, depth: depth, isNewer: sheet.sentAt.flatMap { date in
                    record.sentAt.map { date > $0 }
                } ?? false) {
                    pin(sheet)
                }
                .frame(width: LeaningSheet.size(depth).width, height: LeaningSheet.size(depth).height)
                .rotationEffect(.degrees(LeaningSheet.angles[depth]), anchor: .bottomTrailing)
                .position(
                    x: Self.lean.x - LeaningSheet.size(depth).width / 2,
                    y: Self.lean.y - LeaningSheet.size(depth).height / 2
                )
                .transition(.opacity)
            }

            EaselSign(
                record: record,
                isLatest: index == 0,
                isNew: isUnread(record),
                destination: record.destination(events: events),
                onRoute: onRoute
            )
            .frame(width: sign.width, height: sign.height)
            .id(record.id)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: -26 * direction, y: 8)),
                        removal: .opacity.combined(with: .offset(x: 30 * direction))
                    )
            )
            .position(x: sign.midX, y: sign.midY)

            EaselLedge()
                .frame(width: sign.width + 30, height: 6)
                .position(x: sign.midX, y: sign.maxY + 6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 50, abs(dx) > abs(value.translation.height) * 1.4 else { return }
                // Right reaches back in time; left comes forward.
                step(by: dx > 0 ? 1 : -1)
            }
    }

    private func step(by offset: Int) {
        let target = index + offset
        guard records.indices.contains(target) else {
            BrandHaptics.tick()
            return
        }
        show(records[target], direction: CGFloat(offset))
    }

    private func pin(_ record: NotificationRecord) {
        guard let target = records.firstIndex(where: { $0.id == record.id }) else { return }
        show(record, direction: target > index ? 1 : -1)
    }

    private func show(_ record: NotificationRecord, direction: CGFloat) {
        BrandHaptics.soft()
        self.direction = direction
        withAnimation(motion) {
            pinnedID = record.id == records.first?.id ? nil : record.id
        }
    }
}

// MARK: - Leaning sheets

/// A blank earlier notice leaning behind the easel; only its left edge shows, with the
/// date written up it in small caps. Each one further back is darker and fainter.
private struct LeaningSheet: View {
    let record: NotificationRecord
    let depth: Int
    let isNewer: Bool
    let action: () -> Void

    static let angles: [Double] = [-9, -13, -17]

    static func size(_ depth: Int) -> CGSize {
        CGSize(width: 168, height: 262 - CGFloat(depth) * 14)
    }

    private var dateText: String {
        record.sentAt?.formatted(.dateTime.month(.abbreviated).day()).uppercased() ?? "EARLIER"
    }

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(EaselPaper.color)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.05 + 0.05 * Double(depth)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(BrandPalette.gold.opacity(0.35 - 0.07 * Double(depth)), lineWidth: 0.75)
                )
                .overlay(alignment: .topLeading) {
                    Text(dateText)
                        .font(BrandLabel.font(size: 9, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(BrandPalette.goldDeep.opacity(0.9))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .rotationEffect(.degrees(-90))
                        .frame(width: 14, height: 84)
                        .padding(.leading, 5)
                        .padding(.top, 18)
                }
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: -2, y: 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .opacity(1 - 0.16 * Double(depth))
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint("Puts it on the easel")
    }

    private var accessibilityTitle: String {
        var parts = [isNewer ? "Newer notice" : "Earlier notice"]
        if let sentAt = record.sentAt { parts.append(sentAt.formatted(.dateTime.month(.wide).day())) }
        if let title = record.title { parts.append(title) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Navigator

/// "‹ EARLIER · ● ● ━ · LATEST ›" with a quiet hint underneath.
private struct EaselNavigator: View {
    let count: Int
    /// 0 is the latest.
    let index: Int
    let olderCount: Int
    let onOlder: () -> Void
    let onNewer: () -> Void

    private static let maxDots = 7

    /// Dots run oldest → newest; a window keeps a long history on one line.
    private var dots: [Int] {
        let positions = Array((0..<count).reversed())
        guard positions.count > Self.maxDots,
              let at = positions.firstIndex(of: index) else { return positions }
        let half = Self.maxDots / 2
        let lower = min(max(0, at - half), positions.count - Self.maxDots)
        return Array(positions[lower..<(lower + Self.maxDots)])
    }

    private var hint: String {
        if olderCount == 0 { return "This is the first notice" }
        let leaning = min(olderCount, 3)
        let noun = leaning == 1 ? "1 earlier notice" : "\(leaning) earlier notices"
        return "\(noun) leaning behind · tap one or swipe right"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button(action: onOlder) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("EARLIER")
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .disabled(olderCount == 0)
                .accessibilityLabel("Earlier notice")

                Text("·").accessibilityHidden(true)

                HStack(spacing: 5) {
                    ForEach(dots, id: \.self) { position in
                        Capsule(style: .continuous)
                            .fill(position == index ? BrandPalette.gold : BrandPalette.gold.opacity(0.3))
                            .frame(width: position == index ? 18 : 5, height: 5)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Notice \(count - index) of \(count)")

                Text("·").accessibilityHidden(true)

                Button(action: onNewer) {
                    HStack(spacing: 4) {
                        Text("LATEST")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .disabled(index == 0)
                .accessibilityLabel("Newer notice")
            }
            .font(BrandLabel.font(size: 10, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(BrandPalette.goldDeep)
            .buttonStyle(PressableStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Text(hint)
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
                .padding(.horizontal, 12)
        }
    }
}

// MARK: - Easel

/// The easel itself: an apex knob, two splayed front legs, a back leg and a soft shadow
/// on the floor.
private struct EaselFrame: View {
    var body: some View {
        Canvas { context, size in
            let apex = CGPoint(x: size.width / 2, y: 6)
            let floorY = size.height - 14
            let spread = min(size.width * 0.36, 170)

            // Floor shadow.
            let shadowRect = CGRect(x: size.width / 2 - spread - 20, y: floorY - 6, width: (spread + 20) * 2, height: 14)
            context.fill(
                Path(ellipseIn: shadowRect),
                with: .radialGradient(
                    Gradient(colors: [Color.black.opacity(0.16), Color.black.opacity(0)]),
                    center: CGPoint(x: shadowRect.midX, y: shadowRect.midY),
                    startRadius: 0,
                    endRadius: shadowRect.width / 2
                )
            )

            // Back leg, lighter and further away.
            var back = Path()
            back.move(to: apex)
            back.addLine(to: CGPoint(x: size.width / 2 + spread * 0.18, y: floorY - 10))
            context.stroke(back, with: .color(BrandPalette.goldDeep.opacity(0.4)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Front legs.
            let gold = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [BrandPalette.goldPale, BrandPalette.gold, BrandPalette.goldDeep]),
                startPoint: apex,
                endPoint: CGPoint(x: size.width / 2, y: floorY)
            )
            for direction in [-1.0, 1.0] {
                var leg = Path()
                leg.move(to: apex)
                leg.addLine(to: CGPoint(x: size.width / 2 + spread * direction, y: floorY))
                context.stroke(leg, with: gold, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            }

            // Lower crossbar between the front legs.
            let barY = floorY - (floorY - apex.y) * 0.12
            let barHalf = spread * ((barY - apex.y) / (floorY - apex.y))
            var bar = Path()
            bar.move(to: CGPoint(x: size.width / 2 - barHalf, y: barY))
            bar.addLine(to: CGPoint(x: size.width / 2 + barHalf, y: barY))
            context.stroke(bar, with: .color(BrandPalette.gold.opacity(0.75)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

            // Apex knob.
            let knob = CGRect(x: apex.x - 4, y: apex.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: knob), with: gold)
        }
    }
}

/// The gold ledge under the sign.
private struct EaselLedge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [BrandPalette.goldPale, BrandPalette.gold, BrandPalette.goldDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 6)
            .shadow(color: Color.black.opacity(0.18), radius: 3, y: 2)
    }
}

/// The paper the notices are printed on: cream in the light, the theme's card in the dark.
private enum EaselPaper {
    static let color = Color(
        uiColor: UIColor { traits in
            let card = UIColor(BrandPalette.card)
            guard traits.userInterfaceStyle != .dark else { return card }
            // A warm cream laid over the theme's own card, so a Blush wedding stays blush.
            let cream = UIColor(red: 0.992, green: 0.973, blue: 0.929, alpha: 1)
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            card.resolvedColor(with: traits).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            cream.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            let t: CGFloat = 0.45
            return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
        }
    )
}

/// The sign on the easel.
private struct EaselSign: View {
    let record: NotificationRecord
    let isLatest: Bool
    let isNew: Bool
    let destination: AnnouncementDestination?
    let onRoute: (AnnouncementDestination) -> Void

    private var dateText: String? {
        record.sentAt?.formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }

    private var label: String {
        let lead = isLatest ? "LATEST" : "EARLIER"
        guard let dateText else { return lead }
        return "\(lead) · \(dateText)"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    rule
                    Text(label)
                        .font(BrandLabel.font(size: 9.5, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(BrandPalette.goldDeep)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    rule
                }

                if let title = record.title {
                    Text(title)
                        .brandFont(.announcementHeadline)
                        .foregroundStyle(BrandPalette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 12)
                        .layoutPriority(1)
                }

                if let body = record.body {
                    // A long notice scrolls inside the sign instead of stretching the board.
                    ScrollView {
                        Text(body)
                            .brandFont(.bodyText)
                            .foregroundStyle(BrandPalette.ink.opacity(0.86))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .padding(.top, 8)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(record.body ?? "")

            if let destination {
                Button {
                    onRoute(destination)
                } label: {
                    HStack(spacing: 6) {
                        Text("View \(destination.label)")
                            .font(BrandLabel.font(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(BrandPalette.goldDeep)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .overlay(Capsule(style: .continuous).stroke(BrandPalette.gold.opacity(0.6), lineWidth: 1))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 10)
                .accessibilityHint("Opens \(destination.label), the same place the notification goes")
            }

            Text("— \(ActiveWedding.couple)")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 10)
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EaselPaper.color)
        .overlay {
            // Double gold hairline frame.
            ZStack {
                Rectangle()
                    .stroke(BrandPalette.gold.opacity(0.7), lineWidth: 0.75)
                    .padding(8)
                Rectangle()
                    .stroke(BrandPalette.gold.opacity(0.45), lineWidth: 0.5)
                    .padding(11.5)
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 14, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
        .overlay(alignment: .top) {
            WaxSeal(initial: String(ActiveWedding.snapshot.partnerOne.trimmed.prefix(1)).uppercased().nonEmpty
                ?? String(ActiveWedding.snapshot.initials.prefix(1)))
                .offset(y: -13)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            if isNew {
                UnreadDot()
                    .padding(16)
                    .accessibilityLabel("New")
            }
        }
    }

    private var accessibilityTitle: String {
        var parts = ["Announcement"]
        if let sentAt = record.sentAt {
            parts.append(sentAt.formatted(.dateTime.month(.wide).day()))
        }
        if let title = record.title { parts.append(title) }
        return parts.joined(separator: ", ")
    }

    private var rule: some View {
        Rectangle()
            .fill(BrandPalette.gold.opacity(0.7))
            .frame(width: 22, height: 0.75)
    }
}

/// The gold wax-seal pin holding the sign, pressed with the wedding's first initial.
private struct WaxSeal: View {
    let initial: String

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [BrandPalette.goldPale, BrandPalette.gold, BrandPalette.goldDeep],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 1,
                        endRadius: 20
                    )
                )
            Circle()
                .stroke(BrandPalette.goldDeep.opacity(0.55), lineWidth: 1)
                .padding(4)
            Text(initial)
                .brandFont(.eventTitleSmall)
                .foregroundStyle(Color(hex: 0xFFF8E6))
                .shadow(color: BrandPalette.goldDeep.opacity(0.8), radius: 0.5, y: 0.5)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(6)
        }
        .frame(width: 30, height: 30)
        .shadow(color: Color.black.opacity(0.22), radius: 3, y: 2)
    }
}

