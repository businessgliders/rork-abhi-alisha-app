import SwiftUI

/// "Our Family" — the two families in a two-column grid, each with their portrait and
/// how they're related to the couple. Portraits are cached, so the roster opens offline too.
///
/// This is a section, not a screen: the Story tab shows it beside the timeline.
struct FamilyRoster: View {
    let members: [FamilyMember]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if members.isEmpty {
                VStack(spacing: 18) {
                    IconWatermark(key: .paisley, size: 92, opacity: 0.3)
                    Text("The families will be introduced here soon.")
                        .brandFont(.bodyItalic)
                        .foregroundStyle(BrandPalette.body)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 70)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(members) { member in
                        FamilyTile(member: member)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One person: a round portrait above their name and their place in the family.
private struct FamilyTile: View {
    let member: FamilyMember

    var body: some View {
        VStack(spacing: 12) {
            portrait

            VStack(spacing: 3) {
                if let name = member.displayName {
                    Text(name)
                        .brandFont(.eventTitleSmall)
                        .foregroundStyle(BrandPalette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let relationship = member.relationship {
                    Text(relationship)
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(BrandPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BrandPalette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// The portrait sits in an overlay on a sized circle so `.fill` never widens the tile.
    private var portrait: some View {
        BrandPalette.hairline
            .frame(width: 78, height: 78)
            .overlay {
                if member.photoURL != nil {
                    RemoteImage(url: member.photoURL, contentMode: .fill) {
                        Text(member.monogram)
                            .brandFont(.eventTitleSmall)
                            .foregroundStyle(BrandPalette.goldDeep)
                    }
                    .allowsHitTesting(false)
                } else {
                    Text(member.monogram)
                        .brandFont(.eventTitleSmall)
                        .foregroundStyle(BrandPalette.goldDeep)
                }
            }
            .clipShape(.circle)
            .overlay(
                Circle().stroke(BrandPalette.gold.opacity(0.35), lineWidth: 0.75)
            )
    }
}
