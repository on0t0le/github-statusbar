import Foundation
import Combine

@MainActor
final class PRStore: ObservableObject {
    @Published var waitingOnMe: [PullRequest] = []
    @Published var readyToMerge: [PullRequest] = []
    @Published var inProgress: [PullRequest] = []
    @Published var isLoading = false
    @Published var error: GitHubError?
    @Published var lastUpdated: Date?
    @Published private(set) var totalCount: Int = 0

    private var previousPRs: [PullRequest] = []
    private let service: any GitHubServiceProtocol

    init(service: any GitHubServiceProtocol = GitHubService.shared) {
        self.service = service
    }

    func refresh() async {
        guard let token = KeychainHelper.load(key: "github_pat"), !token.isEmpty else {
            error = .notConfigured
            return
        }
        let username = UserDefaults.standard.string(forKey: "github_username") ?? ""
        let orgFilter = UserDefaults.standard.string(forKey: "github_org_filter") ?? ""

        isLoading = true
        error = nil

        do {
            let result = try await service.fetchPRs(token: token, username: username, orgFilter: orgFilter)
            diffAndEmitEvents(old: previousPRs, new: result.allPRs)
            previousPRs = result.allPRs

            waitingOnMe = result.waitingOnMe
            readyToMerge = result.readyToMergeDeduped
            inProgress = result.inProgress
            totalCount = waitingOnMe.count + readyToMerge.count + inProgress.count
            lastUpdated = Date()
        } catch let e as GitHubError {
            error = e
        } catch {
            self.error = .networkError
        }

        isLoading = false
    }

    private func diffAndEmitEvents(old: [PullRequest], new: [PullRequest]) {
        // Stub: future UserNotifications emitted here for newly added PRs
        _ = Set(new.map(\.id)).subtracting(Set(old.map(\.id)))
    }
}
