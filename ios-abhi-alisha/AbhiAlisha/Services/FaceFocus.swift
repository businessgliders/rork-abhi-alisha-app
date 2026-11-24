import UIKit
import Vision

/// Finds where the faces are in a photograph, once per photo, so wide crops can keep
/// people in frame. Results are remembered for the session; photos with no faces get
/// `nil` and keep a centred crop.
@MainActor
final class FaceFocus {
    static let shared = FaceFocus()

    private var cache: [String: CGPoint?] = [:]

    private init() {}

    /// The centre of all detected faces in unit coordinates (top-left origin).
    func focus(for id: String, image: UIImage) async -> CGPoint? {
        if let known = cache[id] { return known }
        guard let cgImage = image.cgImage else {
            cache[id] = .some(nil)
            return nil
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let point = await Task.detached(priority: .utility) {
            Self.detect(cgImage, orientation: orientation)
        }.value
        cache[id] = .some(point)
        return point
    }

    nonisolated private static func detect(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGPoint? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let faces = (request.results ?? []).filter { $0.confidence > 0.5 }
        guard !faces.isEmpty else { return nil }
        // Union of every face, so a couple stays in frame together.
        let union = faces.map(\.boundingBox).reduce(faces[0].boundingBox) { $0.union($1) }
        // Vision uses a bottom-left origin; flip to top-left.
        return CGPoint(x: union.midX, y: 1 - union.midY)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
