# Launch at Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Launch at login" toggle to SettingsView that registers/unregisters the app as a macOS login item using `SMAppService`.

**Architecture:** Use `SMAppService.mainApp` from the `ServiceManagement` framework (macOS 13+). The toggle applies immediately on change; system state is the source of truth, not `UserDefaults`. State is read back from `SMAppService.mainApp.status` on every `onAppear`.

**Tech Stack:** Swift, SwiftUI, ServiceManagement.framework, XcodeGen

---

### Task 1: Link ServiceManagement framework

**Files:**
- Modify: `project.yml` (add sdk dependency under GitHubWidget target)

No unit test possible — this is a build configuration change.

- [ ] **Step 1: Add ServiceManagement to project.yml**

Open `project.yml`. Under the `GitHubWidget` target, add a `dependencies` key. The result should look like this (add after the `sources` block):

```yaml
targets:
  GitHubWidget:
    type: application
    platform: macOS
    sources:
      - path: GitHubWidget
    dependencies:
      - sdk: ServiceManagement.framework
    settings:
```

- [ ] **Step 2: Regenerate the Xcode project**

```bash
xcodegen generate
```

Expected: `✓ Generated: GitHubWidget.xcodeproj`

- [ ] **Step 3: Verify framework appears in project**

```bash
grep "ServiceManagement" GitHubWidget.xcodeproj/project.pbxproj | head -3
```

Expected: at least one line referencing `ServiceManagement.framework`.

- [ ] **Step 4: Commit**

```bash
git add project.yml GitHubWidget.xcodeproj/project.pbxproj
git commit -m "build: link ServiceManagement framework"
```

---

### Task 2: Add Launch at Login toggle to SettingsView

**Files:**
- Modify: `GitHubWidget/Views/SettingsView.swift`

No unit test possible — `SMAppService` is a system API with no mockable interface. Manual verification described at end of task.

- [ ] **Step 1: Replace SettingsView.swift with the updated version**

Replace the entire contents of `GitHubWidget/Views/SettingsView.swift` with:

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let store: PRStore
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var username = ""
    @State private var orgFilter = ""
    @AppStorage("notifications_enabled") private var notificationsEnabled = false
    @State private var launchAtLogin = false

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

            Toggle("Enable notifications", isOn: Binding(
                get: { notificationsEnabled },
                set: { enabled in
                    notificationsEnabled = enabled
                    if enabled {
                        Task {
                            let granted = await NotificationService.shared.requestPermission()
                            if !granted { notificationsEnabled = false }
                        }
                    } else {
                        store.markAllSeen()
                    }
                }
            ))

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    launchAtLogin = enabled
                    try? enabled
                        ? SMAppService.mainApp.register()
                        : SMAppService.mainApp.unregister()
                }
            ))

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
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func save() {
        KeychainHelper.save(key: "github_pat", value: token)
        UserDefaults.standard.set(username, forKey: "github_username")
        UserDefaults.standard.set(orgFilter, forKey: "github_org_filter")
        dismiss()
    }
}
```

- [ ] **Step 2: Build and verify no compiler errors**

```bash
xcodebuild -project GitHubWidget.xcodeproj -scheme GitHubWidget -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual test — toggle on**

1. Run the app
2. Open settings (left-click status bar icon → gear icon)
3. Toggle "Launch at login" ON
4. Open System Settings → General → Login Items → Open at Login
5. Verify "GitHubWidget" appears in the list

- [ ] **Step 4: Manual test — toggle reflects external changes**

1. Remove the app from Login Items in System Settings (click minus)
2. Close and reopen the Settings panel in the app
3. Verify the "Launch at login" toggle is now OFF (reads live state from SMAppService)

- [ ] **Step 5: Manual test — toggle off**

1. Toggle "Launch at login" ON again via Settings
2. Toggle it OFF
3. Open System Settings → General → Login Items → Open at Login
4. Verify "GitHubWidget" is no longer in the list

- [ ] **Step 6: Commit**

```bash
git add GitHubWidget/Views/SettingsView.swift
git commit -m "feat: add launch at login toggle to settings"
```
