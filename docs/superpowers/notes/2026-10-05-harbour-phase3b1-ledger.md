# SDD ledger — plan: docs/superpowers/plans/2026-10-05-harbour-phase3b1-motion.md

Spec: docs/superpowers/specs/2026-10-04-harbour-phase3-design.md §3.4 + §1 (reachable)
Branch: claude/unified-ui-map-redesign-fc0a89 · start HEAD d054b03
Models: implementers sonnet; reviewers sonnet; escalation + final review fable (opus rate-limited until 2026-10-07)

## Pre-flight scan

| Pair / task | Produces → consumes | Finding |
|---|---|---|
| T1 ↔ T2–T6 | snapNear + test/map/support/out_and_back.dart (fix(), outAndBackRepo(), lonAt, curbs) | T3 appends copyForTest extensions to the support file; T6 imports it from test/state; OK |
| T2 ↔ T3 | RouteGeometry.snap/initialHint/shapeIdForTrip/fallbackShapeId/hasShape/offRouteMeters → BusTrackStore | names match; OK |
| T2 ↔ T4 | RouteGeometry.poseAt + bearingDegrees → renderer | OK |
| T3 ↔ T4 | BusTrack/TrackFix fields (gpsTime, progress, shapeId, tripId, snapped*, offRoute) → renderer | OK |
| T3/T4 ↔ T5 | store.ingest/tracks, renderer.render/delayFor → replay | OK |
| T3/T4 ↔ T6 | providers + BusTrackingState.fromTrack(track, stale) + map_screen renderAll | OK |
| T6 | changes BusTrackingState → old engine + its tests can't compile → deletion folded into T6 (plan already merged) | OK |
| T1 | 6 tests vs snapNear code (verified arithmetic in 3a probe) | consistent |
| T2 | stop placement/scheduled/hint expectations vs code (checked by hand: 200/500/800/total−300; 350; midnight 86430) | consistent |
| T3 | pass test relies on timetable hint 12:00→200 m at first fix; dup assignment ranks; midnight gpsTime | consistent |
| T4 | D medians (12/8/20), interpolation 220, backward-hold loop ≤42 s, extrapolation 220 then hold, reset test pre-renders at 20 s | consistent |
| T5 | fixture built from scratchpad capture (exists); thresholds per spec §1 | OK — NEEDS_CONTEXT path if sources missing |
| T6 | provider test needs SharedPreferences mock (added); TimeTrackApi() default ctor OK | consistent |

Scan clean.
Task 1: base d054b03
Task 1: implementer a48c67cc… (sonnet) dispatched
Task 1: head 9e03de5
Task 1: review approved with Important (plan-mandated): no test guards the 25 m ambiguity cutoff (all 6 tests pass without it)
Ruling: fix round 1 adds a tolerance test on a local U shape with passes ~55 m apart (fix on the far pass, expectation on the near pass: without the cutoff 55 < 62.7 picks the wrong pass; with it the nearer pass wins) and corrects the 2.4 m comment to 2.0 m — Task 3 relies on the cutoff to recover from a wrong hint — cost if wrong: one extra test
Task 1: minor (deferred): lonAt uses 111320 m/deg vs haversine's 111195 (0.1% under-scale); window coverage thin (lo clamp, narrow window, all-excluded null); dartdoc should say null when the window excludes everything, tolerance is relative, ties go to earlier along; unreachable segLen>0 branch; per-segment allocation; hard cliff at the tolerance
Task 1: fix round 1/5 (2 addressed, 0 open — U-shape cutoff test proven RED without the cutoff; comment 2.0 m; commits 9e03de5..e021aa8)
Task 1: complete (commits d054b03..e021aa8, review clean)
Task 2: base e021aa8
Task 2: implementer a4ce9e09… (sonnet) dispatched
Task 2: head aa3c4e4; implementer sign question checked by controller: adapter sets schedDifferenceMins = -delayMins (positive=ahead), so -1 = 1 min late → timetable 60 s earlier — correct
Task 2: review Needs fixes (sonnet ab34c2b6…): Important (plan-mandated) one misplaced stop drags later stops onto the wrong pass (probe [200,2034,1534,1235,1734]); Important zero-length final segment gives heading 0; Important eager full stop_time index at construction
Ruling: fix round 1 — stopProgresses rejects a stop whose snap is >150 m off the shape or jumps further than 300 m + 30 m/s × scheduled Δt past the last accepted stop (tries the capped window first), without advancing `previous`; poseAt takes heading from the last non-degenerate segment; build the per-trip stop index lazily; ALSO (load-bearing for Task 3's hints) stopProgressAtTime picks the closest time within ±30 s and also tries departure+86400 for trips past midnight — cost if wrong: small diff
Task 2: minor (deferred): '$trip|$shape' cache key could collide on '|' (use a record key); snap ignores min/maxAlong without expectedAlong (document/assert); _secondsOf catches everything (use on FormatException); fallback test doesn't exercise headsign/service narrowing; no tests for duplicate times/single stop in scheduledProgress, poseAt below 0; NaN progress unguarded; fallbackShapeId doesn't check hasShape
Task 2: fix round 1/5 (4 addressed, 0 open — windowed stop placement, heading at degenerate segments, lazy index, closest/midnight stop time; commits aa3c4e4..848972d)
Task 2: minor (deferred): a stop just past maxAlong within 150 m of the clamped edge is accepted at the edge; missing stop times give a 300 m window (Metrobus data has all times); bad-stop test assertion could be isNull; initialHint sign comment confirmed correct by controller
Task 2: complete (commits e021aa8..848972d, review clean)
Task 3: base 848972d
Task 3: implementer DONE (commit 5aa9045); review dispatched on review-848972d..5aa9045.diff
Task 3: review — Needs fixes (Important 3, Minor 8)
Ruling: a fix whose tripId is empty or unknown to the repo inherits the previous fix's trip+shape and continues — the feed emits these, and a global snap on an out-and-back flips passes (reviewer reproduced a 950 m jump) — cost if wrong: a bus truly changing trip with no trip ID stays on old shape until a known trip arrives.
Ruling: on a genuine trip change, hint = initialHint ?? (same shape ? previous progress : null) — timetable knows the new trip's start; previous progress is the next best guess — cost if wrong: loop routes briefly hold at the terminus.
Ruling: ignore fixes whose gpsTime is > dropAfter (5 min) older than fetchTime or > 2 min in the future; positionTimeSeconds==0 still falls back to fetchTime — kills ghost resurrection of frozen rows and lock-out by future stamps — cost if wrong: a bus with a badly skewed clock is hidden.
Ruling: _gpsTime builds wall-clock time via DateTime(y,m,d,0,0,secs) — feed seconds are local wall clock (timetrack_api _secondsSinceMidnight); Duration add is off 1 h on DST days and would now trip the 5-min reject — cost if wrong: none known.
Ruling: tracks getter returns UnmodifiableMapView (renderer reads per frame) — cheap — cost if wrong: none.
Parked minors (Task 3): routeNumber 0 falls back to routeRun (Metrobus route IDs numeric); off-route forgets last good progress (renderer handles off-route geographically, Task 4); _statusRank heuristic loose; mutable fixes list exposed; no test for reversed duplicate order.
Task 3: fix round 1 implementer DONE (1b0a7b2); re-review dispatched
Task 3: fix round 1/5 (5 addressed, 0 open; commits 5aa9045..1b0a7b2)
Task 3: complete (commits 5aa9045..1b0a7b2, review clean)
Note for Task 4/5: fixes with feed delay > 5 min are skipped entirely (watch in live tuning).
Task 4: base 1b0a7b2
Task 4: implementer DONE (0bbda78); concern: forget() must be wired on drop (Task 6). Review dispatched
Task 4: review — Needs fixes (Important 2, Minor 6)
Ruling: bound the never-backward hold — along-shape gap ≤ 60 m holds (jitter); a gap whose two poses are ≤ 40 m apart geographically is a pass relabel and is accepted at once (invisible); otherwise hold at most 15 s of render time, then accept the true position (one correction) — spec says "never backward" to stop wrong-pass drift, but an indefinitely frozen dot breaks "always smooth" and hides a real correction — cost if wrong: one visible backward correction after 15 s on a genuine GPS glitch.
Ruling: high-water mark stores the render time it was set at; discard it when render time goes back > 1 s (clock change) or advances > 60 s without a render (stale: next-day trip-ID reuse, dropped/recreated track, app resumed); renderAll prunes marks for vehicles absent from its input — fixes collision and leak without depending on forget() — cost if wrong: none known.
Ruling: a frame rendered off-shape (no progress) clears the mark — avoids the rejoin teleport — cost if wrong: a bus rejoining behind its previous point moves back along the road once.
Ruling: clamp RenderedBus.progress to the shape length — cost: none.
Ruling: slew the per-vehicle delay toward delayFor(track) at ≤ 0.1 s per second of wall time — removes lurches when the median shifts — cost if wrong: D adapts over ~20 s instead of instantly.
Parked (Task 4): heading tween/shortest-arc rotation → Phase 3b-2 marker layer; delayFor allocation per call (45 µs/frame measured); long-gap single-step lurch (inherent to delayed rendering beyond 20 s gaps).
Task 4: fix round 1/5 implementer DONE_WITH_CONCERNS (a83203f) — concern: wrong-pass sequence sweeps along the shape backwards, relabels mid-sweep, ~24 s frozen.
Ruling: _between uses geographic interpolation when the same-trip pair goes backward along the shape by > 60 m (b.progress < a.progress − 60) — a large backward pair is a pass correction or glitch, not motion; gliding across the map between the two real points is short on shared roads and clears the mark — cost if wrong: a genuine GPS glitch > 60 m glides back visibly instead of holding.
Ruling: a relabel (hold rule b) resets the hold-start time — it is a new mark — cost: none.
Ruling: jitter hold (≤ 60 m) stays without its own time bound — at most 60 m of draw error on a stopped bus — parked.
Ruling: glide threshold for backward same-trip pairs is 150 m, not 60 m — brief test (400→330 holds) mandates holding a 70 m GPS backstep; 150 m still catches pass corrections (hundreds of m) — cost if wrong: backsteps 60–150 m hold up to 15 s then correct.
Task 4: fix rounds 1-2 implementer DONE (a83203f, 9294073); re-review dispatched on 0bbda78..9294073
Task 4: fix round 2/5 (all addressed, 0 open; commits 0bbda78..9294073)
Task 4: complete (commits 0bbda78..9294073, review clean)
Note for Task 6: renderAll must receive ALL tracks (it prunes absent ones); call render once per bus per frame with monotonic now.
Task 5: base 9294073
Ruling: Task 5 GTFS source is the reinstalled simulator container 79695710-…/Documents/gtfs_data (brief path A4B7260A gone) — same device, app reinstalled — cost if wrong: trips unresolved → implementer reports NEEDS_CONTEXT.
Ruling: replay test measures moving frames with renderer.currentDelayFor (slewed) falling back to delayFor — the renderer draws with the slewed delay since Task 4 fix round 1 — cost if wrong: none.
Task 5: implementer dispatched
Task 5: implementer NEEDS_CONTEXT — replay fails: advanced/moving 0.87/0.86, max drawn 16510/10834 km/h, 1 backward each (15 s hold expiries, 75 m / 121 m). Root cause measured: feed latency median 10 s (≤19 s) + fix interval ~16 s > D (median interval + 2 s ≈ 17.5 s) → render time runs past the newest fix, extrapolates 5 s, holds, jumps.
Ruling (SPEC CHANGE §3.4, tell user): D is latency-aware — lag_k = fixes[k+1].fetchTime − fixes[k].gpsTime over the last ≤8 pairs; target D = second-largest lag (largest if < 3 values) + 1 s; with < 2 fixes D = (fetchTime − gpsTime of latest) + 15 s; clamp 8–30 s (maxDelay 20 → 30 s); slew unchanged. Smoothness requires render time ≤ newest GPS time until the next fix arrives, i.e. D ≥ latency + interval; the spec's "~12 s" assumed zero latency. Buses will show ~25 s behind real time (feed is already ~10 s stale) — cost if wrong: user may prefer less lag with occasional stops; revert by changing the clamp.
Ruling: replay harness is timezone-independent — derive the capture's UTC offset (rounded to 30 min) from fetch_time vs positionTimeSeconds and feed the store local DateTimes with the capture's wall clock; production store unchanged (device is local) — cost: none.
Ruling: hold-expiry backward steps — decide after re-measuring with latency-aware D (implementer lists residuals).
Task 5: re-measure with latency-aware D — ratio passes (0.986/0.984); residual: 1 backward each (hold expiries 74 m/100 m), jumps from feed-skipped fixes (extrapolate-then-hold), start-up (first fix → second, ≤313 m), a few trip-change/off-route.
Ruling: add a continuity limiter as the renderer's last stage — the drawn bus moves toward the computed target at ≤ 30 m/s (along the shape when same trip+shape with progress on both, else geographically), snapping only on the first frame or after a > 2 s render gap — spec §1 "always smooth": every residual jump is a target discontinuity, and limiting the drawn motion removes all of them at once — cost if wrong: after a skipped fix the bus lags its target for a few seconds while catching up.
Ruling: the bounded-hold expiry (accept true position after 15 s) applies only when the gap is > 150 m; gaps ≤ 150 m hold until the bus passes the mark, the trip changes, it goes off-shape, or the mark expires — spec §1 never-backward + user's core complaint; both residual backward events were 74–100 m GPS backward runs — cost if wrong: a stationary bus may be drawn up to 150 m ahead of its real spot until it moves or changes trip.
Task 5: implementer DONE_WITH_CONCERNS (700cc42) — replay green both fixtures, TZ-independent; backward 0, max drawn 108 km/h (cap), ratio 0.986/0.982.
Ruling: accept deviation — limiter follows the shape only for forward diffs; backward accepted moves (relabel, >150 m expiry) close geographically — walking a relabel along the shape would sweep a whole pass — cost: none known.
Task 5: review dispatched (9294073..700cc42)
Task 5: review — Approved (0 Critical/Important; 7 minor). Polish round for M1 (speed bound → 30 m/s × 1.05), M2 (projected backward check incl. null-progress frames), M3 (gap == 0 returns drawn), M4 (tidy), M6 (tool --start, optional calendars, keep note, close files). M5 docs: controller updates spec §3.4 + global-constraints at Task 6/final. M7 parked → 3b-2 heading tween.
Ruling: Task 5 polish residual (2445 walked back 44 m at trip change after extrapolation) — option (a): a trip-change (or off-route) geographic segment starts from the old trip's high-water pose when the mark is on a's trip and ahead of a.progress — the bus was already drawn there; starting at a's snapped point pulls it back — cost if wrong: none known.
Task 5: polish committed 4d3099c (green, +390). Ruling: accept per-vehicle anchor for trip-change glide start. Pending: cumulative projected backward check (implementer resumed; commits only if green), then scoped re-review of 700cc42..HEAD, then Task 5 complete → Task 6.
Docs: spec §3.4 + plan constraints amended (commit after 4d3099c).
SESSION PAUSED (usage limit) — resume here.
Ruling: cumulative projected check exempts trip-change glides (frames whose surrounding fix pair has a.tripId != b.tripId) and resets the high-water when one starts — the next trip's start can lie behind the old trip's end (terminal turnaround); that motion is real, not drift, and spec's never-backward rule is per trip — cost if wrong: a bogus trip change could hide a ≤ glide-length backward move.
Ruling: cumulative check also exempts same-trip pass-correction glides (pair backward > 150 m, drawn geographically by design) and resets the high-water after — progress across two passes is not comparable; the residual was 7–9 m of drawn motion — cost if wrong: a genuine >150 m backward pair hides its glide (already ruled acceptable in Task 4).
Task 5: polish+checks committed (4d3099c, 9b7b6fd docs, d4af1b5); scoped re-review dispatched on 700cc42..d4af1b5
Task 5: re-review clean (all minors addressed; mutation tests: never-backward off / limiter off / hold off → replay RED)
Task 5: complete (commits 9294073..d4af1b5, review clean)
Task 6: base d4af1b5
Ruling: Task 6 hit-test (_findNearestBus) reads the last frame drawn by _renderBusAnnotations instead of calling the renderer — the renderer is stateful per frame — cost: tap uses a ≤ 1-frame-old position.
Ruling: renderAll always gets all store tracks; route/stale filtering applies to its output — renderAll prunes absent vehicles.
Task 6: implementer dispatched
Task 6: implementer DONE_WITH_CONCERNS (8e4d930); review dispatched
Task 6: review — Approved (0 Critical/Important). Polish round: M1 guard first poll + yield in catch, M2 test the null-store branch, M3 fromTrack stale/offRoute + interval-change store survival, M4 fetchTime after response, M5 README/comments, M7 Fleet View minsFromStop 0. M6 naming parked (3b-2).
Task 6: polish committed 0213b6a (accepted extra edit: tool/analyze_live_vehicle_trace.dart message). Minor-only round; final review covers it.
Task 6: complete (commits d4af1b5..0213b6a, review clean)
Final review: dispatched (fable) on d054b03..0213b6a
Final review (fable): fix first — Important 3 (I1 limiter races 108 km/h up to ~40 s after data gaps: resume, tab switch with paused stream, stale-return, feed outage; I2 mark/anchor keyed by trip only, null-trip route change holds on unrelated shape; I3 cumulative projected check never fires — chord vs arc), Minor 5.
Ruling: renderer snaps (bypasses limiter, resets mark/anchor) on a data discontinuity — newest fix gpsTime − previous fix gpsTime > 60 s, or the track was re-created (fewer fixes than last seen / first fix differs) — the user was not watching continuous data; racing at 108 km/h is worse than one placement — cost if wrong: a 60–90 s feed gap while watching shows one jump.
Ruling: _Mark gains shapeId; mark and anchor apply only on matching shape — cost: none.
Ruling: projected check uses shown ≥ 0.5 × drop and is proven to fire on a synthetic backward step — cost: none.
Ruling: routeGeometryProvider uses .value (keeps previous repo while reloading) — cost: none.
Final fix: 4f24d1e (DONE_WITH_CONCERNS) + docs commit.
Ruling: accept deviations — re-creation detected by the previous newest fix vanishing (first fix rotates at 24 fixes); a gap snap still holds ≤ 60 m behind the same trip+shape mark; replay speed check skips the snap frame — a > 60 s feed gap while watching shows one placement (live data has 63–78 s gaps) instead of a 30 s race; the bus was already frozen after 5 s of extrapolation — cost if wrong: user sees occasional single jumps after long feed gaps.
Final review: scoped re-review dispatched
Final review: re-review clean (all addressed). Docs §3.4 snap rule amended. Next: parity check iOS sim + Android emu.
Parity: iOS sim build + launch OK, map renders (2026-10-05 01:23 NDT); live check deferred — feed empty overnight (no Metrobus service), retry after ~06:30.
