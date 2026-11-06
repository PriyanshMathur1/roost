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
    /// The smallest size each window accepts, in window order. Missing entries count as zero.
    public var minSizes: [Size]

    public init(gap: Double = 8, mainRatio: Double = 0.6, weights: [Double] = [], minSizes: [Size] = []) {
        self.gap = max(gap, 0)
        self.mainRatio = mainRatio.clamped(to: Self.mainRatioRange)
        self.weights = weights
        self.minSizes = minSizes
    }
}

public enum Layout {
    /// Frames for `count` windows on `screen` (the display's visible area), in window order,
    /// ignoring minimum sizes. Every frame is whole points, and frames never overlap.
    public static func frames(count: Int, in screen: Rect, kind: LayoutKind, params: LayoutParams) -> [Rect] {
        var relaxed = params
        relaxed.minSizes = []
        return fit(count: count, in: screen, kind: kind, params: relaxed) ?? []
    }

    /// Like `frames`, but every window gets at least its minimum size, taking the room from
    /// windows that can spare it. Returns nil when the windows can't all fit.
    public static func fit(count: Int, in screen: Rect, kind: LayoutKind, params: LayoutParams) -> [Rect]? {
        guard count > 0 else { return [] }
        let gap = params.gap
        let area = screen.inset(by: gap).rounded()
        guard area.w > 0, area.h > 0 else { return nil }

        let weights = (0..<count).map { i in i < params.weights.count ? max(params.weights[i], 0.01) : 1 }
        let mins = (0..<count).map { i in i < params.minSizes.count ? params.minSizes[i] : .zero }
        if count == 1 {
            return mins[0].w <= area.w + tolerance && mins[0].h <= area.h + tolerance ? [area] : nil
        }

        switch kind.effective(on: screen) {
        case .columns:
            guard mins.allSatisfy({ $0.h <= area.h + tolerance }),
                  let spans = split(start: area.x, length: area.w, gap: gap, weights: weights, mins: mins.map(\.w))
            else { return nil }
            return spans.map { Rect(x: $0.start, y: area.y, w: $0.length, h: area.h) }

        case .rows:
            guard mins.allSatisfy({ $0.w <= area.w + tolerance }),
                  let spans = split(start: area.y, length: area.h, gap: gap, weights: weights, mins: mins.map(\.h))
            else { return nil }
            return spans.map { Rect(x: area.x, y: $0.start, w: area.w, h: $0.length) }

        case .main:
            let usable = area.w - gap
            let stackMins = Array(mins.dropFirst())
            let stackMinW = stackMins.map(\.w).max() ?? 0
            let lowest = mins[0].w, highest = usable - stackMinW
            guard lowest <= highest + tolerance, mins[0].h <= area.h + tolerance else { return nil }
            // The main window's width stays between its own minimum and what leaves the stack
            // its minimum. Within rounding tolerance the two bounds can cross, so keep lo <= hi.
            let hi = highest.rounded(.down)
            let lo = min(lowest.rounded(.up), hi)
            let mainW = (usable * params.mainRatio).rounded().clamped(to: lo...hi)
            let stackX = area.x + mainW + gap
            let stackW = area.maxX - stackX
            guard let stack = split(start: area.y, length: area.h, gap: gap, weights: Array(weights.dropFirst()), mins: stackMins.map(\.h))
            else { return nil }
            return [Rect(x: area.x, y: area.y, w: mainW, h: area.h)]
                + stack.map { Rect(x: stackX, y: $0.start, w: stackW, h: $0.length) }

        case .grid:
            let columns = Int(Double(count).squareRoot().rounded(.up))
            let rowCount = Int((Double(count) / Double(columns)).rounded(.up))
            let rowRanges = (0..<rowCount).map { r in (r * columns)..<min((r + 1) * columns, count) }
            let rowMins = rowRanges.map { range in range.map { mins[$0].h }.max() ?? 0 }
            guard let rows = split(start: area.y, length: area.h, gap: gap, weights: Array(repeating: 1, count: rowCount), mins: rowMins)
            else { return nil }
            var result: [Rect] = []
            for (row, range) in zip(rows, rowRanges) {
                guard let cells = split(start: area.x, length: area.w, gap: gap, weights: Array(repeating: 1, count: range.count),
                                        mins: range.map { mins[$0].w })
                else { return nil }
                result += cells.map { Rect(x: $0.start, y: row.start, w: $0.length, h: row.length) }
            }
            return result
        }
    }

    /// How far a span may fall short of its minimum from rounding to whole points.
    static let tolerance = 1.0

    /// Splits `length` into weighted spans separated by `gap`, giving each span at least
    /// `mins[i]`. Returns nil when the minimums don't fit.
    ///
    /// Spans whose weighted share is below their minimum are pinned at the minimum, and the
    /// rest of the length is shared among the others by weight, until nothing changes.
    /// Edges are rounded from the running total, so rounding never accumulates and the last
    /// span ends exactly at the end.
    static func split(start: Double, length: Double, gap: Double, weights: [Double], mins: [Double] = []) -> [(start: Double, length: Double)]? {
        guard !weights.isEmpty else { return [] }
        let count = weights.count
        let floors = (0..<count).map { i in i < mins.count ? max(mins[i], 0) : 0 }
        let available = length - gap * Double(count - 1)
        guard available > 0, floors.reduce(0, +) <= available + tolerance else { return nil }

        var pinned = [Double?](repeating: nil, count: count)
        while true {
            let freeWeight = (0..<count).filter { pinned[$0] == nil }.map { weights[$0] }.reduce(0, +)
            let freeLength = available - pinned.compactMap { $0 }.reduce(0, +)
            var changed = false
            for i in 0..<count where pinned[i] == nil && freeLength * weights[i] / freeWeight < floors[i] {
                pinned[i] = floors[i]
                changed = true
            }
            if !changed { break }
        }
        let freeWeight = (0..<count).filter { pinned[$0] == nil }.map { weights[$0] }.reduce(0, +)
        let freeLength = available - pinned.compactMap { $0 }.reduce(0, +)
        let lengths = (0..<count).map { i in pinned[i] ?? (freeWeight > 0 ? freeLength * weights[i] / freeWeight : 0) }

        var spans: [(start: Double, length: Double)] = []
        var used = 0.0
        var cursor = start
        for i in 0..<count {
            used += lengths[i]
            let end = i == count - 1 ? start + length : (start + used + gap * Double(i)).rounded()
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
