import Foundation
import Observation
import SwiftData
import SwiftUI
import os

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

    static let failedMessage = "Couldn't export your data. Please try again."
    static let cleanupFailedMessage = "Couldn't remove the temporary files. Please try again."
    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "ExportShareViewModel")

    @ObservationIgnored var announce: @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }

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
    func prepare(
        remove: @escaping @Sendable (ExportShareFiles) throws -> Void = { try $0.remove() },
        generate: @escaping @Sendable () throws -> ExportShareFiles
    ) async {
        guard state == .idle || state == .failed else { return }
        attempt += 1
        let currentAttempt = attempt
        state = .generating
        let worker = Task.detached(priority: .userInitiated) { try generate() }
        do {
            let files = try await worker.value
            guard currentAttempt == attempt, !Task.isCancelled else {
                do {
                    try await Task.detached { try remove(files) }.value
                } catch {
                    // The next export sweeps this directory; a stale result must not report a generation failure.
                    Self.logger.error("Could not remove stale export files")
                }
                if currentAttempt == attempt { state = .idle }
                return
            }
            state = .ready(files)
            announce("Export ready")
        } catch {
            if currentAttempt == attempt {
                state = .failed
                announce(Self.failedMessage)
            }
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
                announce(Self.cleanupFailedMessage)
            }
        default:
            state = .idle
        }
    }
}
