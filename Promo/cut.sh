#!/bin/bash
# Cuts the Halo promo: footage shots framed on the island with a slow push-in, between
# the kinetic title cards. Output: final/Halo-Promo-1080p60.mp4
set -euo pipefail
cd "$(dirname "$0")"
SRC=footage/tour.mov
mkdir -p final shots
# Hides macOS's purple screen-recording indicator in the menu bar (source pixels).
PILL="drawbox=x=1726:y=4:w=96:h=58:color=0x311745:t=fill"

# shot name start end cropWidth cropHeight zoom pillUntil(seconds into shot; -1 none, 999 whole)
shot() {
  local name=$1 start=$2 end=$3 cw=$4 ch=$5 zoom=$6 pill=$7
  local d; d=$(echo "$end - $start" | bc)
  local cover="null"
  if [ "$pill" != "-1" ]; then cover="$PILL:enable='lt(t,$pill)'"; fi
  ffmpeg -loglevel error -y -ss "$start" -t "$d" -i "$SRC" -filter_complex \
    "[0:v]setpts=PTS-STARTPTS,fps=60,$cover,crop=$cw:$ch:1470-$cw/2:0,scale=3840:2160:flags=lanczos,zoompan=z='1+$zoom*on/($d*60)':x='iw/2-iw/zoom/2':y=0:d=1:s=1920x1080:fps=60,fade=t=in:st=0:d=0.12,format=yuv420p[v]" \
    -map "[v]" -an -c:v libx264 -preset slow -crf 14 "shots/$name.mp4"
  echo "shot $name ($d s)"
}

# band name start end pillUntil: a close-up of the menu bar around the notch, enlarged over a gradient.
band() {
  local name=$1 start=$2 end=$3 pill=$4
  local d; d=$(echo "$end - $start" | bc)
  local cover="null"
  if [ "$pill" != "-1" ]; then cover="$PILL:enable='lt(t,$pill)'"; fi
  ffmpeg -loglevel error -y -ss "$start" -t "$d" -i "$SRC2" -filter_complex \
    "[0:v]setpts=PTS-STARTPTS,fps=60,$cover,crop=1100:86:920:0,split[a][b];[a]scale=1920:1080:flags=bilinear,boxblur=60:4,eq=brightness=0.04:saturation=1.7[bg];[b]scale=1920:150:flags=lanczos[band];[bg][band]overlay=0:465,fade=t=in:st=0:d=0.12,format=yuv420p[v]" \
    -map "[v]" -an -t "$d" -c:v libx264 -preset slow -crf 14 "shots/$name.mp4"
  echo "band $name ($d s)"
}

SRC2=footage/tour2.mov
SRC_SAVED=$SRC; SRC=$SRC2
shot siri       2.60  7.20 1000  562 0.04 999
SRC=$SRC_SAVED
band download   9.70 15.80 3.7
band rain      16.20 18.90 -1

shot music      1.60  6.70 1400  788 0.05 1.15
shot lyrics    40.10 43.80 1400  788 0.04 -1
shot charging   8.85 11.90 1000  562 0.03 -1
shot unplugged 12.45 14.90 1000  562 0.03 -1
shot airpods   16.30 18.80 1000  562 0.03 -1
shot controls  23.20 27.10 1400  788 0.05 -1
shot system    31.90 35.80 1400  788 0.04 -1
shot timer     35.95 39.80 1400  788 0.04 -1
shot smartdrop 46.15 49.90 1400  788 0.05 -1
shot clipboard 54.30 58.70 2000 1125 0.04 999

# Smart Clipboard: the phone-number row and its Call action, cut from tour3.mov.
SRC3=footage/tour3.mov
SRC_SAVED2=$SRC; SRC=$SRC3
shot smartclip 2.60 6.10 2000 1125 0.02 999
SRC=$SRC_SAVED2

# Smart Drop's QR reading, recorded on its own (a clean, un-broken take).
SRC4=footage/qrsolo.mov
SRC_SAVED3=$SRC; SRC=$SRC4
shot qrread 0.90 5.60 1400 788 0.05 -1
SRC=$SRC_SAVED3

ORDER="out/t01-meet out/t02-notch out/t03-music shots/music shots/lyrics out/t04-alerts shots/charging shots/unplugged shots/airpods out/t05-controls shots/controls out/t08-mac shots/system out/t07-focus shots/timer out/t06-drop shots/smartdrop out/t15-qr shots/qrread out/t09-clipboard shots/clipboard out/t14-smart-clip shots/smartclip out/t12-siri shots/siri out/t13-live shots/download shots/rain out/t10-montage out/t11-end"
: > shots/list.txt
for clip in $ORDER; do echo "file '$PWD/$clip.mp4'" >> shots/list.txt; done
ffmpeg -loglevel error -y -f concat -safe 0 -i shots/list.txt -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -r 60 \
  -movflags +faststart final/Halo-Promo-1080p60.mp4
ffprobe -v error -show_entries format=duration -of csv=p=0 final/Halo-Promo-1080p60.mp4
