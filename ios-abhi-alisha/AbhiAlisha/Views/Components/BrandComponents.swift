import SwiftUI
import UIKit

/// A short, centred gold rule used under titles and inside cards.
struct GoldRule: View {
    var width: CGFloat = 56
    var alignment: Alignment = .center
    var opacity: Double = 1

    var body: some View {
        Rectangle()
            .fill(BrandPalette.gold.opacity(opacity))
            .frame(width: width, height: 1)
            .frame(maxWidth: .infinity, alignment: alignment)
            .accessibilityHidden(true)
    }
}

/// Small letterspaced caps eyebrow, e.g. "THE CELEBRATIONS".
struct Eyebrow: View {
    let text: String
    var color: Color = BrandPalette.gold
    var size: CGFloat = 11.5

    var body: some View {
        Text(text.uppercased())
            .font(BrandLabel.font(size: size, weight: .semibold))
            .tracking(2.6)
            .foregroundStyle(color)
    }
}

enum PillTone {
    case neutral
    case gold
    case sikh
    case hindu

    var dotColor: Color? {
        switch self {
        case .neutral, .gold: return nil
        case .sikh: return BrandPalette.sikhAmber
        case .hindu: return BrandPalette.hinduGarnet
        }
    }

    var textColor: Color {
        switch self {
        case .neutral: return BrandPalette.body
        case .gold: return BrandPalette.goldDeep
        case .sikh, .hindu: return BrandPalette.ink.opacity(0.82)
        }
    }

    var strokeColor: Color {
        switch self {
        case .neutral: return BrandPalette.hairline
        case .gold: return BrandPalette.gold.opacity(0.45)
        case .sikh: return BrandPalette.sikhAmber.opacity(0.35)
        case .hindu: return BrandPalette.hinduGarnet.opacity(0.32)
        }
    }
}

/// Matte pill badge. Never glass — content stays clean.
struct BrandPill: View {
    let text: String
    var tone: PillTone = .neutral

    var body: some View {
        HStack(spacing: 6) {
            if let dot = tone.dotColor {
                Circle()
                    .fill(dot)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(BrandLabel.font(size: 11.5, weight: .medium))
                .tracking(0.9)
                .foregroundStyle(tone.textColor)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(BrandPalette.background.opacity(0.55))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tone.strokeColor, lineWidth: 0.75)
        )
    }
}

/// Cards keep a matte white surface with a single hairline — deliberately not glass.
struct MatteCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(BrandPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BrandPalette.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 10)
    }
}

/// Light, restrained haptics — never playful.
enum BrandHaptics {
    static func tick() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.55)
    }

    static func soft() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred(intensity: 0.4)
    }
}

extension Animation {
    /// The app's signature unhurried spring.
    static let calm = Animation.spring(response: 0.75, dampingFraction: 0.86)
    static let calmSlow = Animation.spring(response: 1.05, dampingFraction: 0.9)
    static let softFade = Animation.easeInOut(duration: 0.55)
}

/// Keeps reading widths comfortable on iPad without stretching the editorial layout.
struct ReadableWidth: ViewModifier {
    var maxWidth: CGFloat = 620

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func readableWidth(_ maxWidth: CGFloat = 620) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}
