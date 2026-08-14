import SwiftUI

/// Once a guest has found themselves on the list, Home greets them by name instead of
/// asking again. Their party is named, their reply is shown, and they can open the full
/// details or hand the phone back and search for somebody else.
struct RSVPWelcomeCard: View {
    let record: RSVPRecord
    let onOpenDetails: () -> Void
    let onReset: () -> Void

    var body: some View {
        MatteCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: "You're on the list")

                Text(greeting)
                    .brandFont(.eventTitle)
                    .foregroundStyle(BrandPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.trailing, 56)

                GoldRule(width: 40, alignment: .leading)
                    .padding(.top, 16)

                Text(welcomeLine)
                    .brandFont(.bodyItalic)
                    .lineSpacing(BrandFontSpec.bodyItalic.lineSpacing)
                    .foregroundStyle(BrandPalette.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                if let party = partyLine {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(
                            text: "Your party",
                            color: BrandPalette.gold.opacity(0.6),
                            size: 8.5
                        )

                        Text(party)
                            .brandFont(.bodyText)
                            .foregroundStyle(BrandPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 18)
                }

                actions
                    .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                CrestWatermark(width: 66, finish: .pressed(BrandPalette.card))
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                BrandHaptics.soft()
                onOpenDetails()
            } label: {
                HStack(spacing: 8) {
                    Text("View your details")
                        .font(BrandLabel.font(size: 11.5, weight: .semibold))
                        .tracking(1.2)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(BrandPalette.goldDeep)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(BrandPalette.gold.opacity(0.1))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(BrandPalette.gold.opacity(0.45), lineWidth: 0.75)
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Opens your party, events, and any notes you left")

            Button {
                BrandHaptics.tick()
                onReset()
            } label: {
                Text("Not you?")
                    .font(BrandLabel.font(size: 11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(BrandPalette.body.opacity(0.75))
                    .underline(true, pattern: .solid)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search for a different name")

            Spacer(minLength: 0)
        }
    }

    // MARK: - Words

    private var greeting: String {
        guard let firstName = record.firstName else { return "Welcome" }
        return "Welcome, \(firstName)"
    }

    /// Warm either way: glad they're coming, or grateful they let the couple know.
    private var welcomeLine: String {
        switch record.isAttending {
        case true?:
            return "We can't wait to celebrate with you in Cancún."
        case false?:
            return "We'll miss you — thank you for letting us know."
        default:
            return "We have your invitation on file."
        }
    }

    /// Everyone travelling under this invitation, read as a sentence.
    private var partyLine: String? {
        var names: [String] = []
        if let guestName = record.guestName { names.append(guestName) }
        names.append(contentsOf: record.partyMembers)

        guard !names.isEmpty else { return record.partyLine }
        return names.formatted(.list(type: .and, width: .standard))
    }
}
