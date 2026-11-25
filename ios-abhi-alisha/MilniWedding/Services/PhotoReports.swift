import Foundation
import Observation
import Supabase
import SwiftUI

/// A row of `public.photo_reports`: one person's complaint about one Wedding Week photo.
nonisolated struct PhotoReport: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let photoID: String
    let weddingID: String?
    let reporterID: UUID?
    let reason: String?
    let status: String?
    let createdAt: Date?
    let resolvedBy: UUID?
    let resolvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, reason, status
        case photoID = "photo_id"
        case weddingID = "wedding_id"
        case reporterID = "reporter_id"
        case createdAt = "created_at"
        case resolvedBy = "resolved_by"
        case resolvedAt = "resolved_at"
    }

    static let columns =
        "id,photo_id,wedding_id,reporter_id,reason,status,created_at,resolved_by,resolved_at"
}

nonisolated struct PhotoReportInsert: Encodable, Sendable {
    let photo_id: String
    let wedding_id: String
    let reason: String?
}

nonisolated struct PhotoReportResolution: Encodable, Sendable {
    let status: String
    let resolved_by: String
    let resolved_at: String
}

/// Open photo reports for the current wedding, plus the guest-side submission.
/// Hosts and co-hosts see the list in Settings; everyone can report a photo.
@Observable
final class PhotoReportStore {
    static let shared = PhotoReportStore()

    /// Open reports for the active wedding, newest first.
    private(set) var reports: [PhotoReport] = []
    private(set) var photos: [String: WeddingPhoto] = [:]
    private(set) var isRefreshing = false

    var openCount: Int { reports.count }

    private var client: SupabaseClient { ChatBackend.client }

    func refresh() async {
        guard ChatSession.shared.isAdmin else {
            if !reports.isEmpty { reports = [] }
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let weddingID = ActiveWedding.id.lowercased()
        do {
            let rows: [PhotoReport] = try await client.from("photo_reports")
                .select(PhotoReport.columns)
                .eq("wedding_id", value: weddingID)
                .eq("status", value: "open")
                .order("created_at", ascending: false)
                .execute().value
            guard weddingID == ActiveWedding.id.lowercased() else { return }
            withAnimation(.calm) { reports = rows }
            await loadDetails(for: rows)
        } catch {
            print("[Reports] photo reports could not be fetched")
        }
    }

    private func loadDetails(for rows: [PhotoReport]) async {
        let photoIDs = Array(Set(rows.map(\.photoID))).filter { photos[$0] == nil }
        if !photoIDs.isEmpty {
            let found: [WeddingPhoto] = (try? await client.from("event_photos")
                .select(WeddingPhoto.columns)
                .in("id", values: photoIDs)
                .execute().value) ?? []
            for photo in found { photos[photo.id] = photo }
        }
    }

    /// Who reported, from the profiles ChatStore already keeps.
    func name(of reporterID: UUID?) -> String {
        guard let reporterID else { return "a family member" }
        return ChatStore.shared.name(of: reporterID)
    }

    // MARK: - Guest side

    /// A guest reports a photo: one row on the server, hidden on this phone straight away.
    func submit(_ photo: WeddingPhoto, reason: String) async -> SubmitOutcome {
        guard ChatSession.shared.isSignedIn else { return .failed }
        do {
            try await client.from("photo_reports")
                .insert(
                    PhotoReportInsert(
                        photo_id: photo.id,
                        wedding_id: ActiveWedding.id.lowercased(),
                        reason: reason.isEmpty ? nil : String(reason.prefix(300))
                    ),
                    returning: .minimal
                )
                .execute()
            WeddingPhotoStore.shared.hideLocally(photo.id)
            BrandHaptics.tick()
            return .sent
        } catch {
            let description = String(describing: error).lowercased()
            if description.contains("duplicate") || description.contains("409") {
                WeddingPhotoStore.shared.hideLocally(photo.id)
                return .alreadyReported
            }
            print("[Reports] photo report could not be sent")
            return .failed
        }
    }

    enum SubmitOutcome: Sendable {
        case sent
        case alreadyReported
        case failed
    }

    fileprivate static let resolutionError = NSError(
        domain: "PhotoReports", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Not signed in"]
    )

    // MARK: - Host side

    /// Takes the photo down: row and storage files, then marks the report removed.
    func removePhoto(_ report: PhotoReport) async -> Bool {
        do {
            let row: [WeddingPhoto] = try await client.from("event_photos")
                .select(WeddingPhoto.columns)
                .eq("id", value: report.photoID)
                .limit(1)
                .execute().value
            if let photo = row.first {
                let paths = [photo.photoPath, photo.thumbPath]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                if !paths.isEmpty {
                    _ = try? await client.storage.from(WeddingPhoto.bucket).remove(paths: paths)
                }
                try await client.from("event_photos")
                    .delete(returning: .minimal)
                    .eq("id", value: report.photoID)
                    .execute()
            }
            try await resolve(report, status: "removed")
            await WeddingPhotoStore.shared.refresh()
            return true
        } catch {
            print("[Reports] reported photo could not be removed")
            return false
        }
    }

    /// Keeps the photo up and dismisses the report.
    func keep(_ report: PhotoReport) async -> Bool {
        do {
            try await resolve(report, status: "dismissed")
            return true
        } catch {
            print("[Reports] report could not be dismissed")
            return false
        }
    }

    private func resolve(_ report: PhotoReport, status: String) async throws {
        guard let uid = ChatSession.shared.userID?.lower else {
            throw PhotoReportStore.resolutionError
        }
        try await client.from("photo_reports")
            .update(
                PhotoReportResolution(
                    status: status,
                    resolved_by: uid,
                    resolved_at: ChatJSON.isoString(Date())
                ),
                returning: .minimal
            )
            .eq("id", value: report.id)
            .execute()
        withAnimation(.calm) { reports.removeAll { $0.id == report.id } }
    }
}
