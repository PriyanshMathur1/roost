# Tessera: core tiler spec (v0.1)

A macOS menu-bar app that tiles windows automatically: a new window gets a place,
a closed one leaves no gap.

## Clean-room rule

Tessera is written from scratch. Its sources are Apple's public documentation
(Accessibility `AXUIElement`/`AXObserver`, Carbon `RegisterEventHotKey`,
`NSWorkspace`, `NSStatusItem`, `SMAppService`) and our own design.

Shoji (shojimac.com) inspired the product category. Its terms forbid
decompiling or reverse engineering it, so nothing here is derived from its
binary, its website code or its text. Do not paste code, strings, names,
icons or layouts from Shoji or any other closed product into this repo.

## Scope of v0.1

| Area | Behaviour |
|---|---|
| Auto-tiling | Standard windows of regular apps are tiled on the display that holds their centre. A new window is appended; a closed, minimised or hidden window is removed and the rest re-flow. |
| Skipped windows | Anything whose subrole is not `AXStandardWindow` (dialogs, sheets, panels, palettes), native full-screen windows, minimised windows, and windows the user floats. |
| Layouts | `main` (one large window left, others stacked right), `columns`, `rows`, `grid` (near-square grid; the last row widens to fill). Chosen per display. Portrait displays use `rows` when `columns` is selected. |
| Capacity | Up to `maxTiles` (default 6) windows per display; extra windows are left floating where they are. |
| Gaps | One outer and inner gap value (default 8 pt). |
| Keyboard | Prefix ⌃⌥: arrows focus the neighbour; ⇧+arrows swap with it; Return makes the focused window main; `1`–`4` pick a layout; `-`/`=` shrink/grow the focused window's share; `F` floats/unfloats the focused window; `T` toggles tiling. |
| Menu bar | Tiling on/off, layout for the display under the pointer, re-tile now, gap size, launch at login, Accessibility status, quit. |
| Permissions | Prompts for Accessibility on launch and waits, polling, until it is granted. |

## Out of scope for v0.1

Stacks/tabs, learned minimum sizes, per-app float rules UI, drag-to-swap with the
mouse, mouse resizing of splits, Spaces awareness beyond "on-screen windows only",
licensing, auto-update.

## Architecture

- `TesseraCore` (pure Swift, no AppKit): `Rect`, `LayoutKind`, `Layout.frames`,
  `Navigation.neighbor`, `TileState` (ordered window list + per-window weights).
- `Tessera` (app): `AXWindow` (attribute access), `WindowTracker` (observers,
  events), `TilingController` (state per display, applies frames), `HotKeys`,
  `StatusMenu`, `AppDelegate`.

Coordinates in `TesseraCore` are "top-left global" points, the same space
Accessibility uses: origin at the top-left of the primary display, y down.
