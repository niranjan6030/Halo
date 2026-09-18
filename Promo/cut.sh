#!/bin/bash
# Cuts the Halo promo from the tour4/lyrics/smartdrop takes (RecordTool, constant frame
# rate) between the kinetic 4K title cards. Output: final/Halo-Promo-2160p60.mp4
set -euo pipefail
cd "$(dirname "$0")"
SRC=footage/tour4.mov
mkdir -p final shots

# (Flat-color covers were tried here — for macOS's purple recording indicator, for a
# stray menu-bar avatar icon, and for stray frontmost-app menu text — but every one of
# them assumed a fixed background color that isn't actually constant across every shot
# and every state (compact vs expanded), so each one eventually painted over real
# content somewhere. Removed all three; the recording is left as captured, uncovered.)
# Per-clip fade-in removed too: transitions are now real crossfades (xfade) applied
# across the whole timeline in the concat step below, not a fade-from-black on each clip.

# shot name start end cropWidth cropHeight cropX zoom pillUntil(unused, kept for call-site compat)
shot() {
  local name=$1 start=$2 end=$3 cw=$4 ch=$5 cx=$6 zoom=$7
  local d; d=$(echo "$end - $start" | bc)
  ffmpeg -loglevel error -y -ss "$start" -t "$d" -i "$SRC" -filter_complex \
    "[0:v]setpts=PTS-STARTPTS,fps=60,crop=$cw:$ch:$cx:0,scale=3840:2160:flags=lanczos,zoompan=z='1+$zoom*on/($d*60)':x='iw/2-iw/zoom/2':y=0:d=1:s=3840x2160:fps=60,format=yuv420p[v]" \
    -map "[v]" -an -c:v libx264 -preset slow -crf 14 "shots/$name.mp4"
  echo "shot $name ($d s)"
}

# --- Main tour (tour4.mov, constant-frame-rate capture) ---
shot music      5.30  8.90  1400  788 770 0.05 1.15
shot charging  10.80 11.80 1000  562 970 0.03 -1
shot unplugged 15.70 17.50 1000  562 970 0.03 -1
shot airpods   20.10 22.50 1000  562 970 0.03 -1
shot controls  29.70 33.00 1400  788 770 0.05 -1
shot system    37.50 40.50 1400  788 770 0.04 -1
shot timer     41.50 44.50 1400  788 770 0.04 -1
shot clipboard 62.30 63.80 2000 1125 470 0.04 999
shot smartclip 63.90 65.20 1500  844 720 0.03 999
shot qrread    69.60 72.00 1400  788 770 0.05 -1
shot siri      74.30 79.30  560  315 1225 0.04 999
shot download  82.30 87.00 1200  675 870 0.04 999
shot rain      89.40 92.40 1200  675 870 0.03 -1

# --- Lyrics: isolated clean re-take (the live tour's lyrics-page open has a real,
# repeatable render stall in Halo itself — not a capture artifact) ---
SRC_SAVED=$SRC; SRC=footage/lyrics.mov
shot lyrics     6.60 10.80 1400  788 770 0.04 -1
SRC=$SRC_SAVED

# --- Smart Drop: isolated clean re-take. The remove-background pass itself is a real,
# reproducible multi-second stall in Halo (Vision background removal blocking the main
# thread) across every take tried — not a capture artifact — so this uses the clean
# window right after the drop-zone opens rather than chasing the post-processing beat.
SRC_SAVED2=$SRC; SRC=footage/smartdrop2.mov
shot smartdrop  3.30  5.40 1400  788 770 0.05 -1
SRC=$SRC_SAVED2

ORDER="out/t01-meet out/t02-notch out/t03-music shots/music shots/lyrics out/t04-alerts shots/charging shots/unplugged shots/airpods out/t05-controls shots/controls out/t08-mac shots/system out/t07-focus shots/timer out/t06-drop shots/smartdrop out/t15-qr shots/qrread out/t09-clipboard shots/clipboard out/t14-smart-clip shots/smartclip out/t12-siri shots/siri out/t13-live shots/download shots/rain out/t10-montage out/t11-end"
echo "$ORDER" > shots/order.txt
python3 xfade-assemble.py
