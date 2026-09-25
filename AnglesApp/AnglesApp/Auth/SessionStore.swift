import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    private(set) var session: SessionBody?
    private(set) var isRestored = false
    private(set) var isBusy = false
    var errorMessage: String?

    private var pendingAppleNonce: String?
    private let authService = AuthService()
    private let profileService = ProfileService()

    var isSignedIn: Bool {
        session != nil
    }

    var hasCompletedTaste: Bool {
        if let tasteCompletedAt = session?.tasteCompletedAt, !tasteCompletedAt.isEmpty {
            return true
        }
        return false
    }

    func restore() async {
        errorMessage = nil
        let token = KeychainStore.read()
        AuthCredentials.shared.bearerToken = token
        defer { isRestored = true }
        guard let token, !token.isEmpty else {
            session = nil
            return
        }
        do {
            session = try await profileService.session()
        } catch let APIError.httpStatus(code, _) where code == 401 {
            clearLocal()
        } catch {
            errorMessage = "Couldn't reach Angles. Try again."
        }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = pendingAppleNonce ?? AuthNonce.random()
        pendingAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AuthNonce.sha256(nonce)
    }

    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        let nonce = pendingAppleNonce
        pendingAppleNonce = nil
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Couldn't sign in with Apple. Try again."
                return
            }
            await finishApple(
                idToken: token,
                nonce: nonce,
                firstName: credential.fullName?.givenName,
                lastName: credential.fullName?.familyName,
                email: credential.email
            )
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled {
                return
            }
            errorMessage = "Couldn't sign in with Apple. Try again."
        }
    }

    func signOut() async {
        isBusy = true
        defer { isBusy = false }
        try? await authService.signOut()
        clearLocal()
    }

    func deleteAccount() async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            try await profileService.deleteAccount()
            clearLocal()
            return true
        } catch {
            errorMessage = "Couldn't delete your account. Try again."
            return false
        }
    }

    func noteTasteCompleted() {
        guard let current = session, current.tasteCompletedAt == nil else {
            return
        }
        session = SessionBody(
            id: current.id,
            initials: current.initials,
            name: current.name,
            tasteCompletedAt: ISO8601Dates.string(from: Date()),
            avatarUrl: current.avatarUrl
        )
    }

    func handleInvalidatedSession() {
        clearLocal()
    }

    private func finishApple(
        idToken: String,
        nonce: String?,
        firstName: String?,
        lastName: String?,
        email: String?
    ) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let token = try await authService.signInWithApple(
                idToken: idToken,
                nonce: nonce,
                firstName: firstName,
                lastName: lastName,
                email: email
            )
            KeychainStore.write(token)
            AuthCredentials.shared.bearerToken = token
            session = try await profileService.session()
        } catch {
            errorMessage = "Couldn't sign in. Try again."
        }
    }

    private func clearLocal() {
        session = nil
        AuthCredentials.shared.bearerToken = nil
        KeychainStore.delete()
        pendingAppleNonce = nil
    }
}
