#!/usr/bin/env bash
# Print a random millisecond value in [MIN, MAX]. Use to make agent-browser
# waits look human.
#
# Usage:
#   bash scripts/jitter.sh 800 1600   # prints e.g. "1247"
#   agent-browser wait $(bash scripts/jitter.sh 800 1600)

MIN="${1:-600}"
MAX="${2:-1600}"
RANGE=$(( MAX - MIN + 1 ))
echo $(( MIN + RANDOM % RANGE ))
