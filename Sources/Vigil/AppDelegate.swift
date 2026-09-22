import AppKit
import VigilCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store()
    private var settings: SettingsWindow!
    private var session: LockSession!
    private var statusItem: NSStatusItem!
    private let lockItem = NSMenuItem(title: "锁定", action: #selector(lockFromMenu), keyEquivalent: "l")
    private let quitItem = NSMenuItem(title: "退出", action: #selector(quitFromMenu), keyEquivalent: "q")

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A regular foreground app is not allowed onto another app's fullscreen Space.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsWindow(store: store) { [weak self] in
            self?.lock()
        }
        session = LockSession(store: store) { [weak self] in
            self?.settings.show()
            self?.activate()
        }
        installStatusItem()
        settings.show()
        activate()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        session.isLocked ? .terminateCancel : .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func menuWillOpen(_ menu: NSMenu) {
        lockItem.isEnabled = store.hasPassword && !session.isLocked
        quitItem.isEnabled = !session.isLocked
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Vigil")
        statusItem.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        let openItem = NSMenuItem(title: "打开", action: #selector(openSettings), keyEquivalent: "")
        openItem.target = self
        lockItem.target = self
        quitItem.target = self
        menu.addItem(openItem)
        menu.addItem(lockItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        guard !session.isLocked else { return }
        settings.show()
        activate()
    }

    @objc private func lockFromMenu() {
        lock()
    }

    @objc private func quitFromMenu() {
        guard !session.isLocked else { return }
        NSApp.terminate(nil)
    }

    private func lock() {
        switch session.lock() {
        case .locked:
            break
        case .needsPassword:
            settings.show("请先设置密码")
            activate()
        case .caffeinateFailed(let message):
            settings.show(message)
            activate()
        }
    }

    private func activate() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
