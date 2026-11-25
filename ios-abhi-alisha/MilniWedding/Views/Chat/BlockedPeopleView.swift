import SwiftUI

/// Everyone this person has blocked, each with a way to undo it.
struct BlockedPeopleView: View {
    @State private var store = ChatStore.shared
    @State private var working: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ChatPageHeader(eyebrow: "Your chat", title: "Blocked people")

                if store.blockedPeople.isEmpty {
                    ChatEmptyNote(text: "You haven't blocked anyone.", icon: .sun)
                } else {
                    Text("You don't see messages from the people below.")
                        .brandFont(.bodyItalic)
                        .foregroundStyle(BrandPalette.body)
                        .padding(.top, 16)

                    LazyVStack(spacing: 10) {
                        ForEach(store.blockedPeople) { person in
                            HStack(spacing: 12) {
                                ChatAvatar(initials: person.initials, size: 42)
                                Text(person.name)
                                    .brandFont(.chatName)
                                    .foregroundStyle(BrandPalette.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                ChatOutlineButton(title: working == person.id ? "…" : "Unblock") {
                                    unblock(person.id)
                                }
                                .disabled(working != nil)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BrandPalette.card))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
                            .transition(.opacity)
                        }
                    }
                    .padding(.top, 18)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, FloatingTabBar.contentReserve + 24)
            .readableWidth()
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .chatPageNavigation()
        .animation(.calm, value: store.blockedPeople.count)
    }

    private func unblock(_ id: UUID) {
        working = id
        Task {
            _ = await store.unblock(id)
            working = nil
        }
    }
}

extension View {
    /// A quiet inline bar on chat pages: no title, gold back arrow, cream behind.
    func chatPageNavigation() -> some View {
        self
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(BrandPalette.background, for: .navigationBar)
    }
}
