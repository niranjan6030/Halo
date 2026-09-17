#!/bin/bash
# Builds the promo's music and voice-over, and muxes them onto the video from cut.sh.
# Music: 10 stems from one Apple Loop song ("Longing", Apple's Hip Hop pack) — free to
#   use in a finished video under Apple's loop license, since the loops themselves aren't
#   redistributed on their own. Brought in gradually, like a real film score.
# Voice-over: macOS's own Samantha voice (`say`), so it's free to use and needs no
#   internet. Each line is timed to the exact cut points from cut.sh.
set -euo pipefail
cd "$(dirname "$0")"
VIDEO="final/Halo-Promo-1080p60.mp4"
OUT="final/Halo-Promo-1080p60-Audio.mp4"
LEN=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO")
mkdir -p audio/vo
cd audio

# --- Music: decode the loop stems once ---
if [ ! -f raw_bass.wav ]; then
  SRC="/Library/Audio/Apple Loops/Apple/01 Hip Hop"
  for stem in "Bass" "Beat" "Electric Piano" "Guitar" "Pad" "Piano" "Strings 01" "Strings 02" "Synth 01" "Synth 02"; do
    out=$(echo "$stem" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
    ffmpeg -y -loglevel error -i "$SRC/Longing $stem.caf" -ar 44100 -ac 2 "raw_$out.wav"
  done
fi

python3 - "$LEN" <<'PYEOF'
import subprocess, sys
VIDEO_LEN = float(sys.argv[1])
stems = [
    ("piano", 0.55, 0.0, 0.3), ("pad", 0.42, 0.0, 0.3), ("bass", 0.60, 9.5, 2.0),
    ("electric_piano", 0.40, 27.0, 2.0), ("beat", 0.65, 33.5, 2.0), ("synth_01", 0.38, 58.0, 2.0),
    ("guitar", 0.35, 65.0, 2.0), ("strings_01", 0.32, 71.0, 2.5), ("strings_02", 0.30, 86.0, 2.5),
    ("synth_02", 0.34, 89.0, 2.0),
]
inputs, filters, labels = [], [], []
for i, (name, vol, fstart, fdur) in enumerate(stems):
    inputs += ["-stream_loop", "-1", "-i", f"raw_{name}.wav"]
    f = f"[{i}:a]atrim=0:100,asetpts=PTS-STARTPTS,volume={vol},afade=t=in:st={fstart}:d={fdur}[s{i}]"
    filters.append(f); labels.append(f"[s{i}]")
filters.append("".join(labels) + f"amix=inputs={len(stems)}:duration=longest:normalize=0[bed0]")
filters.append(f"[bed0]afade=t=in:st=0:d=1.0,afade=t=out:st={VIDEO_LEN-3.2}:d=3.2,atrim=0:{VIDEO_LEN},"
               f"volume=0.55,alimiter=limit=0.95:attack=5:release=50[bed]")
subprocess.run(["ffmpeg", "-y", "-loglevel", "error"] + inputs +
               ["-filter_complex", ";".join(filters), "-map", "[bed]", "-ar", "44100", "-ac", "2", "music_bed_safe.wav"],
               check=True)
PYEOF

# --- Voice-over: one line per cut, timed to land exactly on it ---
python3 - "$LEN" <<'PYEOF'
import subprocess, sys, json
VIDEO_LEN = float(sys.argv[1])
lines = [
    (3.0, 12.0, "Your notch was always there. Now it finally does something."),
    (13.3, 16.8, "Lyrics, right as they play."),
    (17.3, 26.8, "Every alert — charging, AirPods, anything — shown small, and beautifully."),
    (28.0, 33.5, "Control Center, without ever leaving the notch."),
    (34.3, 39.5, "C P U, memory, battery — know your Mac at a glance."),
    (40.2, 45.6, "Start a focus timer, and actually stay in it."),
    (46.1, 52.0, "Drop a photo. Halo lifts the subject right out."),
    (52.5, 58.3, "Scan a Q R code — copied and opened, instantly."),
    (59.0, 65.2, "Everything you copy, one shortcut away."),
    (65.8, 71.0, "A phone number, an address — Halo just knows."),
    (71.5, 77.8, "Even Siri, right there in the notch."),
    (78.5, 86.0, "Downloads in real time. Rain, before it starts."),
    (89.3, 92.5, "So much more, built right in."),
    (93.3, 97.1, "Halo. A Dynamic Island, for your Mac."),
]
inputs, filters, labels = [], [], []
for i, (start, deadline, text) in enumerate(lines):
    fname = f"vo/line{i:02d}.aiff"
    rate = 168
    for _ in range(6):
        subprocess.run(["say", "-v", "Samantha", "-r", str(rate), "-o", fname, text], check=True)
        dur = float(subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0", fname],
                                    capture_output=True, text=True).stdout.strip())
        if dur <= (deadline - start) - 0.15 or rate >= 230:
            break
        rate += 12
    inputs += ["-i", fname]
    ms = int(round(start * 1000))
    filters.append(f"[{i}:a]aformat=sample_rates=44100:channel_layouts=stereo,adelay={ms}|{ms}[v{i}]")
    labels.append(f"[v{i}]")
filters.append("".join(labels) + f"amix=inputs={len(lines)}:duration=longest:normalize=0[voall]")
filters.append(f"[voall]apad,atrim=0:{VIDEO_LEN},volume=0.9,alimiter=limit=0.9:attack=3:release=40[vo]")
subprocess.run(["ffmpeg", "-y", "-loglevel", "error"] + inputs +
               ["-filter_complex", ";".join(filters), "-map", "[vo]", "-ar", "44100", "-ac", "2", "vo_track_safe.wav"],
               check=True)
PYEOF

# --- Duck the music under the narration and mix ---
ffmpeg -y -loglevel error -i music_bed_safe.wav -i vo_track_safe.wav \
  -filter_complex "[0:a][1:a]sidechaincompress=threshold=0.04:ratio=10:attack=40:release=500:makeup=1[ducked];[ducked][1:a]amix=inputs=2:duration=first:weights=1 1.15,alimiter=limit=0.95:attack=3:release=50[mix]" \
  -map "[mix]" -ar 44100 -ac 2 final_mix.wav

cd ..
ffmpeg -y -loglevel error -i "$VIDEO" -i audio/final_mix.wav \
  -filter_complex "[1:a]apad[a]" -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -shortest "$OUT"
echo "done: $OUT"
