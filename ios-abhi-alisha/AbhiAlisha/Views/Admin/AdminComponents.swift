import SwiftUI

/// The three rooms of the couple's area.
enum AdminTab: String, CaseIterable, Identifiable {
    case send
    case checklist
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .send: return "Send"
        case .checklist: return "Checklist"
        case .timeline: return "Timeline"
        }
    }

    var symbolName: String {
        switch self {
        case .send: return "paperplane"
        case .checklist: return "checklist"
        case .timeline: return "calendar"
        }
    }
}

/// A note being written to every guest — shared so the Timeline can start one.
struct NotificationDraft: Equatable {
    var title: String = ""
    var body: String = ""
}

/// Page header for the couple's screens: eyebrow, Playfair title, gold rule, and the
/// pressed crest in the corner, travelling with the page as it does in the guest app.
struct AdminHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: eyebrow)

                Text(title)
                    .brandFont(.screenTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                GoldRule(width: 58, alignment: .leading)
                    .padding(.top, 2)
            }
            .padding(.top, 34)

            Spacer(minLength: 0)

            CrestWatermark(width: 96, finish: .pressed(BrandPalette.background))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A labelled cream input well.
struct AdminField<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: label, size: 9.5)
                Spacer(minLength: 8)
                if let hint {
                    Text(hint)
                        .font(BrandLabel.font(size: 10, weight: .medium))
                        .foregroundStyle(BrandPalette.body.opacity(0.7))
                        .monospacedDigit()
                }
            }

            content
                .brandFont(.bodyText)
                .foregroundStyle(BrandPalette.ink)
                .tint(BrandPalette.goldDeep)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(BrandPalette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BrandPalette.gold.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

/// A quiet way to leave the device locked again.
struct AdminLockFooter: View {
    @Environment(AdminSession.self) private var session
    @State private var isConfirming = false

    var body: some View {
        Button {
            BrandHaptics.tick()
            isConfirming = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "lock")
                    .font(.system(size: 10, weight: .medium))
                Text("Lock the couple's area")
                    .font(BrandLabel.font(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .textCase(.uppercase)
            }
            .foregroundStyle(BrandPalette.body.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Lock the couple's area?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Lock", role: .destructive) { session.lock() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need the passcode to come back in.")
        }
    }
}

/// A soft line shown in place of content that couldn't load.
struct AdminNote: View {
    let text: String
    var symbol: String = "leaf"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .ultraLight))
                .foregroundStyle(BrandPalette.gold)
            Text(text)
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

/// The floating glass bar for the couple's area, with a way back to the guest app.
/// Like the guest bar, it's the only glass on these screens.
struct AdminTabBar: View {
    @Binding var selection: AdminTab
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AdminTab.allCases) { tab in
                Button {
                    guard tab != selection else { return }
                    BrandHaptics.tick()
                    withAnimation(.calm) { selection = tab }
                } label: {
                    item(title: tab.title, symbol: tab.symbolName, isSelected: tab == selection)
                }
                .buttonStyle(AdminTabItemStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(tab == selection ? [.isButton, .isSelected] : .isButton)
            }

            Rectangle()
                .fill(BrandPalette.gold.opacity(0.25))
                .frame(width: 1, height: 28)

            Button {
                BrandHaptics.tick()
                onClose()
            } label: {
                item(title: "Close", symbol: "xmark", isSelected: false)
                    .frame(width: 72)
            }
            .buttonStyle(AdminTabItemStyle())
            .accessibilityLabel("Return to the guest app")
        }
        .padding(.horizontal, 4)
        .frame(height: FloatingTabBar.barHeight)
        .background(glassSurface)
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.12), BrandPalette.gold.opacity(0.22)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .clipShape(Capsule(style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 22, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
        .padding(.horizontal, FloatingTabBar.edgeInset)
        .padding(.bottom, FloatingTabBar.edgeInset)
        .frame(maxWidth: 560)
    }

    private func item(title: String, symbol: String, isSelected: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .symbolVariant(.none)
                .font(.system(size: 19, weight: isSelected ? .regular : .light))
                .frame(height: 22)
                .shadow(color: isSelected ? BrandPalette.gold.opacity(0.35) : .clear, radius: isSelected ? 7 : 0)

            Text(title.uppercased())
                .font(BrandLabel.font(size: 8.5, weight: isSelected ? .semibold : .medium))
                .tracking(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(isSelected ? BrandPalette.goldDeep : BrandPalette.tabInactive)
        .frame(maxWidth: .infinity)
        .frame(height: FloatingTabBar.barHeight)
        .contentShape(Rectangle())
        .animation(.calm, value: isSelected)
    }

    @ViewBuilder
    private var glassSurface: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular, in: .capsule)
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(BrandPalette.card.opacity(0.22)))
        }
    }
}

private struct AdminTabItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
