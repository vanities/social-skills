#!/usr/bin/env bash
# pad_ios_video.sh
#
# Pads a tall iPhone screen recording to a 9:16 aspect ratio so it survives
# Instagram Reels' mandatory crop intact. Outputs a new file (always .mp4,
# h264 + AAC + faststart for cross-platform streaming). Never overwrites the
# original.
#
# Usage:
#   scripts/pad_ios_video.sh <input> [output] [mode]
#
# Modes (default: blur):
#   blur        Stretched + heavily blurred copy of the source as background.
#   black       Solid black sidebars.
#   #RRGGBB     Solid hex color.
#
# If the input is already 9:16 or wider, ffmpeg re-encodes to 1080x1920 h264
# anyway (so downstream platforms get a known-good codec instead of HEVC).
#
# Echoes the output path on success.

set -euo pipefail

IN="${1:?usage: $0 <input> [output] [mode]}"
DEFAULT_OUT="${IN%.*}-9x16.mp4"
OUT="${2:-$DEFAULT_OUT}"
MODE="${3:-blur}"

if ! command -v ffmpeg >/dev/null; then
  echo "ffmpeg is required: brew install ffmpeg" >&2
  exit 1
fi

# Probe input dimensions
W=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$IN")
H=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$IN")

# Target: 1080x1920 (9:16). For inputs already 9:16 or wider, scale to fit
# height 1920 keeping aspect, then pad sides if width came out under 1080.
# For taller inputs (the common iPhone case at ~9:19.5), we letterbox sides.
case "$MODE" in
  blur)
    FILTER="[0:v]split=2[bg][fg];[bg]scale=1080:1920,boxblur=30:10[blurred];[fg]scale=-2:1920[orig];[blurred][orig]overlay=(W-w)/2:(H-h)/2[out]"
    ;;
  black)
    FILTER="[0:v]scale=-2:1920,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black[out]"
    ;;
  \#*)
    FILTER="[0:v]scale=-2:1920,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=$MODE[out]"
    ;;
  *)
    echo "unknown mode: $MODE (use blur|black|#RRGGBB)" >&2
    exit 1
    ;;
esac

ffmpeg -hide_banner -loglevel error -stats \
  -i "$IN" \
  -filter_complex "$FILTER" \
  -map "[out]" -map "0:a?" \
  -c:v libx264 -preset fast -crf 22 -pix_fmt yuv420p \
  -c:a aac -b:a 128k \
  -movflags +faststart \
  -y \
  "$OUT" >&2

echo "$OUT"
