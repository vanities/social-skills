#!/usr/bin/env bash
# ascii_devotional_video.sh
#
# Builds a short 9:16 MP4 from a daily-devotional screenshot with an animated
# terminal-style ASCII background. Use as an occasional ASCII-inspired video media
# variant for Instagram Reels / X / Pinterest video pins.
#
# Usage:
#   scripts/ascii_devotional_video.sh <screenshot.png> [output.mp4] [theme] [reference]
#
# Output is h264 + AAC + faststart, 1080x1920, with silent audio so social
# platforms treat the file as a normal video upload.

set -euo pipefail

IN="${1:?usage: $0 <screenshot.png> [output.mp4] [theme] [reference]}"
OUT="${2:-}"
THEME="${3:-daily devotional}"
REFERENCE="${4:-}"
DURATION="${ASCII_DEVOTIONAL_DURATION:-7}"
FPS="${ASCII_DEVOTIONAL_FPS:-30}"
FRAME_RATE="${ASCII_DEVOTIONAL_ASCII_FPS:-2}"   # random ASCII texture changes/sec

if [[ -z "$OUT" ]]; then
  OUT="${IN%.*}-ascii-9x16.mp4"
fi

if ! command -v ffmpeg >/dev/null; then
  echo "ffmpeg is required: brew install ffmpeg" >&2
  exit 1
fi
if ! command -v magick >/dev/null; then
  echo "magick (ImageMagick) is required: brew install imagemagick" >&2
  exit 1
fi
if ! command -v rsvg-convert >/dev/null; then
  echo "rsvg-convert is required for reliable SVG text rendering: brew install librsvg" >&2
  exit 1
fi

test -f "$IN" || { echo "input screenshot missing: $IN" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

TARGET_W=1080
TARGET_H=1920
FG_H=1720
FG="$TMP/foreground.png"
magick "$IN" -resize "x${FG_H}" "$FG"
FG_W=$(magick "$FG" -format "%w" info:)
FG_H_ACTUAL=$(magick "$FG" -format "%h" info:)
FG_X=$(( (TARGET_W - FG_W) / 2 ))
FG_Y=$(( (TARGET_H - FG_H_ACTUAL) / 2 ))
FRAME_COUNT=$(( DURATION * FRAME_RATE ))
[[ "$FRAME_COUNT" -lt 1 ]] && FRAME_COUNT=1

rand_in() {
  local min=$1 max=$2
  if (( max < min )); then max=$min; fi
  echo $(( min + RANDOM % (max - min + 1) ))
}

pick() {
  local arr=("$@")
  echo "${arr[$RANDOM % ${#arr[@]}]}"
}

rand_opacity() { printf "0.%02d" $((18 + RANDOM % 52)); }

xml_escape() {
  local s=$1
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//>/&gt;}
  printf '%s' "$s"
}

svg_text() {
  local x=$1 y=$2 size=$3 color=$4 opacity=$5 text=$6
  cat >> "$TMP/dec.svg" <<EOF
<text x="$x" y="$y" font-family="Menlo,Monaco,'SF Mono','Courier New',monospace" font-size="$size" fill="$color" opacity="$opacity" text-anchor="middle">$text</text>
EOF
}

make_frame() {
  local idx=$1
  local bg="$TMP/bg-${idx}.png"
  local dec="$TMP/dec-${idx}.png"
  local frame
  frame=$(printf "%s/frame-%03d.png" "$TMP" "$idx")

  magick -size "${TARGET_W}x${TARGET_H}" "radial-gradient:#06301F-#020504" "$bg"

  cat > "$TMP/dec.svg" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<svg width="$TARGET_W" height="$TARGET_H" xmlns="http://www.w3.org/2000/svg">
<defs>
<filter id="glow" x="-100%" y="-100%" width="300%" height="300%">
  <feGaussianBlur stdDeviation="2.2"/>
  <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>
</defs>
EOF

  local glyphs=("+" "|" "-" "." ":" "*" "†" "✦" "░" "▒" "▓" "0" "1")
  local colors=("#00FF99" "#9CFFD2" "#E8FFF4" "#3CFFB0")
  local words=("FAITH" "GRACE" "HOPE" "MERCY" "AMEN" "LIGHT" "WORD" "PRAY" "PEACE" "TRUTH")
  [[ -n "$REFERENCE" ]] && words+=("$(xml_escape "$REFERENCE")")
  [[ -n "$THEME" ]] && words+=("$(xml_escape "$THEME")")

  # Dense small glyphs across the whole canvas. The screenshot overlay hides the
  # center, leaving animated terminal texture in the side/top/bottom margins.
  for ((i = 0; i < 360; i++)); do
    svg_text "$(rand_in 10 $((TARGET_W - 10)))" "$(rand_in 20 $((TARGET_H - 20)))" \
      "$(rand_in 14 34)" "$(pick "${colors[@]}")" "$(rand_opacity)" "$(pick "${glyphs[@]}")"
  done

  for ((i = 0; i < 34; i++)); do
    svg_text "$(rand_in 40 $((TARGET_W - 40)))" "$(rand_in 80 $((TARGET_H - 80)))" \
      "$(rand_in 18 34)" "$(pick "${colors[@]}")" "0.$((24 + RANDOM % 38))" "$(pick "${words[@]}")"
  done

  cat >> "$TMP/dec.svg" <<EOF
</svg>
EOF
  rsvg-convert "$TMP/dec.svg" -o "$dec"

  magick "$bg" "$dec" -compose screen -composite \
    "$FG" -compose over -gravity center -composite \
    -stroke 'rgba(156,255,210,0.22)' -strokewidth 4 -fill none \
    -draw "roundrectangle $((FG_X - 10)),$((FG_Y - 10)),$((FG_X + FG_W + 10)),$((FG_Y + FG_H_ACTUAL + 10)),20,20" \
    "$frame"
}

for ((idx = 0; idx < FRAME_COUNT; idx++)); do
  make_frame "$idx"
done

ffmpeg -hide_banner -loglevel error -stats \
  -framerate "$FRAME_RATE" -i "$TMP/frame-%03d.png" \
  -f lavfi -t "$DURATION" -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -vf "fps=${FPS},format=yuv420p" \
  -map 0:v -map 1:a -shortest \
  -c:v libx264 -preset fast -crf 22 -pix_fmt yuv420p \
  -c:a aac -b:a 96k \
  -movflags +faststart \
  -y "$OUT" >&2

echo "$OUT"
