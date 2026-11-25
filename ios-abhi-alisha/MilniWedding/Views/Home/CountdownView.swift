import SwiftUI

/// Live countdown to the main ceremony: days / hours / minutes in pale gold Playfair italic,
/// separated by thin vertical gold hairlines, with the ceremony's own date typed in
/// beneath them in the same hand as the couple's names.
struct CountdownView: View {
    let target: Date
    /// Seconds to wait before the date begins typing, so it follows the names.
    var dateStartDelay: Double = 0.35

    var body: some View {
        VStack(spacing: 14) {
            TimelineView(.everyMinute) { context in
                let parts = Self.parts(from: context.date, to: target)

                HStack(alignment: .center, spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        if index > 0 {
                            Rectangle()
                                .fill(BrandPalette.goldPale.opacity(0.45))
                                .frame(width: 1, height: 42)
                        }

                        unit(value: part.value, label: part.label)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.accessibilityLabel(parts: parts, target: target))
            }

            // The date arrives letter by letter, exactly as the names do.
            TypewriterText(
                text: Self.dateLine(for: target),
                spec: .bodyItalic,
                color: Color.white.opacity(0.82),
                letterInterval: 0.045,
                startDelay: dateStartDelay,
                shadow: Color.black.opacity(0.3)
            )
        }
    }

    private func unit(value: Int, label: String) -> some View {
        VStack(spacing: 7) {
            Text("\(value)")
                .brandFont(.countdown)
                .foregroundStyle(Color(hex: 0xEFDDAE))
                .contentTransition(.numericText())
                .monospacedDigit()

            Text(label.uppercased())
                .font(BrandLabel.font(size: 9.5, weight: .medium))
                .tracking(2.2)
                .foregroundStyle(Color(hex: 0xEFDDAE).opacity(0.65))
        }
    }

    private struct Part {
        let value: Int
        let label: String
    }

    private static func parts(from now: Date, to target: Date) -> [Part] {
        let remaining = max(target.timeIntervalSince(now), 0)
        let totalMinutes = Int(remaining / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        return [
            Part(value: days, label: "Days"),
            Part(value: hours, label: "Hours"),
            Part(value: minutes, label: "Minutes")
        ]
    }

    /// The ceremony's date, written out in the couple's own language and calendar.
    static func dateLine(for target: Date) -> String {
        target.formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .year()
        )
    }

    private static func accessibilityLabel(parts: [Part], target: Date) -> String {
        let text = parts.map { "\($0.value) \($0.label.lowercased())" }.joined(separator: ", ")
        return "\(text) until \(dateLine(for: target))"
    }
}
