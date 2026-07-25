import Foundation
import Security

/// A minimal Keychain wrapper for exactly one use so far: persisting the
/// signed-in `AuthUser` across launches — and, per Apple's Sign in with
/// Apple guidance, across reinstalls too, since (unlike `UserDefaults`)
/// Keychain items survive a delete+reinstall by default. Not a
/// general-purpose Keychain abstraction; scoped to this one need.
enum KeychainStore {
    private static let service = "com.bilalhammad.forge.native.auth"
    private static let account = "signedInUser"

    private static func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func save(_ data: Data) {
        SecItemDelete(query() as CFDictionary)
        var attributes = query()
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> Data? {
        var attributes = query()
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func clear() {
        SecItemDelete(query() as CFDictionary)
    }
}
