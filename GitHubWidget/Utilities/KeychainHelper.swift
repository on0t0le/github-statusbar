import Security
import Foundation

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
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

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // nil trustedList = "any application, no password prompt" per SecAccessCreate docs.
    @available(macOS, deprecated: 10.10)
    private static func makeAnyAppAccess(label: String) -> SecAccess? {
        var access: SecAccess?
        SecAccessCreate(label as CFString, nil, &access)
        return access
    }

    // Re-saves the token with an open ACL on every launch. This counteracts "Always Allow"
    // clicks, which replace the open ACL with an app-specific one tied to the current binary
    // signature. By re-saving at launch, any corruption is repaired before the next update
    // installs a new signature — so updates never prompt.
    static func migrateACLIfNeeded(key: String) {
        guard let value = load(key: key) else { return }
        save(key: key, value: value)
    }
}
