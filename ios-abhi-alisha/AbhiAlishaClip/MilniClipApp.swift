import Observation
import SwiftUI

@main
struct MilniClipApp: App {
    @State private var model = ClipModel()

    var body: some Scene {
        WindowGroup {
            ClipRootView()
                .environment(model)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    model.open(url: url)
                }
                .onOpenURL { url in model.open(url: url) }
        }
    }
}

/// What the clip is showing: waiting for a link, looking it up, or the invitation.
@MainActor
@Observable
final class ClipModel {
    enum Phase: Equatable {
        case waiting
        case loading
        case invitation
        case notFound
        case offline
    }

    var phase: Phase = .waiting
    var wedding: ClipWedding?
    var events: [ClipEvent] = []
    var zone: TimeZone = .current
    var lastCode: String?

    private var loadTask: Task<Void, Never>?

    var theme: ClipTheme { wedding?.theme ?? .ivory }

    func open(url: URL) {
        guard let code = ClipLink.code(from: url) else {
            if wedding == nil { phase = .notFound }
            return
        }
        open(code: code)
    }

    func open(code raw: String) {
        guard let code = ClipLink.normalize(raw) else {
            phase = .notFound
            return
        }
        if code == lastCode, phase == .invitation || phase == .loading { return }
        lastCode = code
        // The full app picks this up after it's installed and opens on the invitation.
        ClipHandoffWriter.save(code: code)
        loadTask?.cancel()
        phase = .loading
        loadTask = Task { await load(code: code) }
    }

    func retry() {
        guard let lastCode else { phase = .waiting; return }
        self.lastCode = nil
        open(code: lastCode)
    }

    private func load(code: String) async {
        do {
            let found = try await ClipAPI.preview(code: code)
            async let zone = ClipAPI.timeZone(weddingID: found.id)
            async let schedule = ClipAPI.publicSchedule(weddingID: found.id)
            let (resolvedZone, events) = await (zone, schedule)
            guard !Task.isCancelled else { return }
            self.zone = resolvedZone ?? .current
            self.events = events
            withAnimation(.easeInOut(duration: 0.45)) {
                wedding = found
                phase = .invitation
            }
        } catch ClipAPI.Failure.offline {
            guard !Task.isCancelled else { return }
            phase = .offline
        } catch {
            guard !Task.isCancelled else { return }
            phase = .notFound
        }
    }
}
