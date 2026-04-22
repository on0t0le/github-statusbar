import XCTest
@testable import GitHubWidget

final class PullRequestTests: XCTestCase {

    // MARK: - JSON decoding

    func test_pullRequest_decodesFromJSON() throws {
        let json = """
        {
            "id": 1,
            "number": 42,
            "title": "Fix auth bug",
            "html_url": "https://github.com/org/repo/pull/42",
            "repository_url": "https://api.github.com/repos/org/repo",
            "draft": false,
            "labels": [],
            "user": { "login": "bob", "avatar_url": "https://avatars.githubusercontent.com/u/1" }
        }
        """.data(using: .utf8)!

        let pr = try JSONDecoder().decode(PullRequest.self, from: json)

        XCTAssertEqual(pr.id, 1)
        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.title, "Fix auth bug")
        XCTAssertEqual(pr.htmlUrl, "https://github.com/org/repo/pull/42")
        XCTAssertEqual(pr.user.login, "bob")
        XCTAssertFalse(pr.draft)
    }

    func test_pullRequest_repoName_extractsFromRepositoryUrl() {
        let pr = PullRequest.fixture(repositoryUrl: "https://api.github.com/repos/myorg/myrepo")
        XCTAssertEqual(pr.repoName, "myorg/myrepo")
    }

    func test_pullRequest_repoName_fallsBackWhenUrlMalformed() {
        let pr = PullRequest.fixture(repositoryUrl: "bad-url")
        XCTAssertEqual(pr.repoName, "bad-url")
    }

    // MARK: - PRFetchResult categorization

    func test_fetchResult_waitingOnMe_deduplicatesAcrossQueries() {
        let pr = PullRequest.fixture(id: 1)
        let result = PRFetchResult(
            reviewRequested: [pr],
            changesRequested: [pr],
            assigned: [],
            readyToMerge: []
        )
        XCTAssertEqual(result.waitingOnMe.count, 1)
    }

    func test_fetchResult_readyToMerge_excludesWaitingOnMe() {
        let pr = PullRequest.fixture(id: 1)
        let result = PRFetchResult(
            reviewRequested: [pr],
            changesRequested: [],
            assigned: [],
            readyToMerge: [pr]
        )
        XCTAssertTrue(result.readyToMergeDeduped.isEmpty)
    }

    func test_fetchResult_inProgress_excludesWaitingAndReady() {
        let waiting = PullRequest.fixture(id: 1)
        let ready = PullRequest.fixture(id: 2)
        let inProgressPR = PullRequest.fixture(id: 3)
        let result = PRFetchResult(
            reviewRequested: [waiting],
            changesRequested: [],
            assigned: [waiting, ready, inProgressPR],
            readyToMerge: [ready]
        )
        XCTAssertEqual(result.inProgress.count, 1)
        XCTAssertEqual(result.inProgress[0].id, 3)
    }

    func test_fetchResult_allPRs_deduplicatesAll() {
        let pr = PullRequest.fixture(id: 1)
        let result = PRFetchResult(
            reviewRequested: [pr],
            changesRequested: [pr],
            assigned: [pr],
            readyToMerge: [pr]
        )
        XCTAssertEqual(result.allPRs.count, 1)
    }
}

// MARK: - Fixtures

extension PullRequest {
    static func fixture(
        id: Int = 1,
        number: Int = 1,
        title: String = "Test PR",
        htmlUrl: String = "https://github.com/org/repo/pull/1",
        repositoryUrl: String = "https://api.github.com/repos/org/repo",
        draft: Bool = false
    ) -> PullRequest {
        PullRequest(
            id: id,
            number: number,
            title: title,
            htmlUrl: htmlUrl,
            repositoryUrl: repositoryUrl,
            user: GitHubUser(login: "testuser", avatarUrl: "https://example.com/avatar.png"),
            draft: draft,
            labels: []
        )
    }
}
