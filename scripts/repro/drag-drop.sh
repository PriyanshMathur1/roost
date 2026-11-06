#!/bin/bash
# Dropping a window on another tile swaps the two; letting go inside its own tile snaps it back.
# Uses Roost's real drop path via roostctl (needs debugState on). Exit 0 green, 1 red.
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
for i in 1 2 3; do echo "d$i" > "$TMP/d$i.txt"; open -F -a TextEdit "$TMP/d$i.txt"; sleep 0.6; done
sleep 3
tile() { python3 -c "
import json,os,sys; s=json.load(open(os.path.expanduser('~/Library/Logs/Roost/state.json')))
t=[t for d in s['displays'] for t in d['tiles'] if t.get('title')=='$1']
print(' '.join(str(round(v)) for v in t[0]['target']) if t else 'none')"; }
a1="$(tile d1.txt)"; a2="$(tile d2.txt)"; a3="$(tile d3.txt)"
echo "before: d1 [$a1]  d2 [$a2]  d3 [$a3]"
read x y w h <<< "$a2"
"$ROOSTCTL" drop d1.txt $((x + w / 2)) $((y + h / 2)); sleep 2.5
b1="$(tile d1.txt)"; b2="$(tile d2.txt)"
echo "drop d1 on d2: d1 [$b1]  d2 [$b2]   (expect swapped)"
read x y w h <<< "$a3"
"$ROOSTCTL" drop d3.txt $((x + w / 3)) $((y + h / 3)); sleep 2.5
b3="$(tile d3.txt)"
frame3="$(python3 -c "
import json,os; s=json.load(open(os.path.expanduser('~/Library/Logs/Roost/state.json')))
t=[t for d in s['displays'] for t in d['tiles'] if t.get('title')=='d3.txt'][0]
print(' '.join(str(round(v)) for v in t['frame']))")"
echo "let go of d3 inside its tile: tile [$b3] frame [$frame3]   (expect back on its tile)"
[ "$b1" = "$a2" ] && [ "$b2" = "$a1" ] && [ "$b3" = "$a3" ] && [ "$frame3" = "$a3" ]
