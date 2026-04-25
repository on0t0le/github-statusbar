import Foundation

struct PullRequest: Identifiable, Hashable, Codable {
    let id: Int
    let number: Int
    let title: String
    let htmlUrl: String
    let repositoryUrl: String
    let user: GitHubUser
    let draft: Bool
    let labels: [GitHubLabel]

    var repoName: String {
        let parts = repositoryUrl.split(separator: "/")
        guard parts.count >= 2 else { return repositoryUrl }
        return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
    }

    enum CodingKeys: String, CodingKey {
        case id, number, title, draft, labels, user
        case htmlUrl = "html_url"
        case repositoryUrl = "repository_url"
    }
}

struct GitHubUser: Codable, Hashable {
    let login: String
    let avatarUrl: String

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
    }
}

struct GitHubLabel: Codable, Hashable {
    let name: String
    let color: String
}

struct GitHubSearchResponse: Codable {
    let totalCount: Int
    let items: [PullRequest]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case items
    }
}

struct PRFetchResult {
    let reviewRequested: [PullRequest]
    /// changes requested, author has NOT re-requested review → needs action from author
    let changesRequested: [PullRequest]
    /// changes requested, author HAS re-requested review → waiting on reviewer
    let changesRequestedPending: [PullRequest]
    let assigned: [PullRequest]
    let readyToMerge: [PullRequest]

    init(
        reviewRequested: [PullRequest],
        changesRequested: [PullRequest],
        changesRequestedPending: [PullRequest] = [],
        assigned: [PullRequest],
        readyToMerge: [PullRequest]
    ) {
        self.reviewRequested = reviewRequested
        self.changesRequested = changesRequested
        self.changesRequestedPending = changesRequestedPending
        self.assigned = assigned
        self.readyToMerge = readyToMerge
    }

    var waitingOnMe: [PullRequest] {
        deduplicated(reviewRequested + changesRequested)
    }

    var readyToMergeDeduped: [PullRequest] {
        let waitingIds = Set(waitingOnMe.map(\.id))
        return deduplicated(readyToMerge.filter { !waitingIds.contains($0.id) })
    }

    var inProgress: [PullRequest] {
        let excludedIds = Set((waitingOnMe + readyToMergeDeduped).map(\.id))
        return deduplicated((assigned + changesRequestedPending).filter { !excludedIds.contains($0.id) })
    }

    var allPRs: [PullRequest] {
        deduplicated(reviewRequested + changesRequested + changesRequestedPending + assigned + readyToMerge)
    }

    private func deduplicated(_ prs: [PullRequest]) -> [PullRequest] {
        var seen = Set<Int>()
        return prs.filter { seen.insert($0.id).inserted }
    }
}
