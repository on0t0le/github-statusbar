# Notifications — Design Spec

**Date:** 2026-04-25
**Branch:** feature+notifications

## Overview

Add macOS banner notifications and in-popover visual indicators (blue dot) for:
- New PR assigned for review (review-requested on others' PRs)
- Changes requested on user's own PRs
- User's own PR approved

Notifications are opt-in via a Settings toggle. Blue dots accumulate across refreshes and clear when the popover opens.

## Architecture

### New: `Services/NotificationService.swift`

Single-responsibility: permission, diffing, banner posting.

```swift
final class NotificationService {
    static let shared = NotificationService()

    func requestPermission() async
    func diff(old: PRFetchResult?, new: PRFetchResult, username: String) -> Set<Int>
    func post(title: String, body: String, prId: Int, url: String)
}
```

**`diff` detection rules (checked in priority order):**
1. New ID in `changesRequested` not in old `changesRequested` → "Changes requested" banner, add to unseen
2. New ID in `reviewRequested` not in old `reviewRequested` → "New review request" banner, add to unseen
3. New ID in `readyToMerge` not in old `readyToMerge`, where `user.login == username` → "PR approved" banner, add to unseen

Returns `Set<Int>` of PR IDs that triggered events (used by `PRStore` for blue dots).

### Modified: `Store/PRStore.swift`

- Replace `previousPRs: [PullRequest]` with `previousResult: PRFetchResult?`
- Add `@Published var unseenPRIds: Set<Int> = []`
- Add `func markAllSeen()` → `unseenPRIds = []`
- In `refresh()`: if `notifications_enabled` UserDefaults key is true, call `NotificationService.shared.diff()` and union result into `unseenPRIds`

### Modified: `Views/SettingsView.swift`

Add toggle bound to `UserDefaults "notifications_enabled"`. On toggle-on, call `NotificationService.shared.requestPermission()`. On toggle-off, clear `unseenPRIds` via store.

### Modified: `Views/PRRowView.swift`

Overlay blue dot (`Circle`, 8pt, `.blue`) on trailing edge when `pr.id ∈ store.unseenPRIds`.

### Modified: `App/AppDelegate.swift`

- On launch: if `notifications_enabled`, call `NotificationService.shared.requestPermission()`
- Adopt `UNUserNotificationCenterDelegate` to handle notification tap → open `pr.htmlUrl` in browser
- On popover open: call `store.markAllSeen()`

## Data Flow

```
Timer (5min) / manual refresh
  → GitHubService.fetchPRs() → PRFetchResult
  → PRStore.refresh():
      if notifications_enabled:
        newUnseen = NotificationService.diff(old: previousResult, new: result, username)
        unseenPRIds = unseenPRIds ∪ newUnseen
      previousResult = result
      update waitingOnMe / readyToMerge / inProgress / totalCount

Popover opens (AppDelegate)
  → store.markAllSeen() → unseenPRIds = []

PRRowView renders
  → pr.id ∈ store.unseenPRIds → show blue dot

Notification banner tapped (UNUserNotificationCenterDelegate)
  → open pr.htmlUrl in NSWorkspace.shared.open()
```

## Error Handling & Edge Cases

| Case | Behavior |
|---|---|
| Permission denied by user | No banners; blue dots still work |
| Toggle disabled mid-session | `unseenPRIds` cleared immediately |
| PR appears in multiple categories | At most one notification per PR ID per refresh (changesRequested > reviewRequested > approved) |
| Rapid refreshes | Diff always against last committed `previousResult`; no duplicates |
| Username not set | Approved detection skipped; no false positives |
| First launch (no `previousResult`) | `diff` returns empty; no notifications on initial load |

## Files Changed

| File | Type | Change |
|---|---|---|
| `Services/NotificationService.swift` | New | Permission, diff, banner posting |
| `Store/PRStore.swift` | Modified | `previousResult`, `unseenPRIds`, `markAllSeen()` |
| `Views/SettingsView.swift` | Modified | Notifications toggle |
| `Views/PRRowView.swift` | Modified | Blue dot overlay |
| `App/AppDelegate.swift` | Modified | Permission on launch, delegate, `markAllSeen()` on open |

No model changes. No new API calls. No new dependencies.

## Testing

**Unit tests (`NotificationServiceTests.swift`):**
- `diff` returns empty when `old` is nil (first launch)
- `diff` detects new `reviewRequested` IDs
- `diff` detects new `changesRequested` IDs
- `diff` detects approved only when `user.login == username`
- `diff` deduplicates — same PR doesn't appear twice

**Unit tests (`PRStoreTests.swift`):**
- `markAllSeen()` clears `unseenPRIds`
- `unseenPRIds` accumulates across two refreshes before popover opens
- `unseenPRIds` not populated when `notifications_enabled` is false
