import UIKit
import UserNotifications

@MainActor
enum FollowPush {
    static let categoryIdentifier = "follow"
    static let followBackAction = "FOLLOW_BACK"
    static let viewProfileAction = "VIEW_PROFILE"
    static let promptSeenKey = "angles.followPushPromptSeen"
    static let osPromptedThisInstallKey = "angles.pushOsPromptedThisInstall"
    static let tokenDefaultsKey = "angles.apnsDeviceToken"

    static var tokenEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    static var promptSeen: Bool {
        get { UserDefaults.standard.bool(forKey: promptSeenKey) }
        set { UserDefaults.standard.set(newValue, forKey: promptSeenKey) }
    }

    /// Cleared on reinstall. Stops a second iOS dialog in the same install after Home
    /// already asked, or the person tapped Follows in Settings.
    static var osPromptedThisInstall: Bool {
        get { UserDefaults.standard.bool(forKey: osPromptedThisInstallKey) }
        set { UserDefaults.standard.set(newValue, forKey: osPromptedThisInstallKey) }
    }

    static func registerCategories() {
        let viewProfile = UNNotificationAction(
            identifier: viewProfileAction,
            title: "View profile",
            options: [.foreground]
        )
        let followBack = UNNotificationAction(
            identifier: followBackAction,
            title: "Follow back",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [viewProfile, followBack],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Session start and every foreground. Never the iOS permission dialog — that waits
    /// for Home. Follows off, or iOS blocking banners: drop the stored token so the server
    /// does not send into nothing. Already allowed: ask for the token.
    static func reconcile(notifyFollows: Bool) async {
        let status = await authorizationStatus()
        if !notifyFollows {
            await forgetStoredToken()
            return
        }
        if isAllowed(status) {
            UIApplication.shared.registerForRemoteNotifications()
            return
        }
        await forgetStoredToken()
    }

    private static func forgetStoredToken() async {
        let center = FollowPushCenter.shared
        guard let token = center.deviceToken else {
            return
        }
        do {
            try await ProfileService().unregisterDevice(token: token)
            center.clearToken()
        } catch {
            // Kept for the next foreground.
        }
    }

    static func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        )) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    /// The one automatic ask: Home is on screen. Login, taste, paywall, and splash never
    /// call this. Whatever they answer, the next ask is theirs in Settings.
    static func askOnceOnHome() async {
        guard !osPromptedThisInstall else {
            return
        }
        let status = await authorizationStatus()
        guard status == .notDetermined else {
            if isAllowed(status) {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return
        }
        osPromptedThisInstall = true
        promptSeen = true
        _ = await requestAuthorization()
    }

    /// Settings row and the Follows switch replacement: iOS's dialog if it never asked,
    /// otherwise iOS Settings — the only place that can turn banners off.
    static func enableFromSettings() async {
        let status = await authorizationStatus()
        if status == .notDetermined {
            promptSeen = true
            osPromptedThisInstall = true
            _ = await requestAuthorization()
            return
        }
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            await UIApplication.shared.open(url)
        }
    }

    /// APNs `userInfo` sometimes hands `actorId` as a UUID, or a hex string without dashes.
    static func actorId(from userInfo: [AnyHashable: Any]) -> String? {
        let raw = userInfo["actorId"] ?? userInfo["actorID"]
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = raw as? UUID {
            return value.uuidString
        }
        return nil
    }

    static func uuid(from raw: String) -> UUID? {
        if let id = UUID(uuidString: raw) {
            return id
        }
        let hex = raw.filter(\.isHexDigit)
        guard hex.count == 32 else {
            return nil
        }
        var chars = Array(hex)
        chars.insert(Character("-"), at: 8)
        chars.insert(Character("-"), at: 13)
        chars.insert(Character("-"), at: 18)
        chars.insert(Character("-"), at: 23)
        return UUID(uuidString: String(chars))
    }
}

/// The app delegate and SwiftUI share this. A tap waits here until a session can open the row.
@MainActor
@Observable
final class FollowPushCenter {
    static let shared = FollowPushCenter()

    var deviceToken: String?
    /// Bumps on every token callback, even when iOS hands back the same token, so the root
    /// registers it again with the signed-in account.
    private(set) var tokenRevision = 0
    var pendingActorID: String?
    var pendingIntent: FollowPushIntent = .viewProfile

    private init() {
        deviceToken = UserDefaults.standard.string(forKey: FollowPush.tokenDefaultsKey)
    }

    func storeToken(_ token: String) {
        deviceToken = token
        UserDefaults.standard.set(token, forKey: FollowPush.tokenDefaultsKey)
        tokenRevision &+= 1
    }

    func clearToken() {
        deviceToken = nil
        UserDefaults.standard.removeObject(forKey: FollowPush.tokenDefaultsKey)
    }

    func handle(actionIdentifier: String, actorId: String?) {
        guard let actorId, !actorId.isEmpty else {
            return
        }
        pendingActorID = actorId
        pendingIntent = FollowPushIntent(actionIdentifier: actionIdentifier)
    }

    func clearPending() {
        pendingActorID = nil
        pendingIntent = .viewProfile
    }
}

/// What the person chose on the lock-screen notification. A plain tap opens their posts.
enum FollowPushIntent: Equatable {
    case viewProfile
    case followBack

    init(actionIdentifier: String) {
        switch actionIdentifier {
        case FollowPush.followBackAction:
            self = .followBack
        case FollowPush.viewProfileAction, UNNotificationDefaultActionIdentifier:
            self = .viewProfile
        default:
            self = .viewProfile
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        FollowPush.registerCategories()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            FollowPushCenter.shared.storeToken(token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Registration can fail in the simulator or without the push entitlement. The in-app list still works.
        #if DEBUG
        print("[Angles Push] token registration failed: \(error.localizedDescription)")
        #endif
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actorId = FollowPush.actorId(from: response.notification.request.content.userInfo)
        await MainActor.run {
            FollowPushCenter.shared.handle(
                actionIdentifier: response.actionIdentifier,
                actorId: actorId
            )
        }
    }
}
