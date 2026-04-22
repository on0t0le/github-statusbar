import Foundation

struct PullRequest: Identifiable, Equatable, Codable {
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

struct GitHubUser: Codable, Equatable {
    let login: String
    let avatarUrl: String

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
    }
}

struct GitHubLabel: Codable, Equatable {
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
    let changesRequested: [PullRequest]
    let assigned: [PullRequest]
    let readyToMerge: [PullRequest]

    var waitingOnMe: [PullRequest] {
        deduplicated(reviewRequested + changesRequested)
    }

    var readyToMergeDeduped: [PullRequest] {
        let waitingIds = Set(waitingOnMe.map(\.id))
        return deduplicated(readyToMerge.filter { !waitingIds.contains($0.id) })
    }

    var inProgress: [PullRequest] {
        let excludedIds = Set((waitingOnMe + readyToMergeDeduped).map(\.id))
        return deduplicated(assigned.filter { !excludedIds.contains($0.id) })
    }

    var allPRs: [PullRequest] {
        deduplicated(reviewRequested + changesRequested + assigned + readyToMerge)
    }

    private func deduplicated(_ prs: [PullRequest]) -> [PullRequest] {
        var seen = Set<Int>()
        return prs.filter { seen.insert($0.id).inserted }
    }
}
