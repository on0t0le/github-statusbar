import XCTest
@testable import GitHubWidget

final class GitHubServiceTests: XCTestCase {

    // MARK: - Successful fetch

    func test_fetchPRs_parsesSearchResponse() async throws {
        let json = searchResponseJSON(items: [pullRequestJSON(id: 1)])
        let session = MockURLSession(responseData: json, statusCode: 200)
        let service = GitHubService(session: session)

        let result = try await service.fetchPRs(token: "tok", username: "me", orgFilter: "")

        XCTAssertEqual(result.reviewRequested.count, 1)
        XCTAssertEqual(result.reviewRequested[0].id, 1)
    }

    func test_fetchPRs_deduplicatesSamePRacrossQueries() async throws {
        let json = searchResponseJSON(items: [pullRequestJSON(id: 99)])
        let session = MockURLSession(responseData: json, statusCode: 200)
        let service = GitHubService(session: session)

        let result = try await service.fetchPRs(token: "tok", username: "me", orgFilter: "")

        XCTAssertEqual(result.allPRs.count, 1)
    }

    // MARK: - Error mapping

    func test_fetchPRs_throws_unauthorized_on401() async {
        let session = MockURLSession(responseData: Data(), statusCode: 401)
        let service = GitHubService(session: session)

        do {
            _ = try await service.fetchPRs(token: "bad", username: "me", orgFilter: "")
            XCTFail("Expected throw")
        } catch let error as GitHubError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func test_fetchPRs_throws_rateLimited_on429() async {
        let session = MockURLSession(responseData: Data(), statusCode: 429, retryAfter: "120")
        let service = GitHubService(session: session)

        do {
            _ = try await service.fetchPRs(token: "tok", username: "me", orgFilter: "")
            XCTFail("Expected throw")
        } catch let error as GitHubError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 120))
        }
    }

    func test_fetchPRs_throws_decodingError_onBadJSON() async {
        let session = MockURLSession(responseData: Data("not json".utf8), statusCode: 200)
        let service = GitHubService(session: session)

        do {
            _ = try await service.fetchPRs(token: "tok", username: "me", orgFilter: "")
            XCTFail("Expected throw")
        } catch let error as GitHubError {
            XCTAssertEqual(error, .decodingError)
        }
    }

    // MARK: - Org filter

    func test_fetchPRs_appendsOrgFilterToQuery() async throws {
        let json = searchResponseJSON(items: [])
        let session = MockURLSession(responseData: json, statusCode: 200)
        let service = GitHubService(session: session)

        _ = try await service.fetchPRs(token: "tok", username: "me", orgFilter: "myorg")

        let urls = session.capturedRequests.map { $0.url?.absoluteString ?? "" }
        XCTAssert(urls.allSatisfy { $0.contains("org%3Amyorg") || $0.contains("org:myorg") })
    }

    func test_fetchPRs_appendsRepoFilterToQuery() async throws {
        let json = searchResponseJSON(items: [])
        let session = MockURLSession(responseData: json, statusCode: 200)
        let service = GitHubService(session: session)

        _ = try await service.fetchPRs(token: "tok", username: "me", orgFilter: "myorg/myrepo")

        let urls = session.capturedRequests.map { $0.url?.absoluteString ?? "" }
        XCTAssert(urls.allSatisfy { $0.contains("repo%3Amyorg") || $0.contains("repo:myorg") })
    }
}

// MARK: - Helpers

private func searchResponseJSON(items: [String]) -> Data {
    let itemsJSON = items.joined(separator: ",")
    return """
    {"total_count": \(items.count), "incomplete_results": false, "items": [\(itemsJSON)]}
    """.data(using: .utf8)!
}

private func pullRequestJSON(id: Int) -> String {
    """
    {
        "id": \(id),
        "number": \(id),
        "title": "PR \(id)",
        "html_url": "https://github.com/org/repo/pull/\(id)",
        "repository_url": "https://api.github.com/repos/org/repo",
        "draft": false,
        "labels": [],
        "user": { "login": "alice", "avatar_url": "https://example.com/avatar.png" }
    }
    """
}

// MARK: - MockURLSession

final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    private let responseData: Data
    private let statusCode: Int
    private let retryAfter: String?
    private(set) var capturedRequests: [URLRequest] = []

    init(responseData: Data, statusCode: Int, retryAfter: String? = nil) {
        self.responseData = responseData
        self.statusCode = statusCode
        self.retryAfter = retryAfter
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequests.append(request)
        var headers: [String: String] = [:]
        if let ra = retryAfter { headers["Retry-After"] = ra }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        return (responseData, response)
    }
}
