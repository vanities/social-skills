---
name: warm-all
description: Pick the most-stale enabled platform (by last_run_iso) and run its warm skill once. Designed to be invoked by cron 2-3 times daily; each call advances rotation. Respects per-platform daily caps and the global min-gap. Use when the user says "warm all", "engagement run", or runs /warm-all.
disable-model-invocation: true
allowed-tools: Bash(*) Bash(jq *) Bash(date *) Bash(test *) Read(*) Skill(x-warm *) Skill(pinterest-warm *) Skill(instagram-warm *)
---

# Warm-all — pick one platform, run its warm skill

The intent is **one platform per `/warm-all` invocation**, not all three back-to-back. Cron fires `/warm-all` 2–3 times daily at staggered hours; each call advances the rotation. This guarantees natural pacing and respects the global `min_gap_minutes_between_platforms`.

## Step 1: Read config + state

```bash
CFG=config/engagement-schedule.json
STATE=~/.social-skills/state/engagement-state.json
test -f "$CFG" && test -f "$STATE" || { echo "MISSING config or state"; exit 1; }

NOW_TS=$(date -u +%s)
TODAY=$(date +%Y-%m-%d)
HOUR=$(date +%H | sed 's/^0*//'); HOUR=${HOUR:-0}

START_H=$(jq -r '.global.active_hours.start' "$CFG")
END_H=$(jq -r '.global.active_hours.end' "$CFG")
if [ "$HOUR" -lt "$START_H" ] || [ "$HOUR" -gt "$END_H" ]; then
  echo "outside active hours; exiting"; exit 0
fi
```

## Step 2: Find the most-stale enabled platform

For each enabled platform, compute `staleness = NOW_TS - last_run_ts (or +infinity if never run)`. Pick the platform with the highest staleness, provided:
- it's `enabled: true` in config
- its daily total budget for `actions_today` (sum of all action counts) hasn't hit `daily_action_budget.max`
- its `last_run_iso` is older than `global.min_gap_minutes_between_platforms` ago (so we don't double up against ourselves)

```bash
MIN_GAP_S=$(( $(jq -r '.global.min_gap_minutes_between_platforms' "$CFG") * 60 ))

CANDIDATES=()
for P in x pinterest instagram; do
  ENABLED=$(jq -r ".platforms.$P.enabled" "$CFG")
  [ "$ENABLED" = "true" ] || continue

  LAST=$(jq -r ".$P.last_run_iso // empty" "$STATE")
  if [ -z "$LAST" ]; then
    AGE_S=99999999       # never-run platforms have max staleness
  else
    LAST_TS=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST" +%s 2>/dev/null || echo 0)
    AGE_S=$(( NOW_TS - LAST_TS ))
  fi

  # Reset budget counters if the date rolled
  STORED_DATE=$(jq -r ".$P.actions_today.date // empty" "$STATE")
  if [ "$STORED_DATE" != "$TODAY" ]; then
    DONE=0
  else
    DONE=$(jq -r ".$P.actions_today | [.scroll, .like // 0, .save // 0, .repost // 0, .follow // 0] | add" "$STATE")
  fi
  MAX=$(jq -r ".platforms.$P.daily_action_budget.max" "$CFG")

  # Eligibility: gap met (or never run), budget remaining
  if [ "$AGE_S" -lt "$MIN_GAP_S" ]; then continue; fi
  if [ "$DONE" -ge "$MAX" ]; then continue; fi

  CANDIDATES+=("$AGE_S:$P")
done

# Sort descending by staleness, pick top
PICK=$(printf "%s\n" "${CANDIDATES[@]}" | sort -t: -k1 -rn | head -1 | cut -d: -f2)
echo "picked: ${PICK:-NONE_ELIGIBLE}"
```

(Reminder: this project's shell is **zsh**. Either run this block as bash via `bash -c '<heredoc>'` or replace the array with shuf-friendly emit-and-pipe pattern.)

## Step 3: Invoke the picked platform's warm skill

```bash
case "$PICK" in
  x)         /x-warm ;;
  pinterest) /pinterest-warm ;;
  instagram) /instagram-warm ;;
  "")        echo "no eligible platform — all are within min-gap or budget-exhausted; exiting"; exit 0 ;;
esac
```

Each warm skill self-manages its state; this skill just routes the call.

## Step 4: Report

One line: "ran /<platform>-warm; <N> actions executed; next eligible after <time>".

## Cron entry

Add to crontab three staggered times within the active window:

```cron
17 9   * * * /bin/bash -lc 'cd <repo-path> && claude --print "/warm-all"' >> ~/.social-skills/logs/cron-warm.log 2>&1
43 13  * * * /bin/bash -lc 'cd <repo-path> && claude --print "/warm-all"' >> ~/.social-skills/logs/cron-warm.log 2>&1
22 18  * * * /bin/bash -lc 'cd <repo-path> && claude --print "/warm-all"' >> ~/.social-skills/logs/cron-warm.log 2>&1
```

(Slightly off-the-hour minutes intentionally — :17, :43, :22 — don't fire at exact times. The skill itself does additional intra-run jitter.)

## Failure modes

- **No eligible platform**: not an error — log and exit 0. Cron will try again at the next slot.
- **State file corrupt**: bail with `outcome: failed`, do not auto-recover.
- **Tab not open / not logged in**: each underlying warm skill handles this and aborts cleanly with "run /<platform>-login first" — `/warm-all` should NOT try to recover.
