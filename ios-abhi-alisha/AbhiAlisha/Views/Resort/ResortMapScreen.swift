import SwiftUI

/// The resort map at full size, with every celebration pinned and listed beneath it.
/// Entirely offline: the artwork is bundled and the pins come from the saved schedule.
struct ResortMapScreen: View {
    /// Opened from a celebration: that pin is selected and centred on arrival.
    var focusEventID: String?
    /// When the map was opened from a celebration's own detail, tapping through to that
    /// same celebration simply returns to it rather than stacking another sheet.
    var returnsToEventID: String?

    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selection: [ResortMapPin] = []
    @State private var focus: ResortMapFocus?
    @State private var detailEvent: ScheduleEvent?
    @State private var didPrime = false

    private var pins: [ResortMapPin] { ResortMapPlot.pins(from: store.events) }

    private var currentEventID: String? {
        guard let index = store.currentIndex(), store.events.indices.contains(index) else { return nil }
        return store.events[index].id
    }

    var body: some View {
        GeometryReader { proxy in
            let mapHeight = max(236, proxy.size.height * 0.38)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 8)

                if pins.isEmpty {
                    emptyState
                } else {
                    mapPlate(height: mapHeight)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)

                    hint
                        .padding(.top, 10)

                    if let selected = selection.nonEmpty {
                        Callout(pins: selected, onOpen: open, onClose: clearSelection)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    legend
                        .padding(.top, 22)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .readableWidth(680)
        }
        .background(BrandPalette.background.ignoresSafeArea())
        .animation(.calm, value: selection.map(\.id))
        .sheet(item: $detailEvent) { event in
            EventDetailSheet(event: event)
        }
        .onAppear(perform: primeFocus)
        .onChange(of: pins) { _, _ in primeFocus() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "AVA Resort Cancún")

                Text("Resort Map")
                    .brandFont(.eventTitle)
                    .foregroundStyle(BrandPalette.ink)

                GoldRule(width: 44, alignment: .leading)
                    .padding(.top, 4)
            }

            Spacer(minLength: 12)

            Button {
                BrandHaptics.tick()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(BrandPalette.goldDeep)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(BrandPalette.gold.opacity(0.5), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close map")
        }
    }

    // MARK: - Map

    private func mapPlate(height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return ResortMapCanvas(
            pins: pins,
            currentPinID: currentEventID,
            selectedPinID: selection.first?.id,
            focus: focus,
            onSelect: select
        )
        .frame(height: height)
        .clipShape(shape)
        .overlay(shape.stroke(BrandPalette.gold.opacity(0.3), lineWidth: 0.75))
        .shadow(color: Color.black.opacity(0.07), radius: 18, y: 10)
    }

    private var hint: some View {
        Text("Pinch to zoom  ·  Drag to explore  ·  Double tap to reset")
            .font(BrandLabel.font(size: 9.5, weight: .medium))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(BrandPalette.body.opacity(0.65))
            .frame(maxWidth: .infinity)
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "The Venues")
                .padding(.horizontal, 22)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(pins) { pin in
                        LegendRow(
                            pin: pin,
                            isCurrent: pin.id == currentEventID,
                            isSelected: selection.contains { $0.id == pin.id },
                            action: { reveal(pin) }
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            IconWatermark(key: .arch, size: 70, opacity: 0.32)

            Text("The venues will be marked on the map as soon as the couple place them.")
                .brandFont(.bodyItalic)
                .foregroundStyle(BrandPalette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    // MARK: - Actions

    private func select(_ cluster: [ResortMapPin]) {
        selection = cluster
    }

    private func clearSelection() {
        BrandHaptics.tick()
        selection = []
    }

    /// A legend row lights its pin and brings the map to it.
    private func reveal(_ pin: ResortMapPin) {
        BrandHaptics.tick()
        selection = [pin]
        focus = ResortMapFocus(pinID: pin.id, zoom: 3.8, token: UUID())
    }

    private func open(_ event: ScheduleEvent) {
        BrandHaptics.soft()
        guard event.id != returnsToEventID else {
            dismiss()
            return
        }
        detailEvent = event
    }

    private func primeFocus() {
        guard !didPrime,
              let focusEventID,
              let pin = pins.first(where: { $0.id == focusEventID }) else { return }
        didPrime = true
        selection = [pin]
        focus = ResortMapFocus(pinID: pin.id, zoom: 3.8)
    }
}

// MARK: - Callout

/// The small card a pin raises: what happens there, when, and the way through to everything
/// else about it. A gathered pin shows each celebration it stands for.
private struct Callout: View {
    let pins: [ResortMapPin]
    let onOpen: (ScheduleEvent) -> Void
    let onClose: () -> Void

    var body: some View {
        MatteCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(pins.enumerated()), id: \.element.id) { index, pin in
                    if index > 0 {
                        Rectangle()
                            .fill(BrandPalette.hairline)
                            .frame(height: 1)
                    }

                    Button {
                        onOpen(pin.event)
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            LegendBadge(label: pin.label, isCurrent: false, isSelected: true)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(pin.title)
                                    .brandFont(.eventTitleSmall)
                                    .foregroundStyle(BrandPalette.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let timing = pin.timing {
                                    Text(timing)
                                        .brandFont(.bodySmall)
                                        .foregroundStyle(BrandPalette.body)
                                }

                                if let location = pin.locationName {
                                    Text(location)
                                        .brandFont(.bodyItalic)
                                        .foregroundStyle(BrandPalette.goldDeep)
                                }
                            }

                            Spacer(minLength: 6)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(BrandPalette.gold)
                                .padding(.top, 6)
                        }
                        .padding(.vertical, 15)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityHint("Opens this celebration")
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(BrandPalette.body.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .padding(.top, 4)
            .accessibilityLabel("Close")
        }
    }
}

// MARK: - Legend pieces

/// One venue in the legend: its number, what happens there, and where it is.
private struct LegendRow: View {
    let pin: ResortMapPin
    let isCurrent: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(alignment: .center, spacing: 14) {
                    LegendBadge(label: pin.label, isCurrent: isCurrent, isSelected: isSelected)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(pin.title)
                            .brandFont(.bodyText)
                            .foregroundStyle(BrandPalette.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if let location = pin.locationName {
                            Text(location)
                                .brandFont(.bodySmall)
                                .foregroundStyle(BrandPalette.body.opacity(0.9))
                                .multilineTextAlignment(.leading)
                        }
                    }

                    Spacer(minLength: 6)

                    if isCurrent {
                        Eyebrow(text: "Now", size: 9)
                    }
                }
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Centres the map on this venue")

            Rectangle()
                .fill(BrandPalette.hairline)
                .frame(height: 1)
        }
    }
}

/// The legend's own numeral, cut the same way as the pin it answers to.
private struct LegendBadge: View {
    let label: String
    let isCurrent: Bool
    let isSelected: Bool

    var body: some View {
        Text(label)
            .font(BrandLabel.font(size: 11.5, weight: .semibold))
            .tracking(0.4)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isCurrent ? Color(hex: 0xFFFBF1) : BrandPalette.goldDeep)
            .padding(.horizontal, 9)
            .frame(minWidth: 28, minHeight: 28)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        isCurrent
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color(hex: 0xC2A24C), Color(hex: 0xA9873C)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.clear)
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        BrandPalette.gold.opacity(isSelected || isCurrent ? 0.9 : 0.45),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            }
    }
}

private extension Array {
    var nonEmpty: [Element]? { isEmpty ? nil : self }
}
