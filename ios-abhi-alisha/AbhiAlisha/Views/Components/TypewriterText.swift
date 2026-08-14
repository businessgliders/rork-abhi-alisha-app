import SwiftUI

/// A soft, delayed fade-in used to sequence hero elements after the typed names.
struct CalmFadeIn: ViewModifier {
    var delay: Double
    var duration: Double = 0.75

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible ? 0 : 3)
            .task {
                guard !isVisible else { return }
                guard !reduceMotion else {
                    isVisible = true
                    return
                }
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: duration)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    /// Fades the view up gently after `delay` seconds, once.
    func calmFadeIn(delay: Double, duration: Double = 0.75) -> some View {
        modifier(CalmFadeIn(delay: delay, duration: duration))
    }
}

/// Text that appears one letter at a time, left to right, like handwriting arriving on paper.
///
/// Each letter softly fades up from a slight blur rather than snapping in, and there is
/// deliberately no cursor. It runs once for the lifetime of the view.
struct TypewriterText: View {
    let text: String
    let spec: BrandFontSpec
    var color: Color = BrandPalette.ink
    /// Seconds between letters.
    var letterInterval: Double = 0.10
    /// Seconds to wait before the first letter.
    var startDelay: Double = 0
    var shadow: Color = .clear
    /// Called once the last letter has been revealed.
    var onFinished: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var revealed = 0
    @State private var didRun = false

    private var characters: [(index: Int, value: Character)] {
        Array(text.enumerated()).map { (index: $0.offset, value: $0.element) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(characters, id: \.index) { character in
                let isVisible = character.index < revealed

                Text(String(character.value))
                    .brandFont(spec)
                    .foregroundStyle(color)
                    .shadow(color: shadow, radius: 12, y: 4)
                    .opacity(isVisible ? 1 : 0)
                    .blur(radius: isVisible ? 0 : 3.5)
                    .offset(y: isVisible ? 0 : 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .task {
            guard !didRun else { return }
            didRun = true
            await reveal()
        }
    }

    private func reveal() async {
        guard !reduceMotion else {
            revealed = text.count
            onFinished?()
            return
        }

        if startDelay > 0 {
            try? await Task.sleep(for: .seconds(startDelay))
        }

        for index in 0..<text.count {
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.55)) {
                revealed = index + 1
            }
            try? await Task.sleep(for: .seconds(letterInterval))
        }
        onFinished?()
    }
}
