#!/bin/bash
# Records Smart Clipboard and Smart Drop's QR reading for the promo. ~20 s; hands off.
set -euo pipefail
OUT="${1:-$HOME/Documents/Halo/Promo/footage}"
mkdir -p "$OUT"
send() {
  osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('com.niranjan.Halo.command', \$(), \$({command:'$1'}), true)" >/dev/null
  echo "$(date +%s.%N | cut -c1-14) $1" >> "$OUT/cues3.txt"
}
: > "$OUT/cues3.txt"
osascript -e 'tell application "Finder" to activate'
"$(dirname "$0")/stage" & STAGE=$!
swift -e 'import CoreGraphics; CGWarpMouseCursorPosition(CGPoint(x: 1300, y: 800))'
sleep 2
send demo.clearClipboard; sleep 0.3
echo "$(date +%s.%N | cut -c1-14) record-start" >> "$OUT/cues3.txt"
screencapture -v -V 22 -k "$OUT/tour3.mov" & REC=$!
sleep 1
send demo.copyPhone; sleep 1.5
send showClipboard; sleep 3.5
send demo.closeClipboard; sleep 1
send demo.smartDropQR; sleep 1.5
send demo.readQR; sleep 3.5
send demo.collapse; sleep 1
wait $REC || true
kill $STAGE 2>/dev/null || true
echo "done: $OUT/tour3.mov"
