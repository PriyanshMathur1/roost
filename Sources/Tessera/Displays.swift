import AppKit
import TesseraCore

/// A connected display, with its usable area (without menu bar and Dock) in the
/// top-left global coordinates Accessibility uses.
struct Display: Equatable {
    /// Stable across reconnects and reboots (the display's UUID), so per-display
    /// settings survive.
    let key: String
    let name: String
    let visible: Rect

    static func all() -> [Display] {
        // Cocoa puts the origin at the bottom-left of the primary display, y up.
        // Accessibility puts it at the top-left of the primary display, y down.
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return [] }
        return NSScreen.screens.map { screen in
            let v = screen.visibleFrame
            return Display(
                key: key(for: screen),
                name: screen.localizedName,
                visible: Rect(x: v.minX, y: primaryHeight - v.maxY, w: v.width, h: v.height)
            )
        }
    }

    /// The display containing the point, else the nearest one.
    static func containing(x: Double, y: Double, in displays: [Display]) -> Display? {
        if let hit = displays.first(where: { $0.visible.contains(x: x, y: y) }) { return hit }
        return displays.min { a, b in
            distanceSquared(from: (x, y), to: a.visible) < distanceSquared(from: (x, y), to: b.visible)
        }
    }

    /// The display under the mouse pointer.
    static func underMouse(in displays: [Display]) -> Display? {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return displays.first }
        let p = NSEvent.mouseLocation
        return containing(x: p.x, y: primaryHeight - p.y, in: displays)
    }

    private static func key(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screen.localizedName
        }
        let id = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String? else { return "display-\(id)" }
        return string
    }

    private static func distanceSquared(from p: (Double, Double), to r: Rect) -> Double {
        let dx = max(r.minX - p.0, 0, p.0 - r.maxX)
        let dy = max(r.minY - p.1, 0, p.1 - r.maxY)
        return dx * dx + dy * dy
    }
}
