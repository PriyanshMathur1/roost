#!/bin/bash
# Repro: windows that don't fit must wait inside a tile, never float across others.
# Opens 8 separate TextEdit windows (more than fit), waits for Roost, then checks Roost's
# state dump (needs: defaults write com.priyansh.roost debugState -bool true).
# Exits 0 (green) or 1 (red).
set -euo pipefail
TMP="$(mktemp -d)"
ORIG="$(defaults read com.apple.TextEdit AppleWindowTabbingMode 2>/dev/null || echo __unset__)"
restore() {
  pkill -x TextEdit 2>/dev/null || true
  if [ "$ORIG" = "__unset__" ]; then defaults delete com.apple.TextEdit AppleWindowTabbingMode 2>/dev/null || true
  else defaults write com.apple.TextEdit AppleWindowTabbingMode -string "$ORIG"; fi
  rm -rf "$TMP"
}
trap restore EXIT
pkill -x TextEdit 2>/dev/null || true
defaults write com.apple.TextEdit AppleWindowTabbingMode -string manual
sleep 1
for i in 1 2 3 4 5 6 7 8; do echo "window $i" > "$TMP/w$i.txt"; open -F -a TextEdit "$TMP/w$i.txt"; sleep 0.6; done
sleep 4
python3 - "$HOME/Library/Logs/Roost/state.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
tiles = [t for d in s["displays"] for t in d["tiles"]]
targets = [t["target"] for t in tiles if "target" in t]
# A waiting window must sit inside one tile (it may be smaller if the app has a maximum size),
# so it never crosses into a neighbouring tile.
inside = lambda f, t: f[0] >= t[0] - 2 and f[1] >= t[1] - 2 and f[0] + f[2] <= t[0] + t[2] + 2 and f[1] + f[3] <= t[1] + t[3] + 2
# The one exception: a window too big for every tile is centred on its display, on purpose.
disp = s["displays"][0]["visible"]
centred = lambda f: abs((f[0] + f[2] / 2) - (disp[0] + disp[2] / 2)) <= 3 and abs((f[1] + f[3] / 2) - (disp[1] + disp[3] / 2)) <= 3
bigger_than_every_tile = lambda f: all(f[2] > t[2] + 2 or f[3] > t[3] + 2 for t in targets)
bad = [o for o in s["overflow"] if "frame" not in o or not (any(inside(o["frame"], t) for t in targets)
       or (bigger_than_every_tile(o["frame"]) and centred(o["frame"])))]
print(f"tiles: {len(tiles)} · without a tile: {len(s['overflow'])} · floating loose: {len(bad)}")
for o in bad: print("  loose:", o["app"], o.get("title"), o.get("frame"))
sys.exit(1 if bad or not s["overflow"] else 0)
PY
