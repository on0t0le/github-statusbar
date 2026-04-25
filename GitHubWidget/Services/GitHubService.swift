import Foundation

protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

protocol GitHubServiceProtocol: Sendable {
    func fetchPRs(token: String, username: String, orgFilter: String) async throws -> PRFetchResult
}

actor GitHubService: GitHubServiceProtocol {
    static let shared = GitHubService()

    private let session: URLSessionProtocol

    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    func fetchPRs(token: String, username: String, orgFilter: String) async throws -> PRFetchResult {
        async let reviewRequested = search(
            query: buildQuery("is:pr review-requested:@me state:open", orgFilter: orgFilter),
            token: token
        )
        async let changesRequested = search(
            query: buildQuery("is:pr author:@me review:changes_requested state:open", orgFilter: orgFilter),
            token: token
        )
        async let assigned = search(
            query: buildQuery("is:pr assignee:@me state:open", orgFilter: orgFilter),
            token: token
        )
        async let readyToMerge = search(
            query: buildQuery("is:pr author:@me review:approved state:open", orgFilter: orgFilter),
            token: token
        )

        let (rr, cr, a, rtm) = try await (reviewRequested, changesRequested, assigned, readyToMerge)

        var crActive: [PullRequest] = []
        var crPending: [PullRequest] = []
        await withTaskGroup(of: (PullRequest, Bool).self) { group in
            for pr in cr {
                group.addTask { (pr, await self.hasReviewRequests(pr: pr, token: token)) }
            }
            for await (pr, pending) in group {
                if pending { crPending.append(pr) } else { crActive.append(pr) }
            }
        }

        return PRFetchResult(
            reviewRequested: rr,
            changesRequested: crActive,
            changesRequestedPending: crPending,
            assigned: a,
            readyToMerge: rtm
        )
    }

    private struct PRDetail: Decodable {
        let requestedReviewers: [GitHubUser]
        enum CodingKeys: String, CodingKey {
            case requestedReviewers = "requested_reviewers"
        }
    }

    private func hasReviewRequests(pr: PullRequest, token: String) async -> Bool {
        guard let url = URL(string: "\(pr.repositoryUrl)/pulls/\(pr.number)") else { return false }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let detail = try? JSONDecoder().decode(PRDetail.self, from: data) else {
            return false
        }
        return !detail.requestedReviewers.isEmpty
    }

    private func buildQuery(_ base: String, orgFilter: String) -> String {
        guard !orgFilter.isEmpty else { return base }
        if orgFilter.contains("/") {
            return "\(base) repo:\(orgFilter)"
        } else {
            return "\(base) org:\(orgFilter)"
        }
    }

    private func search(query: String, token: String) async throws -> [PullRequest] {
        var components = URLComponents(string: "https://api.github.com/search/issues")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: "50")
        ]
        guard let url = components.url else { throw GitHubError.networkError }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubError.networkError
        }

        guard let http = response as? HTTPURLResponse else { throw GitHubError.networkError }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(GitHubSearchResponse.self, from: data).items
            } catch {
                throw GitHubError.decodingError
            }
        case 401:
            throw GitHubError.unauthorized
        case 403, 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw GitHubError.rateLimited(retryAfter: retryAfter)
        default:
            throw GitHubError.networkError
        }
    }
}
