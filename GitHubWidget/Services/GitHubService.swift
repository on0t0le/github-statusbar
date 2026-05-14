import Foundation

protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

protocol GitHubServiceProtocol: Sendable {
    func fetchPRs(token: String, username: String, orgFilter: String) async throws -> PRFetchResult
    func fetchEnrichments(prs: [PullRequest], token: String) async -> [Int: PREnrichment]
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
        let requestedTeams: [GitHubTeam]
        let head: PRHead
        struct PRHead: Decodable { let sha: String }
        enum CodingKeys: String, CodingKey {
            case requestedReviewers = "requested_reviewers"
            case requestedTeams = "requested_teams"
            case head
        }
    }

    private struct PRReview: Decodable {
        let state: String
        let user: GitHubUser?
    }

    private struct PRTimelineEvent: Decodable {
        let event: String
        let requestedReviewer: GitHubUser?
        let requestedTeam: GitHubTeam?
        enum CodingKeys: String, CodingKey {
            case event
            case requestedReviewer = "requested_reviewer"
            case requestedTeam = "requested_team"
        }
    }

    private struct CheckRunsResponse: Decodable {
        let checkRuns: [CheckRun]
        struct CheckRun: Decodable {
            let conclusion: String?
        }
        enum CodingKeys: String, CodingKey {
            case checkRuns = "check_runs"
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
        return !detail.requestedReviewers.isEmpty || !detail.requestedTeams.isEmpty
    }

    func fetchEnrichments(prs: [PullRequest], token: String) async -> [Int: PREnrichment] {
        var results: [Int: PREnrichment] = [:]
        await withTaskGroup(of: (Int, PREnrichment?).self) { group in
            for pr in prs {
                group.addTask { (pr.id, await self.enrichPR(pr: pr, token: token)) }
            }
            for await (id, enrichment) in group {
                if let e = enrichment { results[id] = e }
            }
        }
        return results
    }

    private func enrichPR(pr: PullRequest, token: String) async -> PREnrichment? {
        guard let detailURL = URL(string: "\(pr.repositoryUrl)/pulls/\(pr.number)") else { return nil }
        var detailReq = URLRequest(url: detailURL)
        detailReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        detailReq.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        guard let (detailData, detailResp) = try? await session.data(for: detailReq),
              let http = detailResp as? HTTPURLResponse, http.statusCode == 200,
              let detail = try? JSONDecoder().decode(PRDetail.self, from: detailData) else { return nil }

        async let reviewsResult = fetchReviews(pr: pr, token: token)
        async let checksResult = fetchCheckRuns(repositoryUrl: pr.repositoryUrl, sha: detail.head.sha, token: token)
        async let timelineResult = fetchTimeline(pr: pr, token: token)
        let (reviews, checks, timeline) = await (reviewsResult, checksResult, timelineResult)

        var latestByUser: [String: String] = [:]
        for review in reviews {
            guard let login = review.user?.login else { continue }
            if review.state != "COMMENTED" {
                latestByUser[login] = review.state
            } else if latestByUser[login] == nil {
                latestByUser[login] = review.state
            }
        }
        let totalApproved = latestByUser.values.filter { $0 == "APPROVED" }.count

        var originalIndividuals = Set<String>()
        var originalTeams = Set<String>()
        for event in timeline {
            switch event.event {
            case "review_requested":
                if let u = event.requestedReviewer { originalIndividuals.insert(u.login) }
                if let t = event.requestedTeam { originalTeams.insert(t.slug) }
            case "review_request_removed":
                if let u = event.requestedReviewer { originalIndividuals.remove(u.login) }
                if let t = event.requestedTeam { originalTeams.remove(t.slug) }
            default: break
            }
        }

        let totalRequested = originalIndividuals.count + originalTeams.count
        let approvedReviewers: Int
        let totalReviewers: Int
        if totalRequested == 0 {
            approvedReviewers = totalApproved
            totalReviewers = totalApproved
        } else {
            let pendingIndividuals = detail.requestedReviewers.count
            let pendingTeams = detail.requestedTeams.count
            let satisfiedIndividuals = max(0, originalIndividuals.count - pendingIndividuals)
            let satisfiedTeams = max(0, originalTeams.count - pendingTeams)
            approvedReviewers = satisfiedIndividuals + satisfiedTeams
            totalReviewers = totalRequested
        }

        return PREnrichment(
            approvedReviewers: approvedReviewers,
            totalReviewers: totalReviewers,
            checksPassed: checks.passed,
            checksFailed: checks.failed,
            checksTotal: checks.total
        )
    }

    private func fetchReviews(pr: PullRequest, token: String) async -> [PRReview] {
        guard let url = URL(string: "\(pr.repositoryUrl)/pulls/\(pr.number)/reviews") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let reviews = try? JSONDecoder().decode([PRReview].self, from: data) else { return [] }
        return reviews
    }

    private func fetchTimeline(pr: PullRequest, token: String) async -> [PRTimelineEvent] {
        guard let url = URL(string: "\(pr.repositoryUrl)/issues/\(pr.number)/timeline?per_page=100") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let events = try? JSONDecoder().decode([PRTimelineEvent].self, from: data) else { return [] }
        return events
    }

    private func fetchCheckRuns(repositoryUrl: String, sha: String, token: String) async -> (passed: Int, failed: Int, total: Int) {
        guard let url = URL(string: "\(repositoryUrl)/commits/\(sha)/check-runs?per_page=100") else { return (0, 0, 0) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let result = try? JSONDecoder().decode(CheckRunsResponse.self, from: data) else { return (0, 0, 0) }
        let relevant = result.checkRuns.filter { !["skipped", "neutral"].contains($0.conclusion ?? "") }
        let passed = relevant.filter { $0.conclusion == "success" }.count
        let failed = relevant.filter { ["failure", "timed_out", "action_required"].contains($0.conclusion ?? "") }.count
        return (passed, failed, relevant.count)
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
