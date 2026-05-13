import XCTest
@testable import GitHubWidget

@MainActor
final class PRStoreTests: XCTestCase {

    func test_refresh_setsNotConfiguredError_whenNoPAT() async {
        let account = Account.fixture()
        let store = PRStore(account: account, service: MockGitHubService())
        KeychainHelper.delete(key: account.keychainKey)

        await store.refresh()

        XCTAssertEqual(store.error, .notConfigured)
        XCTAssertTrue(store.waitingOnMe.isEmpty)
    }

    func test_refresh_populatesCategories_onSuccess() async {
        let account = Account.fixture()
        let waiting = PullRequest.fixture(id: 1)
        let ready = PullRequest.fixture(id: 2)
        let inProg = PullRequest.fixture(id: 3)
        let mockResult = PRFetchResult(
            reviewRequested: [waiting],
            changesRequested: [],
            assigned: [inProg],
            readyToMerge: [ready]
        )
        let store = PRStore(account: account, service: MockGitHubService(result: mockResult))
        KeychainHelper.save(key: account.keychainKey, value: "test-token")
        defer { KeychainHelper.delete(key: account.keychainKey) }

        await store.refresh()

        XCTAssertNil(store.error)
        XCTAssertEqual(store.waitingOnMe.count, 1)
        XCTAssertEqual(store.readyToMerge.count, 1)
        XCTAssertEqual(store.inProgress.count, 1)
        XCTAssertNotNil(store.lastUpdated)
    }

    func test_refresh_setsError_onServiceThrow() async {
        let account = Account.fixture()
        let store = PRStore(account: account, service: MockGitHubService(error: .unauthorized))
        KeychainHelper.save(key: account.keychainKey, value: "bad-token")
        defer { KeychainHelper.delete(key: account.keychainKey) }

        await store.refresh()

        XCTAssertEqual(store.error, .unauthorized)
    }

    func test_totalCount_sumsCategoryLengths() async {
        let account = Account.fixture()
        let mockResult = PRFetchResult(
            reviewRequested: [.fixture(id: 1), .fixture(id: 2)],
            changesRequested: [],
            assigned: [.fixture(id: 3)],
            readyToMerge: []
        )
        let store = PRStore(account: account, service: MockGitHubService(result: mockResult))
        KeychainHelper.save(key: account.keychainKey, value: "token")
        defer { KeychainHelper.delete(key: account.keychainKey) }

        await store.refresh()

        XCTAssertEqual(store.totalCount, 3)
    }
}

// MARK: - MockGitHubService

final class MockGitHubService: GitHubServiceProtocol, @unchecked Sendable {
    private let result: PRFetchResult?
    private let error: GitHubError?

    init(
        result: PRFetchResult = PRFetchResult(reviewRequested: [], changesRequested: [], assigned: [], readyToMerge: []),
        error: GitHubError? = nil
    ) {
        self.result = result
        self.error = error
    }

    func fetchPRs(token: String, username: String, orgFilter: String) async throws -> PRFetchResult {
        if let error { throw error }
        return result!
    }

    func fetchEnrichments(prs: [PullRequest], token: String) async -> [Int: PREnrichment] { [:] }
}

// MARK: - MockNotificationService

final class MockNotificationService: NotificationServiceProtocol, @unchecked Sendable {
    var diffResult: Set<Int>
    var permissionRequested = false

    init(diffResult: Set<Int> = []) {
        self.diffResult = diffResult
    }

    func requestPermission() async -> Bool {
        permissionRequested = true
        return true
    }

    func diff(old: PRFetchResult?, new: PRFetchResult, username: String) -> Set<Int> { diffResult }
}

// MARK: - Notification tests

extension PRStoreTests {

    func test_markAllSeen_clearsUnseenPRIds() async {
        let account = Account.fixture()
        let mockNotif = MockNotificationService(diffResult: [1, 2])
        let store = PRStore(account: account, service: MockGitHubService(), notificationService: mockNotif)
        UserDefaults.standard.set(true, forKey: "notifications_enabled")
        defer { UserDefaults.standard.removeObject(forKey: "notifications_enabled") }
        KeychainHelper.save(key: account.keychainKey, value: "token")
        defer { KeychainHelper.delete(key: account.keychainKey) }

        await store.refresh()
        XCTAssertEqual(store.unseenPRIds, [1, 2])

        store.markAllSeen()
        XCTAssertTrue(store.unseenPRIds.isEmpty)
    }

    func test_unseenPRIds_accumulatesAcrossRefreshes() async {
        let account = Account.fixture()
        let mockNotif = MockNotificationService(diffResult: [1])
        let store = PRStore(account: account, service: MockGitHubService(), notificationService: mockNotif)
        UserDefaults.standard.set(true, forKey: "notifications_enabled")
        defer { UserDefaults.standard.removeObject(forKey: "notifications_enabled") }
        KeychainHelper.save(key: account.keychainKey, value: "token")
        defer { KeychainHelper.delete(key: account.keychainKey) }

        await store.refresh()
        mockNotif.diffResult = [2]
        await store.refresh()

        XCTAssertEqual(store.unseenPRIds, [1, 2])
    }

    func test_unseenPRIds_notPopulated_whenNotificationsDisabled() async {
        let account = Account.fixture()
        let mockNotif = MockNotificationService(diffResult: [99])
        let store = PRStore(account: account, service: MockGitHubService(), notificationService: mockNotif)
        UserDefaults.standard.set(false, forKey: "notifications_enabled")
        defer { UserDefaults.standard.removeObject(forKey: "notifications_enabled") }
        KeychainHelper.save(key: account.keychainKey, value: "token")
        defer { KeychainHelper.delete(key: account.keychainKey) }

        await store.refresh()
        XCTAssertTrue(store.unseenPRIds.isEmpty)
    }
}
