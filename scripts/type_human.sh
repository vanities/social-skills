#!/usr/bin/env bash
# type_human.sh
#
# Types a string character-by-character via `agent-browser keyboard type`, with
# randomized per-character delays and longer pauses at word boundaries plus
# occasional "thinking" pauses. The TARGET ELEMENT MUST ALREADY BE FOCUSED in
# the active agent-browser session — this script does not click anything.
#
# Use this for high-risk human-typed content where uniform-speed typing is a
# legible bot-detection signature. Comments on other people's posts are the
# primary use case (set 2026-05-05); passwords, captions, and tweet text on
# our own posts can use the cheaper `agent-browser keyboard type` directly.
#
# Usage:
#   bash scripts/type_human.sh "amen amen amen"
#
# Tunable env vars (all in milliseconds):
#   TYPE_HUMAN_MIN_CHAR_MS   default 30   per-char delay min
#   TYPE_HUMAN_MAX_CHAR_MS   default 130  per-char delay max
#   TYPE_HUMAN_MIN_WORD_MS   default 120  delay after a space
#   TYPE_HUMAN_MAX_WORD_MS   default 350
#   TYPE_HUMAN_THINK_PCT     default 5    chance (%) of a "thinking" pause after a char
#   TYPE_HUMAN_MIN_THINK_MS  default 400
#   TYPE_HUMAN_MAX_THINK_MS  default 900

set -euo pipefail

TEXT="${1:?usage: $0 \"text to type\"}"

MIN_CHAR_MS="${TYPE_HUMAN_MIN_CHAR_MS:-30}"
MAX_CHAR_MS="${TYPE_HUMAN_MAX_CHAR_MS:-130}"
MIN_WORD_MS="${TYPE_HUMAN_MIN_WORD_MS:-120}"
MAX_WORD_MS="${TYPE_HUMAN_MAX_WORD_MS:-350}"
THINK_PCT="${TYPE_HUMAN_THINK_PCT:-5}"
MIN_THINK_MS="${TYPE_HUMAN_MIN_THINK_MS:-400}"
MAX_THINK_MS="${TYPE_HUMAN_MAX_THINK_MS:-900}"

rand_ms() {
  local lo="$1" hi="$2"
  echo $(( lo + RANDOM % (hi - lo + 1) ))
}

sleep_ms() {
  awk -v ms="$1" 'BEGIN { printf "%.3f\n", ms/1000 }' | xargs sleep
}

LEN=${#TEXT}
for ((i=0; i<LEN; i++)); do
  CH="${TEXT:$i:1}"
  # `agent-browser keyboard type` accepts a single char fine. Quote the char
  # to handle spaces; backslash any chars that are problematic for shell.
  agent-browser keyboard type "$CH" >/dev/null 2>&1

  if [ "$CH" = " " ]; then
    DELAY=$(rand_ms "$MIN_WORD_MS" "$MAX_WORD_MS")
  elif [ $((RANDOM % 100)) -lt "$THINK_PCT" ]; then
    DELAY=$(rand_ms "$MIN_THINK_MS" "$MAX_THINK_MS")
  else
    DELAY=$(rand_ms "$MIN_CHAR_MS" "$MAX_CHAR_MS")
  fi
  sleep_ms "$DELAY"
done
