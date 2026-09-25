import Foundation

struct AuthService: Sendable {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func signInWithApple(
        idToken: String,
        nonce: String?,
        firstName: String?,
        lastName: String?,
        email: String?
    ) async throws -> String {
        var user: SocialSignInBody.IdToken.UserHints?
        if firstName != nil || lastName != nil || email != nil {
            let name: SocialSignInBody.IdToken.UserHints.NameParts?
            if firstName != nil || lastName != nil {
                name = .init(firstName: firstName, lastName: lastName)
            } else {
                name = nil
            }
            user = .init(name: name, email: email)
        }
        let body = SocialSignInBody(
            provider: "apple",
            idToken: .init(
                token: idToken,
                nonce: nonce,
                user: user
            )
        )
        let (data, headerToken) = try await client.postCapturingHeader(
            path: "api/auth/sign-in/social",
            body: body,
            header: "set-auth-token"
        )
        if let headerToken, !headerToken.isEmpty {
            return headerToken
        }
        let decoded = try JSONDecoder().decode(SocialSignInResponse.self, from: data)
        if let token = decoded.token, !token.isEmpty {
            return token
        }
        throw APIError.decoding("Sign in did not return a session.")
    }

    func signOut(bearer: String) async throws {
        try await client.postEmpty(path: "api/auth/sign-out", bearer: bearer, timeout: 6)
    }
}

private struct SocialSignInBody: Encodable {
    let provider: String
    let idToken: IdToken
    let requestSignUp = true

    struct IdToken: Encodable {
        let token: String
        let nonce: String?
        let user: UserHints?

        struct UserHints: Encodable {
            let name: NameParts?
            let email: String?

            struct NameParts: Encodable {
                let firstName: String?
                let lastName: String?
            }
        }
    }
}

private struct SocialSignInResponse: Decodable {
    let token: String?
}
