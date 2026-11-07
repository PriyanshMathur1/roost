#!/bin/bash
# A window that goes away (minimised here; other Spaces and hidden apps take the same path)
# must come back to its own tile, not the end of the line.
# Needs debugState on and ROOSTCTL. Exit 0 green, 1 red.
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
for i in 1 2 3; do echo "p$i" > "$TMP/p$i.txt"; open -F -a TextEdit "$TMP/p$i.txt"; sleep 0.6; done
sleep 3
tile() { python3 -c "
import json,os; s=json.load(open(os.path.expanduser('~/Library/Logs/Roost/state.json')))
t=[t for d in s['displays'] for t in d['tiles'] if t.get('title')=='$1']
print(' '.join(str(round(v)) for v in t[0]['target']) if t else 'none')"; }
before="$(tile p2.txt)"; echo "p2 before:    [$before]"
"$ROOSTCTL" minimise p2.txt; sleep 2.5
echo "p2 minimised: [$(tile p2.txt)]"
"$ROOSTCTL" restore p2.txt; sleep 3
after="$(tile p2.txt)"; echo "p2 restored:  [$after]   (expect its old tile)"
[ "$before" != none ] && [ "$after" = "$before" ]
