# Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fire macOS banner notifications and show in-popover blue dots when PRs are newly assigned for review, changes are requested on the user's PRs, or the user's PRs are approved.

**Architecture:** A new `NotificationService` owns permission, diff logic, and banner posting. `PRStore` stores `unseenPRIds: Set<Int>` (union across refreshes, cleared when popover opens). `PRRowView` receives an `isUnseen: Bool` flag from `PopoverView` and renders a blue dot. A Settings toggle controls the feature; AppDelegate wires the UNUserNotificationCenter delegate on launch.

**Tech Stack:** Swift, SwiftUI, AppKit, UserNotifications framework, XCTest

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `GitHubWidget/Services/NotificationService.swift` | **Create** | Protocol + class: permission, diff, banner posting, notification tap handling |
| `GitHubWidget/Store/PRStore.swift` | **Modify** | Add `unseenPRIds`, `markAllSeen()`, wire `NotificationService`, replace `previousPRs` |
| `GitHubWidget/Views/PRRowView.swift` | **Modify** | Accept `isUnseen: Bool`, render blue dot |
| `GitHubWidget/Views/PopoverView.swift` | **Modify** | Pass `isUnseen` to each `PRRowView`; pass `store` to `SettingsView` |
| `GitHubWidget/Views/SettingsView.swift` | **Modify** | Add `store: PRStore` param + notifications toggle |
| `GitHubWidget/App/AppDelegate.swift` | **Modify** | Set UNUserNotificationCenter delegate, request permission on launch, call `markAllSeen()` on popover open |
| `GitHubWidgetTests/NotificationServiceTests.swift` | **Create** | Unit tests for `NotificationService.diff` logic |
| `GitHubWidgetTests/PRStoreTests.swift` | **Modify** | Add `MockNotificationService` + tests for `unseenPRIds` accumulation and `markAllSeen` |

---

## Task 1: NotificationService — protocol, diff, banners

**Files:**
- Create: `GitHubWidget/Services/NotificationService.swift`
- Create: `GitHubWidgetTests/NotificationServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `GitHubWidgetTests/NotificationServiceTests.swift`:

```swift
import XCTest
@testable import GitHubWidget

final class NotificationServiceTests: XCTestCase {
    private let service = NotificationService.shared

    private func makeResult(
        reviewRequested: [PullRequest] = [],
        changesRequested: [PullRequest] = [],
        assigned: [PullRequest] = [],
        readyToMerge: [PullRequest] = []
    ) -> PRFetchResult {
        PRFetchResult(
            reviewRequested: reviewRequested,
            changesRequested: changesRequested,
            assigned: assigned,
            readyToMerge: readyToMerge
        )
    }

    func test_diff_returnsEmpty_whenOldIsNil() {
        let new = makeResult(reviewRequested: [.fixture(id: 1)])
        XCTAssertTrue(service.diff(old: nil, new: new, username: "testuser").isEmpty)
    }

    func test_diff_detectsNewReviewRequest() {
        let old = makeResult()
        let new = makeResult(reviewRequested: [.fixture(id: 42)])
        XCTAssertEqual(service.diff(old: old, new: new, username: "me"), [42])
    }

    func test_diff_detectsNewChangesRequested() {
        let old = makeResult()
        let new = makeResult(changesRequested: [.fixture(id: 7)])
        XCTAssertEqual(service.diff(old: old, new: new, username: "me"), [7])
    }

    func test_diff_detectsApprovedForMyPR() {
        // PullRequest.fixture user.login is "testuser"
        let old = makeResult()
        let new = makeResult(readyToMerge: [.fixture(id: 99)])
        XCTAssertEqual(service.diff(old: old, new: new, username: "testuser"), [99])
    }

    func test_diff_skipsApprovedWhenUsernameDoesNotMatch() {
        let old = makeResult()
        let new = makeResult(readyToMerge: [.fixture(id: 99)])
        // fixture login is "testuser", username is "other" → no match
        XCTAssertTrue(service.diff(old: old, new: new, username: "other").isEmpty)
    }

    func test_diff_deduplicates_samePRInMultipleCategories() {
        let old = makeResult()
        let pr = PullRequest.fixture(id: 5)
        let new = makeResult(reviewRequested: [pr], changesRequested: [pr])
        XCTAssertEqual(service.diff(old: old, new: new, username: "me"), [5])
    }

    func test_diff_ignoresAlreadyKnownPRs() {
        let pr = PullRequest.fixture(id: 3)
        let old = makeResult(reviewRequested: [pr])
        let new = makeResult(reviewRequested: [pr])
        XCTAssertTrue(service.diff(old: old, new: new, username: "me").isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```
xcodebuild test -project GitHubWidget.xcodeproj -scheme GitHubWidget -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED|PASSED" | head -20
```

Expected: compile error — `NotificationService` not found.

- [ ] **Step 3: Implement NotificationService**

Create `GitHubWidget/Services/NotificationService.swift`:

```swift
import Foundation
import UserNotifications
import AppKit

protocol NotificationServiceProtocol: AnyObject {
    func requestPermission() async
    func diff(old: PRFetchResult?, new: PRFetchResult, username: String) -> Set<Int>
}

final class NotificationService: NSObject, NotificationServiceProtocol {
    static let shared = NotificationService()
    private override init() {}

    func requestPermission() async {
        try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func diff(old: PRFetchResult?, new: PRFetchResult, username: String) -> Set<Int> {
        guard let old = old else { return [] }
        var unseenIds = Set<Int>()

        let oldChangesIds = Set(old.changesRequested.map(\.id))
        for pr in new.changesRequested where !oldChangesIds.contains(pr.id) {
            post(title: "Changes requested", body: pr.title, prId: pr.id, url: pr.htmlUrl)
            unseenIds.insert(pr.id)
        }

        let oldReviewIds = Set(old.reviewRequested.map(\.id))
        for pr in new.reviewRequested where !oldReviewIds.contains(pr.id) && !unseenIds.contains(pr.id) {
            post(title: "New review request", body: pr.title, prId: pr.id, url: pr.htmlUrl)
            unseenIds.insert(pr.id)
        }

        let oldReadyIds = Set(old.readyToMerge.map(\.id))
        for pr in new.readyToMerge
            where !oldReadyIds.contains(pr.id) && pr.user.login == username && !unseenIds.contains(pr.id) {
            post(title: "PR approved", body: pr.title, prId: pr.id, url: pr.htmlUrl)
            unseenIds.insert(pr.id)
        }

        return unseenIds
    }

    func post(title: String, body: String, prId: Int, url: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["url": url]
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
```

- [ ] **Step 4: Run tests — expect all pass**

```
xcodebuild test -project GitHubWidget.xcodeproj -scheme GitHubWidget -destination 'platform=macOS' -only-testing:GitHubWidgetTests/NotificationServiceTests 2>&1 | grep -E "Test.*passed|Test.*failed|error:" | head -20
```

Expected: 7 tests passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add GitHubWidget/Services/NotificationService.swift GitHubWidgetTests/NotificationServiceTests.swift
git commit -m "feat: add NotificationService with diff logic and UNUserNotificationCenter banners"
```

---

## Task 2: Wire NotificationService into PRStore

**Files:**
- Modify: `GitHubWidget/Store/PRStore.swift`
- Modify: `GitHubWidgetTests/PRStoreTests.swift`

- [ ] **Step 1: Add MockNotificationService and failing tests to PRStoreTests**

Append to `GitHubWidgetTests/PRStoreTests.swift` — add after the existing `MockGitHubService` block:

```swift
// MARK: - MockNotificationService

final class MockNotificationService: NotificationServiceProtocol, @unchecked Sendable {
    var diffResult: Set<Int>
    var permissionRequested = false

    init(diffResult: Set<Int> = []) {
        self.diffResult = diffResult
    }

    func requestPermission() async { permissionRequested = true }

    func diff(old: PRFetchResult?, new: PRFetchResult, username: String) -> Set<Int> { diffResult }
}

// MARK: - Notification tests

extension PRStoreTests {

    func test_markAllSeen_clearsUnseenPRIds() async {
        let mockNotif = MockNotificationService(diffResult: [1, 2])
        let store = PRStore(service: MockGitHubService(), notificationService: mockNotif)
        UserDefaults.standard.set(true, forKey: "notifications_enabled")
        defer { UserDefaults.standard.removeObject(forKey: "notifications_enabled") }
        KeychainHelper.save(key: "github_pat", value: "token")
        defer { KeychainHelper.delete(key: "github_pat") }

        await store.refresh()
        XCTAssertEqual(store.unseenPRIds, [1, 2])

        store.markAllSeen()
        XCTAssertTrue(store.unseenPRIds.isEmpty)
    }

    func test_unseenPRIds_accumulatesAcrossRefreshes() async {
        let mockNotif = MockNotificationService(diffResult: [1])
        let store = PRStore(service: MockGitHubService(), notificationService: mockNotif)
        UserDefaults.standard.set(true, forKey: "notifications_enabled")
        defer { UserDefaults.standard.removeObject(forKey: "notifications_enabled") }
        KeychainHelper.save(key: "github_pat", value: "token")
        defer { KeychainHelper.delete(key: "github_pat") }

        await store.refresh()
        mockNotif.diffResult = [2]
        await store.refresh()

        XCTAssertEqual(store.unseenPRIds, [1, 2])
    }

    func test_unseenPRIds_notPopulated_whenNotificationsDisabled() async {
        let mockNotif = MockNotificationService(diffResult: [99])
        let store = PRStore(service: MockGitHubService(), notificationService: mockNotif)
        UserDefaults.standard.set(false, forKey: "notifications_enabled")
        defer { UserDefaults.standard.removeObject(forKey: "notifications_enabled") }
        KeychainHelper.save(key: "github_pat", value: "token")
        defer { KeychainHelper.delete(key: "github_pat") }

        await store.refresh()
        XCTAssertTrue(store.unseenPRIds.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```
xcodebuild test -project GitHubWidget.xcodeproj -scheme GitHubWidget -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED" | head -20
```

Expected: `PRStore` has no `unseenPRIds`, no `notificationService` init param, no `markAllSeen`.

- [ ] **Step 3: Modify PRStore**

In `GitHubWidget/Store/PRStore.swift`, apply these changes:

**Replace** the properties block (lines 9–13):
```swift
    private var previousPRs: [PullRequest] = []
    private let service: any GitHubServiceProtocol
```
with:
```swift
    @Published var unseenPRIds: Set<Int> = []
    private var previousResult: PRFetchResult?
    private let service: any GitHubServiceProtocol
    private let notificationService: any NotificationServiceProtocol
```

**Replace** the `init` (lines 15–17):
```swift
    init(service: any GitHubServiceProtocol = GitHubService.shared) {
        self.service = service
    }
```
with:
```swift
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
```

**Inside** `refresh()`, replace:
```swift
            diffAndEmitEvents(old: previousPRs, new: result.allPRs)
            previousPRs = result.allPRs
```
with:
```swift
            if UserDefaults.standard.bool(forKey: "notifications_enabled") {
                let newUnseen = notificationService.diff(old: previousResult, new: result, username: username)
                unseenPRIds = unseenPRIds.union(newUnseen)
            }
            previousResult = result
```

**Delete** the entire `diffAndEmitEvents` method:
```swift
    private func diffAndEmitEvents(old: [PullRequest], new: [PullRequest]) {
        // Stub: future UserNotifications emitted here for newly added PRs
        _ = Set(new.map(\.id)).subtracting(Set(old.map(\.id)))
    }
```

- [ ] **Step 4: Run tests — expect all pass**

```
xcodebuild test -project GitHubWidget.xcodeproj -scheme GitHubWidget -destination 'platform=macOS' 2>&1 | grep -E "Test.*passed|Test.*failed|error:" | head -20
```

Expected: all existing + 3 new PRStore tests pass.

- [ ] **Step 5: Commit**

```bash
git add GitHubWidget/Store/PRStore.swift GitHubWidgetTests/PRStoreTests.swift
git commit -m "feat: wire NotificationService into PRStore with unseenPRIds tracking"
```

---

## Task 3: Blue dot in PRRowView + PopoverView

**Files:**
- Modify: `GitHubWidget/Views/PRRowView.swift`
- Modify: `GitHubWidget/Views/PopoverView.swift`

- [ ] **Step 1: Update PRRowView to accept `isUnseen` and show blue dot**

Replace the full content of `GitHubWidget/Views/PRRowView.swift`:

```swift
import SwiftUI
import AppKit

struct PRRowView: View {
    let pr: PullRequest
    let isUnseen: Bool

    var body: some View {
        Button(action: openPR) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .opacity(isUnseen ? 1 : 0)
                    .padding(.top, 4)
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
```

- [ ] **Step 2: Update PopoverView — pass `isUnseen` to all three PRRowView call sites**

In `GitHubWidget/Views/PopoverView.swift`, replace all three `PRRowView(pr: pr)` usages with `PRRowView(pr: pr, isUnseen: store.unseenPRIds.contains(pr.id))`.

There are three ForEach blocks. Update each:

**Waiting on me** (line 54):
```swift
// Before:
PRRowView(pr: pr)
// After:
PRRowView(pr: pr, isUnseen: store.unseenPRIds.contains(pr.id))
```

**Ready to merge** (line 61):
```swift
// Before:
PRRowView(pr: pr)
// After:
PRRowView(pr: pr, isUnseen: store.unseenPRIds.contains(pr.id))
```

**In progress** (line 68):
```swift
// Before:
PRRowView(pr: pr)
// After:
PRRowView(pr: pr, isUnseen: store.unseenPRIds.contains(pr.id))
```

- [ ] **Step 3: Build to verify no compile errors**

```
xcodebuild build -project GitHubWidget.xcodeproj -scheme GitHubWidget -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add GitHubWidget/Views/PRRowView.swift GitHubWidget/Views/PopoverView.swift
git commit -m "feat: add blue dot indicator to PRRowView for unseen PRs"
```

---

## Task 4: Notifications toggle in SettingsView

**Files:**
- Modify: `GitHubWidget/Views/SettingsView.swift`
- Modify: `GitHubWidget/Views/PopoverView.swift`

- [ ] **Step 1: Update SettingsView**

Replace the full content of `GitHubWidget/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    let store: PRStore
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var username = ""
    @State private var orgFilter = ""
    @AppStorage("notifications_enabled") private var notificationsEnabled = false

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
                        Task { await NotificationService.shared.requestPermission() }
                    } else {
                        store.markAllSeen()
                    }
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
    }

    private func save() {
        KeychainHelper.save(key: "github_pat", value: token)
        UserDefaults.standard.set(username, forKey: "github_username")
        UserDefaults.standard.set(orgFilter, forKey: "github_org_filter")
        dismiss()
    }
}
```

- [ ] **Step 2: Pass `store` to SettingsView in PopoverView**

In `GitHubWidget/Views/PopoverView.swift`, find the sheet modifier (line 16–18):
```swift
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
```
Replace with:
```swift
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store)
        }
```

- [ ] **Step 3: Build to verify no compile errors**

```
xcodebuild build -project GitHubWidget.xcodeproj -scheme GitHubWidget -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add GitHubWidget/Views/SettingsView.swift GitHubWidget/Views/PopoverView.swift
git commit -m "feat: add notifications toggle to SettingsView"
```

---

## Task 5: AppDelegate — delegate, permission on launch, markAllSeen on open

**Files:**
- Modify: `GitHubWidget/App/AppDelegate.swift`

- [ ] **Step 1: Update AppDelegate**

Replace the full content of `GitHubWidget/App/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = PRStore()
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        setupStatusItem()
        setupPopover()
        setupBadgeObserver()
        startTimer()
        if UserDefaults.standard.bool(forKey: "notifications_enabled") {
            Task { await NotificationService.shared.requestPermission() }
        }
        Task { await store.refresh() }
    }

    private var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }()

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "GitHub PRs")
        button.imagePosition = .imageLeft
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleClick)
        button.target = self
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 440)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
    }

    private func setupBadgeObserver() {
        store.$totalCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in self?.updateBadge(count: count) }
            .store(in: &cancellables)
    }

    private func startTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.store.refresh() }
        }
    }

    private func updateBadge(count: Int) {
        statusItem.button?.title = count > 0 ? " \(count)" : ""
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            store.markAllSeen()
        }
    }
}
```

- [ ] **Step 2: Run full test suite**

```
xcodebuild test -project GitHubWidget.xcodeproj -scheme GitHubWidget -destination 'platform=macOS' 2>&1 | grep -E "Test.*passed|Test.*failed|error:|BUILD" | head -30
```

Expected: all tests pass, BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add GitHubWidget/App/AppDelegate.swift
git commit -m "feat: wire UNUserNotificationCenter delegate and markAllSeen on popover open"
```

---

## Done

All five tasks produce working, testable increments. The feature is complete when Task 5 commits cleanly with all tests green.
