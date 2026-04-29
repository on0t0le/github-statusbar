import SwiftUI
import AppKit

struct PRRowView: View {
    let pr: PullRequest
    let isUnseen: Bool
    var enrichment: PREnrichment? = nil

    var body: some View {
        Button(action: openPR) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .opacity(isUnseen ? 1 : 0)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.repoName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(pr.title)
                        .font(.subheadline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                    metadataRow
                }
                Spacer(minLength: 4)
                Text("@\(pr.user.login)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isUnseen ? "Unseen" : "")
        .contextMenu {
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pr.htmlUrl, forType: .string)
            }
        }
    }

    @ViewBuilder
    private var metadataRow: some View {
        let hasComments = pr.comments > 0
        let hasReviewers = enrichment.map { $0.totalReviewers > 0 } ?? false
        let hasChecks = enrichment.map { $0.checksTotal > 0 } ?? false
        if hasComments || hasReviewers || hasChecks {
            HStack(spacing: 10) {
                if hasComments {
                    Label("\(pr.comments)", systemImage: "bubble.right")
                        .foregroundColor(.secondary)
                }
                if hasReviewers, let e = enrichment {
                    Label("\(e.approvedReviewers)/\(e.totalReviewers)", systemImage: "person.2")
                        .foregroundColor(e.approvedReviewers == e.totalReviewers ? .green : .secondary)
                }
                if hasChecks, let e = enrichment {
                    Label("\(e.checksPassed)/\(e.checksTotal)", systemImage: ciIcon(e))
                        .foregroundColor(ciColor(e))
                }
            }
            .font(.caption2)
            .padding(.top, 2)
        }
    }

    private func ciIcon(_ e: PREnrichment) -> String {
        if e.checksFailed > 0 { return "xmark.circle.fill" }
        if e.checksPassed == e.checksTotal { return "checkmark.circle.fill" }
        return "clock.circle"
    }

    private func ciColor(_ e: PREnrichment) -> Color {
        if e.checksFailed > 0 { return .red }
        if e.checksPassed == e.checksTotal { return .green }
        return .secondary
    }

    private func openPR() {
        guard let url = URL(string: pr.htmlUrl) else { return }
        NSWorkspace.shared.open(url)
    }
}
