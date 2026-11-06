// A small test runner: XCTest and Swift Testing are not available without a full
// Xcode install. Run with `swift run RoostCoreTests`; it exits 1 if anything fails.
import Foundation
import RoostCore

var failures = 0
var checks = 0
var currentTest = ""

func test(_ name: String, _ body: () -> Void) {
    currentTest = name
    body()
}

func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", line: Int = #line) {
    checks += 1
    if !condition() {
        failures += 1
        print("FAIL [\(currentTest)] line \(line): \(message())")
    }
}

func overlaps(_ a: Rect, _ b: Rect) -> Bool {
    a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
}

let laptop = Rect(x: 0, y: 25, w: 1512, h: 920)       // menu bar below y = 25
let portrait = Rect(x: 1512, y: -300, w: 1080, h: 1920) // a second display, above and right
let odd = Rect(x: 3, y: 7, w: 1001, h: 777)            // sizes that don't divide evenly

// MARK: Layout invariants, for every kind, many counts, several screens and gaps.

test("layout invariants") {
    for screen in [laptop, portrait, odd] {
        for kind in LayoutKind.allCases {
            for gap in [0.0, 8, 13] {
                for count in 0...9 {
                    let weights = (0..<count).map { Double($0 % 3) * 0.4 + 0.6 }
                    for params in [LayoutParams(gap: gap), LayoutParams(gap: gap, mainRatio: 0.35, weights: weights)] {
                        let frames = Layout.frames(count: count, in: screen, kind: kind, params: params)
                        let tag = "\(kind) n=\(count) gap=\(gap) screen=\(screen)"
                        expect(frames.count == count, "count \(frames.count) \(tag)")
                        let area = screen.inset(by: gap)
                        for f in frames {
                            expect(f.w > 0 && f.h > 0, "empty frame \(f) \(tag)")
                            expect(f.x == f.x.rounded() && f.y == f.y.rounded() && f.w == f.w.rounded() && f.h == f.h.rounded(), "not whole points \(f) \(tag)")
                            expect(f.minX >= area.minX.rounded() && f.minY >= area.minY.rounded(), "outside top-left \(f) \(tag)")
                            expect(f.maxX <= area.maxX.rounded() && f.maxY <= area.maxY.rounded(), "outside bottom-right \(f) \(tag)")
                        }
                        for i in frames.indices {
                            for j in frames.indices where j > i {
                                expect(!overlaps(frames[i], frames[j]), "overlap \(frames[i]) \(frames[j]) \(tag)")
                            }
                        }
                        // With gaps, tiles + gaps fill the area exactly (no wasted strips).
                        if count > 0 {
                            let filled = frames.map { $0.w * $0.h }.reduce(0, +)
                            let r = area.rounded()
                            expect(filled <= r.w * r.h, "overfilled \(tag)")
                            if gap == 0 { expect(filled == r.w * r.h, "gaps in a gapless layout: \(filled) vs \(r.w * r.h) \(tag)") }
                        }
                    }
                }
            }
        }
    }
}

extension Rect {
    func rounded() -> Rect {
        let x0 = x.rounded(), y0 = y.rounded()
        return Rect(x: x0, y: y0, w: (x + w).rounded() - x0, h: (y + h).rounded() - y0)
    }
}

// MARK: Specific layouts

test("one window fills the area") {
    let f = Layout.frames(count: 1, in: laptop, kind: .grid, params: LayoutParams(gap: 8))
    expect(f == [Rect(x: 8, y: 33, w: 1496, h: 904)], "\(f)")
}

test("main layout: main on the left at its ratio, stack on the right") {
    let f = Layout.frames(count: 3, in: Rect(x: 0, y: 0, w: 1000, h: 600), kind: .main, params: LayoutParams(gap: 0, mainRatio: 0.6))
    expect(f[0] == Rect(x: 0, y: 0, w: 600, h: 600), "\(f[0])")
    expect(f[1] == Rect(x: 600, y: 0, w: 400, h: 300), "\(f[1])")
    expect(f[2] == Rect(x: 600, y: 300, w: 400, h: 300), "\(f[2])")
}

test("gaps separate neighbours by exactly the gap") {
    let f = Layout.frames(count: 2, in: Rect(x: 0, y: 0, w: 1000, h: 600), kind: .columns, params: LayoutParams(gap: 10))
    expect(f[1].minX - f[0].maxX == 10, "\(f)")
    expect(f[0].minX == 10 && f[1].maxX == 990, "\(f)")
}

test("columns honour weights") {
    let f = Layout.frames(count: 2, in: Rect(x: 0, y: 0, w: 900, h: 600), kind: .columns, params: LayoutParams(gap: 0, weights: [2, 1]))
    expect(f[0].w == 600 && f[1].w == 300, "\(f)")
}

test("columns become rows on a portrait display") {
    expect(LayoutKind.columns.effective(on: portrait) == .rows)
    expect(LayoutKind.main.effective(on: portrait) == .main)
    let f = Layout.frames(count: 2, in: portrait, kind: .columns, params: LayoutParams(gap: 0))
    expect(f[0].w == portrait.w && f[1].minY > f[0].minY, "\(f)")
}

test("grid: 5 windows are 3 + 2, last row widens") {
    let f = Layout.frames(count: 5, in: Rect(x: 0, y: 0, w: 1200, h: 600), kind: .grid, params: LayoutParams(gap: 0))
    expect(f[0].w == 400 && f[2].w == 400, "\(f)")
    expect(f[3].w == 600 && f[4].w == 600, "\(f)")
    expect(f[3].minY == 300, "\(f)")
}

test("mainRatio is clamped") {
    expect(LayoutParams(mainRatio: 0.99).mainRatio == 0.8)
    expect(LayoutParams(mainRatio: 0).mainRatio == 0.2)
    expect(LayoutParams(gap: -4).gap == 0)
}

// MARK: Navigation

test("neighbours in a main layout") {
    // main | a
    //      | b
    let f = [Rect(x: 0, y: 0, w: 600, h: 600), Rect(x: 600, y: 0, w: 400, h: 300), Rect(x: 600, y: 300, w: 400, h: 300)]
    expect(Navigation.neighbor(of: 0, direction: .right, frames: f) == 1, "main → right should be the top of the stack")
    expect(Navigation.neighbor(of: 2, direction: .left, frames: f) == 0)
    expect(Navigation.neighbor(of: 1, direction: .down, frames: f) == 2)
    expect(Navigation.neighbor(of: 2, direction: .up, frames: f) == 1)
    expect(Navigation.neighbor(of: 0, direction: .left, frames: f) == nil)
    expect(Navigation.neighbor(of: 1, direction: .up, frames: f) == nil)
    expect(Navigation.neighbor(of: 9, direction: .up, frames: f) == nil)
}

test("overlapping candidates beat closer diagonal ones") {
    let source = Rect(x: 0, y: 100, w: 100, h: 100)
    let diagonal = Rect(x: 110, y: 0, w: 100, h: 90)     // nearer, but no vertical overlap
    let level = Rect(x: 300, y: 120, w: 100, h: 100)     // further, overlaps
    expect(Navigation.neighbor(of: 0, direction: .right, frames: [source, diagonal, level]) == 2)
}

// MARK: TileState

test("insert respects capacity and duplicates") {
    var s = TileState<String>(maxTiles: 2)
    expect(s.insert("a"))
    expect(!s.insert("a"), "duplicate accepted")
    expect(s.insert("b"))
    expect(!s.insert("c"), "over capacity")
    expect(s.windows == ["a", "b"] && s.isFull)
}

test("remove, swap, promote") {
    var s = TileState<String>()
    for id in ["a", "b", "c", "d"] { s.insert(id) }
    expect(s.promote("c") && s.windows == ["c", "a", "b", "d"], "\(s.windows)")
    expect(!s.promote("c"), "already main")
    expect(s.swap("a", "d") && s.windows == ["c", "d", "b", "a"], "\(s.windows)")
    expect(!s.swap("a", "a") && !s.swap("a", "zz"))
    expect(s.remove("d") && s.windows == ["c", "b", "a"], "\(s.windows)")
    expect(!s.remove("d"))
}

test("resize in main layout moves the one split both ways") {
    var s = TileState<String>(kind: .main, mainRatio: 0.6)
    s.insert("main"); s.insert("side")
    expect(s.resize("main", grow: true) && abs(s.mainRatio - 0.65) < 1e-9, "\(s.mainRatio)")
    expect(s.resize("side", grow: true) && abs(s.mainRatio - 0.6) < 1e-9, "\(s.mainRatio)")
    for _ in 0..<20 { s.resize("main", grow: true) }
    expect(s.mainRatio == 0.8 && !s.resize("main", grow: true), "should stop at the limit")
}

test("resize in columns changes only that window's weight; grid can't resize") {
    var s = TileState<String>(kind: .columns)
    s.insert("a"); s.insert("b")
    expect(s.resize("a", grow: true))
    let p = s.params(gap: 0)
    expect(p.weights[0] > 1 && p.weights[1] == 1, "\(p.weights)")
    s.kind = .grid
    expect(!s.resize("a", grow: true))
    var single = TileState<String>(kind: .columns)
    single.insert("only")
    expect(!single.resize("only", grow: true), "one window has nothing to resize against")
}

test("removing a window forgets its weight") {
    var s = TileState<String>(kind: .columns)
    s.insert("a"); s.insert("b")
    s.resize("a", grow: true)
    s.remove("a"); s.insert("a")
    expect(s.params(gap: 0).weights == [1, 1], "\(s.params(gap: 0).weights)")
}

test("frames and neighbours via TileState") {
    var s = TileState<String>(kind: .columns)
    for id in ["a", "b", "c"] { s.insert(id) }
    let screen = Rect(x: 0, y: 0, w: 900, h: 600)
    let frames = s.frames(in: screen, gap: 0)
    expect(frames.map(\.id) == ["a", "b", "c"] && frames[1].frame.minX == 300, "\(frames)")
    expect(s.neighbor(of: "b", direction: .right, in: screen, gap: 0) == "c")
    expect(s.neighbor(of: "a", direction: .left, in: screen, gap: 0) == nil)
}

// MARK: Minimum sizes

/// The usable area of the MacBook Air 15" this was tested on (menu bar 38 pt, Dock 100 pt).
let macbook = Rect(x: 0, y: 38, w: 1710, h: 974)

test("Chrome's 500 pt minimum width in four columns (seen on a real screen)") {
    var mins = [Size](repeating: .zero, count: 4)
    mins[2] = Size(w: 500, h: 0)
    let f = Layout.fit(count: 4, in: macbook, kind: .columns, params: LayoutParams(gap: 8, minSizes: mins))
    expect(f != nil, "should fit")
    guard let f else { return }
    expect(f[2].w >= 499, "Chrome got \(f[2].w)")
    for i in 0..<3 { expect(f[i + 1].minX - f[i].maxX == 8, "gap \(i): \(f)") }
    expect(f[0].w == f[1].w || abs(f[0].w - f[1].w) <= 1, "the others share equally: \(f)")
    expect(f[3].maxX == 1702, "\(f)")
}

test("Chrome's 375 pt minimum height in a four-window stack") {
    var mins = [Size](repeating: .zero, count: 5)
    mins[2] = Size(w: 0, h: 375)
    let f = Layout.fit(count: 5, in: macbook, kind: .main, params: LayoutParams(gap: 8, minSizes: mins))!
    expect(f[2].h >= 374, "\(f[2])")
    expect(f[4].maxY == 1004, "stack ends at the bottom: \(f)")
    for i in 1..<4 { expect(f[i + 1].minY - f[i].maxY == 8, "\(f)") }
}

test("main window width respects both sides' minimums") {
    let screen = Rect(x: 0, y: 0, w: 1000, h: 600)
    // Main ratio wants 0.8 (792 pt) but the stack needs 400.
    var f = Layout.fit(count: 2, in: screen, kind: .main, params: LayoutParams(gap: 0, mainRatio: 0.8, minSizes: [.zero, Size(w: 400, h: 0)]))!
    expect(f[1].w >= 399 && f[0].w + f[1].w == 1000, "\(f)")
    // Main ratio wants 0.2 but main needs 700.
    f = Layout.fit(count: 2, in: screen, kind: .main, params: LayoutParams(gap: 0, mainRatio: 0.2, minSizes: [Size(w: 700, h: 0), .zero]))!
    expect(f[0].w >= 699, "\(f)")
    // Bounds that cross by a fraction of a point must not crash.
    _ = Layout.fit(count: 2, in: screen, kind: .main, params: LayoutParams(gap: 0, minSizes: [Size(w: 500.4, h: 0), Size(w: 500.4, h: 0)]))
}

test("fit returns nil when minimums can't fit") {
    let four500 = [Size](repeating: Size(w: 500, h: 0), count: 4)
    expect(Layout.fit(count: 4, in: macbook, kind: .columns, params: LayoutParams(gap: 8, minSizes: four500)) == nil)
    expect(Layout.fit(count: 1, in: macbook, kind: .grid, params: LayoutParams(minSizes: [Size(w: 3000, h: 0)])) == nil)
    expect(Layout.fit(count: 2, in: macbook, kind: .columns, params: LayoutParams(minSizes: [Size(w: 0, h: 2000), .zero])) == nil, "too tall")
    expect(Layout.fit(count: 3, in: macbook, kind: .rows, params: LayoutParams(minSizes: [Size(w: 0, h: 600), Size(w: 0, h: 600), .zero])) == nil)
}

test("fit honours minimums in every layout when they fit") {
    var state: UInt64 = 0x9E3779B97F4A7C15
    func random(_ upper: Double) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53) * upper
    }
    var fitted = 0
    for _ in 0..<400 {
        for kind in LayoutKind.allCases {
            let count = Int(random(6)) + 1
            let mins = (0..<count).map { _ in Size(w: random(450), h: random(300)) }
            let params = LayoutParams(gap: 8, mainRatio: 0.3 + random(0.5), weights: (0..<count).map { _ in 0.5 + random(1.5) }, minSizes: mins)
            guard let f = Layout.fit(count: count, in: macbook, kind: kind, params: params) else { continue }
            fitted += 1
            let tag = "\(kind) n=\(count)"
            expect(f.count == count, tag)
            for (r, m) in zip(f, mins) {
                expect(r.w >= m.w - 1 && r.h >= m.h - 1, "\(r) below \(m) \(tag)")
                expect(r.minX >= 8 && r.maxX <= 1702 && r.minY >= 46 && r.maxY <= 1004, "outside \(r) \(tag)")
            }
            for i in f.indices { for j in f.indices where j > i { expect(!overlaps(f[i], f[j]), "overlap \(tag)") } }
        }
    }
    expect(fitted > 1000, "too few random cases fitted to mean anything: \(fitted)")
}

test("trimToFit takes off the newest windows until the rest fit") {
    var s = TileState<String>(kind: .columns)
    for id in ["a", "b", "c", "d"] { s.insert(id) }
    let mins = ["a": Size(w: 500, h: 0), "b": Size(w: 500, h: 0), "c": Size(w: 500, h: 0), "d": Size(w: 500, h: 0)]
    expect(!s.fits(in: macbook, gap: 8, minSizes: mins))
    expect(s.trimToFit(in: macbook, gap: 8, minSizes: mins) == ["d"], "\(s.windows)")
    expect(s.windows == ["a", "b", "c"] && s.fits(in: macbook, gap: 8, minSizes: mins))
    // A single window that can't fit stays (it is the only thing on the display).
    var lone = TileState<String>()
    lone.insert("big")
    expect(lone.trimToFit(in: macbook, gap: 8, minSizes: ["big": Size(w: 5000, h: 0)]).isEmpty && lone.count == 1)
}

test("frames with minimums put the room where it's needed") {
    var s = TileState<String>(kind: .columns)
    for id in ["a", "b", "c", "d"] { s.insert(id) }
    let f = s.frames(in: macbook, gap: 8, minSizes: ["c": Size(w: 500, h: 0)])
    expect(f[2].id == "c" && f[2].frame.w >= 499, "\(f)")
}

test("learning a minimum size from what a window became") {
    let asked = Rect(x: 0, y: 0, w: 417, h: 958)
    // Chrome came out 500 wide: that's its minimum width; the height was fine.
    expect(Size.learnedMinimum(asked: asked, got: Rect(x: 0, y: 0, w: 500, h: 958), known: nil) == Size(w: 500, h: 0))
    // 1–2 pt over is rounding, not a minimum.
    expect(Size.learnedMinimum(asked: asked, got: Rect(x: 0, y: 0, w: 419, h: 959), known: nil) == nil)
    // Smaller than asked (a maximum size) teaches nothing about the minimum.
    expect(Size.learnedMinimum(asked: asked, got: Rect(x: 0, y: 0, w: 300, h: 500), known: nil) == nil)
    // Known minimums only grow.
    let known = Size(w: 520, h: 300)
    expect(Size.learnedMinimum(asked: asked, got: Rect(x: 0, y: 0, w: 500, h: 958), known: known) == nil)
    expect(Size.learnedMinimum(asked: Rect(x: 0, y: 0, w: 600, h: 200), got: Rect(x: 0, y: 0, w: 600, h: 375), known: known) == Size(w: 520, h: 375))
}

// MARK: Minimum tile size

test("minimum tile: the 5-window columns case from the real screen tiles 4, none below 300 pt") {
    // Chrome (500 min), System Settings (723 min), then three TextEdit windows that
    // would otherwise be squeezed to 146 pt.
    var s = TileState<String>(kind: .columns, minTile: Size(w: 300, h: 160))
    for id in ["chrome", "settings", "te1", "te2", "te3"] { s.insert(id) }
    let mins = ["chrome": Size(w: 500, h: 0), "settings": Size(w: 723, h: 0)]
    let dropped = s.trimToFit(in: macbook, gap: 8, minSizes: mins)
    // Settings needs 723 pt; floating it leaves room for all three TextEdit windows.
    expect(dropped == ["settings"], "only the biggest floats: \(dropped)")
    expect(s.windows == ["chrome", "te1", "te2", "te3"], "\(s.windows)")
    let f = s.frames(in: macbook, gap: 8, minSizes: mins)
    expect(f.allSatisfy { $0.frame.w >= 299 }, "\(f)")
    expect(f[0].frame.w >= 499, "\(f)")
    expect(f[3].frame.maxX == 1702, "fills to the edge: \(f)")
}

test("minimum tile applies to height in rows and stacks") {
    var s = TileState<Int>(kind: .rows, maxTiles: 10, minTile: Size(w: 300, h: 160))
    for id in 0..<8 { s.insert(id) }
    // 958 pt tall: 8 rows would be ~113 pt; at 160 pt + 8 pt gaps only 5 fit.
    s.trimToFit(in: macbook, gap: 8, minSizes: [:])
    expect(s.count == 5, "\(s.count)")
    expect(s.frames(in: macbook, gap: 8).allSatisfy { $0.frame.h >= 159 })
}

test("a lone window isn't held to the minimum tile") {
    var s = TileState<String>(minTile: Size(w: 5000, h: 5000))
    s.insert("only")
    expect(s.fits(in: macbook, gap: 8, minSizes: [:]))
    expect(s.frames(in: macbook, gap: 8).first?.frame == macbook.inset(by: 8))
}

test("no minimum tile means the old behaviour") {
    var s = TileState<Int>(kind: .columns, maxTiles: 10)
    for id in 0..<6 { s.insert(id) }
    expect(s.trimToFit(in: macbook, gap: 8, minSizes: [:]).isEmpty && s.count == 6)
}

test("one window too wide for the stack doesn't push out the windows after it (seen on screen)") {
    // Main + stack: Chrome is main; System Settings needs 723 pt but the stack is ~674 pt.
    var s = TileState<String>(kind: .main, minTile: Size(w: 300, h: 165))
    for id in ["chrome", "settings", "te1", "te2"] { s.insert(id) }
    let mins = ["chrome": Size(w: 0, h: 375), "settings": Size(w: 723, h: 470)]
    // With Chrome at least 963 pt (its share), Settings still fits at 723 — so force the
    // real case: main can't give up that much room.
    let tight = mins.merging(["chrome": Size(w: 1012, h: 375)]) { $1 }
    let dropped = s.trimToFit(in: macbook, gap: 8, minSizes: tight)
    expect(dropped == ["settings"], "only Settings should float: \(dropped)")
    expect(s.windows == ["chrome", "te1", "te2"], "\(s.windows)")
    expect(s.fits(in: macbook, gap: 8, minSizes: tight))
}

test("trimToFit keeps order and leaves fitting states alone") {
    var s = TileState<Int>(kind: .columns, maxTiles: 10, minTile: Size(w: 300, h: 0))
    for id in 0..<4 { s.insert(id) }
    expect(s.trimToFit(in: macbook, gap: 8, minSizes: [:]).isEmpty && s.count == 4)
    // A huge window in the middle is skipped; later small ones stay.
    for id in 4..<6 { s.insert(id) }
    let dropped = s.trimToFit(in: macbook, gap: 8, minSizes: [1: Size(w: 1500, h: 0)])
    expect(dropped.contains(1) && s.windows.first == 0, "\(dropped) \(s.windows)")
    expect(s.windows == s.windows.sorted(), "order kept: \(s.windows)")
}

test("windows that can't fit don't use up places under the cap (seen on screen)") {
    // Cap 6. Settings and Chrome are too big for the stack; the 7th window (t3) should get
    // one of the places they would have taken.
    var s = TileState<String>(kind: .main, maxTiles: 6, minTile: Size(w: 300, h: 165))
    let order = ["te1", "te2", "passwords", "te4", "settings", "chrome", "t3"]
    for id in order { expect(s.insert(id, overCapacity: true), id) }
    expect(!s.insert("te1", overCapacity: true), "no duplicates even over capacity")
    let mins = ["passwords": Size(w: 779, h: 360), "settings": Size(w: 723, h: 470), "chrome": Size(w: 0, h: 375)]
    let dropped = s.trimToFit(in: macbook, gap: 8, minSizes: mins)
    expect(!dropped.contains("t3") || s.count == 6, "t3 turned away with room left: kept \(s.windows), dropped \(dropped)")
    expect(s.count <= 6 && s.fits(in: macbook, gap: 8, minSizes: mins), "\(s.windows)")
    // Chrome (375 pt tall) fits once the two biggest, Passwords and Settings, float.
    expect(Set(dropped) == ["passwords", "settings"], "\(dropped)")
}

test("trimToFit enforces the cap even when everything fits") {
    var s = TileState<Int>(kind: .columns, maxTiles: 3)
    for id in 0..<5 { s.insert(id, overCapacity: true) }
    expect(s.count == 5)
    expect(s.trimToFit(in: macbook, gap: 8, minSizes: [:]) == [3, 4] && s.windows == [0, 1, 2], "\(s.windows)")
    expect(!s.insert(9), "plain insert still respects the cap")
}

test("when not all fit, tile as many as possible (seen on screen after a restart)") {
    // Passwords is main; Chrome and Settings came first in the stack and, kept in list
    // order, would leave all four TextEdit windows floating.
    var s = TileState<String>(kind: .main, maxTiles: 6, minTile: Size(w: 300, h: 165))
    for id in ["passwords", "chrome", "settings", "t1", "t2", "t3", "t4"] { s.insert(id, overCapacity: true) }
    let mins = ["passwords": Size(w: 779, h: 360), "settings": Size(w: 723, h: 470), "chrome": Size(w: 0, h: 375)]
    let dropped = s.trimToFit(in: macbook, gap: 8, minSizes: mins)
    expect(Set(dropped) == ["chrome", "settings"], "the two biggest float: \(dropped)")
    expect(s.windows == ["passwords", "t1", "t2", "t3", "t4"], "order kept, main stays: \(s.windows)")
    expect(s.fits(in: macbook, gap: 8, minSizes: mins))
}

// MARK: Desk ↔ meeting memory

test("a display setup is the same whatever order displays are listed in") {
    expect(DisplaySetup(["laptop", "desk"]) == DisplaySetup(["desk", "laptop"]))
    expect(DisplaySetup(["laptop", "desk", "laptop"]).displays == ["desk", "laptop"])
    expect(DisplaySetup(["laptop"]).id == "laptop" && DisplaySetup(["b", "a"]).id == "a+b")
}

test("plugging back in: windows return to the desk monitor in their old order") {
    // At the desk: mail + notes on the laptop, browser/editor/terminal on the monitor.
    let saved = ["laptop": ["mail", "notes"], "desk": ["browser", "editor", "terminal"]]
    // After a meeting on the laptop alone, macOS had piled everything onto the laptop.
    let current = ["laptop": ["editor", "mail", "browser", "notes", "terminal"], "desk": [String]()]
    let all: Set = ["mail", "notes", "browser", "editor", "terminal"]
    let r = Arrangement.restore(saved: saved, current: current, present: all)
    expect(r["laptop"] == ["mail", "notes"], "\(r)")
    expect(r["desk"] == ["browser", "editor", "terminal"], "\(r)")
}

test("windows opened in the meantime keep their place; closed ones are skipped") {
    let saved = ["laptop": ["mail"], "desk": ["browser", "editor"]]
    // "editor" was closed during the meeting; "slides" was opened.
    let current = ["laptop": ["slides", "browser", "mail"], "desk": [String]()]
    let r = Arrangement.restore(saved: saved, current: current, present: ["slides", "browser", "mail"])
    expect(r["laptop"] == ["mail", "slides"], "restored first, then the new one: \(r)")
    expect(r["desk"] == ["browser"], "\(r)")
}

test("saved displays that aren't connected are ignored; each window placed once") {
    let saved = ["laptop": ["a", "b"], "projector": ["c"], "desk": ["a"]]
    let current = ["laptop": ["c"], "desk": ["b"]]
    let r = Arrangement.restore(saved: saved, current: current, present: ["a", "b", "c"])
    expect(Set(r.keys) == ["laptop", "desk"], "\(r)")
    let all = r.values.flatMap { $0 }
    expect(all.count == 3 && Set(all) == ["a", "b", "c"], "every window exactly once: \(r)")
    expect(r["desk"]?.first == "a", "displays are filled in name order, so desk claims a first: \(r)")
}

test("unplugging to the laptop: everything that was on the laptop comes back first") {
    let saved = ["laptop": ["slides", "notes"]]
    let current = ["laptop": ["browser", "notes", "slides", "terminal"]]
    let r = Arrangement.restore(saved: saved, current: current, present: ["browser", "notes", "slides", "terminal"])
    expect(r["laptop"] == ["slides", "notes", "browser", "terminal"], "\(r)")
}

test("after a restart, windows are matched by app and title, then by app") {
    let saved = [
        "laptop": [WindowTag(app: "com.apple.mail", title: "Inbox")],
        "desk": [WindowTag(app: "com.google.Chrome", title: "Docs"), WindowTag(app: "com.google.Chrome", title: "Jira"),
                 WindowTag(app: "com.apple.Terminal", title: "zsh")],
    ]
    let present: [(id: Int, tag: WindowTag)] = [
        (1, WindowTag(app: "com.google.Chrome", title: "Gmail")),  // title changed (new tab)
        (2, WindowTag(app: "com.google.Chrome", title: "Jira")),   // exact
        (3, WindowTag(app: "com.apple.mail", title: "Inbox")),     // exact
        (4, WindowTag(app: "com.apple.Notes", title: "Notes")),    // not saved
    ]
    let r = Arrangement.resolve(saved, present: present)
    expect(r["laptop"] == [3], "\(r)")
    expect(r["desk"] == [1, 2], "exact match keeps its slot, the other Chrome fills the first: \(r)")
}

test("resolve never uses a window twice") {
    let tag = WindowTag(app: "x", title: "same")
    let r = Arrangement.resolve(["a": [tag, tag, tag], "b": [tag]], present: [(1, tag), (2, tag)])
    let all = r.values.flatMap { $0 }
    expect(all.sorted() == [1, 2], "\(r)")
}

// MARK: Dragging between tiles and displays

test("insert at an index, clamped; no duplicates; capacity respected") {
    var s = TileState<String>(maxTiles: 3)
    s.insert("a"); s.insert("b")
    expect(s.insert("x", at: 1) && s.windows == ["a", "x", "b"], "\(s.windows)")
    expect(!s.insert("y", at: 0), "full")
    expect(s.insert("y", at: 99, overCapacity: true) && s.windows.last == "y")
    expect(!s.insert("a", at: 0, overCapacity: true), "duplicate")
    var e = TileState<String>()
    expect(e.insert("z", at: -5) && e.windows == ["z"])
}

test("finding the tile under a drop point") {
    let f = [Rect(x: 0, y: 0, w: 100, h: 100), Rect(x: 100, y: 0, w: 100, h: 100)]
    expect(Navigation.index(containing: 150, 50, frames: f) == 1)
    expect(Navigation.index(containing: 50, 50, frames: f, excluding: 0) == nil, "the dragged window itself doesn't count")
    expect(Navigation.index(containing: 500, 50, frames: f) == nil)
}

test("the display next door, for moving a window across screens") {
    // Laptop below-left, monitor to the right and a little higher.
    let laptop = Rect(x: 0, y: 38, w: 1710, h: 974), monitor = Rect(x: 1710, y: -200, w: 2560, h: 1400)
    expect(Navigation.neighbor(of: 0, direction: .right, frames: [laptop, monitor]) == 1)
    expect(Navigation.neighbor(of: 1, direction: .left, frames: [laptop, monitor]) == 0)
    expect(Navigation.neighbor(of: 0, direction: .left, frames: [laptop, monitor]) == nil)
}

print(failures == 0 ? "OK: \(checks) checks passed" : "FAILED: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
