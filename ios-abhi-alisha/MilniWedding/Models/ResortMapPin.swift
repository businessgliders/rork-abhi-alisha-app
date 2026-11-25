import CoreGraphics
import Foundation

/// The resort map artwork, bundled with the app so it draws with no connection at all.
nonisolated enum ResortMapArtwork {
    static let imageName = "resort_map"
    /// The artwork's own pixel size — pins are placed as a fraction of this, never of the screen.
    static let pixelSize = CGSize(width: 4697, height: 1471)
    static var aspectRatio: CGFloat { pixelSize.width / pixelSize.height }
}

/// One celebration marked on the resort map.
///
/// `unit` is the position on the artwork itself — 0 to 1 across its own width and height —
/// so the pin stays locked to the picture through any amount of zoom and pan.
nonisolated struct ResortMapPin: Identifiable, Hashable, Sendable {
    let event: ScheduleEvent
    let unit: CGPoint
    /// Its place in the legend, counted through the events that are actually plotted.
    let number: Int
    /// The couple's own label when they set one, otherwise the legend number.
    let label: String

    var id: String { event.id }
    var title: String { event.title }
    var locationName: String? { event.locationName }

    /// The pin's position inside a drawn copy of the artwork of the given size.
    func point(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * unit.x, y: size.height * unit.y)
    }

    var timing: String? {
        let parts = [event.displayDate, event.displayTime].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}

extension ScheduleEvent {
    /// Where this celebration sits on the resort map, or nothing at all when the couple
    /// have hidden it or left the coordinates unset.
    var resortMapUnitPoint: CGPoint? {
        guard hideMap != true, isActive != false else { return nil }
        guard let x = resortMapX, let y = resortMapY else { return nil }
        guard (0...100).contains(x), (0...100).contains(y) else { return nil }
        guard !(x == 0 && y == 0) else { return nil }
        return CGPoint(x: x / 100, y: y / 100)
    }
}

/// Builds the plotted set once, so the number on a pin and the number in the legend can
/// never disagree.
nonisolated enum ResortMapPlot {
    static func pins(from events: [ScheduleEvent]) -> [ResortMapPin] {
        events
            .compactMap { event -> (event: ScheduleEvent, unit: CGPoint)? in
                guard let unit = event.resortMapUnitPoint else { return nil }
                return (event, unit)
            }
            .sorted { precedes($0.event, $1.event) }
            .enumerated()
            .map { index, entry in
                let number = index + 1
                return ResortMapPin(
                    event: entry.event,
                    unit: entry.unit,
                    number: number,
                    label: entry.event.resortMapLabel ?? "\(number)"
                )
            }
    }

    /// The couple's own running order, falling back to the clock.
    private static func precedes(_ lhs: ScheduleEvent, _ rhs: ScheduleEvent) -> Bool {
        let left = lhs.sortOrder ?? .greatestFiniteMagnitude
        let right = rhs.sortOrder ?? .greatestFiniteMagnitude
        if left != right { return left < right }
        return (lhs.startsAt ?? .distantFuture) < (rhs.startsAt ?? .distantFuture)
    }
}
