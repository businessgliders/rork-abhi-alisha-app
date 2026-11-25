import SwiftUI

// MARK: - Shared pieces for the Host area
//
// The Host area is Milni's own room, not the wedding's: ivory paper, ink type and a
// midnight header, the same in every wedding so a host always knows where they are.

enum HostStyle {
    static let paper = Milni.ivory
    static let card = Color(hex: 0xFFFDF8)
    static let ink = Milni.ink
    static let muted = Milni.muted
    static let gold = Milni.gold
    static let goldText = Milni.goldText
    static let hairline = Color(hex: 0xE6DCCB)
    static let danger = Color(hex: 0x9A3B2E)
    static let side: CGFloat = 22
}

/// The small letter-spaced caps over a group.
struct HostCaps: View {
    let text: String
    var color: Color = HostStyle.goldText

    init(_ text: String, color: Color = HostStyle.goldText) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Milni.inter(11, weight: 600))
            .tracking(2.2)
            .foregroundStyle(color)
    }
}

/// Cancel · LABEL · Save, the top of every editor sheet.
struct HostSheetBar: View {
    let title: String
    var saveTitle = "Save"
    var canSave = true
    var isSaving = false
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        ZStack {
            HostCaps(title, color: HostStyle.ink)
            HStack {
                Button("Cancel") {
                    BrandHaptics.tick()
                    cancel()
                }
                .font(Milni.inter(16))
                .foregroundStyle(HostStyle.muted)
                .frame(minHeight: 44)

                Spacer()

                Button {
                    BrandHaptics.soft()
                    save()
                } label: {
                    ZStack {
                        Text(saveTitle).opacity(isSaving ? 0 : 1)
                        if isSaving { ProgressView().tint(HostStyle.paper) }
                    }
                    .font(Milni.inter(15, weight: 600))
                    .foregroundStyle(HostStyle.paper)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(Capsule().fill(HostStyle.ink))
                }
                .buttonStyle(MilniPressStyle())
                .disabled(!canSave || isSaving)
                .opacity(canSave ? 1 : 0.35)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, HostStyle.side)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

/// Back chevron · LABEL, the top of a pushed Host screen.
struct HostScreenBar: View {
    let title: String
    let back: () -> Void
    var trailing: AnyView? = nil

    var body: some View {
        ZStack {
            HostCaps(title, color: HostStyle.ink)
            HStack {
                MilniBackButton(action: back).padding(.leading, -10)
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, HostStyle.side)
        .padding(.top, 4)
    }
}

/// A big serif title typed straight onto an underline.
struct HostTitleField: View {
    let placeholder: String
    @Binding var text: String
    var size: CGFloat = 40

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(HostStyle.muted.opacity(0.45)), axis: .vertical)
                .font(Milni.cormorant(size, weight: 500))
                .foregroundStyle(HostStyle.ink)
                .focused($focused)
                .lineLimit(1...3)
                .submitLabel(.done)
            Rectangle()
                .fill(focused ? HostStyle.gold : HostStyle.ink)
                .frame(height: focused ? 1.5 : 1)
                .animation(.calm, value: focused)
        }
    }
}

/// A labelled line of text in an editor.
struct HostField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var multiline = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HostCaps(label, color: HostStyle.muted)
            Group {
                if multiline {
                    TextField("", text: $text, prompt: prompt, axis: .vertical)
                        .lineLimit(3...12)
                } else {
                    TextField("", text: $text, prompt: prompt)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(keyboard == .URL ? .never : .sentences)
                        .autocorrectionDisabled(keyboard == .URL)
                }
            }
            .font(Milni.inter(16))
            .foregroundStyle(HostStyle.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HostStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(HostStyle.hairline, lineWidth: 1))
        }
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(HostStyle.muted.opacity(0.5))
    }
}

/// A plain-words error line that fades in and out.
struct HostErrorLine: View {
    let message: String?

    var body: some View {
        if let message {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                Text(message).fixedSize(horizontal: false, vertical: true)
            }
            .font(Milni.inter(14))
            .foregroundStyle(HostStyle.danger)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HostStyle.danger.opacity(0.07)))
            .transition(.opacity)
        }
    }
}

/// A white card holding rows, hairlines between them.
struct HostCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(HostStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(HostStyle.hairline, lineWidth: 1))
    }
}

struct HostHairline: View {
    var body: some View {
        Rectangle().fill(HostStyle.hairline).frame(height: 1).padding(.leading, 18)
    }
}

/// A gentle quiet message when a list is empty.
struct HostEmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Milni.cormorant(22, italic: true))
            .foregroundStyle(HostStyle.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
    }
}

/// A pill-shaped choice.
struct HostChip: View {
    let title: String
    var symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            BrandHaptics.tick()
            action()
        } label: {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).lineLimit(1)
            }
            .font(Milni.inter(14, weight: isOn ? 600 : 500))
            .foregroundStyle(isOn ? HostStyle.paper : HostStyle.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(isOn ? HostStyle.ink : HostStyle.card))
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : HostStyle.hairline, lineWidth: 1))
        }
        .buttonStyle(MilniPressStyle())
        .animation(.calm, value: isOn)
    }
}

/// The Host area's paper background with a faint warmth at the top.
struct HostPaper: View {
    var body: some View {
        ZStack {
            HostStyle.paper
            RadialGradient(colors: [HostStyle.gold.opacity(0.08), .clear], center: .top, startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

extension String {
    var hostTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Wedding times shown in the wedding's own time zone.
enum HostTime {
    static var zone: TimeZone { TimeZone(identifier: WeddingContext.shared.snapshot.timezone) ?? .current }

    static func day(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = zone
        return date.formatted(style)
    }

    static func time(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = zone
        return date.formatted(style)
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }
}

extension WeddingSnapshot {
    /// "Cancún · Jan 30 – Feb 3, 2027", for the host header and printed card.
    var cityAndDates: String {
        var parts: [String] = []
        if let place = (city ?? venueName)?.trimmingCharacters(in: .whitespaces), !place.isEmpty {
            parts.append(place)
        }
        if let start {
            var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            style.timeZone = timeZone
            var yearStyle = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
            yearStyle.timeZone = timeZone
            if let end, end > start {
                parts.append("\(start.formatted(style)) – \(end.formatted(yearStyle))")
            } else {
                parts.append(start.formatted(yearStyle))
            }
        }
        return parts.joined(separator: " · ")
    }
}
