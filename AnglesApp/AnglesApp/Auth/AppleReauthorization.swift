import AuthenticationServices
import UIKit

enum AppleReauthorizationError: Error {
    case canceled
    case failed
}

/// One Sign in with Apple sheet for a fresh authorization code. Delete account sends it so the
/// server can revoke the app's Apple grant; sign-in itself only needs the identity token.
@MainActor
final class AppleReauthorization: NSObject {
    private var continuation: CheckedContinuation<String, Error>?
    private var controller: ASAuthorizationController?

    func authorizationCode() async throws -> String {
        guard continuation == nil else {
            throw AppleReauthorizationError.failed
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = []
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<String, Error>) {
        let continuation = self.continuation
        self.continuation = nil
        controller = nil
        continuation?.resume(with: result)
    }
}

extension AppleReauthorization: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?
            .authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }
        MainActor.assumeIsolated {
            if let code, !code.isEmpty {
                finish(.success(code))
            } else {
                finish(.failure(AppleReauthorizationError.failed))
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let canceled = (error as? ASAuthorizationError)?.code == .canceled
        MainActor.assumeIsolated {
            finish(.failure(canceled ? AppleReauthorizationError.canceled : AppleReauthorizationError.failed))
        }
    }
}

extension AppleReauthorization: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            return active?.keyWindow ?? active?.windows.first ?? ASPresentationAnchor()
        }
    }
}
