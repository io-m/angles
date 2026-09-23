import Foundation

struct ProfileBody: Decodable, Equatable, Sendable {
    let initials: String
    let avatarUrl: String?
}

private struct DisplayNameBody: Encodable {
    let displayName: String
}

struct ProfileService: Sendable {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func updateName(_ displayName: String) async throws -> ProfileBody {
        try await client.patch(path: "profile", body: DisplayNameBody(displayName: displayName))
    }

    func uploadAvatar(jpeg: Data) async throws -> ProfileBody {
        try await client.putData(
            path: "profile/avatar",
            body: jpeg,
            contentType: "image/jpeg",
            timeout: 30
        )
    }

    func deleteAvatar() async throws -> ProfileBody {
        try await client.deleteJSON(path: "profile/avatar")
    }
}
