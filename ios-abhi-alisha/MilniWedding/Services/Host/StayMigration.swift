import Foundation
import Supabase
import UIKit

/// Moves A&A's bundled "Where we're staying" content into Supabase once, the first time
/// an approved host opens the app: the two maps and the resort PDF go to
/// `wedding-assets/<wedding_id>/stay/`, the photos are copied there too (keeping the
/// original address when a copy fails), and one `stay` row is saved. Guests read it
/// from then on; until it exists they keep seeing the bundled content.
enum StayMigration {
    private static let doneKey = "milni.stayMigrated."

    static func runIfNeeded(content: ContentStore) async {
        let context = WeddingContext.shared
        let snapshot = context.snapshot
        guard context.isHost, snapshot.isMilniWedding, !snapshot.isSampleWedding else { return }
        let weddingID = snapshot.id
        let key = doneKey + weddingID.lowercased()
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let api = HostAPI.shared
        // Another host may already have done it.
        if let existing = try? await api.sections(weddingID: weddingID, kinds: ["stay"]),
           existing.contains(where: { $0.data["photos"] != nil || $0.data["resort_map_url"] != nil }) {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        let folder = "\(weddingID)/stay"
        do {
            guard let resortImage = UIImage(named: ResortMapArtwork.imageName),
                  let wingImage = UIImage(named: WingMapArtwork.imageName) else { return }
            let resortMapURL = try await api.uploadPhoto(resortImage, path: "\(folder)/resort-map.jpg", maxSide: 4096)
            let wingMapURL = try await api.uploadPhoto(wingImage, path: "\(folder)/wing-map.jpg", maxSide: 4096)

            var pdfURL = WingMapArtwork.pdfURL?.absoluteString
            if let source = WingMapArtwork.pdfURL {
                var data = ResortPDFCache.cached(for: source)
                if data == nil { data = await ResortPDFCache.download(source) }
                if let data {
                    pdfURL = (try? await api.upload(data, path: "\(folder)/resort-map.pdf", contentType: "application/pdf")) ?? pdfURL
                }
            }

            var photos: [String] = []
            for (index, url) in ResortMedia.photos.enumerated() {
                if let (data, response) = try? await URLSession.shared.data(from: url),
                   (response as? HTTPURLResponse)?.statusCode == 200,
                   let image = UIImage(data: data),
                   let uploaded = try? await api.uploadPhoto(image, path: "\(folder)/photo-\(index + 1).jpg") {
                    photos.append(uploaded)
                } else {
                    photos.append(url.absoluteString)
                }
            }

            let amenities: [AnyJSON] = ResortAmenity.all.map {
                .object(["title": .string($0.name), "subtitle": .string($0.note), "icon": .string($0.symbolName)])
            }
            let section = HostSection(
                id: "",
                kind: "stay",
                title: "AVA Resort Cancún",
                body: "",
                data: [
                    "photos": .array(photos.map { .string($0) }),
                    "resort_map_url": .string(resortMapURL),
                    "wing_map_url": .string(wingMapURL),
                    "pdf_url": pdfURL.map { .string($0) } ?? .null,
                    "amenities": .array(amenities)
                ],
                sort: 10
            )
            try await api.save(section, weddingID: weddingID)
            UserDefaults.standard.set(true, forKey: key)
            content.invalidate()
            await content.refreshIfNeeded()
        } catch {
            print("[Stay] migration not finished; will retry next launch")
        }
    }
}
