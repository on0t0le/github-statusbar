import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var username = ""
    @State private var orgFilter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("GitHub Personal Access Token")
                    .font(.subheadline)
                SecureField("ghp_...", text: $token)
                    .textFieldStyle(.roundedBorder)
                Text("Required scopes: repo, read:user")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("GitHub Username")
                    .font(.subheadline)
                TextField("yourhandle", text: $username)
                    .textFieldStyle(.roundedBorder)
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
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear(perform: load)
    }

    private func load() {
        token = KeychainHelper.load(key: "github_pat") ?? ""
        username = UserDefaults.standard.string(forKey: "github_username") ?? ""
        orgFilter = UserDefaults.standard.string(forKey: "github_org_filter") ?? ""
    }

    private func save() {
        KeychainHelper.save(key: "github_pat", value: token)
        UserDefaults.standard.set(username, forKey: "github_username")
        UserDefaults.standard.set(orgFilter, forKey: "github_org_filter")
        dismiss()
    }
}
