import AuthenticationServices
import Foundation
import Observation

enum AccountDeletion: Equatable, Sendable {
    case deleted
    /// The user closed Apple's confirmation sheet. Not an error.
    case cancelled
    case failed
}

@MainActor
@Observable
final class SessionStore {
    private(set) var session: SessionBody? {
        didSet {
            if session != nil {
                errorMessage = nil
            }
        }
    }
    private(set) var isRestored = false
    private(set) var isBusy = false
    var errorMessage: String?

    /// Runs after the server confirms a sign-in and before the session is published, so the
    /// first destination already knows this account's StoreKit answer (no paywall frame for a
    /// subscriber). Launch restore skips it; the launch gate prepares StoreKit itself.
    @ObservationIgnored var prepareAccountAccess: (@MainActor (SessionBody) async -> Void)?

    @ObservationIgnored private var committedToken: String?
    private var pendingAppleNonce: String?
    private let authService = AuthService()
    private let profileService = ProfileService()

    var isSignedIn: Bool {
        session != nil
    }

    var hasCompletedTaste: Bool {
        session?.hasUsedTaste == true
    }

    func restore() async {
        await restore(preparingAccess: false)
    }

    /// Login "Try again" after the session read failed on the network.
    func retryRestore() async {
        guard !isBusy else {
            return
        }
        isBusy = true
        defer { isBusy = false }
        await restore(preparingAccess: true)
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

    /// Clears this iPhone's session in one synchronous step so no frame can still read it as
    /// signed in, then revokes it on the server in the background with the captured token.
    func endLocalSession(revokeOnServer: Bool) {
        let token = committedToken ?? AuthCredentials.shared.bearerToken
        clearLocal()
        errorMessage = nil
        guard revokeOnServer, let token, !token.isEmpty else {
            return
        }
        let authService = self.authService
        Task.detached {
            try? await authService.signOut(bearer: token)
        }
    }

    /// Apple confirms first so the server can revoke the app's Sign in with Apple grant; closing
    /// that sheet deletes nothing. Server delete only: the caller ends the local session in the
    /// same frame as the rest of the app state.
    func deleteAccount() async -> AccountDeletion {
        isBusy = true
        defer { isBusy = false }
        let code: String
        do {
            code = try await AppleReauthorization().authorizationCode()
        } catch AppleReauthorizationError.canceled {
            return .cancelled
        } catch {
            errorMessage = "Couldn't confirm with Apple. Try again."
            return .failed
        }
        do {
            try await profileService.deleteAccount(appleAuthorizationCode: code)
            return .deleted
        } catch {
            errorMessage = "Couldn't delete your account. Try again."
            return .failed
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
            tasteConsumedAt: current.tasteConsumedAt,
            termsAcceptedAt: current.termsAcceptedAt,
            avatarUrl: current.avatarUrl
        )
    }

    var hasAcceptedTerms: Bool {
        session?.hasAcceptedTerms == true
    }

    /// Records "Agree and continue" on the server, which is the record that counts; Home and the
    /// first send both wait for it.
    func acceptTerms() async -> Bool {
        guard let current = session else {
            return false
        }
        if current.hasAcceptedTerms {
            return true
        }
        do {
            let accepted = try await profileService.acceptTerms()
            guard session?.id == current.id, let latest = session else {
                return false
            }
            session = SessionBody(
                id: latest.id,
                initials: latest.initials,
                name: latest.name,
                tasteCompletedAt: latest.tasteCompletedAt,
                tasteConsumedAt: latest.tasteConsumedAt,
                termsAcceptedAt: accepted.termsAcceptedAt,
                avatarUrl: latest.avatarUrl
            )
            return true
        } catch {
            return false
        }
    }

    /// True only when the server rejected the session that is live now.
    func isInvalidation(of token: String?) -> Bool {
        guard let token, let committedToken else {
            return false
        }
        return token == committedToken
    }

    private func restore(preparingAccess: Bool) async {
        errorMessage = nil
        let token = KeychainStore.read()
        AuthCredentials.shared.bearerToken = token
        defer { isRestored = true }
        guard let token, !token.isEmpty else {
            session = nil
            committedToken = nil
            return
        }
        do {
            let body = try await profileService.session()
            if preparingAccess {
                await prepareAccountAccess?(body)
            }
            guard AuthCredentials.shared.bearerToken == token else {
                return
            }
            commit(body, token: token)
        } catch let APIError.httpStatus(code, _, _) where code == 401 {
            clearLocal()
        } catch {
            errorMessage = "Couldn't reach Angles. Try again."
        }
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

        let token: String
        do {
            token = try await authService.signInWithApple(
                idToken: idToken,
                nonce: nonce,
                firstName: firstName,
                lastName: lastName,
                email: email
            )
        } catch {
            errorMessage = "Couldn't sign in. Try again."
            return
        }

        KeychainStore.write(token)
        AuthCredentials.shared.bearerToken = token
        do {
            let body = try await profileService.session()
            await prepareAccountAccess?(body)
            guard AuthCredentials.shared.bearerToken == token else {
                errorMessage = "Couldn't sign in. Try again."
                return
            }
            commit(body, token: token)
        } catch let APIError.httpStatus(code, _, _) where code == 401 {
            clearLocal()
            errorMessage = "Couldn't sign in. Try again."
        } catch {
            // The token is valid; Try again re-reads the session without another Apple sheet.
            errorMessage = "Couldn't reach Angles. Try again."
        }
    }

    private func commit(_ body: SessionBody, token: String) {
        committedToken = token
        session = body
    }

    private func clearLocal() {
        session = nil
        committedToken = nil
        AuthCredentials.shared.bearerToken = nil
        KeychainStore.delete()
        pendingAppleNonce = nil
    }
}
