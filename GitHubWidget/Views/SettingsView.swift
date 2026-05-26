import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var accountStore: AccountStore
    @AppStorage("notifications_enabled") private var notificationsEnabled = false
    @State private var launchAtLogin = false
    @State private var editingAccount: Account? = nil
    @State private var showAddAccount = false
    @State private var showDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            accountsSection

            Toggle("Enable notifications", isOn: Binding(
                get: { notificationsEnabled },
                set: { enabled in
                    notificationsEnabled = enabled
                    if enabled {
                        Task {
                            let granted = await NotificationService.shared.requestPermission()
                            if !granted { notificationsEnabled = false }
                        }
                    }
                }
            ))

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        #if DEBUG
                        print("[LaunchAtLogin] \(enabled ? "register" : "unregister") failed: \(error)")
                        #endif
                    }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            ))

            HStack {
                Button("Diagnostics…") { showDiagnostics = true }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
        .sheet(item: $editingAccount) { account in
            AccountEditView(accountStore: accountStore, account: account)
        }
        .sheet(isPresented: $showAddAccount) {
            AccountEditView(accountStore: accountStore, account: nil)
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView()
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GitHub Accounts")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    showAddAccount = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .disabled(accountStore.accounts.count >= 5)
            }

            if accountStore.accounts.isEmpty {
                Text("No accounts configured. Click + to add one.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(accountStore.accounts) { account in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(.subheadline)
                            Text("@\(account.username)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            editingAccount = account
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        Button {
                            accountStore.delete(account: account)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct AccountEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var accountStore: AccountStore
    let account: Account?

    @State private var name: String = ""
    @State private var username: String = ""
    @State private var token: String = ""
    @State private var orgFilter: String = ""

    private var isNew: Bool { account == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add Account" : "Edit Account")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Account Name")
                    .font(.subheadline)
                TextField("Personal, Work, Client X…", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("GitHub Username")
                    .font(.subheadline)
                TextField("yourhandle", text: $username)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Personal Access Token")
                    .font(.subheadline)
                SecureField("ghp_…", text: $token)
                    .textFieldStyle(.roundedBorder)
                Text("Required scopes: repo, read:user")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Org / Repo Filter (optional)")
                    .font(.subheadline)
                TextField("myorg  or  myorg/myrepo", text: $orgFilter)
                    .textFieldStyle(.roundedBorder)
                Text("Leave blank to show all your PRs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || username.isEmpty || (isNew && token.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear(perform: load)
    }

    private func load() {
        guard let account else { return }
        name = account.name
        username = account.username
        orgFilter = account.orgFilter
        token = KeychainHelper.load(key: account.keychainKey) ?? ""
    }

    private func save() {
        if isNew {
            accountStore.add(name: name, username: username, orgFilter: orgFilter, token: token)
        } else if var updated = account {
            updated.name = name
            updated.username = username
            updated.orgFilter = orgFilter
            accountStore.update(account: updated, token: token.isEmpty ? nil : token)
        }
        dismiss()
    }
}

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logger = DiagnosticLogger.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics")
                    .font(.headline)
                Spacer()
                if let path = logger.fileURL?.path {
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                }
            }

            if logger.entries.isEmpty {
                Text("No log entries yet. Trigger a refresh to generate logs.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(logger.entries) { entry in
                                Text(entry.formatted)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .textSelection(.enabled)
                                    .id(entry.id)
                            }
                        }
                        .padding(8)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .onChange(of: logger.entries.count) { _ in
                        if let last = logger.entries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            HStack {
                Button(copied ? "Copied!" : "Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logger.allText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .disabled(logger.entries.isEmpty)

                Button("Clear") { logger.clearLogs() }
                    .disabled(logger.entries.isEmpty)

                Spacer()
                Text("\(logger.entries.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 600, height: 400)
    }
}
