import AppKit

/// Roost's mark: a roof over three tiles (one main window, two stacked beside it).
/// Home + tiling, the app's two ideas. Used for the menu-bar icon, the welcome window and,
/// through scripts/make-icon, the app icon. Self-contained so the icon script can compile it.
enum Brand {
    /// Colours of the app icon background, top to bottom (dusk: indigo into amber).
    static let skyTop = NSColor(srgbRed: 0.17, green: 0.18, blue: 0.43, alpha: 1)
    static let skyBottom = NSColor(srgbRed: 0.94, green: 0.54, blue: 0.29, alpha: 1)
    static let cream = NSColor(srgbRed: 1.0, green: 0.96, blue: 0.88, alpha: 1)

    /// Draws the mark in `rect` (a flipped, y-down context) with `color`.
    static func drawMark(in rect: NSRect, color: NSColor) {
        let s = min(rect.width, rect.height)
        let ox = rect.midX - s / 2, oy = rect.midY - s / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * s, y: oy + y * s) }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
            NSBezierPath(roundedRect: NSRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s),
                         xRadius: 0.045 * s, yRadius: 0.045 * s)
        }
        color.setFill()
        color.setStroke()

        let roof = NSBezierPath()
        roof.move(to: p(0.10, 0.44))
        roof.line(to: p(0.50, 0.11))
        roof.line(to: p(0.90, 0.44))
        roof.lineWidth = 0.085 * s
        roof.lineCapStyle = .round
        roof.lineJoinStyle = .round
        roof.stroke()

        box(0.22, 0.50, 0.29, 0.40).fill()  // main window
        box(0.56, 0.50, 0.22, 0.175).fill() // stack, top
        box(0.56, 0.725, 0.22, 0.175).fill() // stack, bottom
    }

    /// The menu-bar icon: the mark as a template image, so macOS tints it for light, dark
    /// and highlighted menu bars.
    static func menuBarIcon(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            drawMark(in: rect, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Roost"
        return image
    }

    /// The app icon artwork: a macOS-style rounded square with the dusk gradient and the
    /// mark in cream.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            // macOS icon grid: the shape is ~80% of the canvas, corner radius ~22.5% of it.
            let inset = rect.width * 0.1
            let tile = rect.insetBy(dx: inset, dy: inset)
            let radius = tile.width * 0.225
            let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = rect.width * 0.02
            shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.01)
            shadow.set()
            skyTop.setFill()
            shape.fill()
            NSGraphicsContext.current?.restoreGraphicsState()

            NSGradient(starting: skyTop, ending: skyBottom)?.draw(in: shape, angle: 90)
            drawMark(in: tile.insetBy(dx: tile.width * 0.16, dy: tile.width * 0.16), color: cream)
            return true
        }
    }
}
