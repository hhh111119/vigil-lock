import AppKit
import VigilCore

enum LockResult {
    case locked
    case needsPassword
    case caffeinateFailed(String)
}

final class LockSession: NSObject, NSWindowDelegate {
    private let store: Store
    private let onUnlock: () -> Void
    private let caffeinate = Caffeinate()
    private var panels: [LockPanel] = []
    private var lockedAt: Date?
    private var failed = 0
    private var backoffUntil: Date?
    private var timer: Timer?
    private var verifying = false

    var isLocked: Bool { lockedAt != nil }

    init(store: Store, onUnlock: @escaping () -> Void) {
        self.store = store
        self.onUnlock = onUnlock
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func lock() -> LockResult {
        guard store.hasPassword else { return .needsPassword }
        if isLocked { return .locked }
        if store.config.keepAwake {
            do {
                try caffeinate.start()
            } catch {
                return .caffeinateFailed("无法启动 caffeinate")
            }
        }
        lockedAt = Date()
        failed = 0
        backoffUntil = nil
        NSApp.windows.forEach { window in
            if !(window is LockPanel) { window.orderOut(nil) }
        }
        showPanels()
        NSApp.presentationOptions = Self.kiosk
        // Kiosk can drop a panel off the Space it just joined. Put them back.
        showPanels()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        return .locked
    }

    func unlock() {
        timer?.invalidate()
        timer = nil
        caffeinate.stop()
        lockedAt = nil
        failed = 0
        backoffUntil = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        NSApp.presentationOptions = []
        onUnlock()
    }

    @objc private func screensChanged() {
        guard isLocked else { return }
        showPanels()
    }

    private func showPanels() {
        let screens = NSScreen.screens
        if panels.count != screens.count {
            panels.forEach { $0.orderOut(nil) }
            panels = screens.map { makePanel(for: $0) }
        }
        let mouse = NSEvent.mouseLocation
        var keyPanel: LockPanel?
        for (panel, screen) in zip(panels, screens) {
            panel.setFrame(screen.frame, display: false)
            panel.orderFrontRegardless()
            if screen.frame.contains(mouse) { keyPanel = panel }
        }
        (keyPanel ?? panels.first)?.makeKey()
        tick()
    }

    private func makePanel(for screen: NSScreen) -> LockPanel {
        let panel = LockPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isMovable = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.backgroundColor = Theme.bg
        panel.title = "Vigil"
        // Apple's overlay recipe: an accessory app's nonactivating panel, at the
        // screensaver level, allowed to join other apps' fullscreen Spaces.
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        let content = LockContentView(frame: screen.frame)
        content.onSubmit = { [weak self, weak content] in
            self?.submit(content?.password.stringValue ?? "")
        }
        panel.contentView = content
        panel.setFrame(screen.frame, display: false)
        return panel
    }

    private func submit(_ password: String) {
        guard !verifying, isLocked else { return }
        if let until = backoffUntil, Date() < until {
            return
        }
        verifying = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = self?.store.verify(password) ?? false
            DispatchQueue.main.async {
                guard let self else { return }
                self.verifying = false
                self.panels.forEach { ($0.contentView as? LockContentView)?.password.stringValue = "" }
                if ok {
                    self.unlock()
                    return
                }
                self.failed += 1
                let shift = min(self.failed - 1, 3)
                let wait = min(1.0 * pow(2.0, Double(shift)), 8.0)
                self.backoffUntil = Date().addingTimeInterval(wait)
                self.panels.forEach { ($0.contentView as? LockContentView)?.showWrong() }
                self.tick()
            }
        }
    }

    private func tick() {
        guard let lockedAt else { return }
        let elapsed = Date().timeIntervalSince(lockedAt)
        let wait = backoffUntil.map { max(0, $0.timeIntervalSinceNow) } ?? 0
        for panel in panels {
            (panel.contentView as? LockContentView)?.update(
                message: store.config.message,
                keepAwake: store.config.keepAwake,
                elapsed: elapsed,
                wait: wait
            )
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { false }

    private static let kiosk: NSApplication.PresentationOptions = [
        .hideDock,
        .hideMenuBar,
        .disableAppleMenu,
        .disableProcessSwitching,
        .disableForceQuit,
        .disableSessionTermination,
        .disableHideApplication,
    ]
}

final class LockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class LockContentView: NSView {
    var onSubmit: (() -> Void)?
    let password = NSSecureTextField()
    private let elapsedField = NSTextField(labelWithString: "00m 00s")
    private let clock = NSTextField(labelWithString: "00:00")
    private let dateField = NSTextField(labelWithString: "")
    private let messageField = NSTextField(labelWithString: "")
    private let button = NSButton(title: "解锁", target: nil, action: nil)
    private let errorField = NSTextField(labelWithString: "")
    private let footer = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.bg.cgColor

        style(elapsedField, size: 12, color: Theme.subtle, mono: true)
        elapsedField.alignment = .right
        style(clock, size: 96, color: Theme.fg, mono: false)
        clock.font = NSFont(name: "Iowan Old Style", size: 96) ?? .systemFont(ofSize: 96, weight: .medium)
        clock.alignment = .center
        style(dateField, size: 14, color: Theme.muted, mono: false)
        dateField.alignment = .center
        style(messageField, size: 16, color: Theme.fg, mono: false)
        messageField.alignment = .center
        messageField.cell?.wraps = true
        messageField.maximumNumberOfLines = 3

        password.placeholderString = "输入密码解锁"
        password.isBezeled = false
        password.drawsBackground = true
        password.backgroundColor = Theme.surface
        password.textColor = Theme.fg
        password.font = .systemFont(ofSize: 14)
        password.focusRingType = .none
        password.alignment = .left
        password.target = self
        password.action = #selector(submit)

        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = Theme.accent.cgColor
        button.layer?.cornerRadius = 8
        button.contentTintColor = Theme.bg
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.target = self
        button.action = #selector(submit)
        button.keyEquivalent = "\r"

        style(errorField, size: 12, color: Theme.danger, mono: false)
        errorField.alignment = .center
        style(footer, size: 12, color: Theme.subtle, mono: false)
        footer.alignment = .center

        let live = NSTextField(labelWithString: "VIGIL · 守夜中")
        style(live, size: 12, color: Theme.subtle, mono: false)
        addSubview(live)
        live.frame = NSRect(x: 40, y: 0, width: 200, height: 18)
        live.autoresizingMask = [.minYMargin]

        for view in [elapsedField, clock, dateField, messageField, password, button, errorField, footer] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let width = bounds.width
        let height = bounds.height
        subviews.first?.frame = NSRect(x: 40, y: height - 48, width: 220, height: 18)
        elapsedField.frame = NSRect(x: width - 240, y: height - 48, width: 200, height: 18)
        footer.frame = NSRect(x: 40, y: 28, width: width - 80, height: 18)

        let formWidth = min(320, width - 80)
        let formX = (width - formWidth) / 2
        let clockSize = min(112, max(64, width * 0.09))
        clock.font = NSFont(name: "Iowan Old Style", size: clockSize) ?? .systemFont(ofSize: clockSize, weight: .medium)
        var y = height * 0.58
        clock.frame = NSRect(x: 40, y: y, width: width - 80, height: clockSize + 8)
        y -= 28
        dateField.frame = NSRect(x: 40, y: y, width: width - 80, height: 20)
        y -= 56
        messageField.frame = NSRect(x: (width - min(448, width - 80)) / 2, y: y, width: min(448, width - 80), height: 48)
        y -= 56
        password.frame = NSRect(x: formX, y: y, width: formWidth, height: 36)
        y -= 52
        button.frame = NSRect(x: formX, y: y, width: formWidth, height: 40)
        errorField.frame = NSRect(x: formX, y: y - 22, width: formWidth, height: 18)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(password)
    }

    func update(message: String, keepAwake: Bool, elapsed: TimeInterval, wait: TimeInterval) {
        let now = Date()
        clock.stringValue = Self.clockFormatter.string(from: now)
        dateField.stringValue = Self.dateFormatter.string(from: now)
        elapsedField.stringValue = Self.format(elapsed)
        let text = message.isEmpty ? Config.defaultMessage : message
        messageField.stringValue = text
        footer.stringValue = keepAwake ? "进程继续运行 · 屏幕不会休眠" : "进程继续运行 · 未阻止休眠"
        if wait > 0 {
            button.isEnabled = false
            button.title = "请稍候 \(Int(ceil(wait)))s"
        } else {
            button.isEnabled = true
            button.title = "解锁"
        }
    }

    func showWrong() {
        errorField.stringValue = "密码不正确"
    }

    @objc private func submit() {
        errorField.stringValue = ""
        onSubmit?()
    }

    private func style(_ field: NSTextField, size: CGFloat, color: NSColor, mono: Bool) {
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = false
        field.isSelectable = false
        field.textColor = color
        field.font = mono
            ? .monospacedDigitSystemFont(ofSize: size, weight: .regular)
            : .systemFont(ofSize: size)
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        }
        return String(format: "%02dm %02ds", minutes, seconds)
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter
    }()
}
