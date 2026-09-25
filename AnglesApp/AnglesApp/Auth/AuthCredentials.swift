import Foundation

final class AuthCredentials: @unchecked Sendable {
    static let shared = AuthCredentials()

    private let lock = NSLock()
    private var token: String?

    var bearerToken: String? {
        get { lock.withLock { token } }
        set { lock.withLock { token = newValue } }
    }

    /// Clears only the session that failed. A late 401 for an older token must not sign out
    /// the session that replaced it.
    @discardableResult
    func clear(ifMatching expected: String) -> Bool {
        lock.withLock {
            guard token == expected else {
                return false
            }
            token = nil
            return true
        }
    }

    init() {}
}

extension Notification.Name {
    /// `object` is the bearer token the server rejected.
    static let anglesSessionInvalidated = Notification.Name("angles.session.invalidated")
}
