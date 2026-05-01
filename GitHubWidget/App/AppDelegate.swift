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
    private var updateWatcher: DispatchSourceFileSystemObject?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startWatchingForUpdates()
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        setupStatusItem()
        setupPopover()
        setupBadgeObserver()
        startTimer()
        if UserDefaults.standard.bool(forKey: "notifications_enabled") {
            Task { await NotificationService.shared.requestPermission() }
        }
        KeychainHelper.migrateACLIfNeeded(key: "github_pat")
        Task { await store.refresh() }
    }

    private var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }()

    private func startWatchingForUpdates() {
        guard let execPath = Bundle.main.executablePath else { return }
        let fd = open(execPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            // Delay to let the replacement finish before reading the new bundle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.relaunchIfUpdated()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        updateWatcher = source
    }

    private func relaunchIfUpdated() {
        let infoPlistURL = URL(fileURLWithPath: Bundle.main.bundlePath + "/Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let diskVersion = plist["CFBundleVersion"] as? String,
              let runningVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
              diskVersion != runningVersion else { return }

        updateWatcher?.cancel()
        updateWatcher = nil
        let bundleURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            NSApp.terminate(nil)
        }
    }

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
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: store, onClose: { [weak self] in
                self?.popover.performClose(nil)
            })
        )
    }

    private func setupBadgeObserver() {
        store.$totalCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in self?.updateBadge(count: count) }
            .store(in: &cancellables)

        store.$unseenPRIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (ids: Set<Int>) in self?.updateDot(hasUnseen: !ids.isEmpty) }
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

    private func updateDot(hasUnseen: Bool) {
        guard let button = statusItem.button else { return }
        let base = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "GitHub PRs")!
        guard hasUnseen else {
            button.image = base
            return
        }
        let size = base.size
        let dotRadius: CGFloat = 4
        let composed = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.systemBlue.setFill()
            let dotRect = NSRect(
                x: size.width - dotRadius * 2 - 1,
                y: size.height - dotRadius * 2 - 1,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        composed.isTemplate = false
        button.image = composed
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
