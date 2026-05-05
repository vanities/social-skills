#!/usr/bin/env bash
# devotional_video.sh — produce a vertical 9:16 mp4 of a daily devotional.
#
# Inputs:  iPhone screenshot (tall portrait) + narration text.
# Output:  1080×1920 mp4 with chatterbox-cloned voice over the screenshot.
#
# Pipeline: text → chatterbox TTS (in techslop's venv) → ffmpeg assembly.
#
# Usage:
#   scripts/devotional_video.sh <image> <narration_text> [output.mp4]
#
# Requires:
#   - ../techslop/assets/voice_ref.wav (recorded via techslop/record_voice.sh)
#   - ../techslop/scripts/synth_voice.py
#   - ffmpeg with libx264 + aac
#   - uv (for invoking the techslop venv)

set -euo pipefail

IMAGE="${1:?usage: $0 <image> <narration_text> [output]}"
NARRATION="${2:?usage: $0 <image> <narration_text> [output]}"
OUTPUT="${3:-/tmp/devotional-$(date +%Y-%m-%dT%H%M%S).mp4}"

# Locate techslop relative to this repo.
TECHSLOP="$(cd "$(dirname "$0")/.." && pwd)/../techslop"
[ -f "$TECHSLOP/scripts/synth_voice.py" ] || { echo "missing $TECHSLOP/scripts/synth_voice.py"; exit 1; }
VOICE_REF="$TECHSLOP/assets/voice_ref.wav"
[ -f "$VOICE_REF" ] || { echo "missing voice ref: $VOICE_REF — record via $TECHSLOP/record_voice.sh"; exit 1; }
[ -f "$IMAGE" ] || { echo "missing image: $IMAGE"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
AUDIO="$WORK/narration.wav"

echo "[devotional_video] 1/3 synthesizing via chatterbox..."
(cd "$TECHSLOP" && uv run python scripts/synth_voice.py "$NARRATION" "$AUDIO" "$VOICE_REF")

DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$AUDIO")
echo "[devotional_video] 2/3 audio duration = ${DURATION}s"

echo "[devotional_video] 3/3 ffmpeg assemble → $OUTPUT"
# 9:16 vertical (1080×1920). Image is scaled down to fit width=1080 (preserving aspect),
# then padded vertically with black bars to fill 1920. Tall iPhone screenshots
# (9:19.5) end up filling almost the full frame with thin black bars top/bottom.
ffmpeg -y -loop 1 -i "$IMAGE" -i "$AUDIO" \
  -filter_complex "[0:v]scale=1080:-2:force_original_aspect_ratio=decrease,scale='if(gt(iw,1080),1080,iw)':'if(gt(ih,1920),1920,ih)',pad=1080:1920:(ow-iw)/2:(oh-ih)/2:black,format=yuv420p[v]" \
  -map "[v]" -map 1:a \
  -c:v libx264 -preset fast -crf 23 \
  -c:a aac -b:a 128k \
  -t "$DURATION" \
  -shortest \
  "$OUTPUT" 2>&1 | tail -5

echo "[devotional_video] saved: $OUTPUT (${DURATION}s)"
