import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = CorrectionCoordinator()
    private let eventTap = EventTap()
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var pauseItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        eventTap.delegate = coordinator

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        if AccessibilityClient.isTrusted {
            startEventTap()
        } else {
            statusMenuItem.title = "Accessibility permission required"
            AccessibilityClient.requestPermission()
            permissionTimer = Timer.scheduledTimer(
                timeInterval: 1,
                target: self,
                selector: #selector(checkPermission),
                userInfo: nil,
                repeats: true
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        eventTap.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "number.circle",
            accessibilityDescription: "60Minus"
        )

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePaused), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let settings = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit 60Minus", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func startEventTap() {
        if eventTap.start() {
            statusMenuItem.title = "60Minus is running"
            permissionTimer?.invalidate()
            permissionTimer = nil
        } else {
            statusMenuItem.title = "Could not start keyboard monitor"
        }
    }

    @objc private func checkPermission() {
        if AccessibilityClient.isTrusted { startEventTap() }
    }

    @objc private func togglePaused() {
        coordinator.isPaused.toggle()
        pauseItem.title = coordinator.isPaused ? "Resume" : "Pause"
        statusMenuItem.title = coordinator.isPaused ? "60Minus is paused" : "60Minus is running"
    }

    @objc private func frontmostApplicationChanged() {
        coordinator.applicationChanged()
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
