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

    let account: Account
    private var previousResult: PRFetchResult?
    private var currentResult: PRFetchResult?
    private let service: any GitHubServiceProtocol
    private let notificationService: any NotificationServiceProtocol

    init(
        account: Account,
        service: any GitHubServiceProtocol = GitHubService.shared,
        notificationService: any NotificationServiceProtocol = NotificationService.shared
    ) {
        self.account = account
        self.service = service
        self.notificationService = notificationService
    }

    func markAllSeen() {
        unseenPRIds = []
    }

    func refresh() async {
        guard let token = KeychainHelper.load(key: account.keychainKey), !token.isEmpty else {
            error = .notConfigured
            return
        }

        isLoading = true
        error = nil

        do {
            let result = try await service.fetchPRs(
                token: token,
                username: account.username,
                orgFilter: account.orgFilter
            )
            if UserDefaults.standard.bool(forKey: "notifications_enabled") {
                let newUnseen = notificationService.diff(
                    old: previousResult,
                    new: result,
                    username: account.username
                )
                unseenPRIds = unseenPRIds.union(newUnseen)
            }
            previousResult = result
            currentResult = result
            applyCategories(result: result, enrichments: enrichments)
            lastUpdated = Date()

            let allPRs = result.allPRs
            Task { [weak self, token] in
                guard let self else { return }
                let e = await self.service.fetchEnrichments(prs: allPRs, token: token)
                DiagnosticLogger.shared.log("[PRStore] enrichments stored: \(e.count) entries for PRs \(allPRs.map { "#\(String($0.number))" }.joined(separator: ","))")
                self.enrichments = e
                if let result = self.currentResult {
                    self.applyCategories(result: result, enrichments: e)
                }
            }
        } catch let e as GitHubError {
            error = e
        } catch {
            self.error = .networkError
        }

        isLoading = false
    }

    private func applyCategories(result: PRFetchResult, enrichments: [Int: PREnrichment]) {
        let promotedIds = Set(
            result.inProgress.compactMap { pr -> Int? in
                guard let e = enrichments[pr.id],
                      e.totalReviewers > 0,
                      e.approvedReviewers == e.totalReviewers else { return nil }
                return pr.id
            }
        )

        let log = DiagnosticLogger.shared
        if !promotedIds.isEmpty {
            let names = result.inProgress
                .filter { promotedIds.contains($0.id) }
                .map { "#\(String($0.number)) \($0.repoName)" }
                .joined(separator: ", ")
            log.log("[PRStore] enrichment-promoted to readyToMerge: \(names)")
        }

        let newWaitingOnMe = result.waitingOnMe
        let newReadyToMerge = result.readyToMergeDeduped + result.inProgress.filter { promotedIds.contains($0.id) }
        let newInProgress = result.inProgress.filter { !promotedIds.contains($0.id) }

        let fmt: ([PullRequest]) -> String = { $0.map { "#\(String($0.number)) \($0.repoName)" }.joined(separator: ", ") }
        log.log("[PRStore] categories — waitingOnMe: [\(fmt(newWaitingOnMe))]")
        log.log("[PRStore] categories — readyToMerge: [\(fmt(newReadyToMerge))]")
        log.log("[PRStore] categories — inProgress: [\(fmt(newInProgress))]")

        waitingOnMe = newWaitingOnMe
        readyToMerge = newReadyToMerge
        inProgress = newInProgress
        totalCount = waitingOnMe.count + readyToMerge.count + inProgress.count
    }
}
