#!/usr/bin/env bash
# pad_ios_screenshot.sh
#
# Pads a tall iPhone/iPad screenshot to a 4:5 aspect ratio so it survives
# Instagram's auto-crop intact. Outputs a new file; never overwrites.
#
# Usage:
#   scripts/pad_ios_screenshot.sh <input> [output] [mode]
#
# Plain modes (deterministic, fast):
#   edge        Sample the screenshot's mid-height edge pixel (seamless padding).
#   blur        Apple-style: blurred + scaled-up copy of the image as background.
#   random      Pick an aesthetic dark color from a curated palette.
#   #RRGGBB     Solid hex color (e.g. #1A1A1A).
#
# Fancy modes (random gradient bg + SVG decoration layer):
#   gradient    Random radial color gradient — clean, no decorations.
#   bloom       Dimmed blurred-image bg + scattered sparkles + soft glow orbs.
#   sparkle     Deep-night gradient + lots of sparkles + 5-point stars.
#   cosmic      Deep blue/violet gradient + many stars + sparkles + nebula orbs.
#   divine      Golden gradient + Latin crosses + sparkles + a scripture word.
#   holy        Like divine, plus a stylized Bible + flying-dove silhouettes.
#   lovely      Pink/red gradient + hearts + sparkles + a tender word.
#   dream       Dimmed blur bg + faded scripture words + sparkles.
#
# Smart mode:
#   surprise    Picks one of the fancy modes at random. Logs the pick to stderr.
#
# If the input is already 4:5 or wider, the file is copied unchanged.
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

# 4:5 means width/height = 0.8. If already that aspect or wider, copy through.
if [ $((W * 5)) -ge $((H * 4)) ]; then
  cp "$IN" "$OUT"
  echo "$OUT"
  exit 0
fi

TARGET_W=$(( H * 4 / 5 ))
PAD=$(( (TARGET_W - W) / 2 ))
EXTENT="${TARGET_W}x${H}"

# Resolve `surprise` to a real fancy mode.
SURPRISE_POOL=(gradient bloom sparkle cosmic divine holy lovely dream)
if [ "$MODE" = "surprise" ]; then
  MODE="${SURPRISE_POOL[$RANDOM % ${#SURPRISE_POOL[@]}]}"
  echo "[pad] surprise → $MODE" >&2
fi

# ---------- helpers ----------

rand_in() {
  local min=$1 max=$2
  if (( max < min )); then max=$min; fi
  echo $(( min + RANDOM % (max - min + 1) ))
}

# Random x within the LEFT or RIGHT padding strip so decorations
# don't trample the screenshot. Falls back to the full canvas if PAD is tiny.
rand_pad_x() {
  if (( PAD < 60 )); then
    rand_in 0 $((TARGET_W - 1))
  elif (( RANDOM % 2 )); then
    rand_in 10 $((PAD - 20))
  else
    rand_in $((PAD + W + 20)) $((TARGET_W - 10))
  fi
}

# Opacity 0.30..0.85 formatted as "0.XX"
rand_opacity()      { printf "0.%02d" $((30 + RANDOM % 56)); }
# Higher-visibility opacity 0.55..0.95
rand_opacity_high() { printf "0.%02d" $((55 + RANDOM % 41)); }

# Pick a random element from the args list.
pick() {
  local arr=("$@")
  echo "${arr[$RANDOM % ${#arr[@]}]}"
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------- backgrounds (write to $TMP/bg.png) ----------

bg_solid()   { magick -size "$EXTENT" "xc:$1" "$TMP/bg.png"; }

bg_edge() {
  local c
  c=$(magick "$IN" -format "%[pixel:p{0,$((H/2))}]" info:)
  bg_solid "$c"
}

# Apple-style blurred-image bg, with optional dim/desaturate.
bg_blur() {
  local mod_b=${1:-100}
  local mod_s=${2:-85}
  magick "$IN" -resize "${EXTENT}^" -gravity center -extent "$EXTENT" \
    -blur 0x40 -modulate "${mod_b},${mod_s}" "$TMP/bg.png"
}

bg_radial() {
  magick -size "$EXTENT" "radial-gradient:${1}-${2}" "$TMP/bg.png"
}

# ---------- decorations (write to $TMP/dec.png via SVG) ----------

svg_init() {
  cat > "$TMP/dec.svg" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<svg width="$TARGET_W" height="$H" xmlns="http://www.w3.org/2000/svg">
<defs>
<filter id="glow" x="-100%" y="-100%" width="300%" height="300%">
  <feGaussianBlur stdDeviation="2.5"/>
  <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>
<filter id="bigglow" x="-200%" y="-200%" width="500%" height="500%">
  <feGaussianBlur stdDeviation="22"/>
</filter>
</defs>
EOF
}

svg_done() {
  echo '</svg>' >> "$TMP/dec.svg"
  # Prefer rsvg-convert: ImageMagick's SVG path can't resolve fontconfig fonts
  # on macOS, so any <text> element makes magick error out. rsvg-convert uses
  # fontconfig directly and renders Georgia/serif/etc. fine.
  if command -v rsvg-convert >/dev/null; then
    rsvg-convert "$TMP/dec.svg" -o "$TMP/dec.png"
  else
    magick -background none "$TMP/dec.svg" "$TMP/dec.png"
  fi
}

# 4-point twinkle sparkle — two thin diamonds + a white core dot.
svg_sparkle() {
  local cx=$1 cy=$2 size=$3 color=$4 opacity=$5
  local thick=$((size / 5 + 1))
  cat >> "$TMP/dec.svg" <<EOF
<g opacity="$opacity" filter="url(#glow)" transform="translate($cx,$cy)">
  <polygon points="0,-$size $thick,0 0,$size -$thick,0" fill="$color"/>
  <polygon points="-$size,0 0,-$thick $size,0 0,$thick" fill="$color"/>
  <circle cx="0" cy="0" r="$thick" fill="white"/>
</g>
EOF
}

# 5-point star (unit polygon scaled by r).
svg_star() {
  local cx=$1 cy=$2 r=$3 color=$4 opacity=$5
  cat >> "$TMP/dec.svg" <<EOF
<g opacity="$opacity" filter="url(#glow)" transform="translate($cx,$cy)">
  <polygon transform="scale($r)" points="0,-1 0.225,-0.309 0.951,-0.309 0.363,0.118 0.588,0.809 0,0.382 -0.588,0.809 -0.363,0.118 -0.951,-0.309 -0.225,-0.309" fill="$color"/>
</g>
EOF
}

# Latin cross (taller below the crossbar).
svg_cross() {
  local cx=$1 cy=$2 size=$3 color=$4 opacity=$5
  local thick=$((size / 6 + 1))
  local top=$size
  local bot=$((size + size / 3))
  local arm=$((size * 2 / 3))
  local cross_y=$((-size / 3))
  cat >> "$TMP/dec.svg" <<EOF
<g opacity="$opacity" filter="url(#glow)" transform="translate($cx,$cy)">
  <rect x="-$thick" y="-$top" width="$((thick*2))" height="$((top+bot))" fill="$color" rx="2"/>
  <rect x="-$arm" y="$((cross_y-thick))" width="$((arm*2))" height="$((thick*2))" fill="$color" rx="2"/>
</g>
EOF
}

# Heart (cubic Bezier path).
svg_heart() {
  local cx=$1 cy=$2 size=$3 color=$4 opacity=$5
  local s=$size
  cat >> "$TMP/dec.svg" <<EOF
<g opacity="$opacity" filter="url(#glow)" transform="translate($cx,$cy)">
  <path d="M 0,$((s/3)) C 0,-$((s/2)) -$s,-$((s/2)) -$s,$((s/4)) C -$s,$((s*3/4)) 0,$s 0,$((s+s/4)) C 0,$s $s,$((s*3/4)) $s,$((s/4)) C $s,-$((s/2)) 0,-$((s/2)) 0,$((s/3)) Z" fill="$color"/>
</g>
EOF
}

# Stylized closed Bible: rectangle + dark spine + golden cross on the cover.
svg_bible() {
  local cx=$1 cy=$2 size=$3 color=$4 opacity=$5
  local w=$size
  local h=$((size * 5 / 4))
  local cw=$((w / 7 + 1))
  local ch=$((h / 2))
  cat >> "$TMP/dec.svg" <<EOF
<g opacity="$opacity" filter="url(#glow)" transform="translate($cx,$cy)">
  <rect x="-$((w/2))" y="-$((h/2))" width="$w" height="$h" fill="$color" rx="3"/>
  <rect x="-$((w/2))" y="-$((h/2))" width="$((w/10+1))" height="$h" fill="black" opacity="0.45"/>
  <rect x="-$((cw/2))" y="-$((ch/2 + h/12))" width="$cw" height="$ch" fill="#FFD700"/>
  <rect x="-$((w/4))" y="-$((h/14))" width="$((w/2))" height="$((h/14+1))" fill="#FFD700"/>
</g>
EOF
}

# Distant flying-bird silhouette: a wide M-curve (the Hallmark "dove" shape).
svg_bird() {
  local cx=$1 cy=$2 size=$3 color=$4 opacity=$5
  local s=$size
  local sw=$((s / 8 + 2))
  cat >> "$TMP/dec.svg" <<EOF
<path d="M $((cx-s)),$cy Q $((cx-s/2)),$((cy-s/2)) $cx,$cy Q $((cx+s/2)),$((cy-s/2)) $((cx+s)),$cy" fill="none" stroke="$color" stroke-width="$sw" stroke-linecap="round" opacity="$opacity" filter="url(#glow)"/>
EOF
}

# Italic word (rotated). Word must be safe XML (no & < >).
svg_word() {
  local cx=$1 cy=$2 size=$3 color=$4 opacity=$5 rot=$6 word=$7
  cat >> "$TMP/dec.svg" <<EOF
<text x="$cx" y="$cy" font-family="Georgia,Palatino,serif" font-style="italic" font-size="$size" fill="$color" opacity="$opacity" text-anchor="middle" transform="rotate($rot $cx $cy)">$word</text>
EOF
}

# Big soft glow orb — light leak / lens flare feel.
svg_orb() {
  local cx=$1 cy=$2 r=$3 color=$4 opacity=$5
  cat >> "$TMP/dec.svg" <<EOF
<circle cx="$cx" cy="$cy" r="$r" fill="$color" opacity="$opacity" filter="url(#bigglow)"/>
EOF
}

# ---------- bulk decorators ----------

decorate_sparkles() {
  local count=$1; shift
  local colors=("$@")
  for ((i = 0; i < count; i++)); do
    svg_sparkle "$(rand_pad_x)" "$(rand_in 30 $((H - 30)))" \
      "$(rand_in 8 28)" "$(pick "${colors[@]}")" "$(rand_opacity)"
  done
}

decorate_stars() {
  local count=$1; shift
  local colors=("$@")
  for ((i = 0; i < count; i++)); do
    svg_star "$(rand_pad_x)" "$(rand_in 30 $((H - 30)))" \
      "$(rand_in 5 14)" "$(pick "${colors[@]}")" "$(rand_opacity)"
  done
}

decorate_crosses() {
  local count=$1; shift
  local colors=("$@")
  for ((i = 0; i < count; i++)); do
    svg_cross "$(rand_pad_x)" "$(rand_in 120 $((H - 120)))" \
      "$(rand_in 28 70)" "$(pick "${colors[@]}")" "$(rand_opacity_high)"
  done
}

decorate_hearts() {
  local count=$1; shift
  local colors=("$@")
  for ((i = 0; i < count; i++)); do
    svg_heart "$(rand_pad_x)" "$(rand_in 60 $((H - 60)))" \
      "$(rand_in 14 32)" "$(pick "${colors[@]}")" "$(rand_opacity)"
  done
}

decorate_bibles() {
  local count=$1; shift
  local colors=("$@")
  for ((i = 0; i < count; i++)); do
    svg_bible "$(rand_pad_x)" "$(rand_in 150 $((H - 150)))" \
      "$(rand_in 36 72)" "$(pick "${colors[@]}")" "$(rand_opacity_high)"
  done
}

decorate_birds() {
  local count=$1; shift
  local colors=("$@")
  for ((i = 0; i < count; i++)); do
    svg_bird "$(rand_pad_x)" "$(rand_in 80 $((H - 200)))" \
      "$(rand_in 18 48)" "$(pick "${colors[@]}")" "$(rand_opacity_high)"
  done
}

decorate_words() {
  local count=$1
  local words_csv=$2
  shift 2
  local colors=("$@")
  IFS=',' read -ra WORDS <<< "$words_csv"
  for ((i = 0; i < count; i++)); do
    local word="${WORDS[$RANDOM % ${#WORDS[@]}]}"
    local rot
    rot=$(rand_in 0 25); ((RANDOM % 2)) && rot=$((-rot))
    svg_word "$(rand_pad_x)" "$(rand_in 220 $((H - 220)))" \
      "$(rand_in 38 88)" "$(pick "${colors[@]}")" "$(rand_opacity)" "$rot" "$word"
  done
}

decorate_orbs() {
  local count=$1; shift
  local colors=("$@")
  for ((i = 0; i < count; i++)); do
    svg_orb "$(rand_pad_x)" "$(rand_in 100 $((H - 100)))" \
      "$(rand_in 90 220)" "$(pick "${colors[@]}")" "$(rand_opacity)"
  done
}

# ---------- mode dispatch (basics first, exit early) ----------

case "$MODE" in
  edge)
    BG=$(magick "$IN" -format "%[pixel:p{0,$((H/2))}]" info:)
    magick "$IN" -gravity center -background "$BG" -extent "$EXTENT" "$OUT"
    echo "$OUT"; exit 0
    ;;
  blur)
    magick \
      \( "$IN" -resize "${EXTENT}^" -gravity center -extent "$EXTENT" -blur 0x40 -modulate 100,85 \) \
      "$IN" \
      -gravity center -composite \
      "$OUT"
    echo "$OUT"; exit 0
    ;;
  random)
    PALETTE=("#1A1A1A" "#0F2C5A" "#1B3A57" "#2E1F1F" "#0B4F6C" "#3E2C41" "#1F2933" "#243949" "#2D3142" "#0F4C5C" "#5C2018" "#3D2A2A")
    BG=$(pick "${PALETTE[@]}")
    magick "$IN" -gravity center -background "$BG" -extent "$EXTENT" "$OUT"
    echo "$OUT"; exit 0
    ;;
  \#*)
    magick "$IN" -gravity center -background "$MODE" -extent "$EXTENT" "$OUT"
    echo "$OUT"; exit 0
    ;;
esac

# ---------- fancy modes: bg + decorations + composite ----------

case "$MODE" in
  gradient)
    PAIRS=("#1B3A57:#5C2018" "#0F4C5C:#1A1A1A" "#3E2C41:#0B4F6C" "#5A1E3B:#1A0A14" "#3D2E0F:#0A0A0A" "#1B2845:#0A0A18" "#2E1F4F:#0F2C5A" "#5C2018:#0F4C5C" "#1F2933:#3E2C41")
    P=$(pick "${PAIRS[@]}")
    bg_radial "${P%:*}" "${P#*:}"
    svg_init; svg_done
    ;;
  bloom)
    bg_blur 75 60
    svg_init
    decorate_sparkles 35 "#FFFFFF" "#FFFAE0" "#FFD700"
    decorate_orbs 2 "#FFFFE0" "#FFEEAA" "#FFD27F"
    svg_done
    ;;
  sparkle)
    bg_radial "#1B2845" "#0A0A18"
    svg_init
    decorate_sparkles 65 "#FFFFFF" "#FFFAE0" "#FFEC8B" "#E0F0FF"
    decorate_stars 25 "#FFFFFF" "#A0C8FF"
    svg_done
    ;;
  cosmic)
    bg_radial "#1B2845" "#0A0A18"
    svg_init
    decorate_stars 45 "#FFFFFF" "#A0C8FF" "#E0F0FF"
    decorate_sparkles 30 "#FFFFFF" "#A0C8FF" "#FFFAE0"
    decorate_orbs 2 "#3050A0" "#502080" "#1B3A8C"
    svg_done
    ;;
  divine)
    bg_radial "#3D2E0F" "#0A0A0A"
    svg_init
    decorate_crosses 8 "#FFD700" "#FFC107" "#F8F0D0"
    decorate_sparkles 40 "#FFFFFF" "#FFD700" "#FFEC8B"
    decorate_words 2 "grace,faith,amen,blessed,hope,glory,praise,mercy" "#F5DEB3" "#FFFFFF"
    decorate_orbs 1 "#FFD700" "#FFEEAA"
    svg_done
    ;;
  holy)
    bg_radial "#3D2E0F" "#0A0A0A"
    svg_init
    decorate_birds 3 "#FFFFFF" "#F8F0D0"
    decorate_crosses 7 "#FFD700" "#FFC107" "#F8F0D0"
    decorate_bibles 2 "#5C2018" "#3E2723" "#7B1F1F"
    decorate_sparkles 35 "#FFFFFF" "#FFD700"
    decorate_words 2 "amen,blessed,grace,hosanna,hallelujah" "#FFD700" "#F5DEB3"
    decorate_orbs 1 "#FFD700"
    svg_done
    ;;
  lovely)
    bg_radial "#5A1E3B" "#1A0A14"
    svg_init
    decorate_hearts 18 "#FF4081" "#E91E63" "#FFB6C1" "#FFFFFF"
    decorate_sparkles 25 "#FFFFFF" "#FFB6C1" "#FFD700"
    decorate_words 2 "love,grace,joy,blessed,heart,faith,beloved" "#FFFFFF" "#FFB6C1"
    svg_done
    ;;
  mother)
    bg_radial "#6B1F3F" "#1F0810"
    svg_init
    decorate_hearts 22 "#FF4081" "#E91E63" "#FFB6C1" "#FFC1CC" "#FFFFFF"
    decorate_words 4 "mom,mama,mother,love,grace,blessed,beloved,nurturing,tender,thank you" "#FFFFFF" "#FFB6C1" "#FFD700"
    decorate_sparkles 22 "#FFFFFF" "#FFB6C1" "#FFD700"
    svg_done
    ;;
  dream)
    bg_blur 70 65
    svg_init
    decorate_words 4 "grace,faith,love,amen,blessed,shalom,prayer,hope,mercy,glory,rejoice,trust,light" "#FFFFFF" "#F5DEB3"
    decorate_sparkles 28 "#FFFFFF" "#FFFAE0"
    svg_done
    ;;
  *)
    echo "unknown mode: $MODE (use edge|blur|random|gradient|bloom|sparkle|cosmic|divine|holy|lovely|mother|dream|surprise|#RRGGBB)" >&2
    exit 1
    ;;
esac

# Final composite: bg → screenshot centered → decorations on top.
magick "$TMP/bg.png" "$IN" -gravity center -composite "$TMP/dec.png" -composite "$OUT"
echo "$OUT"
