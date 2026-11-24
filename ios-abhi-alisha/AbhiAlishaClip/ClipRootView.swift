import StoreKit
import SwiftUI

struct ClipRootView: View {
    @Environment(ClipModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOverlayShown = false
    @State private var typedCode = ""

    private var theme: ClipTheme { model.theme }
    private var isDark: Bool { theme.forcedDark ?? (colorScheme == .dark) }
    private var palette: ClipPalette { ClipPalette(theme.tokens(dark: colorScheme == .dark)) }

    var body: some View {
        ZStack {
            backdrop
            ScrollView {
                VStack(spacing: 28) {
                    header
                    switch model.phase {
                    case .waiting:
                        codeEntry
                    case .loading:
                        loading
                    case .notFound:
                        message(
                            title: String(localized: "We couldn't find that invitation"),
                            detail: String(localized: "Check the link from the couple, or type the code on their card."),
                            showsEntry: true
                        )
                    case .offline:
                        message(
                            title: String(localized: "You're offline"),
                            detail: String(localized: "Connect to the internet to open your invitation."),
                            showsRetry: true
                        )
                    case .invitation:
                        if let wedding = model.wedding {
                            InvitationCard(wedding: wedding, zone: model.zone, theme: theme, palette: palette)
                                .transition(.opacity)
                            scheduleSection
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 120)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) { getMilniBar }
        .preferredColorScheme(theme.forcedDark.map { $0 ? .dark : .light })
        .tint(palette.accentText)
        .animation(reduceMotion ? .linear(duration: 0.2) : .easeInOut(duration: 0.45), value: model.phase)
        .appStoreOverlay(isPresented: $isOverlayShown) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
        .onChange(of: model.phase) { _, phase in
            guard phase == .invitation else { return }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                isOverlayShown = true
            }
        }
    }

    // MARK: Pieces

    private var backdrop: some View {
        ZStack {
            palette.bg
            RadialGradient(
                colors: [palette.accent.opacity(isDark ? 0.16 : 0.12), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        Text("Milni")
            .font(ClipFont.label(12))
            .tracking(3)
            .foregroundStyle(palette.accentText)
            .accessibilityAddTraits(.isHeader)
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(palette.accent)
            Text("Opening your invitation…")
                .font(ClipFont.body(18, theme: theme))
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var codeEntry: some View {
        VStack(spacing: 18) {
            Text("Open your wedding invitation")
                .font(ClipFont.display(30, theme: theme))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Scan the couple's code, tap their link, or type the code from your invitation.")
                .font(ClipFont.body(18, theme: theme))
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
            entryField
        }
        .padding(.top, 60)
    }

    private var entryField: some View {
        VStack(spacing: 12) {
            TextField(String(localized: "Invitation code"), text: $typedCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { model.open(code: typedCode) }
                .multilineTextAlignment(.center)
                .font(ClipFont.body(22, theme: theme))
                .foregroundStyle(palette.ink)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.card))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.hairline, lineWidth: 1))
            Button {
                model.open(code: typedCode)
            } label: {
                Text("Open invitation")
                    .font(ClipFont.label(13))
                    .tracking(1.4)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(palette.bg)
                    .background(Capsule().fill(palette.accent))
            }
            .buttonStyle(.plain)
            .disabled(ClipLink.normalize(typedCode) == nil)
            .opacity(ClipLink.normalize(typedCode) == nil ? 0.5 : 1)
        }
    }

    private func message(title: String, detail: String, showsEntry: Bool = false, showsRetry: Bool = false) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .font(ClipFont.display(26, theme: theme))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(ClipFont.body(18, theme: theme))
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
            if showsRetry {
                Button(String(localized: "Try again")) { model.retry() }
                    .font(ClipFont.label(13))
                    .padding(.top, 6)
            }
            if showsEntry {
                entryField.padding(.top, 10)
            }
        }
        .padding(.top, 60)
    }

    @ViewBuilder
    private var scheduleSection: some View {
        if model.events.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                Text("Your full schedule is in the app")
                    .font(ClipFont.display(21, theme: theme, style: .title3))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                Text("Get Milni to see every celebration, dress codes and updates from the couple.")
                    .font(ClipFont.body(17, theme: theme))
                    .foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(palette.hairline, lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("The celebrations")
                    .font(ClipFont.label(11.5))
                    .tracking(1.6)
                    .foregroundStyle(palette.accentText)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(model.events) { event in
                        ClipEventRow(event: event, zone: model.zone, theme: theme, palette: palette)
                        if event.id != model.events.last?.id {
                            Rectangle().fill(palette.hairline).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.card))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(palette.hairline, lineWidth: 1))
            }
        }
    }

    private var getMilniBar: some View {
        Button {
            isOverlayShown = true
        } label: {
            Label(String(localized: "Get Milni"), systemImage: "arrow.down.app")
                .font(ClipFont.label(14))
                .tracking(1.2)
                .frame(maxWidth: 520)
                .padding(.vertical, 16)
                .foregroundStyle(palette.bg)
                .background(Capsule().fill(palette.accent))
                .shadow(color: palette.accent.opacity(0.3), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
        .accessibilityHint(Text("Shows Milni in the App Store"))
    }
}

/// One celebration with its time and dress code.
private struct ClipEventRow: View {
    let event: ClipEvent
    let zone: TimeZone
    let theme: ClipTheme
    let palette: ClipPalette

    private var when: String? {
        guard let date = event.startsAt else { return nil }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
        style.timeZone = zone
        return date.formatted(style)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let when {
                Text(when)
                    .font(ClipFont.label(11))
                    .tracking(1)
                    .foregroundStyle(palette.accentText)
            }
            Text(event.title)
                .font(ClipFont.display(21, theme: theme, style: .title3))
                .foregroundStyle(palette.ink)
            if let venue = event.venue, !venue.isEmpty {
                Text(venue)
                    .font(ClipFont.body(17, theme: theme))
                    .foregroundStyle(palette.muted)
            }
            if let dress = event.dressCode {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "tshirt")
                        .font(.caption)
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                    Text(dress)
                        .font(ClipFont.body(16.5, theme: theme))
                        .italic()
                        .foregroundStyle(palette.ink.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Dress code: \(dress)"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

/// The foil invitation: cover photo, monogram, names, dates and place, edged in the
/// wedding's accent foil.
private struct InvitationCard: View {
    let wedding: ClipWedding
    let zone: TimeZone
    let theme: ClipTheme
    let palette: ClipPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shine: CGFloat = -1

    private var foil: LinearGradient {
        LinearGradient(
            colors: [palette.accent.opacity(0.65), palette.accent, Color.white.opacity(0.85), palette.accent, palette.accentText],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            cover
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(foil, lineWidth: 1.6)
                    Text(wedding.initials)
                        .font(ClipFont.display(24, theme: theme, style: .title2))
                        .foregroundStyle(palette.accentText)
                }
                .frame(width: 66, height: 66)
                .background(Circle().fill(palette.card))
                .offset(y: wedding.coverURL == nil ? 0 : -33)
                .padding(.bottom, wedding.coverURL == nil ? 0 : -33)

                Text("You're invited")
                    .font(ClipFont.label(11.5))
                    .tracking(2)
                    .foregroundStyle(palette.accentText)

                Text(wedding.coupleNames)
                    .font(ClipFont.display(36, theme: theme, style: .largeTitle))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .overlay { shimmer.mask(Text(wedding.coupleNames).font(ClipFont.display(36, theme: theme, style: .largeTitle)).multilineTextAlignment(.center).minimumScaleFactor(0.7)) }

                Rectangle()
                    .fill(foil)
                    .frame(width: 64, height: 1)

                if let dates = wedding.dateRange(in: zone) {
                    Text(dates)
                        .font(ClipFont.body(20, theme: theme))
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.center)
                }
                if let place = wedding.place {
                    Text(place)
                        .font(ClipFont.body(17, theme: theme))
                        .foregroundStyle(palette.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, wedding.coverURL == nil ? 26 : 0)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(palette.card))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(foil, lineWidth: 1.2))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.8)
                .padding(7)
                .allowsHitTesting(false)
        )
        .shadow(color: palette.accent.opacity(0.14), radius: 24, y: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).delay(0.6)) { shine = 1.6 }
        }
    }

    private var accessibilityText: String {
        var parts = [String(localized: "You're invited to \(wedding.coupleNames)'s wedding")]
        if let dates = wedding.dateRange(in: zone) { parts.append(dates) }
        if let place = wedding.place { parts.append(place) }
        return parts.joined(separator: ". ")
    }

    /// One slow pass of light across the names (skipped with Reduce Motion).
    private var shimmer: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.55), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.5)
            .offset(x: proxy.size.width * shine)
            .opacity(reduceMotion ? 0 : 1)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var cover: some View {
        if let url = wedding.coverURL {
            Color.clear
                .frame(height: 210)
                .overlay {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill().transition(.opacity)
                        } else {
                            palette.accent.opacity(0.12)
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, palette.card], startPoint: .center, endPoint: .bottom)
                        .frame(height: 90)
                }
                .clipped()
                .accessibilityHidden(true)
        }
    }
}
