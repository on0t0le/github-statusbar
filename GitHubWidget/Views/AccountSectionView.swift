import SwiftUI

struct AccountSectionView: View {
    let account: Account
    @ObservedObject var store: PRStore
    let showAccountHeader: Bool

    var body: some View {
        if showAccountHeader {
            HStack {
                Text(account.name)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Spacer()
                if let error = store.error {
                    Text(error.userMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.separatorColor).opacity(0.2))
        }

        if let error = store.error {
            if !showAccountHeader {
                errorView(error)
            }
        } else if store.waitingOnMe.isEmpty && store.readyToMerge.isEmpty && store.inProgress.isEmpty && !store.isLoading {
            if !showAccountHeader {
                emptyStateView
            } else {
                Text("No open PRs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
        } else {
            prListContent
        }
    }

    @ViewBuilder
    private var prListContent: some View {
        if !store.waitingOnMe.isEmpty {
            SectionHeaderView(emoji: "👀", title: "WAITING ON ME", count: store.waitingOnMe.count)
            ForEach(store.waitingOnMe) { pr in
                PRRowView(pr: pr, isUnseen: store.unseenPRIds.contains(pr.id), enrichment: store.enrichments[pr.id])
                    .id(rowIdentity(for: pr))
                Divider().padding(.leading, 12)
            }
        }
        if !store.readyToMerge.isEmpty {
            SectionHeaderView(emoji: "✅", title: "READY TO MERGE", count: store.readyToMerge.count)
            ForEach(store.readyToMerge) { pr in
                PRRowView(pr: pr, isUnseen: store.unseenPRIds.contains(pr.id), enrichment: store.enrichments[pr.id])
                    .id(rowIdentity(for: pr))
                Divider().padding(.leading, 12)
            }
        }
        if !store.inProgress.isEmpty {
            SectionHeaderView(emoji: "🔄", title: "IN PROGRESS", count: store.inProgress.count)
            ForEach(store.inProgress) { pr in
                PRRowView(pr: pr, isUnseen: store.unseenPRIds.contains(pr.id), enrichment: store.enrichments[pr.id])
                    .id(rowIdentity(for: pr))
                Divider().padding(.leading, 12)
            }
        }
    }

    // Forces SwiftUI to treat a changed enrichment count as a new view identity,
    // so a row can never silently keep showing a stale "X/Y" after enrichments update.
    private func rowIdentity(for pr: PullRequest) -> String {
        let e = store.enrichments[pr.id]
        return "\(pr.id)-\(e?.approvedReviewers ?? -1)-\(e?.totalReviewers ?? -1)"
    }

    private func errorView(_ error: GitHubError) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
                .font(.title2)
            Text(error.userMessage)
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        Text("No open PRs")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding()
    }
}
