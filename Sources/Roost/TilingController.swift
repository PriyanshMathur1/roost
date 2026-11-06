import AppKit
import os
import RoostCore

/// Keeps one `TileState` per display in step with the windows on screen, and moves
/// windows to their tiles.
@MainActor
final class TilingController {
    let settings: Settings
    let tracker = WindowTracker()
    /// Called after anything the menu shows has changed.
    var onStateChange: (() -> Void)?

    private let log = Logger(subsystem: "com.priyansh.roost", category: "tiling")
    private var states: [String: TileState<WindowRef>] = [:]
    private var floating: Set<WindowRef> = []
    /// The smallest size each window has accepted, learned when a window came out bigger
    /// than the tile it was given. Only ever grows; forgotten when the window closes.
    private var minSizes: [WindowRef: Size] = [:]
    /// The same, per app, kept across restarts.
    private var appMinSizes: [String: Size]
    /// Windows left floating because there was no room for another tile. They are tried
    /// again on every re-check, so they join as soon as a tile frees up.
    private var overflow: Set<WindowRef> = []
    /// Windows already reported as not fitting, so each is logged once, not on every re-check.
    private var reportedOverflow: Set<WindowRef> = []
    /// The frame Roost last gave each tiled window, to tell its own moves from the user's.
    private var placed: [WindowRef: Rect] = [:]
    /// Windows that moved while a mouse button was down: a drag in progress.
    private var dragged: Set<WindowRef> = []
    private var dragCheck: DispatchWorkItem?
    /// Where windows were for each display setup this session (desk ↔ meeting memory).
    private var memory: [DisplaySetup: [String: [WindowRef]]] = [:]
    private var lastSetup: DisplaySetup?
    private var started = false

    init(settings: Settings) {
        self.settings = settings
        appMinSizes = settings.appMinSizes
        tracker.onChange = { [weak self] in self?.reconcile() }
        tracker.onWindowMoved = { [weak self] in self?.windowMoved($0) }
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
        // Don't pull a window out from under the pointer mid-drag; the drop re-checks.
        if !dragged.isEmpty && Self.mouseIsDown { return }

        let displays = Display.all()
        let byKey = Dictionary(displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let windows = tracker.tileableWindows()
        let present = Set(windows)
        floating.formIntersection(present)
        minSizes = minSizes.filter { present.contains($0.key) }
        placed = placed.filter { present.contains($0.key) }
        reportedOverflow.formIntersection(present)
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
            states[display.key] = newState(for: display.key)
        }

        let frames = Dictionary(windows.map { ($0, $0.frame) }, uniquingKeysWith: { a, _ in a })

        // A different set of displays than last time: put windows back where they were the
        // last time this set was connected (earlier this session, or before a restart).
        let setup = DisplaySetup(displays.map(\.key))
        if setup != lastSetup {
            restoreArrangement(for: setup, displays: displays, windows: windows.filter { !floating.contains($0) }, frames: frames)
            lastSetup = setup
        }

        // Add new windows to the display under their centre. On first start, left-to-right,
        // top-to-bottom order makes the first tidy look closest to what was there.
        let tiled = Set(states.values.flatMap(\.windows))
        let newcomers = windows
            .filter { !tiled.contains($0) && !floating.contains($0) }
            .compactMap { w -> (WindowRef, Rect)? in
                guard let frame = frames[w] ?? nil else { return nil }
                return (w, frame)
            }
            .sorted { ($0.1.minX, $0.1.minY) < ($1.1.minX, $1.1.minY) }
        for (window, frame) in newcomers {
            guard let display = Display.containing(x: frame.midX, y: frame.midY, in: displays) else { continue }
            states[display.key]?.insert(window, overCapacity: true)
        }

        for display in displays { apply(display, knownFrames: frames) }
        remember(setup)
        onStateChange?()
    }

    private func newState(for displayKey: String) -> TileState<WindowRef> {
        TileState(kind: settings.layout(for: displayKey), maxTiles: settings.maxTiles, minTile: settings.minTile)
    }

    // MARK: Desk ↔ meeting memory

    private func restoreArrangement(for setup: DisplaySetup, displays: [Display], windows: [WindowRef], frames: [WindowRef: Rect?]) {
        let saved: [String: [WindowRef]]
        if let known = memory[setup] {
            saved = known
        } else if let stored = settings.arrangements[setup.id] {
            saved = Arrangement.resolve(stored, present: windows.map { ($0, $0.tag) })
        } else {
            return
        }

        // Where windows are now: the display under each one's centre (macOS has just moved
        // windows off any display that went away), keeping the current tile order.
        var current: [String: [WindowRef]] = Dictionary(uniqueKeysWithValues: displays.map { ($0.key, []) })
        let order = states.values.flatMap(\.windows)
        let ranked = windows.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        for window in ranked {
            guard let f = frames[window] ?? nil,
                  let display = Display.containing(x: f.midX, y: f.midY, in: displays) else { continue }
            current[display.key]?.append(window)
        }

        let plan = Arrangement.restore(saved: saved, current: current, present: Set(windows))
        for (key, list) in plan {
            var state = newState(for: key)
            for window in list { state.insert(window, overCapacity: true) }
            states[key] = state
        }
        log.notice("Restored the window arrangement for \(setup.displays.count) display(s)")
    }

    /// Saves where windows are for the current display setup, in memory and on disk.
    private func remember(_ setup: DisplaySetup) {
        let arrangement = states.filter { setup.displays.contains($0.key) }.mapValues(\.windows)
        memory[setup] = arrangement
        var stored = settings.arrangements
        stored[setup.id] = arrangement.mapValues { $0.map(\.tag) }
        settings.arrangements = stored
    }

    // MARK: Applying tiles

    /// Minimum sizes known for these windows: learned this session, or for their app.
    private func knownMinimums(for windows: [WindowRef]) -> [WindowRef: Size] {
        var result: [WindowRef: Size] = [:]
        for window in windows {
            let own = minSizes[window] ?? .zero
            let app = appMinSizes[window.appID] ?? .zero
            let size = Size(w: max(own.w, app.w), h: max(own.h, app.h))
            if size != .zero { result[window] = size }
        }
        return result
    }

    /// Moves the display's windows to their tiles. A window that comes out bigger than its
    /// tile has a minimum size; it is remembered, and the tiles are worked out again so the
    /// room comes from windows that can spare it. If they can't all fit, the windows needing
    /// the most room are left floating where they are.
    private func apply(_ display: Display, knownFrames: [WindowRef: Rect?] = [:], pass: Int = 0) {
        guard var state = states[display.key] else { return }
        let gap = settings.gap
        let mins = knownMinimums(for: state.windows)
        let trimmed = state.trimToFit(in: display.visible, gap: gap, minSizes: mins)
        for window in trimmed {
            overflow.insert(window)
            placed[window] = nil
            if reportedOverflow.insert(window).inserted {
                log.info("\(window.description, privacy: .public) doesn't fit on \(display.name, privacy: .public); left floating")
            }
        }
        // A window that has a tile again may be reported again if it later stops fitting.
        reportedOverflow.subtract(state.windows)
        states[display.key] = state

        let targets = state.frames(in: display.visible, gap: gap, minSizes: mins)
        for target in targets { placed[target.id] = target.frame }
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
            if let size = Size.learnedMinimum(asked: move.frame, got: actual, known: mins[move.id]) {
                minSizes[move.id] = size
                let app = appMinSizes[move.id.appID] ?? .zero
                appMinSizes[move.id.appID] = Size(w: max(app.w, size.w), h: max(app.h, size.h))
                learned = true
                log.info("\(move.id.description, privacy: .public) won't go below \(Int(size.w))×\(Int(size.h))")
            }
        }
        guard learned else { return }
        settings.appMinSizes = appMinSizes
        // Minimums only grow, so this settles; the cap is a guard against apps that
        // report a different size each time.
        guard pass < 3 else { return }
        // What was left out was judged with what we knew then. Now that minimums are known,
        // other windows may have dropped out instead and freed a place: try them again.
        for window in trimmed {
            overflow.remove(window)
            states[display.key]?.insert(window, overCapacity: true)
        }
        apply(display, pass: pass + 1)
    }

    private func reapply(displayKeys: [String]) {
        let displays = Display.all()
        for display in displays where displayKeys.contains(display.key) { apply(display) }
        remember(DisplaySetup(displays.map(\.key)))
        onStateChange?()
    }

    // MARK: Dragging

    private static var mouseIsDown: Bool { NSEvent.pressedMouseButtons & 1 != 0 }

    /// A window moved. Roost's own moves land on the frame it gave the window and are
    /// ignored. Anything else is the user dragging (or the app moving itself): wait for the
    /// mouse to come up, then treat it as a drop.
    private func windowMoved(_ window: WindowRef) {
        guard started, settings.enabled, let target = placed[window] else { return }
        if let frame = window.frame, frame.isClose(to: target) { return }
        dragged.insert(window)
        scheduleDropCheck()
    }

    private func scheduleDropCheck() {
        dragCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Self.mouseIsDown { return self.scheduleDropCheck() }
                let windows = self.dragged
                self.dragged = []
                for window in windows { self.dropped(window) }
            }
        }
        dragCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Where a window was let go decides what happens:
    /// - on another tile of the same display: the two swap places;
    /// - on another display: it joins that display, at the tile it was dropped on;
    /// - anywhere else: it goes back to its tile.
    private func dropped(_ window: WindowRef) {
        let displays = Display.all()
        // A display was just plugged in or out: that's a re-arrangement, not a drop.
        guard DisplaySetup(displays.map(\.key)) == lastSetup else { return reconcile() }
        guard let from = states.first(where: { $0.value.contains(window) })?.key,
              let frame = window.frame,
              let to = Display.containing(x: frame.midX, y: frame.midY, in: displays) else { return reconcile() }
        let pointer = Self.pointerInAXSpace() ?? (frame.midX, frame.midY)

        let gap = settings.gap
        guard let targetState = states[to.key] else { return reconcile() }
        let tiles = targetState.frames(in: to.visible, gap: gap, minSizes: knownMinimums(for: targetState.windows))
        let hit = Navigation.index(containing: pointer.0, pointer.1, frames: tiles.map(\.frame),
                                   excluding: tiles.firstIndex { $0.id == window })

        if to.key == from {
            if let hit, states[from]!.swap(window, tiles[hit].id) {
                log.info("Dropped \(window.description, privacy: .public) on another tile: swapped")
            }
            reapply(displayKeys: [from])
        } else {
            states[from]!.remove(window)
            states[to.key]!.insert(window, at: hit ?? states[to.key]!.count, overCapacity: true)
            log.info("Moved \(window.description, privacy: .public) to \(to.name, privacy: .public)")
            reapply(displayKeys: [from, to.key])
        }
    }

    private static func pointerInAXSpace() -> (Double, Double)? {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return nil }
        let p = NSEvent.mouseLocation
        return (Double(p.x), Double(primaryHeight - p.y))
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
        guard let (window, key, display) = focusedTile() else { return NSSound.beep() }
        if let next = states[key]?.neighbor(of: window, direction: direction, in: display.visible, gap: settings.gap,
                                            minSizes: knownMinimums(for: states[key]!.windows)) {
            return next.focus()
        }
        // At the edge: focus the nearest tile on the next display that way.
        guard let other = Self.display(direction, of: display),
              let first = states[other.key]?.windows.first else { return NSSound.beep() }
        first.focus()
    }

    /// Swaps with the neighbour in `direction`; at the edge of a display, moves the window to
    /// the next display that way.
    func swap(_ direction: Direction) {
        guard let (window, key, display) = focusedTile() else { return NSSound.beep() }
        if let other = states[key]?.neighbor(of: window, direction: direction, in: display.visible, gap: settings.gap,
                                             minSizes: knownMinimums(for: states[key]!.windows)),
           states[key]?.swap(window, other) == true {
            return reapply(displayKeys: [key])
        }
        guard let next = Self.display(direction, of: display) else { return NSSound.beep() }
        states[key]!.remove(window)
        // Arriving from the left puts it first; from the right, last.
        let index = direction == .left ? (states[next.key]?.count ?? 0) : 0
        states[next.key]?.insert(window, at: index, overCapacity: true)
        reapply(displayKeys: [key, next.key])
        window.focus()
    }

    private static func display(_ direction: Direction, of display: Display) -> Display? {
        let all = Display.all()
        guard let i = all.firstIndex(of: display) else { return nil }
        return Navigation.neighbor(of: i, direction: direction, frames: all.map(\.visible)).map { all[$0] }
    }

    func promote() {
        guard let (window, key, _) = focusedTile(), states[key]?.promote(window) == true else { return NSSound.beep() }
        reapply(displayKeys: [key])
    }

    func resize(grow: Bool) {
        guard let (window, key, _) = focusedTile(), states[key]?.resize(window, grow: grow) == true else { return NSSound.beep() }
        reapply(displayKeys: [key])
    }

    /// Floats the focused window (takes it out of the tiles, leaving it where it is), or
    /// puts a floating one back.
    func toggleFloat() {
        guard let window = WindowRef.focused() else { return NSSound.beep() }
        if floating.remove(window) == nil {
            floating.insert(window)
            placed[window] = nil
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

    /// Forgets every learned minimum size, for when an app now shrinks further.
    func forgetLearnedSizes() {
        minSizes = [:]
        appMinSizes = [:]
        settings.appMinSizes = [:]
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
    var rememberedSetups: Int { settings.arrangements.count }
}
