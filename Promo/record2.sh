#!/bin/bash
# Records the second part of the tour: Siri, live download, rain alert. ~35 s; hands off.
set -euo pipefail
OUT="${1:-$HOME/Documents/Halo/Promo/footage}"
mkdir -p "$OUT"
send() {
  osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('com.niranjan.Halo.command', \$(), \$({command:'$1'}), true)" >/dev/null
  echo "$(date +%s.%N | cut -c1-14) $1" >> "$OUT/cues2.txt"
}
: > "$OUT/cues2.txt"
osascript -e 'tell application "Finder" to activate'
"$(dirname "$0")/stage" & STAGE=$!
swift -e 'import CoreGraphics; CGWarpMouseCursorPosition(CGPoint(x: 1300, y: 800))'
sleep 2
echo "$(date +%s.%N | cut -c1-14) record-start" >> "$OUT/cues2.txt"
screencapture -v -V 36 -k "$OUT/tour2.mov" & REC=$!
sleep 2.5
send demo.siri; sleep 5
send demo.siriClose; sleep 2
send demo.download; sleep 6.5
send demo.rain; sleep 4
send demo.collapse; sleep 1
wait $REC || true
kill $STAGE 2>/dev/null || true
echo "done: $OUT/tour2.mov"
