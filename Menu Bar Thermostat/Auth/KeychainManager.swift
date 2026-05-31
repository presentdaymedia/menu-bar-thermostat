import Foundation
import Security

/// Light-weight helper for storing small string values (e.g. OAuth access / refresh tokens)
/// in the macOS Keychain. Items are saved as *generic-password* entries that are only
/// accessible by this app (same bundle identifier) and silently unlocked after the
/// first device unlock (kSecAttrAccessibleAfterFirstUnlock).
enum KeychainManager {

    /// Adds or updates the token associated with the supplied key.
    /// - Parameters:
    ///   - token: The string value to store.
    ///   - key:   A unique key identifying the item (e.g. "sdmAccessToken").
    /// - Returns: `true` on success, `false` otherwise.
    @discardableResult
    static func store(token: String, for key: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }

        // Delete any existing item first to make the add logic simpler.
        delete(for: key)

        let query: [String: Any] = [
            kSecClass as String            : kSecClassGenericPassword,
            kSecAttrAccount as String      : key,
            kSecAttrService as String      : bundleIdentifier,
            kSecValueData as String        : data,
            // ▶︎ Use the Data-Protection key-chain so the OS never shows a prompt.
            kSecUseDataProtectionKeychain as String : kCFBooleanTrue as Any,
            kSecAttrAccessible as String   : kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieves the token previously stored for the supplied key.
    /// - Parameter key: The identifier used when saving the item.
    /// - Returns: The stored token string, or `nil` if not found / an error occurred.
    static func retrieve(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : key,
            kSecAttrService as String : bundleIdentifier,
            kSecReturnData as String  : kCFBooleanTrue as Any,
            kSecUseDataProtectionKeychain as String : kCFBooleanTrue as Any,
            kSecMatchLimit as String  : kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes any existing entry for the given key.
    /// - Parameter key: The identifier used when saving the item.
    /// - Returns: `true` if the item was removed or didn't exist, `false` on failure.
    @discardableResult
    static func delete(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : key,
            kSecAttrService as String : bundleIdentifier,
            kSecUseDataProtectionKeychain as String : kCFBooleanTrue as Any
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Convenience helper for namespacing all items under this bundle identifier.
    private static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "menu-bar-thermostat"
    }
} 
