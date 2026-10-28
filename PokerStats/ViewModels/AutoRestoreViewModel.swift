import Foundation
import os

/// The top banner for the restore that runs after sign-in. Success and "no
/// backups" hide on their own; a failure stays up with Try Again until the
/// user dismisses it or signs out.
@Observable
@MainActor
final class AutoRestoreViewModel {
    enum Status: Equatable {
        case restoring
        case restored(sessionCount: Int)
        case noBackups
        case failed(message: String, canRetry: Bool)
    }

    private(set) var status: Status?

    @ObservationIgnored private var restore: (@MainActor () async throws -> AutoRestore.Outcome)?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var isSignedIn: @MainActor () -> Bool = { true }
    /// Bumped by each run and by `dismiss()`; a run whose number is stale
    /// reports nothing, even if its restore ignores cancellation.
    @ObservationIgnored private var generation = 0

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "AutoRestoreViewModel")

    var message: String? {
        switch status {
        case .restoring: "Restoring from cloud..."
        case .restored(let sessionCount): "Restored \(sessionCount) sessions"
        case .noBackups: "No backups found"
        case .failed(let message, _): message
        case nil: nil
        }
    }

    var isFailed: Bool {
        if case .failed = status { true } else { false }
    }

    var canRetry: Bool {
        if case .failed(_, true) = status { true } else { false }
    }

    /// Runs `restore` and shows its progress and outcome. `isSignedIn` picks
    /// the next step in the failure copy.
    @discardableResult
    func start(
        isSignedIn: @escaping @MainActor () -> Bool = { true },
        _ restore: @escaping @MainActor () async throws -> AutoRestore.Outcome
    ) -> Task<Void, Never> {
        self.isSignedIn = isSignedIn
        self.restore = restore
        return run(restore)
    }

    /// Try Again on the failure banner: runs the same restore again.
    @discardableResult
    func retry() -> Task<Void, Never>? {
        guard canRetry, let restore else { return nil }
        return run(restore)
    }

    /// Hides the banner and stops a run in flight, so it can't report later
    /// (for example after sign-out).
    func dismiss() {
        generation += 1
        runTask?.cancel()
        runTask = nil
        hideTask?.cancel()
        status = nil
        restore = nil
    }

    private func run(_ restore: @escaping @MainActor () async throws -> AutoRestore.Outcome) -> Task<Void, Never> {
        hideTask?.cancel()
        runTask?.cancel()
        generation += 1
        let thisRun = generation
        status = .restoring
        let task = Task {
            do {
                let outcome = try await restore()
                guard thisRun == generation else { return }
                switch outcome {
                case .restored(let sessionCount):
                    finish(.restored(sessionCount: sessionCount), hideAfter: .seconds(3))
                case .noBackups:
                    finish(.noBackups, hideAfter: .seconds(2))
                case .skippedLocalDataExists, .skippedDataAppearedDuringDownload, .skippedAlreadyRan:
                    // Local data wins; nothing was restored or deleted.
                    dismiss()
                }
            } catch is CancellationError {
                // Stopped by account deletion: nothing to report.
                guard thisRun == generation else { return }
                dismiss()
            } catch {
                UserFacingError.log(error, action: .autoRestore, to: Self.logger)
                guard thisRun == generation else { return }
                let userFacing = UserFacingError(error)
                status = .failed(
                    message: userFacing.bannerMessage(for: .autoRestore, isSignedIn: isSignedIn()),
                    canRetry: userFacing.isRetryable
                )
            }
        }
        runTask = task
        return task
    }

    private func finish(_ status: Status, hideAfter delay: Duration) {
        self.status = status
        restore = nil
        hideTask = Task {
            try? await Task.sleep(for: delay)
            if Task.isCancelled { return }
            self.status = nil
        }
    }
}
