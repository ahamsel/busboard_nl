# SDD ledger — plan: docs/superpowers/plans/2026-10-05-harbour-phase3b3-follow.md
Spec: docs/superpowers/specs/2026-10-04-harbour-phase3-design.md §3.5, §3.2, §4
Plan commit ba215f3

## Preflight scan
| Pair / task | Produces → consumes | Finding |
|---|---|---|
| T1↔T2 | TripStop, tripStops → FollowTracker.stopsFor | consistent |
| T1↔T6 | splitShape → route line updates | consistent |
| T2↔T5 | FollowSnapshot fields → card | consistent; card test builder _bus needs its own def (schedDiff, stale) |
| T2↔T6/T7 | FollowTracker.update API → screen + replay | consistent |
| T3↔T6 | followProvider → screen | consistent |
| T4↔T6 | updateRoute/clearRoute, busMarkers(followedVehicleId), fitBounds → screen | consistent |
| T5↔T6 | FollowCardHeader/Body ctor params → screen | consistent |
| T2 self | _snapshot fallback rules prose vs code | plan flags it; implementer adjusts fallbacks to tests (R1) |
| T3 self | board/row/card tests in prose (harness-dependent) | ok |
| T5 self | stale subtitle: code uses replaceFirst; prose says build directly | prose governs (R2) |
| T6 self | integration described in prose, no full code | ok (integration task; standard model) |
| T7 self | replay harness reuse | ok |
Ruling: R1 — in Task 2, when FollowTracker's _snapshot fallbacks disagree with the tests, the tests and the Rules list govern — the code block flags itself as needing adjustment — cost if wrong: none.
Ruling: R2 — Task 5's stale subtitle is built directly as 'Bus N · Last seen <agoText>' (prose over code) — cost: none.
Task 1: base ba215f3
Task 1: implementer DONE (4a55f33); review dispatched
Task 1: complete (commits ba215f3..4a55f33, review clean)
Task 1: minor (deferred): split point can duplicate a vertex (zero-length segments; harmless); no test for unplaced stop / past-midnight departure / vertex split
Task 2: base 4a55f33
Task 2: implementer DONE (7eda64d). Ruling: accept deviations — linger check >= (test ends at exactly 10 s); lock yourStopIndex once arrived (else a bus >150 m past during the linger loses "Arrived at …") — cost: none. Review dispatched.
Task 2: review — Needs fixes (I1 trip change after/at arrival replaces it with tripEnded; I2 busIndex/stopsToGo flicker after arrival; I3 stopsFor + rebuild every frame for stop-less trips).
Ruling: I1 — once arrived, a trip change is ignored and the follow ends as `arrived` after the linger; before arrival, a trip change when your stop is the trip's last placed stop and the last known p was within 60 m of it also counts as arrival (latch, linger, end arrived) — at the terminus the next trip ID often arrives first — cost if wrong: a bus that turns back 60 m short is reported arrived.
Ruling: I2 — freeze busIndex = yourIndex and stopsToYourStop = 0 once arrived — cost: none.
Ruling: I3 — reload stops only when the (trip, shape) key changes; snapshot equality treats two empty stop lists as equal — cost: none.
Parked (Task 2): your stop with null progress never arrives (ends via trip end/lost); first-stop-of-trip arrives at the terminal immediately (correct per rules).
Task 2: fix round 1 implementer DONE (20bd978). Ruling: accept — while lingering after arrival, a new trip's fixes don't update progress or stops — cost: none. Re-review dispatched.
Task 2: fix round 1/5 (3 addressed, 0 open; commits 7eda64d..20bd978)
Task 2: complete (commits 4a55f33..20bd978, review clean)
Carry to Task 5: during the arrival linger snapshot.bus may be the next trip's state — card uses snapshot.tripId's headsign while arrived; bounds-check busIndex/yourStopIndex against stops.length (shape change after arrival can leave yourStopIndex out of range).
Task 2: minor (deferred): stopsFor empty once is never retried for that trip|shape (RouteGeometry is static, ok)
Task 3: base 20bd978
Task 3: implementer DONE (f7ea4e5); review dispatched
Task 3: review — Approved
Task 3: complete (commits 20bd978..f7ea4e5, review clean)
Task 3: minor (deferred): onTapHint can read "follow bus null" if a caller passes onTap without a vehicle; no test for live row with empty vehicle; Follow button sits in the body (visible because a bus tap opens the sheet at half); capture vehicleId before clear()
Task 4: base f7ea4e5
Task 4: implementer DONE (ac46496); review dispatched
Task 4: review — Approved
Task 4: complete (commits f7ea4e5..ac46496, review clean)
Carry to Task 6: fitBounds padding is logical px (do not multiply by dpr); FollowCamera's closeMeters CenterMove already avoids zero-area bounds; re-push updateRoute after every install (style switch wipes the route source).
Task 4: minor (deferred): fitBounds doc lacks unit; no test for not-following feature props / stale followed bus; notch layer sits under every badge (check on device)
Task 5: base ac46496
Task 5: implementer DONE_WITH_CONCERNS (66ea02d); Ruling: accept reworked stop strip (brief's threw on empty stops / drew bus at -1) and etaText %86400 — cost: none. Concern (badge during linger from next-trip route) → minor, carry to Task 6 if cheap. Review dispatched.
Task 5: review — Needs fixes (I1 strip draws rings past your stop; arrived puts bus after star). Ruling: also take M1 (body ETAs use 'sched' while arrived), M2 (optional routeLabel param for badge/strip, Task 6 passes the trip's route), M3 (minutes semantics 'N minutes to your stop'; 'scheduled' in row semantics) — cheap, rider-visible — cost: none.
Task 5: fix round 1 implementer DONE (9c94535); re-review dispatched
Task 5: fix round 1/5 re-review clean (I1, M1-M3 addressed; no strip key collisions on loops)
Task 5: complete (commits 66ea02d..9c94535, review clean)
Task 6: base 9c94535
Ruling: Task 6 gaps — onStop stops with no toast; onSeeAll expands to full; arrived ending has no toast; tripHeadsign/routeLabel come from snapshot.tripId's trip — cost: none
Task 6: implementer dispatched (sonnet)
Task 6: implementer DONE_WITH_CONCERNS (f9bf4b5). Ruling: Back chip sits above the credit link rather than the peek top — the credit link owns that band — cost: none. Ruling: the followed bus must stay visible even when the route filter excludes its route — the rider asked for that bus — cost: one filter exception; sent to review as a required check. Pan-pause over the platform view → verify on device in live parity. Review dispatched.
Task 6: review — Needs fixes (I1 route filter hides the followed bus). Ruling: also take M1 (bus/stop taps ignored; only an empty tap collapses), M2 (install re-push race), M3 (all four toast strings tested), M4 (pinch + 10 px jitter), M5 (A→B switch test), M6 (dead code) — cheap, and they lock behaviour — cost: none. Pointer pause over the platform view → device check in live parity.
Task 6: fix round 1 dispatched (resume implementer)
Task 6: fix round 1 implementer DONE (3c768d6); re-review dispatched
Task 6: fix round 1/5 re-review clean (I1, M1-M6 addressed)
Task 6: complete (commits 9c94535..3c768d6, review clean)
Carry to live parity: pan/pinch pause over the MapLibre platform view (iOS UiKitView / Android) is unverified on a device
Task 7: base 3c768d6
Ruling: Task 7 adds spec §3.5 amendments for the route-filter exemption, the Back chip position, and no toast on stop/arrival — they record Task 6 rulings — cost: none
Task 7: implementer dispatched (sonnet)
Task 7: implementer DONE (569a18b); controller doc fix 76649e3 (spec §3.2 superseded figure, §3.5 State wording); review dispatched
Controller: rush-hour fixture built: test/fixtures/timetrack/replay_2026-10-05_rush (13:30:06–13:39:56Z, 60 polls, 38 vehicles, 2.1 MB; GTFS from the probe worktree's build/gtfs)
Task 7: review — Approved
Task 7: complete (commits 3c768d6..76649e3, review clean)
Task 7: minor (parked → final fix wave): recreate-after-end branch dead (assert/count endings instead); snapshot identity asserts tautological (comment or drop); fixture loader duplicated; README lacks the 60 s not-found ending
Controller: rush fixture — follow replay passes (both TZ); motion replay FAILS: 2446 13328→13268 at +260 s. Root cause: parked bus, GPS drifts back 57 m; the renderer holds (correct), then a 64 s fix gap triggers the >60 s snap, which ignores never-backward → a 60 m backward jump. Defect in 3b-1 DelayedTrackRenderer snap path, not 3b-3.
Ruling: park the snap-backward defect and the rush fixture for the motion-tune phase (fixture moved to the session scratchpad, so the suite stays green for the final review) — 3b-3 scope is follow mode; the fix belongs with the probe's 3 motion defects — cost: the defect ships in this PR until that phase lands.
Final review: base ba215f3, dispatched (fable)
Final review (fable): fix first — C1 lock-resume false "Lost contact"; I1 trip change judged on delayed drawn progress (terminus → "finished", early switch ends follow); I2 follow latched to stale previous trip; I3 CenterMove ignores padding; I4 Board row targets feed ghost; M1–M6.
Ruling: C1 — don't judge lost/notFound on pre-pause data; skip tracker updates until a post-resume snapshot arrives — cost: none.
Ruling: I1 — on a trip change before arrival, keep following on the old shape while the live fix snaps to it ahead of _p (grace cap 3 min); end tripEnded only once the fix leaves the old shape — real feed switches by timetable clock — cost: a bus that really ended may linger up to 3 min.
Ruling: I2 — if your stop is ahead on the new trip, re-latch to it instead of ending — spec invariant is same vehicle, not same trip — cost: none.
Ruling: I3 — close move honours the fit padding — cost: none.
Ruling: I4 — take it: buildTripIndex prefers the vehicle with the newest position, ignoring positions older than 5 min when a fresher one exists — it is follow's front door; I proposed it to the user, no objection yet, and it is reversible — cost: a small data-layer change outside the plan.
Ruling: M1–M6 all taken (route push throttle = first || (moved ≥ 20 m && ≥ 1 s); chip hint; arrived names the stop arrived at; offstage gap covered by I1; no recentre while following; headsign in snapshot equality) — cost: none.
Final fix wave: dispatched (opus)
Final fix wave: DONE_WITH_CONCERNS (2328301, ea09d97, 22ade72, 1ffaa14; 624 tests). Ruling: accept the I3 512-pt tile constant (78271.5 m/pt; MapLibre's zoom is defined on 512-px tiles); accept the padding offset on the solo move; accept the crossing rule while held — cost: none. Scoped re-review dispatched (fable).
Final re-review (fable): ready to merge except R1 (turnaround hold ends tripEnded without trying the I2 re-latch). Deviations accepted. Concerns a–d ship.
Ruling: fix R1 now (about 10 lines; riders following a bus to its return trip are common) — resumed the final-fix implementer — cost: none. Controller verifies R1 directly (small diff).
Parked (motion-tune): (a) Follow on a stale-labelled bus at its old terminal can end at once; (b) hold should snap the raw fix, not the state's lat/lon; DelayedTrackRenderer gap snap ignores never-backward (rush fixture 2446); probe defects 1–3.
R1: fixed 6fe66bc (626 tests); controller verified the diff (rung 2 before tripEnded on a held trip; _moveToTrip resets _p). Final review complete — ready for live parity.
Live parity (2026-10-05 ~13:52–13:59 NDT, buses running):
- iOS (iPhone 17 sim):
  - Board row → map → "Following bus 2574"; the route line is in the route colour with the driven part faded; the followed bus is larger and the others faded.
  - Bus 2574 sat at its first stop, MUN Centre → "Arrived" at once; it ended after 10 s with no toast.
  - Bus card Follow (1628): fit bus+star, "1 stop to MUN Centre · 1 min", strip correct.
  - Pan over the real UiKitView pauses → "Back to bus 1628"; the chip resumes; the close move puts bus and star above the card; "Arrived at MUN Centre" then a clean end.
  - Dark + accessibility-large: route 15 purple, card legible; chips ellipsize (as in 3b-2).
  - Debug-build input lags about 2 s, so screenshots taken too early looked like lost taps.
- Android (busboard_pixel):
  - Board row (1207) → "Finding bus 1207…" about 20 s (first poll after the map's first build), then the card, route 29 line and strip.
  - Fit then the close move; pan over the platform view pauses → Back chip; arrival → clean end; the Back chip and route cleared.
- Minor (parked): at accessibility-large text the peeking follow card shows See all stops but Stop following sits below the peek (reachable by dragging up).
- Minor (parked): "Finding bus" can take about 20 s on the first map open (stream starts with the map).
Phase 3b-3: complete (ba215f3..6fe66bc).
