<p align="center"><img src="docs/icon.png" width="128" alt="Roost icon"></p>

<h1 align="center">Roost</h1>

<p align="center"><b>Your windows come home to roost.</b><br>
A free, open-source window tiler for macOS that remembers where everything goes, on every display setup.</p>

---

Roost tiles your windows as they open: no dragging, no resizing, no config files.

It also remembers. Plug your laptop into your desk monitor and every window goes back to where
it was the last time you sat there. Unplug for a meeting and your laptop layout comes back. Each
combination of displays gets its own memory, and it survives restarts.

## What it does

- **Tiles automatically.** A new window gets a place; close one and the rest fill the gap.
- **Desk ↔ meeting memory.** Remembers the arrangement for each set of connected displays and
  restores it when that set comes back.
- **Works with stubborn windows.** Some windows won't shrink (Chrome below 500 pt, System
  Settings below 723 pt). Roost notices, gives them the room, and remembers per app. If not
  everything fits, the windows that need the most room float instead of everything getting
  squeezed.
- **Never makes slivers.** No tile goes below a sensible size (300 pt by default; adjustable).
- **Drag to rearrange.** Drop a window on another to swap them, or on another display to move it
  there.
- **Keyboard-first when you want it.** Focus, swap, resize and change layout with ⌃⌥ shortcuts.
- **Four layouts per display:** main + stack, columns, rows, grid. Portrait displays get rows.
- **Leaves alone what it should:** dialogs, sheets, panels, full-screen apps and minimised windows.
- **Private.** Roost makes no network connections. Its only permission is Accessibility, used to
  read where windows are and move them.

## Install

Roost is free and open source, and isn't notarised by Apple (that needs a paid developer
account). So macOS asks you to confirm the first launch:

1. Download **Roost-x.y.z.zip** from [Releases](../../releases/latest), unzip it, and move
   **Roost.app** to **Applications**.
2. Open Roost. macOS says it can't verify the developer. Click **Done**.
3. Open **System Settings › Privacy & Security**, scroll down, and click **Open Anyway** next to
   the Roost message. Confirm with **Open Anyway**.
4. Roost's welcome window opens. Click **Open Accessibility Settings** and turn **Roost** on.
   Then click **Start Tiling**.

Roost lives in the menu bar (a roof over three tiles). It runs on macOS 14 Sonoma or later, on
Apple Silicon and Intel.

### Build from source

Needs the Swift 6 toolchain (the Xcode Command Line Tools are enough).

```bash
git clone https://github.com/PriyanshMathur1/roost.git
cd roost
./scripts/bundle.sh            # builds ~/Applications/Roost.app
open ~/Applications/Roost.app
```

Apps you build yourself aren't quarantined, so there's no Gatekeeper step. See
[Signing](#signing) to keep the Accessibility permission across rebuilds.

## Shortcuts

| Keys | Action |
|---|---|
| ⌃⌥ ← → ↑ ↓ | Focus the window on that side (at a screen edge: the next display) |
| ⌃⌥⇧ ← → ↑ ↓ | Swap with the window on that side (at a screen edge: move to the next display) |
| ⌃⌥ ↩ | Make the focused window the main one |
| ⌃⌥ = / ⌃⌥ - | Grow / shrink the focused window |
| ⌃⌥ 1 – 4 | Layout: main + stack, columns, rows, grid |
| ⌃⌥ F | Float the focused window (or tile it again) |
| ⌃⌥ T | Tiling on / off |

Shortcuts another app already owns are listed as "taken" in the menu under **Keyboard Shortcuts**.

## Menu

Tiling on/off · layout for the display under the pointer · gap · narrowest tile · re-tile ·
reset sizes · forget learned window sizes · keyboard shortcuts · open at login · getting started.

## How it works

- **`RoostCore`** is pure Swift with no AppKit: layouts, minimum-size fitting, neighbour search,
  tile state and the display-setup memory. It has ~43,000 checks
  (`swift run RoostCoreTests`).
- **`Roost`** is the app: it watches apps with the Accessibility API (`AXObserver`), re-reads the
  windows on screen after each change (so a missed event can't leave things wrong), and moves
  windows with `AXUIElementSetAttributeValue`. Shortcuts use Carbon's `RegisterEventHotKey`,
  which needs no extra permission.

More in [docs/SPEC.md](docs/SPEC.md).

## Signing

`scripts/bundle.sh` signs with a code-signing certificate named **Roost Dev** if your login
keychain has one. macOS then ties the Accessibility permission to that certificate and the bundle
ID, so **you grant it once and rebuilds keep it**. Without one, the app is signed ad-hoc and each
rebuild needs the permission again.

To create the certificate (self-signed, valid 10 years, usable only by `codesign`):

```bash
cat > /tmp/roost-cert.cfg <<'CFG'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Roost Dev
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG
cd "$(mktemp -d)" && P=$(openssl rand -hex 12)
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config /tmp/roost-cert.cfg
openssl pkcs12 -export -inkey key.pem -in cert.pem -name "Roost Dev" -out id.p12 -passout pass:$P
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P "$P" -T /usr/bin/codesign
rm key.pem id.p12
```

`security find-identity -p codesigning` lists it as `CSSMERR_TP_NOT_TRUSTED`; that's normal for a
self-signed certificate and doesn't stop signing. If a permission ever goes stale, run
`tccutil reset Accessibility com.priyansh.roost` and allow Roost again.

The app is built into `~/Applications` rather than the project folder because iCloud Drive (a
synced Desktop or Documents folder) adds file attributes that break code signatures.

## Known limits

- Windows on other Spaces drop out of the layout and rejoin at the end when you come back.
- Resizing a tile with the mouse is undone at the next re-tile; use ⌃⌥ = and ⌃⌥ - instead.
- Floating windows stay where they are, so they can sit on top of tiles.

## Contributing

Issues and pull requests are welcome. Please run `swift run RoostCoreTests` before sending a
change, and add checks for any new layout logic.

## License

[MIT](LICENSE) © 2026 Priyansh Mathur
