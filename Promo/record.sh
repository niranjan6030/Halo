#!/bin/bash
# Records Halo's feature tour on this Mac. Takes about 90 seconds; don't touch the Mac.
set -euo pipefail
OUT="${1:-$HOME/Documents/Halo/Promo/footage}"
mkdir -p "$OUT"
send() {
  osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('com.niranjan.Halo.command', \$(), \$({command:'$1'}), true)" >/dev/null
  echo "$(date +%s.%N | cut -c1-14) $1" >> "$OUT/cues.txt"
}
: > "$OUT/cues.txt"
osascript -e 'tell application "Finder" to activate'
"$(dirname "$0")/stage" & STAGE=$!
# Park the pointer away from the notch.
swift -e 'import CoreGraphics; CGWarpMouseCursorPosition(CGPoint(x: 1300, y: 800))'
sleep 2
echo "$(date +%s.%N | cut -c1-14) record-start" >> "$OUT/cues.txt"
screencapture -v -V 95 -k "$OUT/tour.mov" & REC=$!
sleep 3                      # compact song
send showNowPlaying; sleep 4.5
send demo.collapse; sleep 1.5
send showCharging; sleep 3.5
send demo.unplugged; sleep 3.5
send demo.airpods; sleep 3.5
send demo.capsLock; sleep 3.5
send showControls; sleep 5
send showPage.weather; sleep 3.5
send showPage.system; sleep 4
send demo.pomodoro; sleep 4
send demo.stopTimer; send showPage.lyrics; sleep 4.5
send demo.collapse; sleep 1.2
send demo.smartDrop; sleep 2.5
send demo.removeBackground; sleep 4.5
send demo.collapse; sleep 1.2
send showClipboard; sleep 4.5
send demo.closeClipboard; sleep 1
send demo.message; sleep 3.5
send demo.collapse
wait $REC || true
kill $STAGE 2>/dev/null || true
echo "done: $OUT/tour.mov"
