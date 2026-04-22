import XCTest
@testable import GitHubWidget

@MainActor
final class PRStoreTests: XCTestCase {

    func test_refresh_setsNotConfiguredError_whenNoPAT() async {
        let store = PRStore(service: MockGitHubService())
        KeychainHelper.delete(key: "github_pat")

        await store.refresh()

        XCTAssertEqual(store.error, .notConfigured)
        XCTAssertTrue(store.waitingOnMe.isEmpty)
    }

    func test_refresh_populatesCategories_onSuccess() async {
        let waiting = PullRequest.fixture(id: 1)
        let ready = PullRequest.fixture(id: 2)
        let inProg = PullRequest.fixture(id: 3)
        let mockResult = PRFetchResult(
            reviewRequested: [waiting],
            changesRequested: [],
            assigned: [inProg],
            readyToMerge: [ready]
        )
        let service = MockGitHubService(result: mockResult)
        let store = PRStore(service: service)
        KeychainHelper.save(key: "github_pat", value: "test-token")
        defer { KeychainHelper.delete(key: "github_pat") }

        await store.refresh()

        XCTAssertNil(store.error)
        XCTAssertEqual(store.waitingOnMe.count, 1)
        XCTAssertEqual(store.readyToMerge.count, 1)
        XCTAssertEqual(store.inProgress.count, 1)
        XCTAssertNotNil(store.lastUpdated)
    }

    func test_refresh_setsError_onServiceThrow() async {
        let service = MockGitHubService(error: .unauthorized)
        let store = PRStore(service: service)
        KeychainHelper.save(key: "github_pat", value: "bad-token")
        defer { KeychainHelper.delete(key: "github_pat") }

        await store.refresh()

        XCTAssertEqual(store.error, .unauthorized)
    }

    func test_totalCount_sumsCategoryLengths() async {
        let mockResult = PRFetchResult(
            reviewRequested: [.fixture(id: 1), .fixture(id: 2)],
            changesRequested: [],
            assigned: [.fixture(id: 3)],
            readyToMerge: []
        )
        let store = PRStore(service: MockGitHubService(result: mockResult))
        KeychainHelper.save(key: "github_pat", value: "token")
        defer { KeychainHelper.delete(key: "github_pat") }

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
}
