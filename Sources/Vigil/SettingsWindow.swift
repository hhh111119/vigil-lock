import AppKit
import VigilCore

final class SettingsWindow: NSObject, NSTextFieldDelegate {
    private let store: Store
    private let onLock: () -> Void
    private let window: NSWindow
    private let setupBox = NSView()
    private let readyBox = NSView()
    private let password1 = NSSecureTextField()
    private let password2 = NSSecureTextField()
    private let setupError = NSTextField(labelWithString: "")
    private let messageField = NSTextField()
    private let countLabel = NSTextField(labelWithString: "0/80")
    private let awakeSwitch = NSSwitch()
    private let newPassword = NSSecureTextField()
    private let readyError = NSTextField(labelWithString: "")

    init(store: Store, onLock: @escaping () -> Void) {
        self.store = store
        self.onLock = onLock
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 680),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "Vigil"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.bg
        window.isReleasedWhenClosed = false
        window.center()
        build()
        reload()
    }

    func show(_ error: String? = nil) {
        reload()
        if let error {
            readyError.stringValue = error
            readyError.isHidden = false
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
    }

    private func build() {
        guard let content = window.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 52),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
        ])

        root.addArrangedSubview(brandRow())
        root.setCustomSpacing(24, after: root.arrangedSubviews.last!)

        configure(setupBox)
        configure(readyBox)
        root.addArrangedSubview(setupBox)
        root.addArrangedSubview(readyBox)
        setupBox.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        readyBox.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        fillSetup()
        fillReady()
    }

    private func brandRow() -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: nil)
        icon.contentTintColor = Theme.accent
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let mark = NSView()
        mark.wantsLayer = true
        mark.layer?.backgroundColor = Theme.surface.cgColor
        mark.layer?.cornerRadius = 10
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.addSubview(icon)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 44),
            mark.heightAnchor.constraint(equalToConstant: 44),
            icon.centerXAnchor.constraint(equalTo: mark.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
        ])
        let title = label("Vigil", size: 14, color: Theme.fg, weight: .semibold)
        let subtitle = label("守夜 · 锁屏不停机", size: 12, color: Theme.subtle, weight: .regular)
        let words = NSStackView(views: [title, subtitle])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 2
        let row = NSStackView(views: [mark, words])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func fillSetup() {
        let stack = column()
        setupBox.addSubview(stack)
        pin(stack, to: setupBox)
        let lede = wrappingLabel("先设一个解锁密码。只存在这台 Mac 上，不是登录密码，也不上传。")
        stack.addArrangedSubview(lede)
        stack.setCustomSpacing(16, after: lede)
        stack.addArrangedSubview(caption("解锁密码"))
        style(password1, placeholder: "")
        password1.delegate = self
        stack.addArrangedSubview(password1)
        stack.addArrangedSubview(caption("再输入一次"))
        style(password2, placeholder: "")
        stack.addArrangedSubview(password2)
        styleError(setupError)
        stack.addArrangedSubview(setupError)
        let button = filledButton("开始使用")
        button.target = self
        button.action = #selector(createPassword)
        stack.addArrangedSubview(button)
        stack.widthAnchor.constraint(equalTo: password1.widthAnchor).isActive = true
    }

    private func fillReady() {
        let stack = column()
        readyBox.addSubview(stack)
        pin(stack, to: readyBox)
        let lockButton = filledButton("立即锁定")
        lockButton.target = self
        lockButton.action = #selector(lockNow)
        stack.addArrangedSubview(lockButton)
        let hint = label("菜单栏也可以锁定 · 密码存在本机", size: 12, color: Theme.subtle, weight: .regular)
        hint.alignment = .center
        stack.addArrangedSubview(hint)
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: hint)
        stack.addArrangedSubview(caption("守夜留言"))
        style(messageField, placeholder: "", height: 72)
        messageField.delegate = self
        messageField.cell?.wraps = true
        messageField.cell?.isScrollable = false
        messageField.maximumNumberOfLines = 3
        stack.addArrangedSubview(messageField)
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = Theme.subtle
        countLabel.alignment = .right
        stack.addArrangedSubview(countLabel)
        countLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let awakeTitle = label("屏幕常亮", size: 14, color: Theme.fg, weight: .medium)
        let awakeDetail = label("锁定期间阻止空闲休眠", size: 12, color: Theme.subtle, weight: .regular)
        let words = NSStackView(views: [awakeTitle, awakeDetail])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 2
        awakeSwitch.target = self
        awakeSwitch.action = #selector(toggleAwake)
        let row = NSStackView(views: [words, awakeSwitch])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .equalSpacing
        row.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        row.wantsLayer = true
        row.layer?.backgroundColor = Theme.surface.cgColor
        row.layer?.cornerRadius = 10
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.addArrangedSubview(caption("更改密码"))
        style(newPassword, placeholder: "留空表示不更改")
        stack.addArrangedSubview(newPassword)
        let save = secondaryButton("保存密码")
        save.target = self
        save.action = #selector(changePassword)
        stack.addArrangedSubview(save)
        styleError(readyError)
        stack.addArrangedSubview(readyError)
    }

    private func reload() {
        let ready = store.hasPassword
        setupBox.isHidden = ready
        readyBox.isHidden = !ready
        setupError.stringValue = ""
        readyError.stringValue = ""
        messageField.stringValue = store.config.message
        countLabel.stringValue = "\(messageField.stringValue.count)/80"
        awakeSwitch.state = store.config.keepAwake ? .on : .off
    }

    @objc private func createPassword() {
        setupError.stringValue = ""
        let first = password1.stringValue
        let second = password2.stringValue
        if first.count < 4 {
            setupError.stringValue = "至少 4 个字符"
            return
        }
        if first != second {
            setupError.stringValue = "两次输入不一致"
            return
        }
        do {
            try store.setPassword(first)
            password1.stringValue = ""
            password2.stringValue = ""
            reload()
        } catch {
            setupError.stringValue = "没能保存密码"
        }
    }

    @objc private func lockNow() {
        readyError.stringValue = ""
        onLock()
    }

    @objc private func toggleAwake() {
        do {
            try store.setKeepAwake(awakeSwitch.state == .on)
        } catch {
            readyError.stringValue = "没能保存设置"
        }
    }

    @objc private func changePassword() {
        readyError.stringValue = ""
        let value = newPassword.stringValue
        guard !value.isEmpty else { return }
        if value.count < 4 {
            readyError.stringValue = "至少 4 个字符"
            return
        }
        do {
            try store.setPassword(value)
            newPassword.stringValue = ""
        } catch {
            readyError.stringValue = "没能保存密码"
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === messageField else { return }
        if field.stringValue.count > 80 {
            field.stringValue = String(field.stringValue.prefix(80))
        }
        countLabel.stringValue = "\(field.stringValue.count)/80"
        try? store.setMessage(field.stringValue)
    }

    private func column() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func configure(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    private func pin(_ child: NSView, to parent: NSView) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    private func caption(_ text: String) -> NSTextField {
        label(text, size: 12, color: Theme.muted, weight: .medium)
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let field = label(text, size: 14, color: Theme.muted, weight: .regular)
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 3
        field.preferredMaxLayoutWidth = 364
        return field
    }

    private func label(_ text: String, size: CGFloat, color: NSColor, weight: NSFont.Weight) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byWordWrapping
        return field
    }

    private func style(_ field: NSTextField, placeholder: String, height: CGFloat = 36) {
        field.placeholderString = placeholder
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = Theme.surface
        field.textColor = Theme.fg
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.wantsLayer = true
        field.layer?.cornerRadius = 8
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: height).isActive = true
        field.widthAnchor.constraint(equalToConstant: 364).isActive = true
    }

    private func styleError(_ field: NSTextField) {
        field.font = .systemFont(ofSize: 12)
        field.textColor = Theme.danger
        field.stringValue = ""
    }

    private func filledButton(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = Theme.accent.cgColor
        button.layer?.cornerRadius = 8
        button.contentTintColor = Theme.bg
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.widthAnchor.constraint(equalToConstant: 364).isActive = true
        return button
    }

    private func secondaryButton(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 14, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.widthAnchor.constraint(equalToConstant: 364).isActive = true
        return button
    }
}

enum Theme {
    static let bg = NSColor(srgbRed: 0.039, green: 0.039, blue: 0.043, alpha: 1)
    static let surface = NSColor(srgbRed: 0.102, green: 0.102, blue: 0.118, alpha: 1)
    static let fg = NSColor(srgbRed: 0.957, green: 0.957, blue: 0.961, alpha: 1)
    static let muted = NSColor(srgbRed: 0.631, green: 0.631, blue: 0.667, alpha: 1)
    static let subtle = NSColor(srgbRed: 0.443, green: 0.443, blue: 0.478, alpha: 1)
    static let accent = NSColor(srgbRed: 0.784, green: 0.800, blue: 0.831, alpha: 1)
    static let danger = NSColor(srgbRed: 0.769, green: 0.361, blue: 0.361, alpha: 1)
}
