import XCTest
@testable import GitHubWidget

@MainActor
final class AccountStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        super.tearDown()
        if let data = defaults.data(forKey: "accounts"),
           let accounts = try? JSONDecoder().decode([Account].self, from: data) {
            for account in accounts {
                KeychainHelper.delete(key: account.keychainKey)
            }
        }
        defaults.removeSuite(named: suiteName)
    }

    func test_add_storesAccountAndToken() {
        let store = AccountStore(defaults: defaults)
        store.add(name: "Work", username: "bob", orgFilter: "", token: "ghp_abc")
        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.accounts[0].name, "Work")
        XCTAssertEqual(KeychainHelper.load(key: store.accounts[0].keychainKey), "ghp_abc")
    }

    func test_add_enforcesMaxFiveAccounts() {
        let store = AccountStore(defaults: defaults)
        for i in 1...5 {
            store.add(name: "Acct \(i)", username: "u\(i)", orgFilter: "", token: "tok\(i)")
        }
        store.add(name: "Sixth", username: "u6", orgFilter: "", token: "tok6")
        XCTAssertEqual(store.accounts.count, 5)
    }

    func test_delete_removesFromArrayAndKeychain() {
        let store = AccountStore(defaults: defaults)
        store.add(name: "Work", username: "bob", orgFilter: "", token: "ghp_abc")
        let account = store.accounts[0]
        store.delete(account: account)
        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertNil(KeychainHelper.load(key: account.keychainKey))
    }

    func test_update_updatesFieldsAndToken() {
        let store = AccountStore(defaults: defaults)
        store.add(name: "Old", username: "old", orgFilter: "", token: "old_token")
        var updated = store.accounts[0]
        updated.name = "New"
        updated.username = "new"
        store.update(account: updated, token: "new_token")
        XCTAssertEqual(store.accounts[0].name, "New")
        XCTAssertEqual(store.accounts[0].username, "new")
        XCTAssertEqual(KeychainHelper.load(key: updated.keychainKey), "new_token")
    }

    func test_update_preservesTokenWhenNilPassed() {
        let store = AccountStore(defaults: defaults)
        store.add(name: "Old", username: "old", orgFilter: "", token: "existing_token")
        var updated = store.accounts[0]
        updated.name = "Renamed"
        store.update(account: updated, token: nil)
        XCTAssertEqual(KeychainHelper.load(key: updated.keychainKey), "existing_token")
    }

    func test_migrateIfNeeded_promotesOldKeys() {
        KeychainHelper.save(key: "github_pat", value: "old_token")
        defaults.set("olduser", forKey: "github_username")
        defaults.set("oldorg", forKey: "github_org_filter")
        defer { KeychainHelper.delete(key: "github_pat") }

        let store = AccountStore(defaults: defaults)
        store.migrateIfNeeded()

        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.accounts[0].name, "Account 1")
        XCTAssertEqual(store.accounts[0].username, "olduser")
        XCTAssertEqual(store.accounts[0].orgFilter, "oldorg")
        XCTAssertEqual(KeychainHelper.load(key: store.accounts[0].keychainKey), "old_token")
        XCTAssertNil(KeychainHelper.load(key: "github_pat"))
        XCTAssertNil(defaults.string(forKey: "github_username"))
        XCTAssertNil(defaults.string(forKey: "github_org_filter"))
    }

    func test_migrateIfNeeded_isNoOpIfAccountsKeyExists() {
        let store = AccountStore(defaults: defaults)
        store.add(name: "Existing", username: "u", orgFilter: "", token: "tok")
        let countBefore = store.accounts.count

        store.migrateIfNeeded()

        XCTAssertEqual(store.accounts.count, countBefore)
    }

    func test_migrateIfNeeded_startsEmptyWhenNoOldData() {
        let store = AccountStore(defaults: defaults)
        store.migrateIfNeeded()
        XCTAssertTrue(store.accounts.isEmpty)
    }

    func test_persistsAcrossInstances() {
        let store1 = AccountStore(defaults: defaults)
        store1.add(name: "Persist", username: "u", orgFilter: "", token: "tok")
        let key = store1.accounts[0].keychainKey

        let store2 = AccountStore(defaults: defaults)
        XCTAssertEqual(store2.accounts.count, 1)
        XCTAssertEqual(store2.accounts[0].name, "Persist")
        KeychainHelper.delete(key: key)
    }
}
