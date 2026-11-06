/// Where windows that don't fit wait: each sits exactly behind a tile, fully covered, so
/// nothing overlaps. Bringing one forward (Dock, ⌘-Tab, ⌃⌥Tab) shows it in that tile.
public enum Stacking {
    /// A window of `size` centred on `display`; if it's bigger, pinned to the top-left.
    public static func centred(_ size: Size, in display: Rect) -> Rect {
        Rect(x: (display.x + max((display.w - size.w) / 2, 0)).rounded(), y: (display.y + max((display.h - size.h) / 2, 0)).rounded(),
             w: size.w, h: size.h)
    }

    public static func homes<ID: Hashable>(for extras: [ID], tiles: [(id: ID, frame: Rect)], minSizes: [ID: Size]) -> [ID: Rect] {
        guard let last = tiles.last else { return [:] }
        var homes: [ID: Rect] = [:]
        for id in extras {
            let min = minSizes[id] ?? .zero
            let fits = { (r: Rect) in r.w + 1 >= min.w && r.h + 1 >= min.h }
            if fits(last.frame) {
                homes[id] = last.frame
            } else if let roomiest = tiles.map(\.frame).filter(fits).max(by: { $0.w * $0.h < $1.w * $1.h }) {
                homes[id] = roomiest
            }
            // Fits no tile: no home. Behind a tile it would spill over its neighbours, so the
            // caller centres it instead (`centred`).
        }
        return homes
    }
}
