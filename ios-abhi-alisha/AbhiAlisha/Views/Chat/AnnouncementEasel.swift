import SwiftUI

/// Announcements as a notice board: the pinned note stands on a thin gold easel, with
/// two older notices peeking out behind it, and everything earlier is listed below,
/// fading a little more with each step back in time. Tapping an earlier notice lifts it
/// onto the easel; the one it replaces drops back into the list in its own place.
/// With Reduce Motion, every change is a plain crossfade.
struct AnnouncementEasel: View {
    /// Newest first, as stored.
    let records: [NotificationRecord]
    let events: [ScheduleEvent]
    /// The height of the easel stage, about 45% of the screen.
    let stageHeight: CGFloat
    let isUnread: (NotificationRecord) -> Bool
    let onRoute: (AnnouncementDestination) -> Void

    /// An earlier notice pinned by hand; nil means the latest stands on the easel.
    @State private var pinnedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pinned: NotificationRecord? {
        records.first { $0.id == pinnedID } ?? records.first
    }

    private var earlier: [NotificationRecord] {
        guard let pinned else { return [] }
        return records.filter { $0.id != pinned.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let pinned {
                EaselStage(
                    record: pinned,
                    isLatest: pinned.id == records.first?.id,
                    isNew: isUnread(pinned),
                    peekCount: min(2, records.count - 1),
                    destination: pinned.destination(events: events),
                    minHeight: stageHeight,
                    reduceMotion: reduceMotion,
                    onRoute: onRoute
                )
            }

            if !earlier.isEmpty {
                BoardHeading(text: "Earlier on the board")
                    .padding(.top, 30)
                    .padding(.bottom, 14)

                VStack(spacing: 10) {
                    ForEach(Array(earlier.enumerated()), id: \.element.id) { index, record in
                        EarlierNoticeRow(
                            record: record,
                            depth: index,
                            isNew: isUnread(record)
                        ) {
                            pin(record)
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .animation(reduceMotion ? .softFade : .calm, value: pinned?.id)
        .onChange(of: records.first?.id) { _, _ in
            // A brand-new announcement always takes the easel.
            pinnedID = nil
        }
    }

    private func pin(_ record: NotificationRecord) {
        BrandHaptics.soft()
        withAnimation(reduceMotion ? .softFade : .calm) {
            pinnedID = record.id == records.first?.id ? nil : record.id
        }
    }
}

// MARK: - Stage

private struct EaselStage: View {
    let record: NotificationRecord
    let isLatest: Bool
    let isNew: Bool
    let peekCount: Int
    let destination: AnnouncementDestination?
    let minHeight: CGFloat
    let reduceMotion: Bool
    let onRoute: (AnnouncementDestination) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Two older notices tucked behind, slightly darker.
                if peekCount >= 2 {
                    PeekingNotice(rotation: 3.5, offset: CGSize(width: 10, height: 8))
                }
                if peekCount >= 1 {
                    PeekingNotice(rotation: -5, offset: CGSize(width: -8, height: 4))
                }

                EaselSign(
                    record: record,
                    isLatest: isLatest,
                    isNew: isNew,
                    destination: destination,
                    onRoute: onRoute
                )
                .id(record.id)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 16)).combined(with: .scale(scale: 0.98, anchor: .bottom)),
                            removal: .opacity.combined(with: .offset(y: 10))
                        )
                )
            }
            // The ledge the sign rests on.
            .overlay(alignment: .bottom) {
                EaselLedge()
                    .padding(.horizontal, -18)
                    .offset(y: 7)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 30)
            .padding(.top, 22)

            Spacer(minLength: 64)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minHeight)
        .background {
            EaselFrame()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

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

/// An older notice peeking from behind the sign.
private struct PeekingNotice: View {
    let rotation: Double
    let offset: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(EaselPaper.color)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(BrandPalette.gold.opacity(0.28), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 3)
            .rotationEffect(.degrees(rotation))
            .offset(offset)
            .accessibilityHidden(true)
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
        let lead = isLatest ? "LATEST" : "PINNED"
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
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }

                if let body = record.body {
                    Text(body)
                        .brandFont(.bodyText)
                        .foregroundStyle(BrandPalette.ink.opacity(0.86))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
            }
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
                .padding(.top, 18)
                .accessibilityHint("Opens \(destination.label), the same place the notification goes")
            }

            Text("— \(ActiveWedding.couple)")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .padding(.top, 16)
        }
        .padding(.horizontal, 26)
        .padding(.top, 34)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
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

// MARK: - Earlier

private struct BoardHeading: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(BrandPalette.gold.opacity(0.5)).frame(height: 0.75)
            Text(text.uppercased())
                .font(BrandLabel.font(size: 10, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(BrandPalette.goldDeep)
                .fixedSize()
            Rectangle().fill(BrandPalette.gold.opacity(0.5)).frame(height: 0.75)
        }
        .padding(.horizontal, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A compact earlier notice: date in small caps, title, a one-line preview. Each step
/// further down the board is a little fainter, smaller and flatter.
private struct EarlierNoticeRow: View {
    let record: NotificationRecord
    let depth: Int
    let isNew: Bool
    let action: () -> Void

    private var fade: Double { max(0.45, 1 - 0.22 * Double(depth)) }
    private var scale: CGFloat { max(0.88, 1 - 0.03 * CGFloat(depth)) }
    private var shadowStrength: Double { max(0.02, 0.09 - 0.02 * Double(depth)) }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let sentAt = record.sentAt {
                        Text(sentAt.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                            .font(BrandLabel.font(size: 9.5, weight: .semibold))
                            .tracking(1.8)
                            .foregroundStyle(BrandPalette.goldDeep)
                            .monospacedDigit()
                    }
                    Text(record.title ?? "Announcement")
                        .brandFont(.chatName)
                        .foregroundStyle(BrandPalette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let body = record.body {
                        Text(body)
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if isNew {
                    UnreadDot()
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(EaselPaper.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BrandPalette.gold.opacity(0.3), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(shadowStrength), radius: 10 - min(8, CGFloat(depth) * 2), y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(scale, anchor: .top)
        .opacity(fade)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint("Pins it to the easel")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityTitle: String {
        var parts = ["Announcement"]
        if let sentAt = record.sentAt {
            parts.append(sentAt.formatted(.dateTime.month(.wide).day()))
        }
        parts.append(record.title ?? "Untitled")
        return parts.joined(separator: ", ")
    }
}
