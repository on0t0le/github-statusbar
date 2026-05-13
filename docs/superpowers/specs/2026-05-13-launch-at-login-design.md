# Launch at Login — Design Spec

**Date:** 2026-05-13
**Status:** Approved

## Overview

Add a "Launch at login" toggle to `SettingsView` so users can register/unregister the app as a macOS login item without leaving the app.

## API Choice

Use `SMAppService.mainApp` from the `ServiceManagement` framework (macOS 13+). This API registers the main app bundle itself — no helper bundle, no entitlements changes, no `UserDefaults` required. The system maintains authoritative state; we read it back on every `onAppear`.

Alternatives rejected:
- `LSSharedFileList` — deprecated, removed in future OS versions
- `UserDefaults` + deferred apply — state drifts if user changes login items in System Settings manually

## Architecture

### Framework linkage

Add `ServiceManagement` to the `GitHubWidget` target in `project.yml` under `dependencies`. No entitlements changes needed (app is not sandboxed).

### SettingsView changes

- Add `@State private var launchAtLogin = false`
- In `load()`: set `launchAtLogin = (SMAppService.mainApp.status == .enabled)`
- Add `Toggle("Launch at login", isOn: Binding(...))` below the existing notifications toggle
- Binding `set` closure: call `try SMAppService.mainApp.register()` when `true`, `try SMAppService.mainApp.unregister()` when `false`. Errors are silently swallowed (mirrors the notifications toggle pattern; no action the user can take on failure).
- No changes to `save()` — this setting is system-managed, not persisted in `UserDefaults` or Keychain.

## Data Flow

```
onAppear → load() → SMAppService.mainApp.status → launchAtLogin state
Toggle interaction → SMAppService.mainApp.register/unregister() → system Login Items
```

## Error Handling

Silent failure matches existing notifications toggle pattern. `SMAppService` errors in this context are rare (e.g., damaged bundle) and not actionable by the user.

## Testing

No unit tests required — `SMAppService` is a system API with no mockable interface. Manual test: toggle on → verify app appears in System Settings → General → Login Items → Open at Login. Toggle off → verify it disappears.

## Out of Scope

- Right-click context menu toggle (deferred, user selected settings-only)
- Visual error feedback on registration failure
