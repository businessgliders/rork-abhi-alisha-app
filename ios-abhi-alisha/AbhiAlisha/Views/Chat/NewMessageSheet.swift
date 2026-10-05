import SwiftUI

/// Pick one approved family member for a private chat, or several (and a name) for a group.
struct NewMessageSheet: View {
    let onOpen: (UUID) -> Void

    @State private var store = ChatStore.shared
    @State private var search = ""
    @State private var selected: [UUID] = []
    @State private var groupName = ""
    @State private var isWorking = false
    @State private var didFail = false
    @Environment(\.dismiss) private var dismiss

    private var people: [ChatProfile] {
        let all = store.approvedPeople
        guard let query = ChatJSON.clean(search) else { return all }
        return all.filter { $0.name.localizedStandardContains(query) }
    }

    private var isGroup: Bool { selected.count > 1 }

    private var canStart: Bool {
        if selected.isEmpty { return false }
        if isGroup { return ChatJSON.clean(groupName) != nil }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Choose one person for a private chat, or a few to start a group.")
                        .brandFont(.bodyItalic)
                        .foregroundStyle(BrandPalette.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if !selected.isEmpty {
                        selectedRow
                            .padding(.top, 16)
                            .transition(.opacity)
                    }

                    if isGroup {
                        groupNameField
                            .padding(.top, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    searchField
                        .padding(.top, 18)

                    peopleList
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
                .readableWidth()
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(BrandPalette.background.ignoresSafeArea())
            .animation(.calm, value: selected)
            .safeAreaInset(edge: .bottom) {
                startBar
            }
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(BrandPalette.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(BrandLabel.font(size: 14, weight: .medium))
                        .foregroundStyle(BrandPalette.goldDeep)
                }
            }
        }
        .tint(BrandPalette.goldDeep)
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
        .task { await store.refreshAll() }
    }

    // MARK: - Pieces

    private var selectedRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(selected, id: \.self) { id in
                    Button {
                        toggle(id)
                    } label: {
                        HStack(spacing: 6) {
                            Text(store.firstName(of: id))
                                .brandFont(.bodySmall)
                                .foregroundStyle(BrandPalette.ink)
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(BrandPalette.goldDeep)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Capsule().fill(BrandPalette.gold.opacity(0.15)))
                        .overlay(Capsule().stroke(BrandPalette.gold.opacity(0.45), lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(store.name(of: id))")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var groupNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Group name", size: 9.5)
            TextField("e.g. The cousins", text: $groupName)
                .textInputAutocapitalization(.words)
                .brandFont(.bodyText)
                .foregroundStyle(BrandPalette.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BrandPalette.card))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BrandPalette.gold.opacity(0.35), lineWidth: 1))
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(BrandPalette.gold)
            TextField("Search the family", text: $search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .brandFont(.bodyText)
                .foregroundStyle(BrandPalette.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BrandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BrandPalette.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private var peopleList: some View {
        if people.isEmpty {
            ChatEmptyNote(
                text: store.approvedPeople.isEmpty
                    ? "Family members will appear here once Abhi & Alisha welcome them in."
                    : "No one by that name yet."
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(people) { person in
                    let isOn = selected.contains(person.id)
                    Button {
                        toggle(person.id)
                    } label: {
                        HStack(spacing: 12) {
                            ChatAvatar(initials: person.initials, size: 40)
                            Text(person.name)
                                .brandFont(.chatName)
                                .foregroundStyle(BrandPalette.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 21, weight: .light))
                                .foregroundStyle(isOn ? BrandPalette.goldDeep : BrandPalette.hairline)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(isOn ? BrandPalette.gold.opacity(0.1) : BrandPalette.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isOn ? BrandPalette.gold.opacity(0.5) : BrandPalette.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    private var startBar: some View {
        VStack(spacing: 8) {
            if didFail {
                Text("That couldn't be started just now. Please try again.")
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
            }
            GoldActionButton(
                title: isGroup ? "Create group" : "Open chat",
                systemImage: isGroup ? "person.3" : "bubble.left",
                isBusy: isWorking,
                isEnabled: canStart,
                action: start
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .readableWidth()
        .background(BrandPalette.background.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Behaviour

    private func toggle(_ id: UUID) {
        BrandHaptics.tick()
        withAnimation(.calm) {
            if let index = selected.firstIndex(of: id) {
                selected.remove(at: index)
            } else {
                selected.append(id)
            }
        }
    }

    private func start() {
        guard canStart, !isWorking else { return }
        isWorking = true
        didFail = false
        Task {
            let id: UUID?
            if isGroup {
                id = await store.startGroup(title: groupName, with: selected)
            } else if let person = selected.first {
                id = await store.startDirect(with: person)
            } else {
                id = nil
            }
            isWorking = false
            if let id {
                onOpen(id)
            } else {
                didFail = true
            }
        }
    }
}
