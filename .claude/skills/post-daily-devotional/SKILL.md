---
name: post-daily-devotional
description: Screenshot the iOS simulator's daily devotional and post it to Instagram. Use when the user says "post the devotional", "publish today's devotional", or runs /post-daily-devotional.
disable-model-invocation: true
allowed-tools: Bash(bash scripts/daily_devotional.sh*) Bash(xcrun simctl*) Bash(uv run social-agents*)
---

Run the daily-devotional pipeline from the repo root:

```!
bash scripts/daily_devotional.sh
```

If the script fails:

1. Read its stderr output above and identify the failing step (simulator not booted, login session expired, agent could not find UI element).
2. Surface a one-line cause and propose the next action (e.g., "Boot the simulator" / "Re-run `social-agents login --platform instagram --account adam`").

If the script succeeds, confirm the screenshot path that was uploaded.
