import Foundation
import ImageIO
import UIKit

/// Turns a picked photograph into the two files that go up: a 2048px JPEG at 0.82 and a
/// 400px thumbnail at 0.75. Both are written to a staging folder straight away, so even
/// fifty photos never sit in memory at once, and the capture time is read from the
/// photo's own EXIF.
nonisolated enum WeddingPhotoProcessor {
    struct Output: Sendable {
        let fullName: String
        let thumbName: String
        let thumbData: Data
        let takenAt: Date?
    }

    static var stagingFolder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = base.appending(path: "wedding-uploads", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func stagedURL(_ name: String) -> URL? {
        stagingFolder?.appending(path: name)
    }

    static func discard(_ names: [String]) {
        for name in names {
            if let url = stagedURL(name) { try? FileManager.default.removeItem(at: url) }
        }
    }

    static func prepare(_ data: Data, fallbackDate: Date?) async -> Output? {
        await Task.detached(priority: .userInitiated) {
            process(data, fallbackDate: fallbackDate)
        }.value
    }

    private static func process(_ data: Data, fallbackDate: Date?) -> Output? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let folder = stagingFolder,
              let full = jpeg(from: source, maxPixel: 2048, quality: 0.82),
              let thumb = jpeg(from: source, maxPixel: 400, quality: 0.75) else { return nil }

        let id = UUID().uuidString.lowercased()
        let fullName = "\(id).jpg"
        let thumbName = "\(id)_t.jpg"
        do {
            try full.write(to: folder.appending(path: fullName), options: .atomic)
            try thumb.write(to: folder.appending(path: thumbName), options: .atomic)
        } catch {
            return nil
        }
        return Output(
            fullName: fullName,
            thumbName: thumbName,
            thumbData: thumb,
            takenAt: captureDate(of: source) ?? fallbackDate
        )
    }

    /// Downsamples straight from the file, upright, without decoding it at full size.
    private static func jpeg(from source: CGImageSource, maxPixel: Int, quality: CGFloat) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: quality)
    }

    /// EXIF DateTimeOriginal, read with its own offset when the camera recorded one,
    /// otherwise in the phone's time zone.
    private static func captureDate(of source: CGImageSource) -> Date? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        guard let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String) else { return nil }
        let offset = (exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifOffsetTime] as? String)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let offset, !offset.isEmpty {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            if let date = formatter.date(from: raw + offset) { return date }
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: raw)
    }
}

/// Decides which celebration a photograph belongs to.
nonisolated enum WeddingPhotoTagger {
    /// The event running when it was taken (30 minutes before the start to an hour after
    /// the end, nearest start wins); otherwise the one happening now; otherwise the one
    /// the picker was opened from; otherwise nil, and the couple choose.
    static func eventID(
        for takenAt: Date?,
        in events: [ScheduleEvent],
        now: Date,
        origin: String?
    ) -> String? {
        if let takenAt {
            let matches = events.filter { event in
                guard let start = event.startsAt else { return false }
                let end = event.endsAt ?? start.addingTimeInterval(2 * 3600)
                return takenAt >= start.addingTimeInterval(-30 * 60) && takenAt <= end.addingTimeInterval(60 * 60)
            }
            let best = matches.min { lhs, rhs in
                abs((lhs.startsAt ?? .distantFuture).timeIntervalSince(takenAt))
                    < abs((rhs.startsAt ?? .distantFuture).timeIntervalSince(takenAt))
            }
            if let best { return best.id }
        }
        if let current = events.first(where: { $0.isHappening(at: now) }) {
            return current.id
        }
        if let origin, events.contains(where: { $0.id == origin }) {
            return origin
        }
        return nil
    }
}
