/// A rectangle in "top-left global" points: origin at the top-left of the primary
/// display, y growing downwards. This is the space the Accessibility API uses.
public struct Rect: Equatable, Hashable, CustomStringConvertible, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var midX: Double { x + w / 2 }
    public var midY: Double { y + h / 2 }
    public var isPortrait: Bool { h > w }

    public func inset(by d: Double) -> Rect {
        Rect(x: x + d, y: y + d, w: max(w - 2 * d, 0), h: max(h - 2 * d, 0))
    }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= minX && px < maxX && py >= minY && py < maxY
    }

    /// True when both rectangles are within `tolerance` points on every edge.
    public func isClose(to other: Rect, tolerance: Double = 2) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
            && abs(w - other.w) <= tolerance && abs(h - other.h) <= tolerance
    }

    public var description: String { "(\(Int(x)),\(Int(y)) \(Int(w))x\(Int(h)))" }
}

public enum Direction: String, CaseIterable, Sendable {
    case left, right, up, down
}
