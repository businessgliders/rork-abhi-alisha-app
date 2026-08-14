import SwiftUI

/// A request to bring one pin to the middle of the map at a given zoom.
/// `token` is bumped when the same pin is asked for twice, so a repeat tap still re-centres.
struct ResortMapFocus: Equatable {
    let pinID: String
    var zoom: CGFloat = 3.4
    var token: UUID?
}

/// The bundled resort map with every celebration pinned to it.
///
/// The picture and its pins live in a single stack that is scaled and offset together, so a
/// pin is fixed to the place on the artwork it belongs to — it can never drift as the map is
/// zoomed or dragged. Only the marker itself counter-scales, so it stays legible.
struct ResortMapCanvas: View {
    let pins: [ResortMapPin]
    var currentPinID: String?
    var selectedPinID: String?
    var focus: ResortMapFocus?
    var isInteractive: Bool = true
    var onSelect: (([ResortMapPin]) -> Void)?

    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero

    private static let minScale: CGFloat = 1
    private static let maxScale: CGFloat = 8
    /// How close two markers may come, on screen, before they are gathered into one.
    private static let clusterSpacing: CGFloat = 46

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size
            let fitted = Self.fitted(in: container)

            ZStack(alignment: .topLeading) {
                Image(ResortMapArtwork.imageName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fitted.width, height: fitted.height)
                    .accessibilityHidden(true)

                ForEach(clusters(in: fitted)) { cluster in
                    marker(cluster)
                        .position(cluster.anchor)
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: container.width, height: container.height)
            .contentShape(Rectangle())
            .gesture(
                magnifyGesture(container: container, fitted: fitted),
                including: isInteractive ? .all : .subviews
            )
            .simultaneousGesture(
                panGesture(container: container, fitted: fitted),
                including: isInteractive ? .all : .subviews
            )
            .onTapGesture(count: 2) {
                guard isInteractive else { return }
                reset()
            }
            .onChange(of: container, initial: true) { _, size in
                applyFocus(focus, container: size, fitted: Self.fitted(in: size), animated: false)
            }
            .onChange(of: focus) { _, request in
                applyFocus(request, container: container, fitted: fitted, animated: true)
            }
            .onChange(of: pins) { _, _ in
                applyFocus(focus, container: container, fitted: fitted, animated: false)
            }
        }
        .background(BrandPalette.card)
        .clipped()
        .accessibilityElement(children: isInteractive ? .contain : .ignore)
    }

    // MARK: - Markers

    @ViewBuilder
    private func marker(_ cluster: PinCluster) -> some View {
        let isCurrent = cluster.members.contains { $0.id == currentPinID }
        let isSelected = cluster.members.contains { $0.id == selectedPinID }

        let face = ResortMapMarker(
            label: cluster.label,
            isCurrent: isCurrent,
            isSelected: isSelected
        )
        .scaleEffect(1 / scale)

        if isInteractive, let onSelect {
            Button {
                BrandHaptics.tick()
                onSelect(cluster.members)
            } label: {
                face
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(cluster.accessibilityLabel)
            .accessibilityHint("Shows this celebration")
        } else {
            face.allowsHitTesting(false)
        }
    }

    /// Markers that would sit on top of one another at this zoom are gathered into one,
    /// wearing every number it stands for. Zooming in parts them again.
    private func clusters(in fitted: CGSize) -> [PinCluster] {
        guard fitted.width > 0 else { return [] }
        let threshold = Self.clusterSpacing / max(scale, 0.001)
        var result: [PinCluster] = []

        for pin in pins {
            let point = pin.point(in: fitted)
            if let index = result.firstIndex(where: { hypot($0.anchor.x - point.x, $0.anchor.y - point.y) < threshold }) {
                result[index].members.append(pin)
            } else {
                result.append(PinCluster(anchor: point, members: [pin]))
            }
        }
        return result
    }

    // MARK: - Gestures

    private func magnifyGesture(container: CGSize, fitted: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let next = min(max(steadyScale * value.magnification, Self.minScale), Self.maxScale)
                let ratio = next / max(steadyScale, 0.001)
                scale = next
                offset = clamp(
                    CGSize(width: steadyOffset.width * ratio, height: steadyOffset.height * ratio),
                    scale: next,
                    container: container,
                    fitted: fitted
                )
            }
            .onEnded { _ in
                steadyScale = scale
                steadyOffset = offset
            }
    }

    private func panGesture(container: CGSize, fitted: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                offset = clamp(
                    CGSize(
                        width: steadyOffset.width + value.translation.width,
                        height: steadyOffset.height + value.translation.height
                    ),
                    scale: scale,
                    container: container,
                    fitted: fitted
                )
            }
            .onEnded { _ in
                steadyOffset = offset
            }
    }

    private func reset() {
        BrandHaptics.soft()
        withAnimation(.calm) {
            scale = Self.minScale
            offset = .zero
        }
        steadyScale = Self.minScale
        steadyOffset = .zero
    }

    // MARK: - Geometry

    /// The artwork drawn whole inside the space it is given, in its own proportions.
    private static func fitted(in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }
        let width = min(container.width, container.height * ResortMapArtwork.aspectRatio)
        return CGSize(width: width, height: width / ResortMapArtwork.aspectRatio)
    }

    /// Keeps the artwork from being dragged away from the frame it sits in.
    private func clamp(_ value: CGSize, scale: CGFloat, container: CGSize, fitted: CGSize) -> CGSize {
        let limitX = max(0, (fitted.width * scale - container.width) / 2)
        let limitY = max(0, (fitted.height * scale - container.height) / 2)
        return CGSize(
            width: min(max(value.width, -limitX), limitX),
            height: min(max(value.height, -limitY), limitY)
        )
    }

    private func applyFocus(_ request: ResortMapFocus?, container: CGSize, fitted: CGSize, animated: Bool) {
        guard let request,
              fitted.width > 0,
              let pin = pins.first(where: { $0.id == request.pinID }) else { return }

        let zoom = min(max(request.zoom, Self.minScale), Self.maxScale)
        let target = pin.point(in: fitted)
        let centred = CGSize(
            width: (fitted.width / 2 - target.x) * zoom,
            height: (fitted.height / 2 - target.y) * zoom
        )
        let settled = clamp(centred, scale: zoom, container: container, fitted: fitted)

        if animated {
            withAnimation(.calm) {
                scale = zoom
                offset = settled
            }
        } else {
            scale = zoom
            offset = settled
        }
        steadyScale = zoom
        steadyOffset = settled
    }
}

/// A run of pins close enough together to share one marker.
private struct PinCluster: Identifiable {
    var anchor: CGPoint
    var members: [ResortMapPin]

    var id: String { members.map(\.id).joined(separator: "+") }
    var label: String { members.map(\.label).joined(separator: " · ") }

    var accessibilityLabel: String {
        members
            .map { pin in [pin.label, pin.title].joined(separator: ", ") }
            .joined(separator: "; ")
    }
}

/// The pin itself. Its colours are fixed rather than adaptive: it always sits on the same
/// photograph, so it should read the same way whatever the rest of the app is wearing.
private struct ResortMapMarker: View {
    let label: String
    let isCurrent: Bool
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulses = false

    private static let cream = Color(hex: 0xFDFAF3)
    private static let gold = Color(hex: 0xC2A24C)
    private static let goldDeep = Color(hex: 0xA9873C)
    private static let numeral = Color(hex: 0x8A6C2C)

    private var diameter: CGFloat {
        if isCurrent { return 34 }
        return isSelected ? 31 : 27
    }

    private var isHighlighted: Bool { isCurrent || isSelected }

    var body: some View {
        Text(label)
            .font(BrandLabel.font(size: isCurrent ? 13 : 11.5, weight: .semibold))
            .tracking(0.4)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isCurrent ? Self.cream : Self.numeral)
            .padding(.horizontal, 9)
            .frame(minWidth: diameter, minHeight: diameter)
            .background {
                Capsule(style: .continuous)
                    .fill(fill)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        isCurrent ? Color(hex: 0xFFF2CE).opacity(0.9) : Self.gold.opacity(isHighlighted ? 0.95 : 0.7),
                        lineWidth: isHighlighted ? 1.4 : 1
                    )
            }
            .background { halo }
            .shadow(color: Color.black.opacity(0.24), radius: 5, y: 2)
            .shadow(color: Self.gold.opacity(isCurrent ? 0.55 : 0), radius: 13)
            .animation(.calm, value: isCurrent)
            .animation(.calm, value: isSelected)
    }

    private var fill: AnyShapeStyle {
        if isCurrent {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Self.gold, Self.goldDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Self.cream.opacity(0.97))
    }

    /// A single ring breathing outwards from the celebration that is happening now.
    @ViewBuilder
    private var halo: some View {
        if isCurrent {
            Capsule(style: .continuous)
                .stroke(Self.gold.opacity(0.85), lineWidth: 1.2)
                .scaleEffect(pulses ? 1.75 : 1)
                .opacity(pulses ? 0 : 0.9)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                        pulses = true
                    }
                }
        }
    }
}
