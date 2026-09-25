import Foundation

final class AuthCredentials: @unchecked Sendable {
    static let shared = AuthCredentials()

    private let lock = NSLock()
    private var token: String?

    var bearerToken: String? {
        get { lock.withLock { token } }
        set { lock.withLock { token = newValue } }
    }

    private init() {}
}

extension Notification.Name {
    static let anglesSessionInvalidated = Notification.Name("angles.session.invalidated")
}
