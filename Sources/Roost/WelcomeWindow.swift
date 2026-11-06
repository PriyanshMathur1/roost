import AppKit

/// The first-run window: what Roost does, the one permission it needs (with live status),
/// and the keys to start with. Reopened from the menu with "Getting Started…".
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    var onFinish: (() -> Void)?

    private var window: NSWindow?
    private var statusLabel: NSTextField?
    private var statusDot: NSTextField?
    private var permissionButton: NSButton?
    private var startButton: NSButton?
    private var timer: Timer?

    func show() {
        if window == nil { build() }
        refresh()
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let trusted = AX.isTrusted
        statusDot?.stringValue = trusted ? "●" : "○"
        statusDot?.textColor = trusted ? .systemGreen : .systemOrange
        statusLabel?.stringValue = trusted
            ? "Allowed. Roost can arrange your windows."
            : "Not allowed yet. Turn Roost on in Privacy & Security › Accessibility."
        permissionButton?.isHidden = trusted
        startButton?.isEnabled = trusted
        startButton?.keyEquivalent = trusted ? "\r" : ""
    }

    @objc private func openSettings() {
        AX.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func finish() {
        window?.close()
        onFinish?()
    }

    // MARK: Layout

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 10),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.title = "Welcome to Roost"
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.delegate = self

        let logo = NSImageView(image: Brand.appIcon(size: 96))
        logo.setContentHuggingPriority(.required, for: .vertical)

        let title = label("Welcome to Roost", size: 22, weight: .bold)
        let intro = label("""
            Roost tiles your windows as they open, and remembers where they go on every display setup. \
            Plug into your monitor or unplug for a meeting, and every window goes back to its place.
            """, size: 13, color: .secondaryLabelColor)

        let stepOne = label("1. Allow Roost to arrange windows", size: 14, weight: .semibold)
        let why = label("""
            macOS asks you to approve any app that moves other apps' windows. Roost uses this only to \
            read where windows are and to move and resize them. It never reads their contents.
            """, size: 12, color: .secondaryLabelColor)
        let dot = label("○", size: 14)
        let status = label("", size: 12)
        let statusRow = NSStackView(views: [dot, status])
        statusRow.spacing = 6
        let open = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openSettings))
        open.bezelStyle = .rounded

        let stepTwo = label("2. The keys to start with", size: 14, weight: .semibold)
        let keys = NSGridView(views: [
            ["⌃⌥ ← → ↑ ↓", "Focus the window on that side"],
            ["⌃⌥⇧ ← → ↑ ↓", "Swap with it (at a screen edge: move to the next display)"],
            ["⌃⌥ ↩", "Make the focused window the big one"],
            ["⌃⌥ 1 – 4", "Layout: main + stack, columns, rows, grid"],
            ["⌃⌥ F", "Float a window, or tile it again"],
            ["⌃⌥ ⇥", "Next window waiting in this tile"],
        ].map { [label($0[0], size: 12, weight: .medium, mono: true), label($0[1], size: 12, color: .secondaryLabelColor)] })
        keys.rowSpacing = 6
        keys.columnSpacing = 16
        let drag = label("Or drag: drop a window on another to swap them, or onto another display to move it there.",
                         size: 12, color: .secondaryLabelColor)

        let start = NSButton(title: "Start Tiling", target: self, action: #selector(finish))
        start.bezelStyle = .rounded
        start.controlSize = .large

        let stack = NSStackView(views: [logo, title, intro, spacer(6), stepOne, why, statusRow, open, spacer(6),
                                        stepTwo, keys, drag, spacer(4), start])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 36, left: 32, bottom: 28, right: 32)
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(4, after: stepOne)
        stack.setCustomSpacing(4, after: stepTwo)
        start.translatesAutoresizingMaskIntoConstraints = false
        for view in [intro, why, drag] {
            view.widthAnchor.constraint(equalToConstant: 456).isActive = true
        }

        w.contentView = stack
        statusDot = dot
        statusLabel = status
        permissionButton = open
        startButton = start
        window = w
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor, mono: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.isSelectable = false
        return field
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}
