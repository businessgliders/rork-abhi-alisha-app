import SwiftUI

/// Every question the couple has answered, on its own screen: searchable, grouped and
/// collapsed, with the first group open on arrival.
struct QuestionsView: View {
    @Environment(ContentStore.self) private var content
    @Environment(\.dismiss) private var dismiss

    @State private var expandedFaqID: String?
    @State private var expandedSections: Set<String> = []
    @State private var didPrimeSections = false
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    QuestionSearchField(text: $query)
                        .padding(.top, 24)

                    if isSearching {
                        Text(resultCount == 1 ? "1 answer" : "\(resultCount) answers")
                            .font(BrandLabel.font(size: 10, weight: .medium))
                            .tracking(1.8)
                            .textCase(.uppercase)
                            .foregroundStyle(BrandPalette.body.opacity(0.75))
                            .padding(.top, 14)
                    }

                    let groups = matchingGroups
                    if groups.isEmpty {
                        emptyQuestions
                    } else {
                        VStack(spacing: 10) {
                            ForEach(groups, id: \.section.id) { group in
                                QuestionGroup(
                                    section: group.section,
                                    items: group.items,
                                    isExpanded: isExpanded(group.section),
                                    expandedFaqID: $expandedFaqID,
                                    onToggle: { toggle(group.section) }
                                )
                            }
                        }
                        .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .readableWidth()
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(BrandPalette.background.ignoresSafeArea())
            .animation(.softFade, value: query)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(BrandLabel.font(size: 13, weight: .medium))
                        .foregroundStyle(BrandPalette.goldDeep)
                }
            }
        }
        .task {
            await content.refreshIfNeeded()
        }
        .onChange(of: content.faqs.count) { _, _ in primeSectionsIfNeeded() }
        .onAppear(perform: primeSectionsIfNeeded)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Everything you asked")

            Text("Questions")
                .brandFont(.screenTitle)
                .foregroundStyle(BrandPalette.ink)

            GoldRule(width: 58, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyQuestions: some View {
        VStack(spacing: 14) {
            IconWatermark(key: .sparkle, size: 70, opacity: 0.3)

            Text(
                isSearching
                    ? "Nothing matches “\(query)”. Try a different word."
                    : "The couple's answers will appear here soon."
            )
            .brandFont(.bodyItalic)
            .foregroundStyle(BrandPalette.body)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 46)
    }

    // MARK: - State

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var resultCount: Int {
        matchingGroups.reduce(0) { $0 + $1.items.count }
    }

    private var matchingGroups: [(section: FaqSection, items: [Faq])] {
        content.allSectionsInReadingOrder().compactMap { section in
            let items = matching(content.faqs(in: section))
            return items.isEmpty ? nil : (section, items)
        }
    }

    private func matching(_ items: [Faq]) -> [Faq] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return items }
        return items.filter { faq in
            let haystack = [faq.question, faq.answer].compactMap { $0 }.joined(separator: " ")
            return haystack.localizedStandardContains(needle)
        }
    }

    /// While searching every surviving group is open, so no match ever hides.
    private func isExpanded(_ section: FaqSection) -> Bool {
        isSearching || expandedSections.contains(section.id)
    }

    private func toggle(_ section: FaqSection) {
        BrandHaptics.tick()
        withAnimation(.calm) {
            if expandedSections.contains(section.id) {
                expandedSections.remove(section.id)
            } else {
                expandedSections.insert(section.id)
            }
        }
    }

    private func primeSectionsIfNeeded() {
        guard !didPrimeSections,
              let first = content.allSectionsInReadingOrder().first else { return }
        didPrimeSections = true
        expandedSections = [first.id]
    }
}
