import Security
import Foundation

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Migrates token from legacy keychain (where "Always Allow" re-adds the app's code
    // signature to the ACL on each click, breaking the "any app" intent on the next update)
    // to the Data Protection keychain (no code-signature ACL, never prompts on updates).
    // Flag set only on success — retries if previous attempt was denied.
    static func migrateACLIfNeeded(key: String) {
        let flagKey = "keychain_dp_migrated_\(key)"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        // Already in Data Protection keychain — nothing to migrate.
        if load(key: key) != nil {
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }

        // Read from legacy keychain. May prompt once if item has app-specific ACL.
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(legacyQuery as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return  // No legacy item or access denied — retry next launch.
        }

        save(key: key, value: value)
        UserDefaults.standard.set(true, forKey: flagKey)
    }
}
