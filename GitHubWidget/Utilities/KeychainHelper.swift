import Security
import Foundation

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)

        // Build access ACL that allows any application — prevents re-prompt after app upgrades
        // when ad-hoc signing changes the binary signature each build.
        // SecACL APIs are deprecated but remain the only way to set "any app" ACL on macOS.
        let access = makeAnyAppAccess(label: key)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        if let access { addQuery[kSecAttrAccess as String] = access }
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // nil trustedList = "any application, no password prompt" per SecAccessCreate docs.
    // Do NOT iterate and rewrite ACLs — doing so preserves the default prompt selector
    // (confirm flag), which causes macOS to re-prompt even with an open trusted list.
    @available(macOS, deprecated: 10.10)
    private static func makeAnyAppAccess(label: String) -> SecAccess? {
        var access: SecAccess?
        SecAccessCreate(label as CFString, nil, &access)
        return access
    }

    // Re-saves an existing item to apply the corrected ACL. Call once on app launch
    // to silently migrate items written by older builds (which preserved the prompt flag).
    static func migrateACLIfNeeded(key: String) {
        let flagKey = "keychain_acl_v2_\(key)"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        if let value = load(key: key) {
            save(key: key, value: value)
        }
        UserDefaults.standard.set(true, forKey: flagKey)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
