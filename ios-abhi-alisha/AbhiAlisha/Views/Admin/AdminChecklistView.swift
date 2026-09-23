import SwiftUI

/// The wedding-day checklist: a gold completion ring, tasks grouped by category, tap to
/// tick, swipe to delete. Everything works offline and syncs when the signal returns.
struct AdminChecklistView: View {
    @Environment(ChecklistStore.self) private var checklist

    @State private var composing: ComposeTarget?

    private enum ComposeTarget: Identifiable {
        case new
        case edit(ChecklistItem)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let item): return item.id
            }
        }

        var item: ChecklistItem? {
            if case .edit(let item) = self { return item }
            return nil
        }
    }

    var body: some View {
        List {
            Group {
                AdminHeader(eyebrow: "The big day", title: "Checklist")

                CompletionCard(
                    done: checklist.completedCount,
                    total: checklist.totalCount,
                    progress: checklist.progress,
                    isWaitingToSync: checklist.hasPendingChanges,
                    isShowingSaved: checklist.loadFailed
                )
                .padding(.top, 14)

                addButton
                    .padding(.top, 4)

                if checklist.sections.isEmpty {
                    AdminNote(
                        text: checklist.loadFailed && !checklist.hasLoadedFromServer
                            ? "Your checklist will appear here once you're connected."
                            : "Nothing on the list yet. Add the first task above.",
                        symbol: "checklist"
                    )
                }
            }
            .plainRow()

            ForEach(checklist.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        ChecklistRow(item: item) {
                            BrandHaptics.soft()
                            withAnimation(.calm) { checklist.toggle(item) }
                        }
                        .plainRow(vertical: 0)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                BrandHaptics.tick()
                                withAnimation(.calm) { checklist.delete(item) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                composing = .edit(item)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(BrandPalette.goldDeep)
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { composing = .edit(item) }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                withAnimation(.calm) { checklist.delete(item) }
                            }
                        }
                    }
                } header: {
                    SectionHeader(section: section)
                }
                .listSectionSeparator(.hidden)
            }

            AdminLockFooter()
                .padding(.top, 20)
                .padding(.bottom, FloatingTabBar.contentReserve)
                .plainRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .environment(\.defaultMinListRowHeight, 1)
        .sheet(item: $composing) { target in
            ChecklistComposeSheet(item: target.item, categories: checklist.categories) { draft in
                withAnimation(.calm) {
                    if let item = target.item {
                        checklist.edit(item, with: draft)
                    } else {
                        checklist.add(draft)
                    }
                }
            }
        }
        .task {
            checklist.start()
            await checklist.refresh()
        }
        .refreshable {
            await checklist.refresh()
        }
    }

    private var addButton: some View {
        Button {
            BrandHaptics.soft()
            composing = .new
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Add a task")
                    .font(BrandLabel.font(size: 12, weight: .semibold))
                    .tracking(1.5)
                    .textCase(.uppercase)
            }
            .foregroundStyle(BrandPalette.goldDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BrandPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BrandPalette.gold.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
    }
}

private extension View {
    /// A list row stripped back to the page: no background, no separators.
    func plainRow(vertical: CGFloat = 6) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: vertical, leading: 22, bottom: vertical, trailing: 22))
    }
}

// MARK: - Completion

private struct CompletionCard: View {
    let done: Int
    let total: Int
    let progress: Double
    let isWaitingToSync: Bool
    let isShowingSaved: Bool

    var body: some View {
        MatteCard(cornerRadius: 24) {
            HStack(spacing: 22) {
                CompletionRing(progress: progress)
                    .frame(width: 96, height: 96)
                    .overlay {
                        Text("\(Int((progress * 100).rounded()))%")
                            .brandFont(.eventTitleSmall)
                            .foregroundStyle(BrandPalette.ink)
                            .contentTransition(.numericText())
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Progress", size: 9.5)

                    Text(total == 0 ? "A fresh list" : "\(done) of \(total) done")
                        .brandFont(.eventTitleSmall)
                        .foregroundStyle(BrandPalette.ink)
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subline)
                        .brandFont(.bodySmall)
                        .foregroundStyle(BrandPalette.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if isWaitingToSync {
                        StatusPill(symbol: "arrow.triangle.2.circlepath", text: "Waiting to sync")
                            .padding(.top, 4)
                    } else if isShowingSaved {
                        StatusPill(symbol: "icloud.slash", text: "Showing saved list")
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .animation(.calm, value: done)
        .animation(.calm, value: isWaitingToSync)
    }

    private var subline: String {
        if total == 0 { return "Add your first task below." }
        if done == total { return "Everything's ready. Enjoy every moment." }
        let left = total - done
        return left == 1 ? "Just one still to go." : "\(left) still to go."
    }
}

private struct CompletionRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(BrandPalette.hairline, lineWidth: 6)

            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(
                        colors: [BrandPalette.goldPale, BrandPalette.gold, BrandPalette.goldDeep, BrandPalette.gold],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: BrandPalette.gold.opacity(0.35), radius: 6)
                .opacity(progress > 0 ? 1 : 0)
        }
        .animation(.calmSlow, value: progress)
        .accessibilityElement()
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent complete")
    }
}

private struct StatusPill: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(BrandLabel.font(size: 10, weight: .semibold))
                .tracking(0.8)
        }
        .foregroundStyle(BrandPalette.goldDeep)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(Capsule().stroke(BrandPalette.gold.opacity(0.45), lineWidth: 0.75))
    }
}

// MARK: - Rows

private struct SectionHeader: View {
    let section: ChecklistSection

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow(text: section.name)
            Spacer(minLength: 8)
            Text("\(section.doneCount)/\(section.items.count)")
                .font(BrandLabel.font(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(BrandPalette.body.opacity(0.7))
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandPalette.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BrandPalette.hairline).frame(height: 1).padding(.horizontal, 22)
        }
        .listRowInsets(EdgeInsets())
    }
}

private struct ChecklistRow: View {
    let item: ChecklistItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 14) {
                checkmark
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    if let title = item.title {
                        Text(title)
                            .brandFont(.bodyText)
                            .foregroundStyle(item.isDone ? BrandPalette.body.opacity(0.65) : BrandPalette.ink)
                            .strikethrough(item.isDone, color: BrandPalette.gold.opacity(0.7))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let notes = item.notes {
                        Text(notes)
                            .brandFont(.bodySmall)
                            .foregroundStyle(BrandPalette.body.opacity(item.isDone ? 0.6 : 1))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }

                    if let due = item.dueDate {
                        dueLine(due)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BrandPalette.hairline.opacity(0.7)).frame(height: 1)
        }
        .accessibilityAddTraits(item.isDone ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(item.isDone ? "Marks this task as not done" : "Marks this task as done")
    }

    private var checkmark: some View {
        ZStack {
            Circle()
                .stroke(BrandPalette.gold.opacity(item.isDone ? 0 : 0.6), lineWidth: 1.2)

            if item.isDone {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .transition(.scale.combined(with: .opacity))

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFFFBF1))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 26, height: 26)
    }

    private func dueLine(_ date: Date) -> some View {
        let isOverdue = item.isOverdue()
        return HStack(spacing: 5) {
            Image(systemName: "calendar")
                .font(.system(size: 9.5, weight: .medium))
            Text(isOverdue ? "Overdue · \(ChecklistDates.display(date))" : "Due \(ChecklistDates.display(date))")
                .font(BrandLabel.font(size: 10.5, weight: .semibold))
                .tracking(0.5)
        }
        .foregroundStyle(isOverdue ? BrandPalette.overdue : BrandPalette.body.opacity(0.8))
    }
}

// MARK: - Compose

/// Add or edit one task: title, notes, due date and category.
private struct ChecklistComposeSheet: View {
    let item: ChecklistItem?
    let categories: [String]
    let onSave: (ChecklistDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var category: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date

    init(item: ChecklistItem?, categories: [String], onSave: @escaping (ChecklistDraft) -> Void) {
        self.item = item
        self.categories = categories
        self.onSave = onSave
        _title = State(initialValue: item?.title ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _category = State(initialValue: item?.category ?? "")
        _hasDueDate = State(initialValue: item?.dueDate != nil)
        _dueDate = State(initialValue: item?.dueDate ?? Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Checklist")
                    Text(item == nil ? "New Task" : "Edit Task")
                        .brandFont(.eventTitle)
                        .foregroundStyle(BrandPalette.ink)
                    GoldRule(width: 44, alignment: .leading)
                        .padding(.top, 4)
                }
                .padding(.top, 28)

                AdminField(label: "Title") {
                    TextField("Confirm the florist's arrival", text: $title)
                        .textInputAutocapitalization(.sentences)
                }

                AdminField(label: "Notes") {
                    TextField("Anything worth remembering", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                categoryField

                dueField

                GoldActionButton(
                    title: item == nil ? "Add task" : "Save changes",
                    isEnabled: title.nonEmpty != nil
                ) {
                    onSave(
                        ChecklistDraft(
                            title: title.trimmed,
                            notes: notes.nonEmpty,
                            category: category.nonEmpty,
                            dueDate: hasDueDate ? dueDate : nil
                        )
                    )
                    dismiss()
                }
                .padding(.top, 6)

                Button("Cancel") { dismiss() }
                    .font(BrandLabel.font(size: 12, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(BrandPalette.body)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
            .readableWidth(560)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(BrandPalette.background.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .animation(.calm, value: hasDueDate)
    }

    private var categoryField: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdminField(label: "Category") {
                TextField("Ceremony, Décor, Family…", text: $category)
                    .textInputAutocapitalization(.words)
            }

            if !categories.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(categories, id: \.self) { name in
                        let isChosen = name.caseInsensitiveCompare(category.trimmed) == .orderedSame
                        Button {
                            BrandHaptics.tick()
                            category = name
                        } label: {
                            Text(name)
                                .font(BrandLabel.font(size: 11.5, weight: .medium))
                                .tracking(0.6)
                                .foregroundStyle(isChosen ? Color(hex: 0xFFFBF1) : BrandPalette.goldDeep)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(isChosen ? BrandPalette.goldDeep : BrandPalette.card)
                                )
                                .overlay(Capsule().stroke(BrandPalette.gold.opacity(0.45), lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var dueField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $hasDueDate) {
                Eyebrow(text: "Due date", size: 9.5)
            }
            .tint(BrandPalette.gold)

            if hasDueDate {
                DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(BrandPalette.goldDeep)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(BrandPalette.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(BrandPalette.gold.opacity(0.3), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
