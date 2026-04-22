# GitHub PR Widget

macOS menubar app showing GitHub pull requests that need your attention.

## What it shows

- **👀 Waiting on me** — review requested on your PRs, or changes requested that need your update
- **✅ Ready to merge** — your PRs that have been approved
- **🔄 In progress** — PRs assigned to you

Badge count on the menubar icon shows the total PRs across all categories. Refreshes every 5 minutes. Click any PR to open it in your browser.

## Prerequisites

- macOS 13+
- Xcode 15+
- [Homebrew](https://brew.sh) (for xcodegen)

## Build & Run

```
brew install xcodegen
xcodegen generate
open GitHubWidget.xcodeproj
```

Press **⌘R** in Xcode to run.

## Configuration

1. **Generate a GitHub Personal Access Token**
   - Go to github.com/settings/tokens → **Generate new token (classic)**
   - Required scopes: `repo`, `read:user`
   - Copy the generated token (starts with `ghp_`)

2. **Configure the app**
   - Click the menubar icon
   - Click the ⚙ gear icon
   - Paste your token in the **Personal Access Token** field
   - Enter your **GitHub username**
   - Optionally filter to a specific org (`myorg`) or repo (`myorg/myrepo`)
   - Click **Save**

The token is stored securely in your macOS Keychain.

## Future

- macOS notifications for new review requests and PR status changes
