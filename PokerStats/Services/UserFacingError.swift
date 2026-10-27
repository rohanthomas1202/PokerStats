import Auth
import Foundation
import Functions
import PostgREST
import Storage
import os

/// What the user is told when a cloud or sign-in request fails, by category.
/// The copy is short and fixed; the raw error goes to the log only (`log`).
///
/// Account deletion keeps its own copy (`AuthViewModel.DeleteAccountFailure`).
enum UserFacingError: Equatable, Sendable {
    case offline
    case timeout
    /// The session is gone or the server answered 401.
    case authExpired
    /// The server answered 5xx.
    case serverError
    /// The backup was made by a newer app version.
    case backupTooNew
    /// The user signed out or switched accounts while the request ran (#222).
    case sessionChanged
    /// Cloud backup needs an account and none is signed in.
    case notSignedIn
    case unknown

    /// The request that failed; picks the copy for `.unknown`.
    enum Action: String, Sendable {
        case signIn
        case loadBackups
        case backup
        case restore
        case autoRestore
    }

    init(_ error: any Error) {
        self = Self.category(of: error)
    }

    // MARK: - Copy

    static let offlineMessage = "Couldn't reach the server. Your data on this phone is safe. Try again."
    static let timeoutMessage = "The server took too long to answer. Your data on this phone is safe. Try again."
    static let serverErrorMessage = "Something went wrong on our server. Your data on this phone is safe. Try again in a few minutes."
    static let authExpiredMessage = "Your sign-in expired. Sign in again, then try again."
    static let backupTooNewMessage = "This backup is from a newer version of PokerStats. Update the app, then try again."
    static let sessionChangedMessage = "You signed out or switched accounts before this finished. Try again."
    static let sessionChangedSignedOutMessage = "You signed out before this finished. Sign in and try again."
    static let notSignedInMessage = "Sign in to use cloud backup."

    /// Copy for the screen where `action` was started. `isSignedIn` picks the
    /// next step after `.sessionChanged`.
    func message(for action: Action, isSignedIn: Bool = true) -> String {
        switch self {
        case .offline: Self.offlineMessage
        case .timeout: Self.timeoutMessage
        case .serverError: Self.serverErrorMessage
        // A 401 while signing in means Apple's token was refused, not an expired session.
        case .authExpired: action == .signIn ? Self.unknownMessage(for: action) : Self.authExpiredMessage
        case .backupTooNew: Self.backupTooNewMessage
        case .sessionChanged: isSignedIn ? Self.sessionChangedMessage : Self.sessionChangedSignedOutMessage
        case .notSignedIn: Self.notSignedInMessage
        case .unknown: Self.unknownMessage(for: action)
        }
    }

    /// Copy for the app-wide banner, which has no screen to say what failed.
    func bannerMessage(for action: Action, isSignedIn: Bool = true) -> String {
        let message = message(for: action, isSignedIn: isSignedIn)
        guard self != .unknown, self != .notSignedIn else { return message }
        switch action {
        case .backup: return "Backup didn't finish. \(message)"
        case .restore, .autoRestore: return "Restore didn't finish. \(message)"
        case .signIn, .loadBackups: return message
        }
    }

    static func unknownMessage(for action: Action) -> String {
        switch action {
        case .signIn: "Couldn't sign in with Apple. Please try again."
        case .loadBackups: "Couldn't load your backups. Try again."
        case .backup: "Couldn't back up right now. Your data on this phone is safe. Try again."
        case .restore: "Couldn't restore this backup. Your data on this phone wasn't changed. Try again."
        case .autoRestore: "Couldn't restore your backup. Try again."
        }
    }

    /// False when trying again right away can't help.
    var isRetryable: Bool {
        switch self {
        case .backupTooNew, .notSignedIn, .authExpired: false
        case .offline, .timeout, .serverError, .sessionChanged, .unknown: true
        }
    }

    // MARK: - Logging

    /// Logs the category publicly and the raw error privately.
    static func log(_ error: any Error, action: Action, to logger: Logger) {
        let category = String(describing: Self(error))
        let kind = String(describing: type(of: error))
        logger.error("\(action.rawValue, privacy: .public) failed: \(category, privacy: .public) \(kind, privacy: .public) \(String(describing: error), privacy: .private)")
    }

    // MARK: - Mapping

    private static func category(of error: any Error) -> Self {
        switch error {
        case let error as URLError:
            return category(of: error.code)
        case BackupError.schemaVersionTooNew(_):
            return .backupTooNew
        case BackupError.notAuthenticated:
            return .notSignedIn
        case SupabaseError.sessionExpired:
            return .authExpired
        case SupabaseError.refreshUnavailable:
            // The refresh failed offline, on a timeout or a 5xx; the cause isn't kept.
            return .offline
        case SupabaseError.sessionChanged:
            return .sessionChanged
        case SupabaseError.httpError(let statusCode, _):
            return category(ofStatus: statusCode)
        case AuthError.sessionMissing:
            return .authExpired
        case AuthError.refreshDiscarded:
            return .sessionChanged
        case AuthError.api(_, _, _, let response):
            return category(ofStatus: response.statusCode)
        case FunctionsError.httpError(let code, _):
            return category(ofStatus: code)
        case let error as HTTPError:
            return category(ofStatus: error.response.statusCode)
        case let error as StorageError:
            if error.error == "InvalidJWT" { return .authExpired }
            return error.statusCode.flatMap { Int($0) }.map { category(ofStatus: $0) } ?? .unknown
        case let error as PostgrestError:
            return category(ofPostgrestCode: error.code)
        default:
            return .unknown
        }
    }

    private static func category(of code: URLError.Code) -> Self {
        switch code {
        case .timedOut:
            .timeout
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .callIsActive, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed:
            .offline
        default:
            .unknown
        }
    }

    private static func category(ofStatus statusCode: Int) -> Self {
        switch statusCode {
        case 401: .authExpired
        case 408: .timeout
        case 500...599: .serverError
        default: .unknown
        }
    }

    /// PostgREST error bodies carry a code but no HTTP status.
    /// PGRST000-003: the database is unreachable (503/504). PGRST301-303: the JWT was rejected (401).
    private static func category(ofPostgrestCode code: String?) -> Self {
        switch code {
        case "PGRST000", "PGRST001", "PGRST002", "PGRST003": .serverError
        case "PGRST301", "PGRST302", "PGRST303": .authExpired
        default: .unknown
        }
    }
}
