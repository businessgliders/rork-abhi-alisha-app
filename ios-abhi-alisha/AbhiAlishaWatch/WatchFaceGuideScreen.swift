import SwiftUI

/// One way to dress an Apple face in the wedding's black and gold: which face to
/// pick, the mood it gives, and the taps that get there. Steps follow watchOS 26's
/// editing flow — touch and hold, Edit, Digital Crown — and ship inside the app,
/// so the guide reads the same with no connection at all.
struct WatchFaceGuideScreen: View {
    @State private var didTick = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header

                ForEach(Self.recipes) { recipe in
                    recipeCard(recipe)
                }

                crestDivider

                tip(
                    title: "SHARE THE LOOK",
                    body: "Touch and hold your finished face and tap Share. Send it to the party — everyone matches."
                )
                tip(
                    title: "IN THE SMART STACK",
                    body: "Follow a celebration on your iPhone and its live card rises on the watch at the right moment."
                )
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { didTick = true }
        .sensoryFeedback(.selection, trigger: didTick)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 4) {
            Image("crest")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18)
                .foregroundStyle(WatchTheme.gold.opacity(0.7))
                .accessibilityHidden(true)

            Text("MAKE YOUR WEDDING FACE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(WatchTheme.gold.opacity(0.75))

            Text("Apple keeps the watch faces to itself — so dress one of theirs in black and gold.")
                .font(.watchCormorant(13))
                .foregroundStyle(WatchTheme.creamDim)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 6)
        }
        .padding(.bottom, 2)
    }

    private func recipeCard(_ recipe: FaceRecipe) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(recipe.name)
                    .font(.watchPlayfair(15, weight: .semibold))
                    .foregroundStyle(WatchTheme.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 6)

                if let tag = recipe.tag {
                    Text(tag)
                        .font(.system(size: 7.5, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(WatchTheme.gold.opacity(0.85))
                }
            }

            Text(recipe.mood)
                .font(.watchCormorant(12.5))
                .foregroundStyle(WatchTheme.creamDim)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 6) {
                        Text(verbatim: "\(index + 1)")
                            .font(.watchCormorant(12, weight: .semibold))
                            .foregroundStyle(WatchTheme.gold)
                            .frame(width: 9)

                        Text(step)
                            .font(.watchCormorant(12))
                            .foregroundStyle(WatchTheme.cream.opacity(0.88))
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WatchTheme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recipe.name). \(recipe.mood) \(recipe.steps.enumerated().map { "Step \($0.offset + 1): \($0.element)" }.joined(separator: " "))")
    }

    private func tip(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(WatchTheme.gold.opacity(0.75))

            Text(body)
                .font(.watchCormorant(12.5))
                .foregroundStyle(WatchTheme.cream.opacity(0.88))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    private var crestDivider: some View {
        Image("crest")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 12)
            .foregroundStyle(WatchTheme.gold.opacity(0.4))
            .padding(.top, 2)
            .accessibilityHidden(true)
    }

    // MARK: - The recipes

    private struct FaceRecipe: Identifiable {
        let name: String
        let tag: String?
        let mood: String
        let steps: [String]

        var id: String { name }
    }

    private static let recipes: [FaceRecipe] = [
        FaceRecipe(
            name: "Infograph",
            tag: "SIGNATURE",
            mood: "The richest look — the countdown crest front and centre, gold everywhere.",
            steps: [
                "Touch and hold your face, swipe all the way left, and tap the plus. Pick Infograph.",
                "Touch and hold again, tap Edit, and make the dial black with gold as the accent.",
                "Swipe to the last page, tap the centre slot, and turn the Digital Crown to Abhi & Alisha — the days crest takes the middle.",
                "Add the days gauge to a corner, and switch Tint Complications on when the page offers it.",
                "Press the Digital Crown to save."
            ]
        ),
        FaceRecipe(
            name: "Infograph Modular",
            tag: nil,
            mood: "One calm card: the celebration, its time, its place.",
            steps: [
                "Touch and hold, swipe to the plus, and pick Infograph Modular.",
                "In Edit: black dial, gold accent, and Tint Complications on if it's offered.",
                "On the complications page, tap the big centre slot and choose Abhi & Alisha — it reads Happening now the moment it's true.",
                "The small circles can take the days crest too."
            ]
        ),
        FaceRecipe(
            name: "X-Large",
            tag: nil,
            mood: "Just the count — giant gold numerals, nothing else.",
            steps: [
                "Touch and hold, swipe to the plus, and pick X-Large.",
                "In Edit, set the numerals to gold.",
                "Give its one slot to Abhi & Alisha — far from Cancún it counts the days in giant type; close in, it names the next celebration."
            ]
        )
    ]
}
