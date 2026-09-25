import Foundation

struct ProfileBody: Decodable, Equatable, Sendable {
    let initials: String
    let avatarUrl: String?
}

private struct DisplayNameBody: Encodable {
    let displayName: String
}

private struct SubscriptionSyncBody: Encodable {
    let signedTransactionInfo: String
}

struct ProfileService: Sendable {
    private static let writeTimeout: TimeInterval = 6

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

    func following() async throws -> FollowingListResponse {
        try await client.get(path: "profile/following")
    }

    func blocks() async throws -> FollowingListResponse {
        try await client.get(path: "profile/blocks")
    }

    func block(id: String) async throws -> BlockStateResponse {
        try await client.put(path: "users/\(id)/block", timeout: Self.writeTimeout)
    }

    func unblock(id: String) async throws -> BlockStateResponse {
        try await client.deleteJSON(path: "users/\(id)/block", timeout: Self.writeTimeout)
    }

    func session() async throws -> SessionBody {
        try await client.get(path: "profile/session")
    }

    func subscription() async throws -> SubscriptionBody {
        try await client.get(path: "profile/subscription", timeout: Self.writeTimeout)
    }

    func usage() async throws -> UsageSummary {
        try await client.get(path: "profile/usage", timeout: Self.writeTimeout)
    }

    func syncSubscription(signedTransactionInfo: String) async throws -> SubscriptionBody {
        try await client.post(
            path: "profile/subscription/sync",
            body: SubscriptionSyncBody(signedTransactionInfo: signedTransactionInfo),
            timeout: Self.writeTimeout
        )
    }

    func deleteAccount() async throws {
        try await client.delete(path: "profile")
    }
}
