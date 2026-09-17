#!/bin/bash
# Builds the promo's final audio using the user's REAL TTSMaker voice-over
# (adjusted for timing/loudness/tone) and a real downloaded music bed, and
# muxes the result onto the video.
# Music: "Small Joys" by Aventure (Bensound), free license with attribution.
#   Attribution to include in the video description when posting:
#   Music by: Bensound  |  Artist: Aventure  |  License code: LVY3L0Z26PP8WH5M
# Voice-over: the user's own TTSMaker recording, split into its 14 lines and
#   placed on the exact same cut points as the original scripted timing.
set -euo pipefail
cd "$(dirname "$0")"
VIDEO="final/Halo-Promo-1080p60.mp4"
OUT="final/Halo-Promo-1080p60-RealVO.mp4"
LEN=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO")
cd audio

# --- Music: trim the downloaded track to the video length, fade in/out ---
ffmpeg -y -loglevel error -i bensound-smalljoys.mp3 -t "$LEN" \
  -af "afade=t=in:st=0:d=1.5,afade=t=out:st=$(python3 -c "print(${LEN}-3.5)"):d=3.5,volume=0.5,alimiter=limit=0.95:attack=5:release=50" \
  -ar 44100 -ac 2 music_bed_real.wav

# --- Voice-over: place each real line at its matching cut point ---
python3 - "$LEN" <<'PYEOF'
import subprocess, sys
VIDEO_LEN = float(sys.argv[1])
starts = [3.0, 13.3, 17.3, 28.0, 34.3, 40.2, 46.1, 52.5, 59.0, 65.8, 71.5, 78.5, 89.3, 93.3]
inputs, filters, labels = [], [], []
for i, start in enumerate(starts):
    fname = f"vo_real/line{i:02d}.wav"
    inputs += ["-i", fname]
    ms = int(round(start * 1000))
    filters.append(f"[{i}:a]aformat=sample_rates=44100:channel_layouts=stereo,adelay={ms}|{ms}[v{i}]")
    labels.append(f"[v{i}]")
filters.append("".join(labels) + f"amix=inputs={len(starts)}:duration=longest:normalize=0[voall]")
filters.append(f"[voall]apad,atrim=0:{VIDEO_LEN},volume=1.6,alimiter=limit=0.92:attack=3:release=40[vo]")
subprocess.run(["ffmpeg", "-y", "-loglevel", "error"] + inputs +
               ["-filter_complex", ";".join(filters), "-map", "[vo]", "-ar", "44100", "-ac", "2", "vo_track_real.wav"],
               check=True)
PYEOF

# --- Duck the music under the narration and mix ---
ffmpeg -y -loglevel error -i music_bed_real.wav -i vo_track_real.wav \
  -filter_complex "[0:a][1:a]sidechaincompress=threshold=0.04:ratio=10:attack=40:release=500:makeup=1[ducked];[ducked][1:a]amix=inputs=2:duration=first:weights=1 1.15,alimiter=limit=0.95:attack=3:release=50[mix]" \
  -map "[mix]" -ar 44100 -ac 2 final_mix_real.wav

cd ..
ffmpeg -y -loglevel error -i "$VIDEO" -i audio/final_mix_real.wav \
  -filter_complex "[1:a]apad[a]" -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -shortest "$OUT"
echo "done: $OUT"
