#!/bin/bash
# Repro: a window with native tabs must take exactly one tile.
# Opens 4 TextEdit documents as tabs of one window, waits for Roost, then checks Roost's
# state dump (needs: defaults write com.priyansh.roost debugState -bool true).
# Exits 0 (green) or 1 (red). Restores TextEdit's tabbing preference afterwards.
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
defaults write com.apple.TextEdit AppleWindowTabbingMode -string always
sleep 1
for i in 1 2 3 4; do echo "tab $i" > "$TMP/tab$i.txt"; open -F -a TextEdit "$TMP/tab$i.txt"; sleep 0.8; done
sleep 3
python3 - "$HOME/Library/Logs/Roost/state.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
tiles = [t for d in s["displays"] for t in d["tiles"]]
# Only this test's own documents (TextEdit may have other windows open).
te = [t for t in tiles if t["app"] == "com.apple.TextEdit" and (t.get("title") or "").startswith("tab")]
te += [t for t in s["overflow"] if t["app"] == "com.apple.TextEdit" and (t.get("title") or "").startswith("tab")]
print(f"tiles: {len(tiles)} · TextEdit tiles: {len(te)} · overflow: {len(s['overflow'])}")
for t in te: print("  TextEdit tile:", t.get("title"), t.get("target"))
sys.exit(0 if len(te) == 1 else 1)
PY
