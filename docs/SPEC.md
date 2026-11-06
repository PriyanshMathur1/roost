# Roost: spec (v0.2)

A macOS menu-bar app that tiles windows automatically and remembers where they go for each set
of connected displays.

## Clean-room rule

Roost is written from scratch, from Apple's public documentation (Accessibility
`AXUIElement`/`AXObserver`, Carbon `RegisterEventHotKey`, `NSWorkspace`, `NSStatusItem`,
`SMAppService`) and our own design. Don't paste code, strings, names, icons or layouts from
closed-source products into this repo.

## Behaviour

| Area | Behaviour |
|---|---|
| Auto-tiling | Standard windows of regular apps are tiled on the display that holds their centre. New windows are added; closed, minimised or hidden ones are removed and the rest re-flow. |
| Skipped windows | Anything whose subrole isn't `AXStandardWindow` (dialogs, sheets, panels), native full-screen windows, minimised windows, and windows the user floats (⌃⌥F). Each skip is logged once with its reason. |
| Layouts | `main` (one large window left, others stacked right), `columns`, `rows`, `grid`. Per display. Portrait displays use `rows` when `columns` is chosen. |
| Minimum sizes | When a window comes out bigger than its tile, that size is its minimum. The layout gives it the room, taking it from windows that can spare it. Learned per window and per app (saved across restarts). |
| Fitting | Every tile is at least the Narrowest Tile setting (300 pt wide, ~165 pt tall by default) when more than one window is tiled. Up to 6 tiles per display. When not everything fits, the main window stays and the rest are added smallest-minimum first; the windows needing the most room float. Windows left out are retried after new minimums are learned. |
| Desk ↔ meeting memory | After each change, the window order per display is saved for the current display setup (the set of connected displays), in memory and on disk (by app + title). When a setup is connected again, its windows go back to their saved displays in saved order; other windows keep their current display. After a restart, windows are matched by app and title, then by app. |
| Dragging | A move that isn't Roost's own is a drag; on mouse-up: dropped on another tile of the same display → swap; on another display → move there, at the tile it was dropped on; elsewhere → back to its tile. |
| Keyboard | ⌃⌥ arrows focus; ⌃⌥⇧ arrows swap (at a display edge: move to the next display); ⌃⌥↩ promote; ⌃⌥=/- grow/shrink; ⌃⌥1–4 layout; ⌃⌥F float; ⌃⌥T on/off. |
| First run | A welcome window explains the one permission with live status, and the keys to start with. |
| Privacy | No network access. |

## Architecture

- `RoostCore` (pure Swift, no AppKit, tested by `swift run RoostCoreTests`):
  `Rect`/`Size`, `Layout.fit` (layouts with minimum sizes), `Navigation` (neighbours, drop
  targets), `TileState` (per-display window order, weights, fitting), `Arrangement` +
  `DisplaySetup` (desk ↔ meeting memory).
- `Roost` (app): `AXWindow` (Accessibility access), `WindowTracker` (observers; any event
  schedules one debounced re-read of the windows on screen), `TilingController` (state per
  display, applying frames, learning minimums, drags, memory), `HotKeys`, `AppDelegate` (menu),
  `WelcomeWindow`, `Brand` (the mark and icon), `Settings` (UserDefaults).

Coordinates in `RoostCore` are "top-left global" points, the space Accessibility uses: origin at
the top-left of the primary display, y down.
