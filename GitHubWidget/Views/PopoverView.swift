import SwiftUI

struct PopoverView: View {
    let accountStores: [(account: Account, store: PRStore)]
    let accountStore: AccountStore
    var onClose: (() -> Void)?
    @State private var showSettings = false

    private var showAccountHeaders: Bool { accountStores.count > 1 }

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
            SettingsView(accountStore: accountStore)
        }
    }

    private var headerView: some View {
        HStack {
            Text("GitHub PRs")
                .font(.headline)
            Spacer()
            Button {
                for (_, store) in accountStores { Task { await store.refresh() } }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(accountStores.contains { $0.store.isLoading })
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
        if accountStores.isEmpty {
            Text("No accounts configured")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(accountStores, id: \.account.id) { (account, store) in
                        AccountSectionView(
                            account: account,
                            store: store,
                            showAccountHeader: showAccountHeaders
                        )
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    private var footerView: some View {
        HStack(spacing: 6) {
            if accountStores.contains(where: { $0.store.isLoading }) {
                ProgressView().scaleEffect(0.6)
                Text("Refreshing…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let date = accountStores.compactMap(\.store.lastUpdated).max() {
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
