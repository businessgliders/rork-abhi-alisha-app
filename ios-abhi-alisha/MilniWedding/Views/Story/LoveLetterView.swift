import SwiftUI

/// The couple's own invitation, set as an actual letter: gold corner brackets, their
/// salutation in Playfair italic, and their words in Cormorant. It stands in for the
/// story itself on the Story tab.
///
/// Every line is optional; anything empty is left out and the layout closes up.
struct LoveLetterView: View {
    let letter: LoveLetter

    var body: some View {
        VStack(spacing: 0) {
            if let dateLine = letter.dateLine?.nonEmpty {
                Text(dateLine.uppercased())
                    .font(BrandLabel.font(size: 10, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(BrandPalette.gold)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 26)
            }

            if let salutation = letter.salutation?.nonEmpty {
                Text(salutation)
                    .brandFont(.letterSalutation)
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 22)
            }

            if !letter.paragraphs.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(letter.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .brandFont(.bodyText)
                            .lineSpacing(BrandFontSpec.bodyText.lineSpacing * 1.35)
                            .foregroundStyle(BrandPalette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let closing = letter.closing?.nonEmpty {
                Text(closing)
                    .brandFont(.bodyItalic)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 30)
            }

            if let signature = letter.signature?.nonEmpty {
                Text(signature)
                    .brandFont(.eventTitleSmall)
                    .foregroundStyle(BrandPalette.goldDeep)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 10)
            }

            GoldRule(width: 46, opacity: 0.8)
                .padding(.top, 30)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(BrandPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrandPalette.hairline, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            CornerBracket(corner: .topLeading)
                .padding(14)
        }
        .overlay(alignment: .bottomTrailing) {
            CornerBracket(corner: .bottomTrailing)
                .padding(14)
        }
    }
}

/// A thin gold bracket that frames the letter at two opposite corners.
private struct CornerBracket: View {
    enum Corner {
        case topLeading
        case bottomTrailing
    }

    let corner: Corner
    private let length: CGFloat = 26

    var body: some View {
        ZStack(alignment: alignment) {
            Rectangle()
                .fill(BrandPalette.gold.opacity(0.55))
                .frame(width: length, height: 1)

            Rectangle()
                .fill(BrandPalette.gold.opacity(0.55))
                .frame(width: 1, height: length)
        }
        .frame(width: length, height: length, alignment: alignment)
        .accessibilityHidden(true)
    }

    private var alignment: Alignment {
        corner == .topLeading ? .topLeading : .bottomTrailing
    }
}

