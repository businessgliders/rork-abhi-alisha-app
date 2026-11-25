import SwiftUI

/// A guest reports a Wedding Week photo. A reason is picked, an optional note is
/// added, and the photo disappears from this phone the moment the report is sent.
struct PhotoReportSheet: View {
    let photo: WeddingPhoto
    /// Called when the report went through and the viewer should close.
    var onRemoved: (() -> Void)?

    @State private var pick: Int = 0
    @State private var note = ""
    @State private var isSending = false
    @State private var outcome: PhotoReportStore.SubmitOutcome?
    @State private var failureLine: String?
    @Environment(\.dismiss) private var dismiss

    private let picks = ["Inappropriate", "Not from this wedding", "Other"]
    private static let noteLimit = 300

    private var composedReason: String {
        let base = picks[pick]
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (pick == 2, clean.isEmpty) {
        case (true, true): return base
        case (true, false): return "\(base) — \(clean)"
        case (false, false): return "\(base) — \(clean)"
        case (false, true): return base
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if outcome == .sent || outcome == .alreadyReported {
                    sentState
                } else {
                    pickingState
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
            .readableWidth(480)
        }
        .scrollIndicators(.hidden)
        .background(BrandPalette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }

    private var pickingState: some View {
        VStack(spacing: 22) {
            Image(systemName: "flag")
                .symbolVariant(.none)
                .font(.system(size: 24, weight: .ultraLight))
                .foregroundStyle(BrandPalette.goldDeep)
                .frame(width: 72, height: 72)
                .background(Circle().fill(BrandPalette.card))
                .overlay(Circle().stroke(BrandPalette.gold.opacity(0.55), lineWidth: 1))
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Report photo")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(BrandPalette.ink)
                    .multilineTextAlignment(.center)
                Text("The couple reviews every report. Only they see who reported it.")
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.body)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                ForEach(picks.indices, id: \.self) { index in
                    chip(index)
                }
            }

            TextField(
                "Add a note (optional)",
                text: $note,
                prompt: Text("Add a note (optional)")
            )
            .brandFont(.bodyText)
            .foregroundStyle(BrandPalette.ink)
            .textInputAutocapitalization(.sentences)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BrandPalette.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BrandPalette.hairline, lineWidth: 1)
            )
            .disabled(isSending)
            .onChange(of: note) {
                if note.count > Self.noteLimit { note = String(note.prefix(Self.noteLimit)) }
            }

            if let failureLine {
                Text(failureLine)
                    .brandFont(.bodySmall)
                    .foregroundStyle(BrandPalette.overdue)
                    .multilineTextAlignment(.center)
            }

            GoldActionButton(title: "Report", systemImage: "flag", isBusy: isSending) {
                send()
            }
            ChatOutlineButton(title: "Cancel", systemImage: "xmark") {
                dismiss()
            }
        }
    }

    private func chip(_ index: Int) -> some View {
        let isSelected = pick == index
        return Button {
            BrandHaptics.tick()
            withAnimation(.softFade) { pick = index }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolVariant(.none)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(isSelected ? BrandPalette.goldDeep : BrandPalette.body)
                Text(picks[index])
                    .brandFont(.bodyText)
                    .foregroundStyle(BrandPalette.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BrandPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? BrandPalette.gold.opacity(0.7) : BrandPalette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(isSending)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var sentState: some View {
        VStack(spacing: 18) {
            Image(systemName: outcome == .alreadyReported ? "envelope" : "checkmark.circle")
                .symbolVariant(.none)
                .font(.system(size: 24, weight: .ultraLight))
                .foregroundStyle(BrandPalette.goldDeep)
                .frame(width: 72, height: 72)
                .background(Circle().fill(BrandPalette.card))
                .overlay(Circle().stroke(BrandPalette.gold.opacity(0.55), lineWidth: 1))
                .accessibilityHidden(true)

            Text(
                outcome == .alreadyReported
                    ? "You've already reported this photo"
                    : "Thanks — the couple will review this."
            )
            .font(.system(.title3, design: .serif, weight: .semibold))
            .foregroundStyle(BrandPalette.ink)
            .multilineTextAlignment(.center)

            Text("The photo is hidden on this phone in the meantime.")
                .brandFont(.bodyText)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)

            GoldActionButton(title: "Done", systemImage: "checkmark") {
                let wasRemoved = outcome == .sent || outcome == .alreadyReported
                dismiss()
                if wasRemoved, let onRemoved {
                    // Let the sheet leave first, then close the viewer behind it.
                    Task {
                        try? await Task.sleep(for: .seconds(0.45))
                        onRemoved()
                    }
                }
            }
        }
    }

    private func send() {
        isSending = true
        failureLine = nil
        Task {
            let outcome = await PhotoReportStore.shared.submit(photo, reason: composedReason)
            isSending = false
            switch outcome {
            case .sent:
                withAnimation(.softFade) { self.outcome = .sent }
            case .alreadyReported:
                withAnimation(.softFade) { self.outcome = .alreadyReported }
            case .failed:
                failureLine = "The report couldn't be sent. Please check your connection and try again."
            }
        }
    }
}
