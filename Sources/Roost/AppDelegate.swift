import AppKit
import ServiceManagement
import RoostCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private lazy var controller = TilingController(settings: settings)
    private let hotKeys = HotKeys()
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        controller.onStateChange = { [weak self] in self?.updateIcon() }
        registerShortcuts()
        updateIcon()

        if AX.isTrusted {
            controller.start()
        } else {
            AX.requestTrust()
            // There is no notification for the grant, so check until it arrives.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard AX.isTrusted else { return }
                    timer.invalidate()
                    self?.controller.start()
                    self?.updateIcon()
                }
            }
        }
    }

    // MARK: Shortcuts

    private func registerShortcuts() {
        typealias K = HotKeys.Key
        let c = controller
        var list: [HotKeys.Shortcut] = []
        let arrows: [(Int, Direction, String)] = [(K.left, .left, "←"), (K.right, .right, "→"), (K.up, .up, "↑"), (K.down, .down, "↓")]
        for (key, direction, glyph) in arrows {
            list.append(.init(keyCode: key, modifiers: HotKeys.ctrlOpt, label: "⌃⌥\(glyph)  Focus \(direction.rawValue)") { c.focus(direction) })
            list.append(.init(keyCode: key, modifiers: HotKeys.ctrlOptShift, label: "⌃⌥⇧\(glyph)  Swap \(direction.rawValue)") { c.swap(direction) })
        }
        list.append(.init(keyCode: K.returnKey, modifiers: HotKeys.ctrlOpt, label: "⌃⌥↩  Make main") { c.promote() })
        list.append(.init(keyCode: K.equal, modifiers: HotKeys.ctrlOpt, label: "⌃⌥=  Grow") { c.resize(grow: true) })
        list.append(.init(keyCode: K.minus, modifiers: HotKeys.ctrlOpt, label: "⌃⌥-  Shrink") { c.resize(grow: false) })
        list.append(.init(keyCode: K.f, modifiers: HotKeys.ctrlOpt, label: "⌃⌥F  Float / tile window") { c.toggleFloat() })
        list.append(.init(keyCode: K.t, modifiers: HotKeys.ctrlOpt, label: "⌃⌥T  Tiling on / off") { c.setEnabled(!c.isEnabled) })
        for (i, kind) in LayoutKind.allCases.enumerated() {
            list.append(.init(keyCode: K.digits[i], modifiers: HotKeys.ctrlOpt, label: "⌃⌥\(i + 1)  \(kind.title)") { c.setLayout(kind) })
        }
        hotKeys.register(list)
    }

    // MARK: Menu

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let active = controller.isEnabled && AX.isTrusted
        let image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Roost")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !active
        button.toolTip = active ? "Roost: tiling \(controller.tiledCount) windows" : "Roost: paused"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !AX.isTrusted {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
            menu.addItem(disabled("Roost needs it to move windows."))
            menu.addItem(.separator())
        }

        let toggle = item("Tiling", #selector(toggleTiling))
        toggle.state = controller.isEnabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(disabled("\(controller.tiledCount) tiled · \(controller.floatingCount) floating"))
        menu.addItem(.separator())

        let displays = Display.all()
        if let display = Display.underMouse(in: displays) {
            let current = controller.layout(for: display.key)
            menu.addItem(disabled(displays.count > 1 ? "Layout on \(display.name)" : "Layout"))
            for kind in LayoutKind.allCases {
                let entry = item("   \(kind.title)", #selector(chooseLayout(_:)))
                entry.representedObject = [kind.rawValue, display.key]
                entry.state = kind == current ? .on : .off
                menu.addItem(entry)
            }
            menu.addItem(.separator())
        }

        let gapMenu = NSMenu()
        for gap in Settings.gapChoices {
            let entry = item(gap == 0 ? "None" : "\(Int(gap)) pt", #selector(chooseGap(_:)))
            entry.representedObject = gap
            entry.state = gap == settings.gap ? .on : .off
            gapMenu.addItem(entry)
        }
        let gapItem = NSMenuItem(title: "Gap", action: nil, keyEquivalent: "")
        gapItem.submenu = gapMenu
        menu.addItem(gapItem)

        let tileMenu = NSMenu()
        for width in Settings.minTileChoices {
            let entry = item(width == 0 ? "No limit" : "\(Int(width)) pt", #selector(chooseMinTile(_:)))
            entry.representedObject = width
            entry.state = width == settings.minTileWidth ? .on : .off
            tileMenu.addItem(entry)
        }
        let tileItem = NSMenuItem(title: "Narrowest Tile", action: nil, keyEquivalent: "")
        tileItem.submenu = tileMenu
        menu.addItem(tileItem)
        menu.addItem(item("Re-tile Now", #selector(retile)))
        menu.addItem(item("Reset Sizes", #selector(resetSizes)))

        let keys = NSMenu()
        for label in hotKeys.registered { keys.addItem(disabled(label)) }
        for label in hotKeys.failed { keys.addItem(disabled("\(label)  (taken by another app)")) }
        let keysItem = NSMenuItem(title: "Keyboard Shortcuts", action: nil, keyEquivalent: "")
        keysItem.submenu = keys
        menu.addItem(keysItem)
        menu.addItem(.separator())

        let login = item("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Quit Roost", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleTiling() { controller.setEnabled(!controller.isEnabled) }
    @objc private func retile() { controller.reconcile() }
    @objc private func resetSizes() { controller.resetSizes() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func chooseLayout(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], let kind = LayoutKind(rawValue: pair[0]) else { return }
        controller.setLayout(kind, displayKey: pair[1])
    }

    @objc private func chooseMinTile(_ sender: NSMenuItem) {
        guard let width = sender.representedObject as? Double else { return }
        controller.setMinTileWidth(width)
    }

    @objc private func chooseGap(_ sender: NSMenuItem) {
        guard let gap = sender.representedObject as? Double else { return }
        controller.setGap(gap)
    }

    @objc private func openAccessibilitySettings() {
        AX.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
