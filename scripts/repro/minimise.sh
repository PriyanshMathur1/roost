#!/bin/bash
# Minimising a tiled window removes it and the rest reflow; restoring it brings it back.
# Needs debugState on and roostctl (swiftc -O scripts/repro/roostctl.swift -o "$ROOSTCTL").
set -euo pipefail
ROOSTCTL="${ROOSTCTL:?set ROOSTCTL to the built roostctl}"
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
for i in 1 2 3; do echo "m$i" > "$TMP/m$i.txt"; open -F -a TextEdit "$TMP/m$i.txt"; sleep 0.6; done
sleep 3
check() { python3 - "$1" <<'PY'
import json, os, sys
s = json.load(open(os.path.expanduser("~/Library/Logs/Roost/state.json")))
tiles = [t for d in s["displays"] for t in d["tiles"]]
names = [t.get("title") for t in tiles]
where = "tiled" if "m2.txt" in names else ("stacked" if any(o.get("title") == "m2.txt" for o in s["overflow"]) else "gone")
# no gaps: every tile's window actually sits on its tile
off = [t["title"] for t in tiles if t.get("frame") and t.get("target") and any(abs(a - b) > 3 for a, b in zip(t["frame"], t["target"]))]
print(f"{sys.argv[1]:10s} tiles={len(tiles)} m2.txt={where} windows-off-their-tile={off or 'none'}")
print(where, len(tiles), "ok" if not off else "bad")
PY
}
a="$(check before | tail -1)"; check before | head -1
"$ROOSTCTL" minimise m2.txt; sleep 2.5
b="$(check minimised | tail -1)"; check minimised | head -1
"$ROOSTCTL" restore m2.txt; sleep 3
c="$(check restored | tail -1)"; check restored | head -1
read wa na oa <<< "$a"; read wb nb ob <<< "$b"; read wc nc oc <<< "$c"
# Minimised: out of the layout. Restored: back (tiled, or stacked if every tile is full).
# Throughout: every tiled window sits exactly on its tile (the rest reflowed, no gaps).
[ "$wb" = gone ] && [ "$wc" != gone ] && [ "$oa$ob$oc" = okokok ]
