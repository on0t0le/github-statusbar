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

    // Isolated to contain deprecation warnings for SecACL APIs (no modern replacement).
    @available(macOS, deprecated: 10.10)
    private static func makeAnyAppAccess(label: String) -> SecAccess? {
        var access: SecAccess?
        SecAccessCreate(label as CFString, nil, &access)
        guard let access else { return nil }
        var aclList: CFArray?
        SecAccessCopyACLList(access, &aclList)
        if let acls = aclList as? [SecACL] {
            for acl in acls {
                var appList: CFArray?
                var desc: CFString?
                var prompt = SecKeychainPromptSelector()
                SecACLCopyContents(acl, &appList, &desc, &prompt)
                SecACLSetContents(acl, nil, desc ?? label as CFString, prompt)
            }
        }
        return access
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
