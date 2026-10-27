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

    /// Runs `restore` and shows its progress and outcome.
    @discardableResult
    func start(_ restore: @escaping @MainActor () async throws -> AutoRestore.Outcome) -> Task<Void, Never> {
        self.restore = restore
        return run(restore)
    }

    /// Try Again on the failure banner: runs the same restore again.
    @discardableResult
    func retry() -> Task<Void, Never>? {
        guard canRetry, let restore else { return nil }
        return run(restore)
    }

    func dismiss() {
        hideTask?.cancel()
        status = nil
        restore = nil
    }

    private func run(_ restore: @escaping @MainActor () async throws -> AutoRestore.Outcome) -> Task<Void, Never> {
        hideTask?.cancel()
        status = .restoring
        return Task {
            do {
                switch try await restore() {
                case .restored(let sessionCount):
                    finish(.restored(sessionCount: sessionCount), hideAfter: .seconds(3))
                case .noBackups:
                    finish(.noBackups, hideAfter: .seconds(2))
                case .skippedLocalDataExists, .skippedDataAppearedDuringDownload, .skippedAlreadyRan:
                    // Local data wins; nothing was restored or deleted.
                    dismiss()
                }
            } catch {
                UserFacingError.log(error, action: .autoRestore, to: Self.logger)
                let userFacing = UserFacingError(error)
                status = .failed(
                    message: userFacing.bannerMessage(for: .autoRestore),
                    canRetry: userFacing.isRetryable
                )
            }
        }
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
