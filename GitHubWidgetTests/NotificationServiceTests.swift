import XCTest
@testable import GitHubWidget

final class NotificationServiceTests: XCTestCase {
    private let service = NotificationService.shared

    private func makeResult(
        reviewRequested: [PullRequest] = [],
        changesRequested: [PullRequest] = [],
        assigned: [PullRequest] = [],
        readyToMerge: [PullRequest] = []
    ) -> PRFetchResult {
        PRFetchResult(
            reviewRequested: reviewRequested,
            changesRequested: changesRequested,
            assigned: assigned,
            readyToMerge: readyToMerge
        )
    }

    func test_diff_returnsEmpty_whenOldIsNil() {
        let new = makeResult(reviewRequested: [.fixture(id: 1)])
        XCTAssertTrue(service.diff(old: nil, new: new, username: "testuser").isEmpty)
    }

    func test_diff_detectsNewReviewRequest() {
        let old = makeResult()
        let new = makeResult(reviewRequested: [.fixture(id: 42)])
        XCTAssertEqual(service.diff(old: old, new: new, username: "me"), [42])
    }

    func test_diff_detectsNewChangesRequested() {
        let old = makeResult()
        let new = makeResult(changesRequested: [.fixture(id: 7)])
        XCTAssertEqual(service.diff(old: old, new: new, username: "me"), [7])
    }

    func test_diff_detectsApprovedForMyPR() {
        // PullRequest.fixture user.login is "testuser"
        let old = makeResult()
        let new = makeResult(readyToMerge: [.fixture(id: 99)])
        XCTAssertEqual(service.diff(old: old, new: new, username: "testuser"), [99])
    }

    func test_diff_skipsApprovedWhenUsernameDoesNotMatch() {
        let old = makeResult()
        let new = makeResult(readyToMerge: [.fixture(id: 99)])
        // fixture login is "testuser", username is "other" → no match
        XCTAssertTrue(service.diff(old: old, new: new, username: "other").isEmpty)
    }

    func test_diff_deduplicates_samePRInMultipleCategories() {
        let old = makeResult()
        let pr = PullRequest.fixture(id: 5)
        let new = makeResult(reviewRequested: [pr], changesRequested: [pr])
        XCTAssertEqual(service.diff(old: old, new: new, username: "me"), [5])
    }

    func test_diff_ignoresAlreadyKnownPRs() {
        let pr = PullRequest.fixture(id: 3)
        let old = makeResult(reviewRequested: [pr])
        let new = makeResult(reviewRequested: [pr])
        XCTAssertTrue(service.diff(old: old, new: new, username: "me").isEmpty)
    }
}
