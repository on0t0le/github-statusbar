import SwiftUI
import AppKit

struct PRRowView: View {
    let pr: PullRequest

    var body: some View {
        Button(action: openPR) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.repoName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(pr.title)
                        .font(.subheadline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
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
        .contextMenu {
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pr.htmlUrl, forType: .string)
            }
        }
    }

    private func openPR() {
        guard let url = URL(string: pr.htmlUrl) else { return }
        NSWorkspace.shared.open(url)
    }
}
