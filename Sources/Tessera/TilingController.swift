import AppKit
import os
import TesseraCore

/// Keeps one `TileState` per display in step with the windows on screen, and moves
/// windows to their tiles.
@MainActor
final class TilingController {
    let settings: Settings
    let tracker = WindowTracker()
    /// Called after anything the menu shows has changed.
    var onStateChange: (() -> Void)?

    private let log = Logger(subsystem: "com.priyansh.tessera", category: "tiling")
    private var states: [String: TileState<WindowRef>] = [:]
    private var floating: Set<WindowRef> = []
    /// The smallest size each window has accepted, learned when a window came out bigger
    /// than the tile it was given. Only ever grows; forgotten when the window closes.
    private var minSizes: [WindowRef: Size] = [:]
    /// Windows left floating because there was no room for another tile. They are tried
    /// again on every re-check, so they join as soon as a tile frees up.
    private var overflow: Set<WindowRef> = []
    private var started = false

    init(settings: Settings) {
        self.settings = settings
        tracker.onChange = { [weak self] in self?.reconcile() }
    }

    func start() {
        guard !started else { return }
        started = true
        tracker.start()
        reconcile()
    }

    var isEnabled: Bool { settings.enabled }

    func setEnabled(_ on: Bool) {
        settings.enabled = on
        if on { reconcile() }
        onStateChange?()
    }

    // MARK: Reconcile

    /// Re-reads the windows on screen, updates every display's tiles, and moves windows
    /// whose frame differs from their tile.
    func reconcile() {
        guard started, settings.enabled, AX.isTrusted else { return }
        let displays = Display.all()
        let byKey = Dictionary(displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let windows = tracker.tileableWindows()
        let present = Set(windows)
        floating.formIntersection(present)
        minSizes = minSizes.filter { present.contains($0.key) }
        overflow = []

        // Forget displays that went away (their windows are picked up again below,
        // on whichever display now holds them), and windows that are gone.
        states = states.filter { byKey[$0.key] != nil }
        for key in states.keys {
            for id in states[key]!.windows where !present.contains(id) {
                states[key]!.remove(id)
            }
        }
        for display in displays where states[display.key] == nil {
            states[display.key] = TileState(kind: settings.layout(for: display.key), maxTiles: settings.maxTiles, minTile: settings.minTile)
        }

        // Add new windows to the display under their centre. On first start, left-to-right,
        // top-to-bottom order makes the first tidy look closest to what was there.
        let tiled = Set(states.values.flatMap(\.windows))
        let frames = Dictionary(windows.map { ($0, $0.frame) }, uniquingKeysWith: { a, _ in a })
        let newcomers = windows
            .filter { !tiled.contains($0) && !floating.contains($0) }
            .compactMap { w -> (WindowRef, Rect)? in
                guard let frame = frames[w] ?? nil else { return nil }
                return (w, frame)
            }
            .sorted { ($0.1.minX, $0.1.minY) < ($1.1.minX, $1.1.minY) }
        for (window, frame) in newcomers {
            guard let display = Display.containing(x: frame.midX, y: frame.midY, in: displays) else { continue }
            if !(states[display.key]?.insert(window) ?? false) {
                log.debug("No room for \(window.description, privacy: .public) on \(display.name, privacy: .public)")
            }
        }

        for display in displays { apply(display, knownFrames: frames) }
        onStateChange?()
    }

    /// Moves the display's windows to their tiles. A window that comes out bigger than its
    /// tile has a minimum size; it is remembered, and the tiles are worked out again so the
    /// room comes from windows that can spare it. If they can't all fit, the newest windows
    /// are left floating where they are.
    private func apply(_ display: Display, knownFrames: [WindowRef: Rect?] = [:], pass: Int = 0) {
        guard var state = states[display.key] else { return }
        let gap = settings.gap
        for window in state.trimToFit(in: display.visible, gap: gap, minSizes: minSizes) {
            overflow.insert(window)
            log.info("\(window.description, privacy: .public) doesn't fit on \(display.name, privacy: .public); left floating")
        }
        states[display.key] = state

        let targets = state.frames(in: display.visible, gap: gap, minSizes: minSizes)
        let moves = targets.filter { target in
            let current = (pass == 0 ? knownFrames[target.id] : nil) ?? target.id.frame
            return !(current?.isClose(to: target.frame) ?? false)
        }
        for (pid, group) in Dictionary(grouping: moves, by: { $0.id.pid }) {
            AX.withEnhancedUserInterfaceOff(pid: pid) {
                for move in group { move.id.setFrame(move.frame) }
            }
        }

        var learned = false
        for move in moves {
            guard let actual = move.id.frame else { continue }
            if let size = Size.learnedMinimum(asked: move.frame, got: actual, known: minSizes[move.id]) {
                minSizes[move.id] = size
                learned = true
                log.info("\(move.id.description, privacy: .public) won't go below \(Int(size.w))×\(Int(size.h))")
            }
        }
        // Minimums only grow, so this settles; the cap is a guard against apps that
        // report a different size each time.
        if learned && pass < 3 { apply(display, pass: pass + 1) }
    }

    private func reapply(displayKey: String) {
        guard let display = Display.all().first(where: { $0.key == displayKey }) else { return }
        apply(display)
        onStateChange?()
    }

    // MARK: Commands (keyboard and menu)

    /// The focused window and the display whose tiles hold it.
    private func focusedTile() -> (window: WindowRef, key: String, display: Display)? {
        guard let window = WindowRef.focused() else { return nil }
        guard let key = states.first(where: { $0.value.contains(window) })?.key,
              let display = Display.all().first(where: { $0.key == key }) else { return nil }
        return (window, key, display)
    }

    func focus(_ direction: Direction) {
        guard let (window, key, display) = focusedTile(),
              let next = states[key]?.neighbor(of: window, direction: direction, in: display.visible, gap: settings.gap, minSizes: minSizes)
        else { return NSSound.beep() }
        next.focus()
    }

    func swap(_ direction: Direction) {
        guard let (window, key, display) = focusedTile(),
              let other = states[key]?.neighbor(of: window, direction: direction, in: display.visible, gap: settings.gap, minSizes: minSizes),
              states[key]?.swap(window, other) == true
        else { return NSSound.beep() }
        reapply(displayKey: key)
    }

    func promote() {
        guard let (window, key, _) = focusedTile(), states[key]?.promote(window) == true else { return NSSound.beep() }
        reapply(displayKey: key)
    }

    func resize(grow: Bool) {
        guard let (window, key, _) = focusedTile(), states[key]?.resize(window, grow: grow) == true else { return NSSound.beep() }
        reapply(displayKey: key)
    }

    /// Floats the focused window (takes it out of the tiles, leaving it where it is), or
    /// puts a floating one back.
    func toggleFloat() {
        guard let window = WindowRef.focused() else { return NSSound.beep() }
        if floating.remove(window) == nil {
            floating.insert(window)
            for key in states.keys { states[key]!.remove(window) }
        }
        reconcile()
    }

    /// Changes the layout of the display holding the focused window, or under the pointer.
    func setLayout(_ kind: LayoutKind, displayKey: String? = nil) {
        let key = displayKey ?? focusedTile()?.key ?? Display.underMouse(in: Display.all())?.key
        guard let key else { return }
        settings.setLayout(kind, for: key)
        states[key]?.kind = kind
        // Another layout may have room for windows that were left floating.
        reconcile()
    }

    func layout(for displayKey: String) -> LayoutKind {
        states[displayKey]?.kind ?? settings.layout(for: displayKey)
    }

    func resetSizes() {
        for key in states.keys { states[key]!.resetSizes() }
        reconcile()
    }

    func setMinTileWidth(_ width: Double) {
        settings.minTileWidth = width
        for key in states.keys { states[key]!.minTile = settings.minTile }
        reconcile()
    }

    func setGap(_ gap: Double) {
        settings.gap = gap
        reconcile()
    }

    var tiledCount: Int { states.values.reduce(0) { $0 + $1.count } }
    var floatingCount: Int { floating.count + overflow.count }
}
