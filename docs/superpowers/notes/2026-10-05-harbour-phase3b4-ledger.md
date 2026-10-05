# SDD ledger — plan: (bounded, no plan doc) .superpowers/sdd/2026-10-05-harbour-phase3b4-motion/brief.md
Approved in chat 2026-10-05: 4 motion fixes (delay 40 s + decaying dead-reckoning; spur plausibility glide; 3-falling-fixes → raw GPS; no backward gap snap + forward gap glide). User: 'whatever gets us to a more realistic useful solution'.
Ruling: one implementer (opus) for all four — they share the renderer and the probe tuning loop; splitting would fight over constants — cost: a larger review surface.
Base: f75bc7e
Implementer DONE_WITH_CONCERNS (009b0b3..4f968c7). Frozen 7.3→2.5 %, starved 12.9→7.6 % (both targets missed); far, backward, snaps>100 m and lurches all → 0; wrong-way 60→10; D p50 39 s.
Ruling: accept the missed frozen/starved targets — my targets were estimates; the remaining options cost about 15 s more lag or allow overshoot past the hold (visible backward) — cost: 2.5 % of moving time still frozen, mostly at stops and in feed stalls.
Ruling: accept largest-lag D, 2-fall reverse rule, gap glide across trip changes — each measured on the probe and fixtures; separate commits — cost: none known.
Final review dispatched (fable).
Final review (fable): APPROVE. Important: I1 60 m/s catch-up on straight chords; I2 reverse-rule exit ratchets on the last withheld snap. 8 minors.
Ruling: fix I1, I2, the spec wording and the shared plausibility helper now; time-scaled D2 slack optional if the probe holds; the other minors are accepted — cost: one small commit.
Fix round dispatched (resume implementer).
Fix round: 4a86a29 (I1, I2, M3, M6, M7; M1 tried and dropped — wrong-way 10→11). 644 tests. Probe unchanged except fast frames 634→580. Controller verified the diff.
Live check (iOS sim, 15:22 NDT): 40 s recording, frames every 4 s — buses 9 and 29 move steadily in every frame (no freezes or jumps); bus 1 waits at the MUN terminal, then departs. Android not re-run (the user is using the emulator).
Phase 3b-4: complete (f75bc7e..4a86a29).

## Implementer report (condensed)

Commits: 009b0b3 probe · fda92a0 D4 · 8d51c04 D4 retro-withhold · 8ca882f D2 + rush_1204 · 467e16e gap rules · 7b978db D1 + rush_1330 · 3d326d7 D = largest lag · 4f968c7 spec/README.
Tests: 643 pass / 7 skip in both TZ; analyze clean; motion_replay on 5 fixtures; follow tests green. Every commit verified in a clean detached worktree.

## Changes
- **D4 (store):**
  - Once 3 fixes in a row on one trip and shape each lie more than 30 m behind the one before (2 falls), all but the first are stored with progress and snapped place null.
  - The middle fix is withheld retroactively.
  - The run ends on an advance of more than 30 m, or on a trip or shape change.
  - The snap is kept in `TrackFix.snapProgress` for the window and the hint.
  - 3 falls left rush_1204 failing.
- **D2:** a step along the shape needs `Δp ≤ max(1.6·geo, geo+200)`, and steps of 200 m or less always pass; otherwise a straight glide. Same test in `_towards`.
- **Gap:**
  - A gap of 60 s–3 min on a track that was not re-created (trip changes included) goes through never-backward and does not snap.
  - The limiter runs at 60 m/s until the dot reaches its target.
  - A gap over 3 min, or a re-created track, still snaps.
- **D1:**
  - maxDelay 40 s.
  - Dead-reckoning `v·τ·(1−e^(−t/τ))`, with τ 7 s, horizon 20 s and a 55 m cap. v is the last pair's speed, clamped to 0–30, and 0 if the last pair fails D2.
  - maxExtrapolation removed.
  - D = the LARGEST of the last 8 lags + 1 s (was the second-largest).

## Metrics (full 115-min probe, baseline → final)
- Frozen while moving: 7.3 % → 2.5 % (target < 2 %, missed).
- Starved: 12.93 % → 7.63 % (target < 3 %, missed).
- Far episodes: 4 → 0. Backward: 5 → 0. Snaps over 100 m: 14 → 0. Lurches: 10 → 0. Wrong-way: 60 → 10.
- Frozen runs ≥10 s / ≥30 s: 315/28 → 120/8.
- D p50/p90: 30/30 → 39.1/40 s. Dot→latest fix p50/p90: 35/146 → 64/213 m.
- Dot→render-time GPS p50/p90/p99/max: 8/36/140/1185 → 6/30/90/432 m.

Named cases:
- route 14 spur: 28 m (was 1.1 km);
- route 2: 136–165 m (was 371–578 m);
- v1312: 126/134 m (was 276/414 m);
- v2574: 83 m;
- ghost: never drawn.

Tuning table:
- Only uncapped dead-reckoning plus maxDelay 45 reaches 2.0 % frozen. That allows an overshoot of about 200 m (past the 150 m hold release).
- Starved under 3 % needs D of about 55 s, since the newest fix's age is p97 59 s.

## motion_replay_test exemptions
1. A reverse-run pair (`progressWithheld`).
2. A spur step (the D2 test).
3. An off-route pair. This is an existing rule, not a new one: v1628 already failed at base, hidden.
4. A 60 m/s cap during the gap catch-up window.

## Concerns
- The two missed targets.
- Lag is about +9 s.
- Calls beyond the brief: 2 falls, the gap glide also across trip changes, the largest lag.
- Root cause left in place: the snap prefers the earlier pass on reused roads; a heading-aware snap would fix it, out of scope.
- The short-gap glide can sit far from the bus for a few seconds (v1627 432 m for 18 s).
- The probe's switch count reads 123, was 125.
