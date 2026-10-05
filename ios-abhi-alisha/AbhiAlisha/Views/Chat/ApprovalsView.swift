import SwiftUI

/// For Abhi & Alisha: everyone waiting to join, with Approve and Decline.
struct ApprovalsView: View {
    @State private var store = ChatStore.shared
    @State private var working: UUID?
    @State private var decliningPerson: ChatProfile?
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ChatPageHeader(eyebrow: "For Abhi & Alisha", title: "Approvals")

                if store.pendingPeople.isEmpty {
                    ChatEmptyNote(text: "No one is waiting to join right now.", icon: .sun)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(store.pendingPeople) { person in
                            card(for: person)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }
                    .padding(.top, 22)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, FloatingTabBar.contentReserve + 24)
            .readableWidth()
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refreshAdmin() }
        .background(BrandPalette.background.ignoresSafeArea())
        .chatPageNavigation()
        .animation(.calm, value: store.pendingPeople.map(\.id))
        .overlay(alignment: .top) {
            if let toast {
                ChatToast(text: toast)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.calm, value: toast)
        .confirmationDialog(
            "Decline \(decliningPerson?.name ?? "this person")?",
            isPresented: Binding(get: { decliningPerson != nil }, set: { if !$0 { decliningPerson = nil } }),
            titleVisibility: .visible
        ) {
            Button("Decline", role: .destructive) {
                if let person = decliningPerson { decide(person, approved: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to use the family chat.")
        }
        .task { await store.refreshAdmin() }
    }

    private func card(for person: ChatProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ChatAvatar(initials: person.initials, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .brandFont(.chatName)
                        .foregroundStyle(BrandPalette.ink)
                    if let created = person.createdAt {
                        Text("Asked to join " + ChatTime.relative(created))
                            .font(BrandLabel.font(size: 11, weight: .medium))
                            .foregroundStyle(BrandPalette.body)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                GoldActionButton(
                    title: "Approve",
                    systemImage: "checkmark",
                    isBusy: working == person.id,
                    isEnabled: working == nil
                ) {
                    decide(person, approved: true)
                }

                ChatOutlineButton(title: "Decline", isDestructive: true) {
                    decliningPerson = person
                }
                .disabled(working != nil)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BrandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
    }

    private func decide(_ person: ChatProfile, approved: Bool) {
        working = person.id
        Task {
            let done = await store.setStatus(of: person, approved: approved)
            working = nil
            if done {
                BrandHaptics.tick()
                show(approved ? "\(person.name) is welcome in." : "Declined.")
            } else {
                show("That couldn't be saved just now.")
            }
        }
    }

    private func show(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if toast == text { toast = nil }
        }
    }
}
