import Foundation
import Security

enum KeychainStore {
    private static let service = "app.angles.ios.auth"
    private static let account = "session-token"
    private static let installMarkerKey = "angles.installMarker"

    /// iOS keeps Keychain items when the app is deleted, but not UserDefaults. A token found
    /// without the marker belongs to an earlier install, so a reinstall starts at Continue with Apple.
    static func discardTokenFromEarlierInstall(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: installMarkerKey) else {
            return
        }
        delete()
        defaults.set(true, forKey: installMarkerKey)
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String) {
        delete()
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
