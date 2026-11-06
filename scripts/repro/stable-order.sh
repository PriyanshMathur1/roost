#!/bin/bash
# Repro: re-checks (app switches) must never move windows between tiles.
# Opens 8 TextEdit windows (some stack), records which window is in each tile, switches apps
# a few times (each switch makes Roost re-check), and requires the same tile order after.
# Needs: defaults write com.priyansh.roost debugState -bool true. Exit 0 green, 1 red.
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
for i in 1 2 3 4 5 6 7 8; do echo "w$i" > "$TMP/w$i.txt"; open -F -a TextEdit "$TMP/w$i.txt"; sleep 0.5; done
sleep 3
# Every tile except the last: the last tile's front window is meant to change when a window
# stacked behind it is brought forward.
order() { python3 -c "import json,os; s=json.load(open(os.path.expanduser('~/Library/Logs/Roost/state.json'))); t=[(t.get('title') or '?') for d in s['displays'] for t in d['tiles']]; print(' '.join(t[:-1]))"; }
before="$(order)"
for app in Finder TextEdit Finder TextEdit; do open -a "$app"; sleep 1.2; done
# Bring stacked windows forward, as ⌃⌥Tab or a Dock click does.
for i in 8 7 6 5; do open -a TextEdit "$TMP/w$i.txt"; sleep 1.2; done
after="$(order)"
echo "before: $before"
echo "after:  $after"
[ "$before" = "$after" ]
