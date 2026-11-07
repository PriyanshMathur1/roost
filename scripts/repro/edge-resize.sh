#!/bin/bash
# Dragging the main window's edge narrower: the main tile keeps the new width and the stack
# grows beside it (instead of the window snapping back). Restores the display's layout.
# Needs debugState on and ROOSTCTL. Exit 0 green, 1 red.
set -euo pipefail
ROOSTCTL="${ROOSTCTL:?set ROOSTCTL to the built roostctl}"
TMP="$(mktemp -d)"
STATE="$HOME/Library/Logs/Roost/state.json"
LAYOUT0="$(python3 -c "import json; print(json.load(open('$STATE'))['displays'][0]['layout'])")"
ORIG="$(defaults read com.apple.TextEdit AppleWindowTabbingMode 2>/dev/null || echo __unset__)"
restore() {
  pkill -x TextEdit 2>/dev/null || true
  "$ROOSTCTL" reset-sizes; sleep 1
  "$ROOSTCTL" layout "$LAYOUT0"
  if [ "$ORIG" = "__unset__" ]; then defaults delete com.apple.TextEdit AppleWindowTabbingMode 2>/dev/null || true
  else defaults write com.apple.TextEdit AppleWindowTabbingMode -string "$ORIG"; fi
  rm -rf "$TMP"
}
trap restore EXIT
"$ROOSTCTL" layout main; sleep 1; "$ROOSTCTL" reset-sizes; sleep 1.5
pkill -x TextEdit 2>/dev/null || true
defaults write com.apple.TextEdit AppleWindowTabbingMode -string manual
sleep 1
for i in 1 2; do echo "r$i" > "$TMP/r$i.txt"; open -F -a TextEdit "$TMP/r$i.txt"; sleep 0.6; done
sleep 3
read title x y w h <<< "$(python3 -c "
import json; t=json.load(open('$STATE'))['displays'][0]['tiles'][0]
print(t['title'], *[round(v) for v in t['target']])")"
echo "main before: '$title' ${w}x${h} at $x,$y"
"$ROOSTCTL" resize "$title" $((w - 200)) $h; sleep 2.5
python3 - "$STATE" "$title" $((w - 200)) <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); want = float(sys.argv[3])
tiles = s["displays"][0]["tiles"]; main = tiles[0]; stack = tiles[1] if len(tiles) > 1 else None
ok_main = main["title"] == sys.argv[2] and abs(main["target"][2] - want) <= 2 and all(abs(a - b) <= 3 for a, b in zip(main["frame"], main["target"]))
ok_stack = stack is not None and abs(stack["target"][0] - (main["target"][0] + main["target"][2] + 8)) <= 1
print(f"main after: {main['title']} target {[round(v) for v in main['target']]} frame {[round(v) for v in main['frame']]} (want width {want:.0f})")
print(f"stack starts at x={stack['target'][0] if stack else None}")
sys.exit(0 if ok_main and ok_stack else 1)
PY
