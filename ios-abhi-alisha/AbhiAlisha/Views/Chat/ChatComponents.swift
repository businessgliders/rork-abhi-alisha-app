import SwiftUI

/// Where the Chat tab's navigation can go.
enum ChatRoute: Hashable {
    case announcements
    case openChannel
    case thread(UUID)
    case blocked
    case approvals
    case reports
}

extension BrandFontSpec {
    /// Names and conversation titles.
    static let chatName = BrandFontSpec(.playfairItalic, size: 20, weight: 500, textStyle: .headline, maxSize: 30)
    /// The sender's name above a run of group messages.
    static let chatSender = BrandFontSpec(.playfairItalic, size: 14, weight: 500, textStyle: .footnote, maxSize: 22)
    /// Message text.
    static let chatMessage = BrandFontSpec(.cormorant, size: 19, weight: 500, textStyle: .body, maxSize: 32)
    static let chatMessageItalic = BrandFontSpec(.cormorantItalic, size: 18, weight: 450, textStyle: .body, maxSize: 30)
    /// The one-line preview under a conversation's name.
    static let chatPreview = BrandFontSpec(.cormorant, size: 16.5, weight: 500, textStyle: .subheadline, maxSize: 24)
    /// An announcement's headline inside its gold bubble.
    static let announcementTitle = BrandFontSpec(.playfairItalic, size: 21, weight: 500, textStyle: .headline, maxSize: 32)
}

/// The mark beside the two channels everyone shares: the couple's crest on gold for
/// Announcements, a pair of speech marks for Questions & Chat.
struct ChannelBadge: View {
    enum Kind {
        case announcements
        case questions
    }

    let kind: Kind
    var size: CGFloat = 46

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                switch kind {
                case .announcements:
                    Image("crest")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(Color(hex: 0xFFFBF1))
                        .padding(size * 0.2)
                case .questions:
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: size * 0.34, weight: .light))
                        .foregroundStyle(BrandPalette.goldDeep)
                }
            }
            .overlay(Circle().stroke(BrandPalette.gold.opacity(0.55), lineWidth: 1))
            .overlay(
                Circle()
                    .inset(by: -3.5)
                    .stroke(BrandPalette.gold.opacity(0.2), lineWidth: 0.75)
            )
            .padding(3.5)
            .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .announcements:
            AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        case .questions:
            AnyShapeStyle(BrandPalette.hairline.opacity(0.55))
        }
    }
}

/// The gold back chevron used at the top of every full-screen chat page.
struct ChatBackButton: View {
    var label: String = "Back to Chat"

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            BrandHaptics.tick()
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(BrandPalette.goldDeep)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Initials (or the crest, for the family room) inside a fine double gold ring, in the
/// same hand as the Our Family portraits.
struct ChatAvatar: View {
    let initials: String
    var size: CGFloat = 46
    var showsCrest: Bool = false

    var body: some View {
        Circle()
            .fill(BrandPalette.hairline.opacity(0.55))
            .frame(width: size, height: size)
            .overlay {
                if showsCrest {
                    Image("crest")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(BrandPalette.goldDeep)
                        .padding(size * 0.2)
                } else {
                    Text(initials)
                        .font(Font(BrandFont.uiFont(.playfairItalic, size: size * 0.38, weight: 500, maxSize: size * 0.38)))
                        .foregroundStyle(BrandPalette.goldDeep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                }
            }
            .overlay(Circle().stroke(BrandPalette.gold.opacity(0.55), lineWidth: 1))
            .overlay(
                Circle()
                    .inset(by: -3.5)
                    .stroke(BrandPalette.gold.opacity(0.2), lineWidth: 0.75)
            )
            .padding(3.5)
            .accessibilityHidden(true)
    }
}

/// The small gold dot that means "something new here".
struct UnreadDot: View {
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(BrandPalette.gold)
            .frame(width: size, height: size)
            .shadow(color: BrandPalette.gold.opacity(0.5), radius: 4)
            .accessibilityHidden(true)
    }
}

/// A brief note that floats in and leaves on its own.
struct ChatToast: View {
    let text: String

    var body: some View {
        Text(text)
            .brandFont(.bodySmall)
            .foregroundStyle(BrandPalette.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Capsule(style: .continuous).fill(BrandPalette.card))
            .overlay(Capsule(style: .continuous).stroke(BrandPalette.gold.opacity(0.4), lineWidth: 0.75))
            .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// A gold-outline pill button for quiet secondary actions.
struct ChatOutlineButton: View {
    let title: String
    var systemImage: String?
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            BrandHaptics.tick()
            action()
        } label: {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(BrandLabel.font(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
            .foregroundStyle(isDestructive ? BrandPalette.overdue : BrandPalette.goldDeep)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(Capsule(style: .continuous).fill(BrandPalette.card))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isDestructive ? BrandPalette.overdue.opacity(0.4) : BrandPalette.gold.opacity(0.5), lineWidth: 0.9)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Eyebrow, Playfair title and gold rule, for every chat page.
struct ChatPageHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: eyebrow)

            Text(title)
                .brandFont(.screenTitle)
                .foregroundStyle(BrandPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            GoldRule(width: 58, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A soft line in place of an empty list.
struct ChatEmptyNote: View {
    let text: String
    var icon: EventIconKey = .paisley

    var body: some View {
        VStack(spacing: 16) {
            IconWatermark(key: icon, size: 80, opacity: 0.3)
            Text(text)
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
    }
}

/// How times read in the chat.
enum ChatTime {
    /// Beside a conversation: a time today, otherwise a day or a date.
    static func listStamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 6 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Between messages from different days.
    static func dayHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
