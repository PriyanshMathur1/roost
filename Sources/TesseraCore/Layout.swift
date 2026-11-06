public enum LayoutKind: String, CaseIterable, Codable, Sendable {
    /// One large window on the left, the others stacked on the right.
    case main
    /// Every window side by side.
    case columns
    /// Every window full width, one above another.
    case rows
    /// A near-square grid; the last row's windows widen to fill it.
    case grid

    public var title: String {
        switch self {
        case .main: "Main + stack"
        case .columns: "Columns"
        case .rows: "Rows"
        case .grid: "Grid"
        }
    }

    /// Columns on a portrait display would be too narrow to use, so they become rows.
    public func effective(on screen: Rect) -> LayoutKind {
        self == .columns && screen.isPortrait ? .rows : self
    }
}

public struct LayoutParams: Equatable, Sendable {
    public static let mainRatioRange: ClosedRange<Double> = 0.2...0.8

    public var gap: Double
    /// Share of the width the main window takes in `.main`.
    public var mainRatio: Double
    /// Relative size of each window, in window order. Missing entries count as 1.
    public var weights: [Double]

    public init(gap: Double = 8, mainRatio: Double = 0.6, weights: [Double] = []) {
        self.gap = max(gap, 0)
        self.mainRatio = mainRatio.clamped(to: Self.mainRatioRange)
        self.weights = weights
    }
}

public enum Layout {
    /// Frames for `count` windows on `screen` (the display's visible area), in window order.
    /// Every frame is whole points, and frames never overlap.
    public static func frames(count: Int, in screen: Rect, kind: LayoutKind, params: LayoutParams) -> [Rect] {
        guard count > 0 else { return [] }
        let gap = params.gap
        let area = screen.inset(by: gap).rounded()
        guard area.w > 0, area.h > 0 else { return [] }
        if count == 1 { return [area] }

        let weights = (0..<count).map { i in i < params.weights.count ? max(params.weights[i], 0.01) : 1 }

        switch kind.effective(on: screen) {
        case .columns:
            return split(start: area.x, length: area.w, gap: gap, weights: weights).map {
                Rect(x: $0.start, y: area.y, w: $0.length, h: area.h)
            }
        case .rows:
            return split(start: area.y, length: area.h, gap: gap, weights: weights).map {
                Rect(x: area.x, y: $0.start, w: area.w, h: $0.length)
            }
        case .main:
            let usable = area.w - gap
            let mainW = (usable * params.mainRatio).rounded()
            let main = Rect(x: area.x, y: area.y, w: mainW, h: area.h)
            let stackX = area.x + mainW + gap
            let stackW = area.maxX - stackX
            let stack = split(start: area.y, length: area.h, gap: gap, weights: Array(weights.dropFirst())).map {
                Rect(x: stackX, y: $0.start, w: stackW, h: $0.length)
            }
            return [main] + stack
        case .grid:
            let columns = Int(Double(count).squareRoot().rounded(.up))
            let rowCount = Int((Double(count) / Double(columns)).rounded(.up))
            let rowSpans = split(start: area.y, length: area.h, gap: gap, weights: Array(repeating: 1, count: rowCount))
            var result: [Rect] = []
            for (r, row) in rowSpans.enumerated() {
                let inRow = min(columns, count - r * columns)
                for span in split(start: area.x, length: area.w, gap: gap, weights: Array(repeating: 1, count: inRow)) {
                    result.append(Rect(x: span.start, y: row.start, w: span.length, h: row.length))
                }
            }
            return result
        }
    }

    /// Splits `length` into weighted spans separated by `gap`. Edges are rounded from the
    /// running total, so rounding never accumulates and the last span ends exactly at the end.
    static func split(start: Double, length: Double, gap: Double, weights: [Double]) -> [(start: Double, length: Double)] {
        guard !weights.isEmpty else { return [] }
        let available = length - gap * Double(weights.count - 1)
        let total = weights.reduce(0, +)
        var spans: [(start: Double, length: Double)] = []
        var used = 0.0
        var cursor = start
        for (i, weight) in weights.enumerated() {
            used += weight
            let end = i == weights.count - 1
                ? start + length
                : (start + available * used / total + gap * Double(i)).rounded()
            spans.append((cursor, max(end - cursor, 0)))
            cursor = end + gap
        }
        return spans
    }
}

extension Rect {
    func rounded() -> Rect {
        let x0 = x.rounded(), y0 = y.rounded()
        return Rect(x: x0, y: y0, w: (x + w).rounded() - x0, h: (y + h).rounded() - y0)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
