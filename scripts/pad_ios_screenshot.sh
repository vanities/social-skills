#!/usr/bin/env bash
# pad_ios_screenshot.sh
#
# Pads a tall iPhone/iPad screenshot to a 4:5 aspect ratio so it survives
# Instagram's auto-crop intact. Outputs a new file; never overwrites.
#
# Usage:
#   scripts/pad_ios_screenshot.sh <input> [output] [mode]
#
# Modes (default: edge):
#   edge        Sample the screenshot's mid-height edge pixel (seamless padding).
#   blur        Apple-style: blurred + scaled-up copy of the image as background.
#   random      Pick an aesthetic color from a curated palette.
#   #RRGGBB     Solid hex color (e.g. #1A1A1A).
#
# If the input is already 4:5 or wider, the file is copied unchanged.
#
# Echoes the output path on success.

set -euo pipefail

IN="${1:?usage: $0 <input> [output] [mode]}"
DEFAULT_OUT="${IN%.*}-4x5.${IN##*.}"
OUT="${2:-$DEFAULT_OUT}"
MODE="${3:-edge}"

if ! command -v magick >/dev/null; then
  echo "magick (ImageMagick) is required: brew install imagemagick" >&2
  exit 1
fi

W=$(magick "$IN" -format "%w" info:)
H=$(magick "$IN" -format "%h" info:)

# 4:5 means width/height = 0.8. If the image is already that aspect or wider,
# no padding needed — just copy through.
if [ $((W * 5)) -ge $((H * 4)) ]; then
  cp "$IN" "$OUT"
  echo "$OUT"
  exit 0
fi

TARGET_W=$(( H * 4 / 5 ))
EXTENT="${TARGET_W}x${H}"

case "$MODE" in
  edge)
    BG=$(magick "$IN" -format "%[pixel:p{0,$((H/2))}]" info:)
    magick "$IN" -gravity center -background "$BG" -extent "$EXTENT" "$OUT"
    ;;
  blur)
    magick \
      \( "$IN" -resize "${EXTENT}^" -gravity center -extent "$EXTENT" -blur 0x40 -modulate 100,85 \) \
      "$IN" \
      -gravity center -composite \
      "$OUT"
    ;;
  random)
    PALETTE=("#1A1A1A" "#0F2C5A" "#1B3A57" "#2E1F1F" "#0B4F6C" "#3E2C41" "#1F2933" "#243949" "#2D3142" "#0F4C5C" "#5C2018" "#3D2A2A")
    BG="${PALETTE[$RANDOM % ${#PALETTE[@]}]}"
    magick "$IN" -gravity center -background "$BG" -extent "$EXTENT" "$OUT"
    ;;
  \#*)
    magick "$IN" -gravity center -background "$MODE" -extent "$EXTENT" "$OUT"
    ;;
  *)
    echo "unknown mode: $MODE (use edge|blur|random|#RRGGBB)" >&2
    exit 1
    ;;
esac

echo "$OUT"
