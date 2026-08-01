---
name: quantitative-self
description: How to read and interpret the owner's health and activity data — Oura Ring readiness, sleep, and activity scores — what thresholds signal something worth surfacing, and how to weight this data when scheduling or advising. Consult it in morning heartbeats, when the owner asks about sleep or energy, and before scheduling anything physically or cognitively demanding.
---

# Quantitative self and health tracking

The owner wears an Oura Ring. Its data is the most reliable objective signal you
have for his current physical state — more useful than asking "how are you
feeling?" and less intrusive than making him report it. Read it in morning
heartbeats; don't wait to be asked.

## Oura Ring

API: https://api.ouraring.com/v2/usercollection/
Token: OURA_TOKEN in ~/workspace/TOOLS.md (under the Oura section).

The API requires a Bearer auth header. Read the token from TOOLS.md and pass it
with `curl`:

    curl -s -H "Authorization: Bearer <OURA_TOKEN>" \
      "https://api.ouraring.com/v2/usercollection/daily_readiness?start_date=$(date +%F)"

Check the policy skill first — if a dedicated Oura action is available and
pre-approved, use it instead of raw curl.

### Endpoints to use

- `daily_readiness` — the single most useful score: did his body recover?
- `daily_sleep` — sleep duration, efficiency, latency, timing
- `daily_activity` — steps, active calories, equivalent walking distance

Always query with `start_date=$(date -d 'yesterday' +%F)` or today's date. The
API returns the most recent available record; yesterday's sleep is more
informative in the morning than the incomplete current-day activity.

### Interpreting the scores

All scores run 0–100.

**Readiness** (the most important):

| Score | Meaning | How to use it |
|-------|---------|---------------|
| 85–100 | Optimal | Normal workday, exercise fine |
| 70–84 | Good | No restrictions |
| 60–69 | Fair | Mention it if something demanding is being planned |
| < 60 | Pay attention | Surface the alert; advise lighter load |
| < 50 | Poor | Alert immediately; avoid hard commitments |

**Sleep score**: same thresholds. Below 50 is notable even if readiness looks
OK — chronic sleep debt accumulates before readiness catches it.

**What to look for beyond the score**: low HRV baseline (below the owner's
7-day average), elevated resting heart rate (+5 bpm above normal), or SpO2
dips. These appear in the `contributors` breakdown.

### Heartbeat protocol

Morning heartbeat (before ~10:00):
1. Fetch `daily_readiness` for yesterday/today.
2. If readiness ≥ 70 AND sleep ≥ 60 → no alert needed, mention scores only if
   the owner asks or if today has demanding commitments.
3. If readiness < 60 OR sleep < 50 → surface a brief alert with the scores and
   the main contributor driving the low score.
4. Do not moralize or suggest specific interventions beyond noting the score —
   he is a physician, he can interpret it.

Late heartbeats (afternoon/evening): skip Oura unless explicitly asked.
Yesterday's sleep score is stale data by then.

## Adding other trackers

If a new wearable or health API is configured (token in TOOLS.md, API
documented there), follow the same pattern: one morning check, threshold-based
alerting, no unsolicited evening data. Update this skill with the new tracker's
endpoints and score interpretation when it is added.
