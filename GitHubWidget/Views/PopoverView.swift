import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: PRStore
    var onClose: (() -> Void)?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
            Divider()
            footerView
        }
        .frame(width: 340)
        .sheet(isPresented: $showSettings, onDismiss: { onClose?() }) {
            SettingsView(store: store)
        }
    }

    private var headerView: some View {
        HStack {
            Text("GitHub PRs")
                .font(.headline)
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(store.isLoading)
            Button { showSettings = true } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var contentView: some View {
        if let error = store.error {
            errorView(error)
        } else if store.waitingOnMe.isEmpty && store.readyToMerge.isEmpty && store.inProgress.isEmpty && !store.isLoading {
            emptyStateView
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !store.waitingOnMe.isEmpty {
                        SectionHeaderView(emoji: "👀", title: "WAITING ON ME", count: store.waitingOnMe.count)
                        ForEach(store.waitingOnMe) { pr in
                            PRRowView(pr: pr, isUnseen: store.unseenPRIds.contains(pr.id))
                            Divider().padding(.leading, 12)
                        }
                    }
                    if !store.readyToMerge.isEmpty {
                        SectionHeaderView(emoji: "✅", title: "READY TO MERGE", count: store.readyToMerge.count)
                        ForEach(store.readyToMerge) { pr in
                            PRRowView(pr: pr, isUnseen: store.unseenPRIds.contains(pr.id))
                            Divider().padding(.leading, 12)
                        }
                    }
                    if !store.inProgress.isEmpty {
                        SectionHeaderView(emoji: "🔄", title: "IN PROGRESS", count: store.inProgress.count)
                        ForEach(store.inProgress) { pr in
                            PRRowView(pr: pr, isUnseen: store.unseenPRIds.contains(pr.id))
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    private var footerView: some View {
        HStack(spacing: 6) {
            if store.isLoading {
                ProgressView().scaleEffect(0.6)
                Text("Refreshing…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let date = store.lastUpdated {
                Text("Updated \(date, formatter: Self.relativeFormatter)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("v\(version)")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

struct SectionHeaderView: View {
    let emoji: String
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text("\(emoji) \(title) (\(count))")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.separatorColor).opacity(0.1))
    }
}
