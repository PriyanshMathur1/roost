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

/// A width and height in points.
public struct Size: Equatable, Hashable, Codable, Sendable {
    public var w: Double
    public var h: Double

    public init(w: Double, h: Double) {
        self.w = w
        self.h = h
    }

    public static let zero = Size(w: 0, h: 0)
}

public enum Direction: String, CaseIterable, Sendable {
    case left, right, up, down
}

extension Size {
    /// The minimum size implied by asking a window for `asked` and getting `got`, when that
    /// says more than `known`; otherwise nil. A window that comes out a couple of points
    /// bigger is rounding (text cells, pixel snapping), not a minimum.
    public static func learnedMinimum(asked: Rect, got: Rect, known: Size?, slack: Double = 2) -> Size? {
        let before = known ?? .zero
        var size = before
        if got.w > asked.w + slack { size.w = max(size.w, got.w) }
        if got.h > asked.h + slack { size.h = max(size.h, got.h) }
        return size != before ? size : nil
    }
}

/// Learns a window's minimum size from what it becomes when asked to be smaller, but only
/// once the same oversized result has been seen twice. A single glimpse can be a window
/// mid-animation (leaving full screen, restoring from the Dock), not a real minimum.
public struct MinimumLearner<ID: Hashable> {
    private var pending: [ID: Size] = [:]
    private var tries: [ID: Int] = [:]
    public static var maxTries: Int { 3 }

    public init() {}

    /// True while a size is waiting for confirmation and it's worth asking the window again.
    public func wantsRecheck(_ id: ID) -> Bool {
        pending[id] != nil && (tries[id] ?? 0) < Self.maxTries
    }

    /// Returns a newly confirmed minimum, or nil while it is still unconfirmed.
    public mutating func observe(_ id: ID, asked: Rect, got: Rect, known: Size? = nil) -> Size? {
        guard let candidate = Size.learnedMinimum(asked: asked, got: got, known: known) else {
            pending[id] = nil  // it took the size after all
            tries[id] = nil
            return nil
        }
        if let previous = pending[id], abs(previous.w - candidate.w) <= 2, abs(previous.h - candidate.h) <= 2 {
            pending[id] = nil
            tries[id] = nil
            return candidate
        }
        pending[id] = candidate
        tries[id, default: 0] += 1
        return nil
    }
}
