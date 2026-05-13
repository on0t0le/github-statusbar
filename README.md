# GitHub PR Widget

A macOS menubar app that keeps your GitHub pull requests one click away.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.0-orange)

## Overview

GitHub PR Widget lives in your menubar and surfaces the PRs that need your attention — no browser tab required. It refreshes every 5 minutes and shows a badge count so you always know your workload at a glance.

## Features

### PR triage at a glance

| Category | What it means |
|---|---|
| 👀 **Waiting on me** | Review requested, or changes requested on your own PR |
| ✅ **Ready to merge** | Your PRs that have been approved |
| 🔄 **In progress** | PRs assigned to you |

Click any PR in the list to open it in your browser.

### Notifications

Opt-in desktop notifications alert you when PR status changes — new review requests, approvals, and more. Toggle in Settings.

### Launch at login

Register the app as a macOS login item directly from Settings — no System Settings detour needed.

### Org / repo filtering

Scope the PR list to a specific org (`myorg`) or repo (`myorg/myrepo`). Leave blank to see all your PRs across GitHub.

### Multiple accounts

Connect up to 5 GitHub accounts (personal, work, client orgs) simultaneously. Each account is shown as its own labelled section in the popover. Add, edit, and remove accounts from Settings — tokens are stored per-account in the macOS Keychain.

### Secure token storage

Your GitHub Personal Access Token is stored in the macOS Keychain, never in plaintext.

## Setup

### 1. Generate a GitHub token

Go to **github.com/settings/tokens → Generate new token (classic)**

Required scopes: `repo`, `read:user`

Copy the token (starts with `ghp_`).

### 2. Configure the app

1. Click the menubar icon
2. Click the ⚙ gear icon to open Settings
3. Click **+** to add an account
4. Enter a name (e.g. "Personal"), your GitHub username, and paste your token
5. Optionally enter an org or repo filter
6. Click **Add**

Repeat for additional accounts (up to 5).

## Requirements

- macOS 13 Ventura or later
- A GitHub account with a Personal Access Token

---

## Building from source

```bash
brew install xcodegen
xcodegen generate
open GitHubWidget.xcodeproj
```

Press **⌘R** in Xcode to run.

### Package as .pkg

```bash
# Archive
xcodebuild archive \
  -project GitHubWidget.xcodeproj \
  -scheme GitHubWidget \
  -configuration Release \
  -archivePath build/GitHubWidget.xcarchive \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-"

# Package
mkdir -p build/pkg-root/Applications
ditto build/GitHubWidget.xcarchive/Products/Applications/GitHubWidget.app \
  build/pkg-root/Applications/GitHubWidget.app

pkgbuild \
  --root build/pkg-root \
  --identifier com.github-widget.GitHubWidget \
  --version 1.1.1 \
  --install-location / \
  build/GitHubWidget.pkg
```

`CODE_SIGN_IDENTITY="-"` signs ad-hoc (no Apple Developer account required). For distribution, replace with your Developer ID identity and run `productsign` + `xcrun notarytool`.
