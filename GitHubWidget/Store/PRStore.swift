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
    @Published private(set) var enrichments: [Int: PREnrichment] = [:]

    @Published private(set) var unseenPRIds: Set<Int> = []
    private var previousResult: PRFetchResult?
    private let service: any GitHubServiceProtocol
    private let notificationService: any NotificationServiceProtocol

    init(
        service: any GitHubServiceProtocol = GitHubService.shared,
        notificationService: any NotificationServiceProtocol = NotificationService.shared
    ) {
        self.service = service
        self.notificationService = notificationService
    }

    func markAllSeen() {
        unseenPRIds = []
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
            if UserDefaults.standard.bool(forKey: "notifications_enabled") {
                let newUnseen = notificationService.diff(old: previousResult, new: result, username: username)
                unseenPRIds = unseenPRIds.union(newUnseen)
            }
            previousResult = result

            waitingOnMe = result.waitingOnMe
            readyToMerge = result.readyToMergeDeduped
            inProgress = result.inProgress
            totalCount = waitingOnMe.count + readyToMerge.count + inProgress.count
            lastUpdated = Date()

            let allPRs = result.allPRs
            Task { [weak self, token] in
                guard let self else { return }
                let e = await self.service.fetchEnrichments(prs: allPRs, token: token)
                self.enrichments = e
            }
        } catch let e as GitHubError {
            error = e
        } catch {
            self.error = .networkError
        }

        isLoading = false
    }


}
