#!/usr/bin/env bash
# devotional_video_remote.sh — talking-head devotional video via remote Hallo2 server.
#
# Same shape as devotional_video.sh but pipes through a Hallo2 inference server
# running on the user's GPU box (alias `pc`, default http://pc:8000).
#
# Pipeline:
#   1. Synthesize narration locally with chatterbox-tts (Mac handles this fine).
#   2. POST audio.wav + photo.png to $HALLO2_SERVER/generate.
#   3. Server runs Hallo2 on the 5090 → returns mp4.
#
# Usage:
#   scripts/devotional_video_remote.sh <photo> <narration_text> [output.mp4]
#
# Env overrides:
#   HALLO2_SERVER   default http://pc:8000
#   HALLO2_TIMEOUT  default 600 (seconds; Hallo2 inference is slow even on a 5090)

set -euo pipefail

PHOTO="${1:?usage: $0 <photo> <narration_text> [output]}"
NARRATION="${2:?usage: $0 <photo> <narration_text> [output]}"
OUTPUT="${3:-/tmp/devotional-talking-$(date +%Y-%m-%dT%H%M%S).mp4}"

HALLO2_SERVER="${HALLO2_SERVER:-http://pc:8000}"
TIMEOUT="${HALLO2_TIMEOUT:-600}"

TECHSLOP="$(cd "$(dirname "$0")/.." && pwd)/../techslop"
[ -f "$TECHSLOP/scripts/synth_voice.py" ] || { echo "missing $TECHSLOP/scripts/synth_voice.py"; exit 1; }
VOICE_REF="$TECHSLOP/assets/voice_ref.wav"
[ -f "$VOICE_REF" ] || { echo "missing voice ref: $VOICE_REF"; exit 1; }
[ -f "$PHOTO" ] || { echo "missing photo: $PHOTO"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
AUDIO="$WORK/narration.wav"

echo "[remote] 1/3 health check $HALLO2_SERVER/health"
HEALTH=$(curl -s --max-time 10 "$HALLO2_SERVER/health" || echo "")
echo "$HEALTH" | grep -q '"ok": *true' || { echo "[remote] server unreachable or unhealthy: $HEALTH"; exit 2; }
echo "$HEALTH" | grep -q '"weights_present": *true' || echo "[remote] WARN: server reports no weights"

echo "[remote] 2/3 synthesizing narration locally via chatterbox..."
(cd "$TECHSLOP" && uv run python scripts/synth_voice.py "$NARRATION" "$AUDIO" "$VOICE_REF")

echo "[remote] 3/3 POST $HALLO2_SERVER/generate (timeout ${TIMEOUT}s)..."
curl -s --fail --max-time "$TIMEOUT" \
  -X POST "$HALLO2_SERVER/generate" \
  -F "image=@$PHOTO" \
  -F "audio=@$AUDIO" \
  -o "$OUTPUT"

echo "[remote] saved: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
