# Tessera

An automatic window tiler for macOS that lives in the menu bar. Open a window and it
gets a place; close one and the others fill the space.

See [docs/SPEC.md](docs/SPEC.md) for scope, design and the clean-room rule.

## Build and run

Needs the Swift 6 toolchain (Xcode Command Line Tools are enough).

```bash
./scripts/bundle.sh          # builds ~/Applications/Tessera.app
open ~/Applications/Tessera.app
```

On first launch macOS asks for Accessibility access. Turn Tessera on in
**System Settings › Privacy & Security › Accessibility**. Tiling starts on its own
within a couple of seconds.

## Signing

`scripts/bundle.sh` signs with a code-signing certificate named **Tessera Dev** when
your login keychain has one. macOS then ties the Accessibility grant to that
certificate and the bundle ID, so **you grant it once and rebuilds keep it**. Without
the certificate the app is signed ad-hoc and every rebuild needs the grant again.

To create the certificate (self-signed, valid 10 years, usable only by `codesign`):

```bash
cat > /tmp/tessera-cert.cfg <<'CFG'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Tessera Dev
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG
cd "$(mktemp -d)" && P=$(openssl rand -hex 12)
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config /tmp/tessera-cert.cfg
openssl pkcs12 -export -inkey key.pem -in cert.pem -name "Tessera Dev" -out id.p12 -passout pass:$P
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P "$P" -T /usr/bin/codesign
rm key.pem id.p12
```

`security find-identity -p codesigning` lists it as `CSSMERR_TP_NOT_TRUSTED`; that is
normal for a self-signed certificate and doesn't stop signing.

If a grant ever goes stale (for example after switching certificates), clear it and
allow Tessera again:

```bash
tccutil reset Accessibility com.priyansh.tessera
```

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

- At most 6 tiled windows per display, and no tile narrower than the **Narrowest Tile** setting
  (300 pt by default). Windows beyond that float where they open and join when a tile frees up.
- Windows that won't shrink (Chrome below 500 pt, System Settings below 723 pt) are measured
  the first time and given the room; the measurements are forgotten when Tessera quits.
- Dragging a window to another display doesn't move its tile there yet. Float it (⌃⌥F), move it, then tile it again.
- Windows on other Spaces drop out of the layout and rejoin at the end when you come back.
