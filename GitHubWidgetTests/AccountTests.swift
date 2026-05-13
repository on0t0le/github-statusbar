import XCTest
@testable import GitHubWidget

final class AccountTests: XCTestCase {

    func test_keychainKey_includesUUID() {
        let id = UUID()
        let account = Account(id: id, name: "Work", username: "bob", orgFilter: "")
        XCTAssertEqual(account.keychainKey, "github_pat_\(id.uuidString)")
    }

    func test_codable_roundtrips() throws {
        let id = UUID()
        let account = Account(id: id, name: "Personal", username: "alice", orgFilter: "myorg")
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Personal")
        XCTAssertEqual(decoded.username, "alice")
        XCTAssertEqual(decoded.orgFilter, "myorg")
    }
}

extension Account {
    static func fixture(
        id: UUID = UUID(),
        name: String = "Test Account",
        username: String = "testuser",
        orgFilter: String = ""
    ) -> Account {
        Account(id: id, name: name, username: username, orgFilter: orgFilter)
    }
}
