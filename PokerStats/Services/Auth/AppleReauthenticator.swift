import AuthenticationServices
import UIKit

/// The parts of a Sign in with Apple credential the app uses.
struct AppleAuthorization: Sendable {
    let identityToken: Data?
    let authorizationCode: Data?
    let fullName: PersonNameComponents?
    let appleUserId: String

    init(identityToken: Data?, authorizationCode: Data?, fullName: PersonNameComponents?, appleUserId: String) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.fullName = fullName
        self.appleUserId = appleUserId
    }

    init(_ credential: ASAuthorizationAppleIDCredential) {
        self.init(
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode,
            fullName: credential.fullName,
            appleUserId: credential.user
        )
    }
}

/// Runs Sign in with Apple outside `SignInWithAppleButton`: to re-confirm
/// before account deletion, and for Try Again after a failed sign-in.
@MainActor
final class AppleReauthenticator: NSObject {
    private var continuation: CheckedContinuation<AppleAuthorization, Error>?
    private var controller: ASAuthorizationController?

    /// Asks the user to confirm and returns the fresh authorization code,
    /// which `delete-account` needs to revoke the Apple token.
    func authorizationCode() async throws -> String {
        let authorization: AppleAuthorization
        do {
            authorization = try await authorize { _ in }
        } catch let error as ASAuthorizationError where error.code == .canceled {
            throw AccountDeletionError.reauthenticationCancelled
        }
        guard let data = authorization.authorizationCode,
              let code = String(data: data, encoding: .utf8) else {
            throw AuthServiceError.appleSignInFailed("Missing authorization code")
        }
        return code
    }

    /// Runs one Sign in with Apple request; `configure` sets its scopes and
    /// nonce. Cancelling throws `ASAuthorizationError.canceled`.
    func authorize(configure: (ASAuthorizationAppleIDRequest) -> Void) async throws -> AppleAuthorization {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        configure(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AppleAuthorization, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}

extension AppleReauthenticator: @preconcurrency ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failure(AuthServiceError.appleSignInFailed("Missing Apple ID credential")))
            return
        }
        finish(.success(AppleAuthorization(credential)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(.failure(error))
    }
}

extension AppleReauthenticator: @preconcurrency ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return window
        }
        if let scene = scenes.first {
            return UIWindow(windowScene: scene)
        }
        return ASPresentationAnchor()
    }
}
