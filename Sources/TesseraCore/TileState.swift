/// The tiling state of one display: which windows are tiled, in what order, and how big.
/// Generic over the window identifier so it can be tested without real windows.
public struct TileState<ID: Hashable>: Equatable {
    public static var weightRange: ClosedRange<Double> { 0.3...3 }

    public private(set) var windows: [ID] = []
    public var kind: LayoutKind
    public var maxTiles: Int
    public private(set) var mainRatio: Double
    private var weights: [ID: Double] = [:]

    public init(kind: LayoutKind = .main, maxTiles: Int = 6, mainRatio: Double = 0.6) {
        self.kind = kind
        self.maxTiles = max(maxTiles, 1)
        self.mainRatio = mainRatio.clamped(to: LayoutParams.mainRatioRange)
    }

    public var count: Int { windows.count }
    public var isFull: Bool { windows.count >= maxTiles }
    public func contains(_ id: ID) -> Bool { windows.contains(id) }
    public func index(of id: ID) -> Int? { windows.firstIndex(of: id) }

    /// Appends a window. Returns false when it is already tiled or the display is full.
    @discardableResult
    public mutating func insert(_ id: ID) -> Bool {
        guard !contains(id), !isFull else { return false }
        windows.append(id)
        return true
    }

    @discardableResult
    public mutating func remove(_ id: ID) -> Bool {
        guard let i = index(of: id) else { return false }
        windows.remove(at: i)
        weights[id] = nil
        return true
    }

    /// Exchanges the places of two tiled windows. Each keeps its own size weight.
    @discardableResult
    public mutating func swap(_ a: ID, _ b: ID) -> Bool {
        guard a != b, let i = index(of: a), let j = index(of: b) else { return false }
        windows.swapAt(i, j)
        return true
    }

    /// Moves a window to the first (main) place; the others keep their order.
    @discardableResult
    public mutating func promote(_ id: ID) -> Bool {
        guard let i = index(of: id), i > 0 else { return false }
        windows.remove(at: i)
        windows.insert(id, at: 0)
        return true
    }

    /// Grows (`grow == true`) or shrinks the share of `id`. Returns false when the layout
    /// has nothing to change (grid, a single window) or the size is already at its limit.
    @discardableResult
    public mutating func resize(_ id: ID, grow: Bool, step: Double = 0.05) -> Bool {
        guard let i = index(of: id), windows.count > 1 else { return false }
        switch kind {
        case .grid:
            return false
        case .main:
            // The main window's share and the stack's share are two sides of one split.
            let delta = (i == 0) == grow ? step : -step
            let next = (mainRatio + delta).clamped(to: LayoutParams.mainRatioRange)
            guard next != mainRatio else { return false }
            mainRatio = next
            return true
        case .columns, .rows:
            let current = weights[id] ?? 1
            let next = (grow ? current * 1.2 : current / 1.2).clamped(to: Self.weightRange)
            guard next != current else { return false }
            weights[id] = next
            return true
        }
    }

    /// Forget every resize: equal weights and the default main share.
    public mutating func resetSizes(mainRatio: Double = 0.6) {
        weights = [:]
        self.mainRatio = mainRatio.clamped(to: LayoutParams.mainRatioRange)
    }

    public func params(gap: Double) -> LayoutParams {
        LayoutParams(gap: gap, mainRatio: mainRatio, weights: windows.map { weights[$0] ?? 1 })
    }

    /// The frame each tiled window should have on `screen`, in window order.
    public func frames(in screen: Rect, gap: Double) -> [(id: ID, frame: Rect)] {
        let rects = Layout.frames(count: windows.count, in: screen, kind: kind, params: params(gap: gap))
        return Array(zip(windows, rects)).map { (id: $0.0, frame: $0.1) }
    }

    /// The tiled window next to `id` in `direction`, judged by where the windows sit on `screen`.
    public func neighbor(of id: ID, direction: Direction, in screen: Rect, gap: Double) -> ID? {
        guard let i = index(of: id) else { return nil }
        let rects = frames(in: screen, gap: gap).map(\.frame)
        return Navigation.neighbor(of: i, direction: direction, frames: rects).map { windows[$0] }
    }

    public static func == (lhs: TileState, rhs: TileState) -> Bool {
        lhs.windows == rhs.windows && lhs.kind == rhs.kind && lhs.maxTiles == rhs.maxTiles
            && lhs.mainRatio == rhs.mainRatio && lhs.weights == rhs.weights
    }
}
