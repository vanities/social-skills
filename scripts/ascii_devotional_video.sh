#!/usr/bin/env bash
# ascii_devotional_video.sh
#
# Builds a 9:16 MP4 from a daily-devotional screenshot with an animated
# terminal/ASCII background.
#
# HEAVILY VARIANT: each run randomly picks ONE color palette AND ONE animation
# style, so odd-day Reels look meaningfully different day to day (instead of the
# old single green-terminal look). The verse reference + theme phrase are still
# woven into the floating words.
#
# Usage:
#   scripts/ascii_devotional_video.sh <screenshot.png> [output.mp4|.png] [theme] [reference]
#
# If [output] ends in .png, renders a SINGLE preview frame (fast, no encode) —
# handy for previewing palette/style combos.
#
# Env overrides (all optional):
#   ASCII_DEVOTIONAL_PALETTE     force a palette: matrix amber ice synthwave gold
#                                crimson cosmic ember mono ocean rose slate
#   ASCII_DEVOTIONAL_STYLE       force a style:   scatter rain bands starfield grid pulse
#   ASCII_DEVOTIONAL_SEED        integer; reproduces palette+style+layout exactly
#   ASCII_DEVOTIONAL_DURATION    seconds (default 7)
#   ASCII_DEVOTIONAL_FPS         output fps (default 30)
#   ASCII_DEVOTIONAL_FRAME_RATE  generated frames/sec (default 6 — higher = smoother motion, slower render)
#
# Output is h264 + AAC + faststart, 1080x1920, with silent audio so social
# platforms treat the file as a normal video upload.

set -euo pipefail

IN="${1:?usage: $0 <screenshot.png> [output.mp4|.png] [theme] [reference]}"
OUT="${2:-}"
THEME="${3:-daily devotional}"
REFERENCE="${4:-}"
DURATION="${ASCII_DEVOTIONAL_DURATION:-7}"
FPS="${ASCII_DEVOTIONAL_FPS:-30}"
FRAME_RATE="${ASCII_DEVOTIONAL_FRAME_RATE:-${ASCII_DEVOTIONAL_ASCII_FPS:-6}}"   # generated frames/sec

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

FONT="Menlo,Monaco,'SF Mono','Courier New',monospace"

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

# clamp an int to 1..99 and print as "0.NN" opacity
dec2() { local n=$1; (( n < 1 )) && n=1; (( n > 99 )) && n=99; printf "0.%02d" "$n"; }

# triangle wave: idx, period -> 0..100 (ramps up then down) — for breathing/pulse
tri() {
  local i=$1 p=$2 h t
  h=$(( p / 2 )); (( h < 1 )) && h=1
  t=$(( i % p ))
  if (( t <= h )); then echo $(( t * 100 / h )); else echo $(( (p - t) * 100 / h )); fi
}

xml_escape() {
  # NOTE: do NOT use ${s//</&lt;} — bash 5.2+ (and zsh) treat an unquoted '&'
  # in a ${//} replacement as the matched text, turning '<' into '<lt;' and
  # producing invalid XML. Build entities via plain assignment instead (where
  # '&' is always literal) so this is correct on bash 3.2, 5.2+, and zsh.
  local s=$1
  case $s in
    *'&'*|*'<'*|*'>'*) : ;;                 # has a special char -> escape below
    *) printf '%s' "$s"; return ;;          # fast path: nothing to escape
  esac
  local out='' i ch
  for (( i = 0; i < ${#s}; i++ )); do
    ch=${s:i:1}
    case $ch in
      '&') out+='&amp;' ;;
      '<') out+='&lt;' ;;
      '>') out+='&gt;' ;;
      *)   out+=$ch ;;
    esac
  done
  printf '%s' "$out"
}

# emit one <text> glyph into the working SVG. 7th arg = optional attr (e.g. glow filter).
# Escapes the glyph text here so SVG-special chars (< > &) in GLYPHS/WORDS can't
# produce malformed XML that breaks rsvg-convert.
emit() {
  local x=$1 y=$2 size=$3 color=$4 opacity=$5 text=$6 extra=${7:-}
  text=$(xml_escape "$text")
  echo "<text x=\"$x\" y=\"$y\" font-family=\"$FONT\" font-size=\"$size\" fill=\"$color\" opacity=\"$opacity\" text-anchor=\"middle\"$extra>$text</text>" >> "$TMP/dec.svg"
}

# ---------------------------------------------------------------------------
# Palettes: each sets a background radial gradient, a glyph color set, and an
# accent color (used for bright "heads", sparkles, and the screenshot border).
# ---------------------------------------------------------------------------
PALETTES="matrix amber ice synthwave gold crimson cosmic ember mono ocean rose slate"

set_palette() {
  case "$1" in
    matrix)    BG1="#06301F"; BG2="#020504"; COLORS=("#00FF99" "#9CFFD2" "#E8FFF4" "#3CFFB0"); ACCENT="#00FF99" ;;
    amber)     BG1="#2A1A00"; BG2="#070300"; COLORS=("#FFB300" "#FFD37A" "#FFE9B0" "#FF8A00"); ACCENT="#FFC247" ;;
    ice)       BG1="#002430"; BG2="#01070C"; COLORS=("#00E5FF" "#9CF6FF" "#E6FEFF" "#36C6FF"); ACCENT="#5FE6FF" ;;
    synthwave) BG1="#240033"; BG2="#0A0014"; COLORS=("#FF2FB9" "#FF7AD9" "#B36BFF" "#FFD1F2"); ACCENT="#FF5FCB" ;;
    gold)      BG1="#2A2200"; BG2="#0A0800"; COLORS=("#FFD700" "#FFE98A" "#FFF6CF" "#FFB300"); ACCENT="#FFDB4D" ;;
    crimson)   BG1="#2A0008"; BG2="#0A0002"; COLORS=("#FF2D55" "#FF7A93" "#FFD1DA" "#C81E3A"); ACCENT="#FF4D6A" ;;
    cosmic)    BG1="#120A2E"; BG2="#03010C"; COLORS=("#7A5CFF" "#B0A0FF" "#E0DBFF" "#4CC3FF"); ACCENT="#9A86FF" ;;
    ember)     BG1="#2A0E00"; BG2="#0A0300"; COLORS=("#FF5A1F" "#FF9A5A" "#FFD0A8" "#FF2D00"); ACCENT="#FF7A3C" ;;
    mono)      BG1="#0E0E0E"; BG2="#000000"; COLORS=("#FFFFFF" "#CFCFCF" "#9A9A9A" "#EDEDED"); ACCENT="#FFFFFF" ;;
    ocean)     BG1="#002A24"; BG2="#000A08"; COLORS=("#00FFC8" "#6FFFE0" "#CFFFF4" "#1FB89A"); ACCENT="#3FFFD0" ;;
    rose)      BG1="#2A0018"; BG2="#0A0006"; COLORS=("#FF4FA3" "#FF9AC8" "#FFD6E8" "#FF1F7A"); ACCENT="#FF6FB3" ;;
    slate)     BG1="#0C1622"; BG2="#01040A"; COLORS=("#5C7CFF" "#9AB0FF" "#D6E2FF" "#3C5AC8"); ACCENT="#7E97FF" ;;
    *)         BG1="#06301F"; BG2="#020504"; COLORS=("#00FF99" "#9CFFD2" "#E8FFF4" "#3CFFB0"); ACCENT="#00FF99" ;;
  esac
  BG="radial-gradient:${BG1}-${BG2}"
}

GLYPHS=("+" "|" "-" "." ":" "*" "†" "✦" "░" "▒" "▓" "0" "1" "/" "=" ";" "<" ">" "^" "~")

# WORDS get the verse reference + theme phrase woven in (kept from the original).
# Stored raw; emit() escapes at render time (single source of XML escaping).
WORDS=("FAITH" "GRACE" "HOPE" "MERCY" "AMEN" "LIGHT" "WORD" "PRAY" "PEACE" "TRUTH" "GLORY" "REFUGE")
[[ -n "$REFERENCE" ]] && WORDS+=("$REFERENCE")
[[ -n "$THEME" ]] && WORDS+=("$THEME")

# ---------------------------------------------------------------------------
# Styles: each appends glyphs to the working SVG for frame $idx. Motion comes
# from $idx; RUN_SEED gives per-run variance while staying stable across frames.
# ---------------------------------------------------------------------------
STYLES="scatter rain bands starfield grid pulse"

# chaotic dense field that re-randomizes every frame (the original look)
draw_scatter() {
  local i
  for ((i = 0; i < 300; i++)); do
    emit "$(rand_in 8 $((TARGET_W - 8)))" "$(rand_in 16 $((TARGET_H - 16)))" \
      "$(rand_in 13 32)" "$(pick "${COLORS[@]}")" "$(rand_opacity)" "$(pick "${GLYPHS[@]}")"
  done
  for ((i = 0; i < 28; i++)); do
    emit "$(rand_in 40 $((TARGET_W - 40)))" "$(rand_in 70 $((TARGET_H - 70)))" \
      "$(rand_in 17 32)" "$(pick "${COLORS[@]}")" "0.$((22 + RANDOM % 40))" "$(pick "${WORDS[@]}")"
  done
}

# Matrix-style vertical columns: bright glowing head + fading trail, falling
draw_rain() {
  local idx=$1 spacing=28 cell=30 col cols colX sp period phase headY t ty op clr i
  cols=$(( TARGET_W / spacing ))
  for ((col = 0; col <= cols; col++)); do
    colX=$(( col * spacing + 14 + (RUN_SEED + col * 7) % 8 ))
    sp=$(( 1 + (RUN_SEED / (col + 1) + col * 13) % 3 ))
    period=$(( TARGET_H + 12 * cell ))
    phase=$(( (col * 97 + RUN_SEED * 3) % period ))
    headY=$(( (idx * sp * cell + phase) % period - 6 * cell ))
    if (( headY > -cell && headY < TARGET_H + cell )); then
      emit "$colX" "$headY" 26 "$ACCENT" "0.95" "$(pick "${GLYPHS[@]}")" ' filter="url(#glow)"'
    fi
    for ((t = 1; t <= 8; t++)); do
      ty=$(( headY - t * cell ))
      (( ty < 0 || ty > TARGET_H )) && continue
      op=$(( 80 - t * 9 ))
      clr="${COLORS[$(( t % ${#COLORS[@]} ))]}"
      emit "$colX" "$ty" 24 "$clr" "$(dec2 "$op")" "$(pick "${GLYPHS[@]}")"
    done
  done
  for ((i = 0; i < 10; i++)); do
    emit "$(rand_in 60 $((TARGET_W - 60)))" "$(rand_in 90 $((TARGET_H - 90)))" \
      24 "${COLORS[2]}" "0.$((20 + RANDOM % 30))" "$(pick "${WORDS[@]}")"
  done
}

# horizontal teletype rows scrolling sideways
draw_bands() {
  local idx=$1 step=64 y xoff x clr row yy
  for ((y = 40; y < TARGET_H; y += step)); do
    xoff=$(( (idx * 8 + y / step * 37 + RUN_SEED) % 48 ))
    for ((x = -40; x < TARGET_W + 40; x += 26)); do
      clr="${COLORS[$(( (x / 26 + y / step) % ${#COLORS[@]} ))]}"
      emit "$(( x + xoff ))" "$y" 20 "$clr" "$(dec2 $(( 18 + (x / 26 + idx) % 22 )))" "$(pick "${GLYPHS[@]}")"
    done
  done
  for ((row = 0; row < 12; row++)); do
    yy=$(( 80 + row * 150 ))
    (( yy > TARGET_H - 40 )) && continue
    emit "$(rand_in 80 $((TARGET_W - 80)))" "$yy" 26 "$ACCENT" "0.55" "$(pick "${WORDS[@]}")"
  done
}

# sparse drifting glowing points + sparkles, calm
draw_starfield() {
  local idx=$1 i sx sy sz
  for ((i = 0; i < 90; i++)); do
    sx=$(( (i * 97 + RUN_SEED * 13) % TARGET_W ))
    sy=$(( ( (i * 53 + idx * 5 + RUN_SEED) % (TARGET_H + 40) ) - 20 ))
    if (( i % 7 == 0 )); then
      sz=$(( 22 + (i % 4) * 8 ))
      emit "$sx" "$sy" "$sz" "$ACCENT" "0.9" "$(pick "✦" "✧" "*" "+")" ' filter="url(#glow)"'
    else
      sz=$(( 11 + (i % 3) * 4 ))
      emit "$sx" "$sy" "$sz" "${COLORS[$(( i % ${#COLORS[@]} ))]}" "$(dec2 $(( 18 + (i + idx) % 30 )))" "$(pick "." ":" "·" "+" "'")"
    fi
  done
  for ((i = 0; i < 12; i++)); do
    emit "$(rand_in 80 $((TARGET_W - 80)))" "$(rand_in 100 $((TARGET_H - 100)))" \
      "$(rand_in 22 34)" "${COLORS[2]}" "0.$((22 + RANDOM % 30))" "$(pick "${WORDS[@]}")"
  done
}

# regular aligned grid whose cells cycle color each frame (LED board / matrix)
draw_grid() {
  local idx=$1 step=60 gx gy clr i
  for ((gy = step; gy < TARGET_H; gy += step)); do
    for ((gx = step; gx < TARGET_W; gx += step)); do
      clr="${COLORS[$(( (gx / step + gy / step + idx) % ${#COLORS[@]} ))]}"
      if (( (gx / step * (gy / step) + idx + RUN_SEED) % 13 == 0 )); then
        emit "$gx" "$gy" 30 "$ACCENT" "0.85" "$(pick "${GLYPHS[@]}")" ' filter="url(#glow)"'
      else
        emit "$gx" "$gy" 26 "$clr" "$(dec2 $(( 16 + (gx / step + gy / step) % 18 )))" "$(pick "${GLYPHS[@]}")"
      fi
    done
  done
  for ((i = 0; i < 8; i++)); do
    emit "$(rand_in 80 $((TARGET_W - 80)))" "$(rand_in 120 $((TARGET_H - 120)))" \
      30 "${COLORS[2]}" "0.5" "$(pick "${WORDS[@]}")"
  done
}

# sparse large glyphs that breathe (grow/shrink) with glow
draw_pulse() {
  local idx=$1 i px py fr sz op
  for ((i = 0; i < 24; i++)); do
    px=$(( (i * 131 + RUN_SEED * 7) % (TARGET_W - 40) + 20 ))
    py=$(( (i * 197 + RUN_SEED * 11) % (TARGET_H - 60) + 30 ))
    fr=$(tri $(( idx + i * 5 )) 14)
    sz=$(( 24 + fr * 34 / 100 ))
    op=$(( 28 + fr * 55 / 100 ))
    if (( i % 4 == 0 )); then
      emit "$px" "$py" "$sz" "$ACCENT" "$(dec2 "$op")" "$(pick "✦" "†" "*" "+")" ' filter="url(#glow)"'
    else
      emit "$px" "$py" "$sz" "${COLORS[$(( i % ${#COLORS[@]} ))]}" "$(dec2 "$op")" "$(pick "${GLYPHS[@]}")"
    fi
  done
  for ((i = 0; i < 8; i++)); do
    fr=$(tri $(( idx + i * 9 )) 14)
    emit "$(( (i * 263 + RUN_SEED) % (TARGET_W - 160) + 80 ))" "$(( (i * 167 + RUN_SEED * 3) % (TARGET_H - 160) + 80 ))" \
      "$(( 30 + fr * 16 / 100 ))" "${COLORS[2]}" "$(dec2 $(( 30 + fr * 40 / 100 )))" "$(pick "${WORDS[@]}")"
  done
}

make_frame() {
  local idx=$1 out=$2 bg="$TMP/bg.png" dec="$TMP/dec.png"

  magick -size "${TARGET_W}x${TARGET_H}" "$BG" "$bg"

  cat > "$TMP/dec.svg" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<svg width="$TARGET_W" height="$TARGET_H" xmlns="http://www.w3.org/2000/svg">
<defs>
<filter id="glow" x="-100%" y="-100%" width="300%" height="300%">
  <feGaussianBlur stdDeviation="2.4"/>
  <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>
</defs>
EOF

  "draw_${STYLE}" "$idx"

  echo "</svg>" >> "$TMP/dec.svg"
  rsvg-convert "$TMP/dec.svg" -o "$dec"

  magick "$bg" "$dec" -compose screen -composite \
    "$FG" -compose over -gravity center -composite \
    -stroke "${ACCENT}55" -strokewidth 4 -fill none \
    -draw "roundrectangle $((FG_X - 10)),$((FG_Y - 10)),$((FG_X + FG_W + 10)),$((FG_Y + FG_H_ACTUAL + 10)),20,20" \
    "$out"
}

# --- pick palette + style (random per run unless forced/seeded) --------------
RUN_SEED=$(( RANDOM ))
if [[ -n "${ASCII_DEVOTIONAL_SEED:-}" ]]; then
  RANDOM=$ASCII_DEVOTIONAL_SEED
  RUN_SEED=$ASCII_DEVOTIONAL_SEED
fi
PALETTE="${ASCII_DEVOTIONAL_PALETTE:-$(pick $PALETTES)}"
STYLE="${ASCII_DEVOTIONAL_STYLE:-$(pick $STYLES)}"
set_palette "$PALETTE"
echo "[ascii-devotional-video] palette=$PALETTE style=$STYLE seed=$RUN_SEED" >&2

# --- single-frame preview mode (output ends in .png) -------------------------
case "$OUT" in
  *.png|*.PNG)
    mkdir -p "$(dirname "$OUT")"
    make_frame "$(( FRAME_COUNT / 2 ))" "$OUT"
    echo "$OUT"
    exit 0
    ;;
esac

# --- full video --------------------------------------------------------------
for ((idx = 0; idx < FRAME_COUNT; idx++)); do
  make_frame "$idx" "$(printf "%s/frame-%03d.png" "$TMP" "$idx")"
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
