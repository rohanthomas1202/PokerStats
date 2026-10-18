import AuthenticationServices
import UIKit

/// Asks the user to confirm with Sign in with Apple and returns the fresh
/// authorization code, which `delete-account` needs to revoke the Apple token.
@MainActor
final class AppleReauthenticator: NSObject {
    private var continuation: CheckedContinuation<String, Error>?
    private var controller: ASAuthorizationController?

    func authorizationCode() async throws -> String {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<String, Error>) {
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
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.authorizationCode,
              let code = String(data: data, encoding: .utf8) else {
            finish(.failure(AuthServiceError.appleSignInFailed("Missing authorization code")))
            return
        }
        finish(.success(code))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            finish(.failure(AccountDeletionError.reauthenticationCancelled))
        } else {
            finish(.failure(error))
        }
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
