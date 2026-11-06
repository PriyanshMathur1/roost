# Tessera

An automatic window tiler for macOS that lives in the menu bar. Open a window and it
gets a place; close one and the others fill the space.

See [docs/SPEC.md](docs/SPEC.md) for scope, design and the clean-room rule.

## Build and run

Needs the Swift 6 toolchain (Xcode Command Line Tools are enough).

```bash
./scripts/bundle.sh          # builds build/Tessera.app
open build/Tessera.app
```

On first launch macOS asks for Accessibility access. Turn Tessera on in
**System Settings › Privacy & Security › Accessibility**. Tiling starts on its own
within a couple of seconds.

The build is signed ad-hoc, so **each rebuild needs the grant again**: in that
settings pane, remove Tessera with **−**, then open the new build.

## Tests

```bash
swift run TesseraCoreTests
```

XCTest needs a full Xcode install, so the layout engine's tests are a small
executable that exits non-zero on failure.

## Shortcuts

| Keys | Action |
|---|---|
| ⌃⌥ ← → ↑ ↓ | Focus the window in that direction |
| ⌃⌥⇧ ← → ↑ ↓ | Swap with the window in that direction |
| ⌃⌥ ↩ | Make the focused window the main one |
| ⌃⌥ = / ⌃⌥ - | Grow / shrink the focused window |
| ⌃⌥ 1–4 | Layout: main + stack, columns, rows, grid |
| ⌃⌥ F | Float the focused window (or tile it again) |
| ⌃⌥ T | Tiling on / off |

Shortcuts another app already owns are listed as "taken" in the menu.

## Layout

- `Package.swift`: three targets
- `Sources/TesseraCore`: pure layout maths, navigation, tile state (no AppKit)
- `Sources/Tessera`: the app (Accessibility, hotkeys, menu bar)
- `Tests/TesseraCoreTests`: test runner
- `scripts/bundle.sh`: packages the `.app`

## Known limits (v0.1)

- At most 6 tiled windows per display; extra windows float where they open.
- Windows that refuse to get as small as their tile overlap their neighbours.
- Dragging a window to another display doesn't move its tile there yet. Float it (⌃⌥F), move it, then tile it again.
- Windows on other Spaces drop out of the layout and rejoin at the end when you come back.
