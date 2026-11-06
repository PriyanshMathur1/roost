import AppKit
import ApplicationServices
import RoostCore

/// A window of another app, reached through the Accessibility API.
/// Equality and hashing use `CFEqual`/`CFHash`, which identify the same window
/// across separate `AXUIElement` references.
struct WindowRef: Hashable, CustomStringConvertible {
    let element: AXUIElement
    let pid: pid_t

    static func == (lhs: WindowRef, rhs: WindowRef) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }

    var description: String {
        let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
        return "\(app) “\(AX.string(element, kAXTitleAttribute) ?? "")”"
    }

    /// The app's bundle ID, used to remember things about an app across restarts.
    var appID: String { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid-\(pid)" }

    /// How this window can be recognised after a restart.
    var tag: WindowTag { WindowTag(app: appID, title: AX.string(element, kAXTitleAttribute) ?? "") }

    // MARK: State

    var frame: Rect? {
        guard let p = AX.point(element, kAXPositionAttribute), let s = AX.size(element, kAXSizeAttribute) else { return nil }
        return Rect(x: p.x, y: p.y, w: s.width, h: s.height)
    }

    /// Ordinary document/app windows only: not dialogs, sheets, panels, palettes or popovers.
    var isStandard: Bool {
        AX.string(element, kAXRoleAttribute) == kAXWindowRole
            && AX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole
    }

    var isMinimized: Bool { AX.bool(element, kAXMinimizedAttribute) ?? false }
    var isFullScreen: Bool { AX.bool(element, "AXFullScreen") ?? false }
    var canMove: Bool { AX.isSettable(element, kAXPositionAttribute) && AX.isSettable(element, kAXSizeAttribute) }

    // MARK: Actions

    /// Size, then position, then size again: a window that can't take the new size at its old
    /// position (it would cross a screen edge) gets it once it has moved.
    func setFrame(_ r: Rect) {
        var size = CGSize(width: r.w, height: r.h)
        var origin = CGPoint(x: r.x, y: r.y)
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
    }

    func focus() {
        NSRunningApplication(processIdentifier: pid)?.activate()
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    // MARK: Lookup

    /// The focused window of the frontmost app.
    static func focused() -> WindowRef? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AX.application(app.processIdentifier)
        guard let window = AX.element(appElement, kAXFocusedWindowAttribute) else { return nil }
        return WindowRef(element: window, pid: app.processIdentifier)
    }

    static func windows(of pid: pid_t) -> [WindowRef] {
        AX.elements(AX.application(pid), kAXWindowsAttribute).map { WindowRef(element: $0, pid: pid) }
    }
}

/// Thin, typed helpers over the C Accessibility API.
enum AX {
    /// How long one call to an app may take before we give up on it, so a hung app
    /// can't freeze Roost.
    static let messagingTimeout: Float = 0.4

    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (value(element, attribute) as? NSNumber)?.boolValue
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let array = value(element, attribute) as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &size) ? size : nil
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    /// Chromium and Electron apps animate every move while "enhanced user interface" is on
    /// (it is switched on by assistive apps), which makes tiling visibly slow. Turn it off
    /// for the duration of `body`, then restore it.
    static func withEnhancedUserInterfaceOff(pid: pid_t, _ body: () -> Void) {
        let app = application(pid)
        let key = "AXEnhancedUserInterface" as CFString
        let wasOn = bool(app, "AXEnhancedUserInterface") ?? false
        if wasOn { AXUIElementSetAttributeValue(app, key, kCFBooleanFalse) }
        body()
        if wasOn { AXUIElementSetAttributeValue(app, key, kCFBooleanTrue) }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to Privacy & Security › Accessibility.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
