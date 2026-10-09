import UIKit

/// Keeps a cook alive for the seconds iOS grants after the app leaves the screen. A cook takes
/// 5-9 s, which is exactly long enough to lock the phone or switch apps in the middle of one.
/// Without this the request dies, and the server only learns the phone is gone.
@MainActor
enum CookBackgroundTask {
    static func run<T>(_ work: () async throws -> T) async rethrows -> T {
        var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: "angles.cook") {
            // Out of time: end the task so iOS does not terminate the app. The retry layer
            // picks the same attempt back up when the app returns.
            if identifier != .invalid {
                UIApplication.shared.endBackgroundTask(identifier)
                identifier = .invalid
            }
        }
        defer {
            if identifier != .invalid {
                UIApplication.shared.endBackgroundTask(identifier)
            }
        }
        return try await work()
    }
}
