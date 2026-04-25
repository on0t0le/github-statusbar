# GitHub PR Widget — Design Spec

**Date:** 2026-04-21
**Platform:** macOS
**Stack:** SwiftUI, AppKit (NSStatusItem)

## Overview

Menubar-only macOS app (no dock icon) showing GitHub pull requests assigned to the user or awaiting their review. Refreshes every 5 minutes. Opens PRs in browser on click.

## Architecture

Three layers:

### GitHubService
- Fetches PRs via GitHub REST Search API using a Personal Access Token (PAT)
- Three queries per cycle:
  - `is:pr assignee:@me state:open`
  - `is:pr review-requested:@me state:open`
  - `is:pr author:@me review:changes_requested state:open`
- Deduplicates results by PR id
- Runs on a 5-minute `Timer`
- Future: diffs old vs new PRs, emits change events for notifications

### PRStore
- `ObservableObject` holding categorized PR lists
- Categories:
  - **Waiting on me** — review requested, or changes requested by others awaiting re-review
  - **In progress** — assigned, draft, or awaiting CI
  - **Ready to merge** — approved, all checks green
- Future: stores pending notification events from diff results

### MenuBarUI
- `NSStatusItem` with SwiftUI popover
- Icon: SF Symbol `arrow.triangle.pull` with red badge showing total PR count (hidden when 0)
- Settings stored in `UserDefaults` (non-sensitive) and Keychain (PAT)

## UI

**Popover** (~340pt wide):
```
┌─────────────────────────────────┐
│ GitHub PRs          [⚙] [↻]    │
├─────────────────────────────────┤
│ 👀 WAITING ON ME (2)            │
│  • org/repo  Fix auth bug  @bob │
│  • org/repo  Add tests     @ann │
├─────────────────────────────────┤
│ ✅ READY TO MERGE (1)           │
│  • org/repo  Update deps   @me  │
├─────────────────────────────────┤
│ 🔄 IN PROGRESS (3)              │
│  • ...                          │
├─────────────────────────────────┤
│ Last updated: 2 min ago         │
└─────────────────────────────────┘
```

- `[⚙]` opens Settings sheet
- `[↻]` triggers manual refresh
- Click PR row → opens URL in default browser
- Right-click PR row → copy URL

**Settings sheet:**
- Secure PAT input field (stored in Keychain via `Security` framework)
- GitHub username field
- Optional org/repo filter
- Save button

## Data Flow

```
Timer (5min) / manual refresh
  → GitHubService.fetch()
    → GET /search/issues?q=is:pr+assignee:@me+state:open
    → GET /search/issues?q=is:pr+review-requested:@me+state:open
    → GET /search/issues?q=is:pr+author:@me+review:changes_requested+state:open
    → deduplicate by PR id
    → categorize
  → PRStore.update(newPRs)
    → diff old vs new (future: emit notification events)
  → MenuBarUI re-renders via @Published
```

## Error Handling

| Condition | User-facing message |
|-----------|-------------------|
| No PAT configured | "Add token in Settings" |
| 401 Unauthorized | "Invalid token — check Settings" |
| Rate limit (429/403) | "Rate limited, retry in Xm" |
| Network offline | "No connection" + last-fetch timestamp |

**Rate limits:** GitHub Search API allows 30 req/min authenticated. Two requests per 5-min cycle is well within limits.

**Security:** PAT stored exclusively in Keychain via `Security` framework. Never written to `UserDefaults` or disk.

## Future: Notifications

`PRStore` diffs old vs new PRs on each fetch. New PRs or status changes will emit events consumed by a `NotificationService` using the `UserNotifications` framework. Stub extension point is included in `PRStore` from day one.

## Testing

**Unit tests:**
- `GitHubService` — mock `URLSession`, test JSON parsing, error mapping, deduplication
- `PRStore` — test categorization logic with fixture PRs, test diff logic

**Manual checklist:**
- PAT stored and retrieved from Keychain correctly
- Popover opens/closes, PRs render correctly
- Click opens correct URL in browser
- Error states display (bad token, offline)
- 5-min timer fires and updates badge count

## File Structure

```
GitHubWidget/
├── App/
│   └── GitHubWidgetApp.swift       # AppDelegate, NSStatusItem setup
├── Services/
│   └── GitHubService.swift         # API fetching, PAT auth
├── Store/
│   └── PRStore.swift               # State, categorization, diff
├── Models/
│   └── PullRequest.swift           # PR model
├── Views/
│   ├── PopoverView.swift           # Main popover
│   ├── PRRowView.swift             # Single PR row
│   └── SettingsView.swift          # PAT + config settings
└── Utilities/
    └── KeychainHelper.swift        # PAT Keychain read/write
```

## README

README.md must include:
- Prerequisites (macOS 13+, Xcode)
- How to generate a GitHub PAT (required scopes: `repo`, `read:user`)
- How to build and run
- How to configure (PAT + username)
