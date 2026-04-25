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

## Build a .pkg installer

### 1. Generate the Xcode project

```bash
brew install xcodegen
xcodegen generate
```

### 2. Build a release archive

```bash
xcodebuild archive \
  -project GitHubWidget.xcodeproj \
  -scheme GitHubWidget \
  -configuration Release \
  -archivePath build/GitHubWidget.xcarchive \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-"
```

`CODE_SIGN_IDENTITY="-"` signs ad-hoc (no Apple Developer account needed). For notarization, replace with your Developer ID identity.

### 3. Export the .app

```bash
xcodebuild -exportArchive \
  -archivePath build/GitHubWidget.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

Create `ExportOptions.plist` in the repo root:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>mac-application</string>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
```

### 4. Package with pkgbuild

```bash
mkdir -p build/pkg-root/Applications
ditto build/export/GitHubWidget.app build/pkg-root/Applications/GitHubWidget.app

pkgbuild \
  --root build/pkg-root \
  --identifier com.github-widget.GitHubWidget \
  --version 1.0.0 \
  --install-location / \
  build/GitHubWidget.pkg
```

The `.pkg` installs `GitHubWidget.app` to `/Applications`.

### 5. (Optional) Sign and notarize

Sign the package with a Developer ID Installer certificate:

```bash
productsign \
  --sign "Developer ID Installer: Your Name (TEAMID)" \
  build/GitHubWidget.pkg \
  build/GitHubWidget-signed.pkg
```

Then submit for notarization:

```bash
xcrun notarytool submit build/GitHubWidget-signed.pkg \
  --apple-id you@example.com \
  --team-id TEAMID \
  --password "@keychain:AC_PASSWORD" \
  --wait

xcrun stapler staple build/GitHubWidget-signed.pkg
```

## Future

- macOS notifications for new review requests and PR status changes
