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

    init(session: URLSessionProtocol = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()) {
        self.session = session
    }

    func fetchPRs(token: String, username: String, orgFilter: String) async throws -> PRFetchResult {
        let log = DiagnosticLogger.shared
        log.log("[fetchPRs] start username=\(username) orgFilter='\(orgFilter)'")

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
        log.log("[fetchPRs] search results: reviewRequested=\(rr.count) changesRequested=\(cr.count) assigned=\(a.count) readyToMerge=\(rtm.count)")

        // GitHub search index lags after a review is submitted.
        // Cross-check reviewRequested against actual reviews to drop PRs the user already acted on.
        let filteredRR = await filterAlreadyReviewed(prs: rr, username: username, token: token)
        if filteredRR.count != rr.count {
            let removed = rr.filter { pr in !filteredRR.contains(where: { $0.id == pr.id }) }
            log.log("[fetchPRs] filtered \(rr.count - filteredRR.count) already-reviewed PRs: \(removed.map { "#\(String($0.number)) \($0.repoName)" }.joined(separator: ", "))")
        }

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
        log.log("[fetchPRs] final: reviewRequested=\(filteredRR.count) crActive=\(crActive.count) crPending=\(crPending.count) assigned=\(a.count) readyToMerge=\(rtm.count)")

        return PRFetchResult(
            reviewRequested: filteredRR,
            changesRequested: crActive,
            changesRequestedPending: crPending,
            assigned: a,
            readyToMerge: rtm
        )
    }

    private func filterAlreadyReviewed(prs: [PullRequest], username: String, token: String) async -> [PullRequest] {
        var result: [PullRequest] = []
        await withTaskGroup(of: (PullRequest, Bool).self) { group in
            for pr in prs {
                group.addTask {
                    let reviews = await self.fetchReviews(pr: pr, token: token)
                    var latestState: String? = nil
                    for review in reviews {
                        guard review.user?.login == username else { continue }
                        if review.state != "COMMENTED" && review.state != "PENDING" {
                            latestState = review.state
                        } else if latestState == nil && review.state == "COMMENTED" {
                            latestState = review.state
                        }
                    }
                    let alreadyActed = latestState == "APPROVED" || latestState == "CHANGES_REQUESTED"
                    DiagnosticLogger.shared.log("[filterAlreadyReviewed] PR#\(pr.number) \(pr.repoName) latestReview=\(latestState ?? "nil") filtered=\(alreadyActed)")
                    return (pr, !alreadyActed)
                }
            }
            for await (pr, needsReview) in group {
                if needsReview { result.append(pr) }
            }
        }
        return result
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

    private struct GraphQLReviewNode: Decodable {
        let state: String
        let onBehalfOf: TeamConnection?
        struct TeamConnection: Decodable {
            let nodes: [TeamNode]
        }
        struct TeamNode: Decodable {
            let slug: String
        }
    }

    private struct GraphQLPRData {
        let reviewNodes: [GraphQLReviewNode]
        let pendingTeamSlugs: Set<String>
        let reviewDecision: String?
    }

    private struct GraphQLResponse: Decodable {
        let data: GraphQLData?
        struct GraphQLData: Decodable {
            let repository: RepositoryData?
            struct RepositoryData: Decodable {
                let pullRequest: PRData?
            }
            struct PRData: Decodable {
                let latestOpinionatedReviews: ReviewConnection?
                let reviewRequests: ReviewRequestConnection?
                let reviewDecision: String?
                struct ReviewConnection: Decodable {
                    let nodes: [GraphQLReviewNode]
                }
                struct ReviewRequestConnection: Decodable {
                    let nodes: [ReviewRequestNode]
                }
                struct ReviewRequestNode: Decodable {
                    let requestedReviewer: RequestedReviewer?
                    struct RequestedReviewer: Decodable {
                        let slug: String?
                        enum CodingKeys: String, CodingKey { case slug }
                    }
                }
            }
        }
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

    private struct TeamMember: Decodable {
        let login: String
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

        let urlParts = pr.repositoryUrl.split(separator: "/")
        let owner = urlParts.count >= 2 ? String(urlParts[urlParts.count - 2]) : ""
        let repo = urlParts.count >= 1 ? String(urlParts[urlParts.count - 1]) : ""

        async let reviewsResult = fetchReviews(pr: pr, token: token)
        async let checksResult = fetchCheckRuns(repositoryUrl: pr.repositoryUrl, sha: detail.head.sha, token: token)
        async let timelineResult = fetchTimeline(pr: pr, token: token)
        async let graphqlDataResult = fetchGraphQLReviews(owner: owner, repo: repo, number: pr.number, token: token)
        let (reviews, checks, timeline, graphqlData) = await (reviewsResult, checksResult, timelineResult, graphqlDataResult)

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

        // Real-time signals from PR detail: team/individual removed immediately on review submit
        let prDetailPendingTeams = Set(detail.requestedTeams.map(\.slug))
        let prDetailPendingIndividuals = Set(detail.requestedReviewers.map(\.login))

        // Both sources from the same GraphQL snapshot — consistent with each other
        var teamsApprovedViaOnBehalfOf = Set<String>()
        for node in graphqlData.reviewNodes where node.state == "APPROVED" {
            for team in node.onBehalfOf?.nodes ?? [] {
                teamsApprovedViaOnBehalfOf.insert(team.slug)
            }
        }
        let graphqlPendingTeams = graphqlData.pendingTeamSlugs

        // Only do membership lookup for teams pending in BOTH GraphQL AND real-time PR detail
        let teamsNeedingMembershipCheck = originalTeams.filter {
            graphqlPendingTeams.contains($0) &&
            prDetailPendingTeams.contains($0) &&
            !teamsApprovedViaOnBehalfOf.contains($0)
        }
        var teamsApprovedViaMembership = Set<String>()
        await withTaskGroup(of: (String, Set<String>).self) { group in
            for slug in teamsNeedingMembershipCheck {
                group.addTask { (slug, await self.fetchTeamMembers(org: owner, teamSlug: slug, token: token)) }
            }
            for await (slug, members) in group {
                if members.contains(where: { latestByUser[$0] == "APPROVED" }) {
                    teamsApprovedViaMembership.insert(slug)
                }
            }
        }

        let log = DiagnosticLogger.shared
        log.log("[enrichPR] PR#\(pr.number) \(owner)/\(repo)")
        log.log("  latestByUser: \(latestByUser)")
        log.log("  originalTeams: \(originalTeams), originalIndividuals: \(originalIndividuals)")
        log.log("  prDetailPending teams: \(prDetailPendingTeams), individuals: \(prDetailPendingIndividuals)")
        log.log("  graphqlPending: \(graphqlPendingTeams), onBehalfOf: \(teamsApprovedViaOnBehalfOf), membership: \(teamsApprovedViaMembership)")
        log.log("  graphqlReviewNodes: \(graphqlData.reviewNodes.map { "\($0.state) onBehalfOf:\($0.onBehalfOf?.nodes.map(\.slug) ?? [])" })")
        log.log("  reviewDecision: \(graphqlData.reviewDecision ?? "nil")")

        let totalRequested = originalIndividuals.count + originalTeams.count
        let approvedReviewers: Int
        let totalReviewers: Int
        if totalRequested == 0 {
            approvedReviewers = totalApproved
            totalReviewers = totalApproved
        } else {
            let approvedIndividualLogins = originalIndividuals.filter { login in
                latestByUser[login] == "APPROVED" || !prDetailPendingIndividuals.contains(login)
            }
            let satisfiedTeamSlugs = originalTeams.filter { slug in
                !graphqlPendingTeams.contains(slug) ||
                !prDetailPendingTeams.contains(slug) ||
                teamsApprovedViaOnBehalfOf.contains(slug) ||
                teamsApprovedViaMembership.contains(slug)
            }
            let granularApproved = approvedIndividualLogins.count + satisfiedTeamSlugs.count
            // reviewDecision=="APPROVED" means GitHub considers all required reviews satisfied.
            // Use it as a fallback when granular signals under-count (e.g. team "on behalf of"
            // approval where onBehalfOf is empty and read:org scope is absent).
            let reviewDecisionOverride = granularApproved < totalRequested && graphqlData.reviewDecision == "APPROVED"
            approvedReviewers = reviewDecisionOverride ? totalRequested : granularApproved
            totalReviewers = totalRequested
            if reviewDecisionOverride {
                log.log("  ✓ reviewDecision override: granular=\(granularApproved) → \(totalRequested)/\(totalRequested)")
            }

            // log which signal caused each approval for debuggability
            for login in approvedIndividualLogins {
                let via = latestByUser[login] == "APPROVED" ? "latestByUser" : "prDetailNotPending"
                log.log("  ✓ individual \(login) via \(via)")
            }
            for slug in satisfiedTeamSlugs {
                let via: String
                if !graphqlPendingTeams.contains(slug) { via = "graphqlNotPending" }
                else if !prDetailPendingTeams.contains(slug) { via = "prDetailNotPending" }
                else if teamsApprovedViaOnBehalfOf.contains(slug) { via = "onBehalfOf" }
                else { via = "membership" }
                log.log("  ✓ team \(slug) via \(via)")
            }
            let pendingIndividuals = originalIndividuals.subtracting(approvedIndividualLogins)
            let pendingTeams = originalTeams.subtracting(satisfiedTeamSlugs)
            if !pendingIndividuals.isEmpty || !pendingTeams.isEmpty {
                log.log("  ✗ still pending — individuals: \(pendingIndividuals), teams: \(pendingTeams)")
            }
        }

        log.log("  → approvedReviewers=\(approvedReviewers)/\(totalReviewers) totalRequested=\(totalRequested) checks=\(checks.passed)/\(checks.total) failed=\(checks.failed)")
        return PREnrichment(
            approvedReviewers: approvedReviewers,
            totalReviewers: totalReviewers,
            checksPassed: checks.passed,
            checksFailed: checks.failed,
            checksTotal: checks.total
        )
    }

    private func fetchGraphQLReviews(owner: String, repo: String, number: Int, token: String) async -> GraphQLPRData {
        let query = """
        query($owner: String!, $repo: String!, $number: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $number) {
              reviewDecision
              latestOpinionatedReviews(last: 20) {
                nodes {
                  state
                  onBehalfOf(first: 10) {
                    nodes {
                      slug
                    }
                  }
                }
              }
              reviewRequests(first: 20) {
                nodes {
                  requestedReviewer {
                    ... on Team {
                      slug
                    }
                  }
                }
              }
            }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["owner": owner, "repo": repo, "number": number]
        ]
        guard let url = URL(string: "https://api.github.com/graphql"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return GraphQLPRData(reviewNodes: [], pendingTeamSlugs: [], reviewDecision: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let result = try? JSONDecoder().decode(GraphQLResponse.self, from: data),
              let pr = result.data?.repository?.pullRequest else {
            return GraphQLPRData(reviewNodes: [], pendingTeamSlugs: [], reviewDecision: nil)
        }
        let reviewNodes = pr.latestOpinionatedReviews?.nodes ?? []
        let pendingTeamSlugs = Set(
            (pr.reviewRequests?.nodes ?? []).compactMap { $0.requestedReviewer?.slug }
        )
        return GraphQLPRData(reviewNodes: reviewNodes, pendingTeamSlugs: pendingTeamSlugs, reviewDecision: pr.reviewDecision)
    }

    private func fetchTeamMembers(org: String, teamSlug: String, token: String) async -> Set<String> {
        guard let url = URL(string: "https://api.github.com/orgs/\(org)/teams/\(teamSlug)/members?per_page=100") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            DiagnosticLogger.shared.log("  [fetchTeamMembers] network error for \(org)/\(teamSlug)")
            return []
        }
        guard http.statusCode == 200,
              let members = try? JSONDecoder().decode([TeamMember].self, from: data) else {
            DiagnosticLogger.shared.log("  [fetchTeamMembers] failed status=\(http.statusCode) for \(org)/\(teamSlug)")
            return []
        }
        let logins = Set(members.map(\.login))
        DiagnosticLogger.shared.log("  [fetchTeamMembers] \(org)/\(teamSlug) → \(logins.count) members: \(logins)")
        return logins
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
            DiagnosticLogger.shared.log("[search] network error: \(error.localizedDescription)")
            throw GitHubError.networkError
        }

        guard let http = response as? HTTPURLResponse else { throw GitHubError.networkError }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(GitHubSearchResponse.self, from: data).items
            } catch {
                DiagnosticLogger.shared.log("[search] decode error: \(error)")
                throw GitHubError.decodingError
            }
        case 401:
            DiagnosticLogger.shared.log("[search] unauthorized (401)")
            throw GitHubError.unauthorized
        case 403, 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            DiagnosticLogger.shared.log("[search] rate limited status=\(http.statusCode) retryAfter=\(retryAfter.map(String.init) ?? "nil")")
            throw GitHubError.rateLimited(retryAfter: retryAfter)
        default:
            DiagnosticLogger.shared.log("[search] unexpected status=\(http.statusCode)")
            throw GitHubError.networkError
        }
    }
}
