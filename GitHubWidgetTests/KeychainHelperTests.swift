import XCTest
@testable import GitHubWidget

final class KeychainHelperTests: XCTestCase {
    private let testKey = "test_keychain_key_\(UUID().uuidString)"

    override func tearDown() {
        super.tearDown()
        KeychainHelper.delete(key: testKey)
    }

    func test_saveAndLoad_roundtrips() {
        KeychainHelper.save(key: testKey, value: "secret-token")
        XCTAssertEqual(KeychainHelper.load(key: testKey), "secret-token")
    }

    func test_load_returnsNilForMissingKey() {
        XCTAssertNil(KeychainHelper.load(key: testKey))
    }

    func test_save_overwritesExistingValue() {
        KeychainHelper.save(key: testKey, value: "old-value")
        KeychainHelper.save(key: testKey, value: "new-value")
        XCTAssertEqual(KeychainHelper.load(key: testKey), "new-value")
    }

    func test_delete_removesValue() {
        KeychainHelper.save(key: testKey, value: "to-delete")
        KeychainHelper.delete(key: testKey)
        XCTAssertNil(KeychainHelper.load(key: testKey))
    }
}
