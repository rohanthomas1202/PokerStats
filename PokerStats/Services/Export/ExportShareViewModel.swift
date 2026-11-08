import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ExportShareViewModel {
    enum State: Equatable {
        case idle
        case generating
        case ready(ExportShareFiles)
        case failed
        case removing
        case cleanupFailed(ExportShareFiles)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var attempt = 0

    func prepare(container: ModelContainer) async {
        await prepare {
            // Construct and use the context on the worker, never transfer live models.
            let context = ModelContext(container)
            let sessions = try context.fetch(FetchDescriptor<Session>())
            let hands = try context.fetch(FetchDescriptor<Hand>())
            let settings = try context.fetch(FetchDescriptor<Settings>()).first ?? Settings()
            return try ExportShareFiles.write(ExportEngine.makeFiles(sessions: sessions, hands: hands, settings: settings))
        }
    }

    /// The synchronous generator always runs on a detached worker, including fetches and disk IO.
    func prepare(generate: @escaping @Sendable () throws -> ExportShareFiles) async {
        guard state == .idle || state == .failed else { return }
        attempt += 1
        let currentAttempt = attempt
        state = .generating
        let worker = Task.detached(priority: .userInitiated) { try generate() }
        do {
            let files = try await worker.value
            guard currentAttempt == attempt, !Task.isCancelled else {
                try await Task.detached { try files.remove() }.value
                if currentAttempt == attempt { state = .idle }
                return
            }
            state = .ready(files)
        } catch {
            if currentAttempt == attempt { state = .failed }
        }
    }

    /// Closing the export flow (including cancelling it) invalidates any late worker result.
    func cleanup(remove: @escaping @Sendable (ExportShareFiles) throws -> Void = { try $0.remove() }) async {
        guard state != .removing else { return }
        attempt += 1
        switch state {
        case .ready(let files), .cleanupFailed(let files):
            state = .removing
            do {
                try await Task.detached { try remove(files) }.value
                state = .idle
            } catch {
                // Retain ownership and show an error rather than re-sharing stale files.
                state = .cleanupFailed(files)
            }
        default:
            state = .idle
        }
    }
}
