# SDD ledger — plan: docs/superpowers/plans/2026-10-05-harbour-phase3b2-map.md
Spec: docs/superpowers/specs/2026-10-04-harbour-phase3-design.md (§3.1–3.3, 3.6, 2.4)
Branch: claude/unified-ui-map-redesign-fc0a89; plan commit f9feae5

## Preflight scan
| Pair / task | Produces → consumes | Finding |
|---|---|---|
| T1↔T7 | MapStyle.assetFor/brightnessFor → screen style + layer brightness | consistent |
| T2↔T4 | MarkerImages ids + badge/notch/myStop → MapLayers | consistent (notch id via RoutePalette.ofName('10') == of(10)) |
| T3↔T4 | HeadingSmoother.smooth/prune → busMarkers | consistent |
| T4↔T7 | MapSurface/MapCamera, busMarkers, MapLayers, hit-test fns, FakeMapSurface → screen + screen test | consistent |
| T4(rename)↔T5–T8 | BusTrackingState.lat/lon/heading → all later code/tests | consistent after plan edit (rename is T4 Step 0) |
| T5↔T6 | stopArrivalsProvider, schedDiffMins → cards | consistent |
| T6↔T7 | StopCardHeader/Body, BusCardHeader/Body, MyStopCard.header/body → sheet | consistent; T6 Interfaces prose names MyStopHeader/ConsumerWidget but code uses private _MyStopHeader / StatelessWidget StopCardHeader |
| T6↔T7 | T6 deletes bus/stop_bottom_sheet; map_screen imports them until T7 | conflict → R1 |
| T7↔T8 | BBSheet keyed per selection (T7); T8 edits BBSheet.build only | consistent |
| T1 self | tests ↔ code; committed-styles test needs the generator run (network) | ok |
| T2 self | sampled pixels avoid text; sizes via badgeSize | ok |
| T3 self | test arithmetic checked (45° per 250 ms; -90→270) | ok |
| T4 self | install order, dedupe, reload, my stop | ok; `enableInteraction` may not exist on addSymbolLayer (plan gives fallback) |
| T5 self | fakes extend real APIs; fetchDeparturesResult signature to mirror | ok |
| T6 self | test strings match code | ok |
| T7 self | stub map; no pumpAndSettle (ticker); BBSheet re-key with shared controller flagged in plan | ok, risk carried |
| T8 self | hairline test helper usage approximate ("adapt") | ok |

Ruling: R1 — Task 6 does not delete bus_bottom_sheet.dart / stop_bottom_sheet.dart / test/bus_bottom_sheet_test.dart; Task 7 deletes them with the screen rewrite — map_screen imports them until Task 7, so deleting earlier breaks the build — cost if wrong: none.
Ruling: R2 — where a task's Interfaces prose and its code block disagree on a widget's class name or base class, the code block governs — the code is what later tasks reference — cost if wrong: none.
Task 1: base f9feae5
Task 1: implementer dispatched (sonnet)
Task 1: implementer DONE (50d571d); review dispatched
Task 1: review — Approved; minors: shield/airport/place-dot sprites keep Positron light colours. Ruling: drop highway-shield-non-us and airport, strip icon-image from place labels — spec §3.1 removes POI icons; airport icon is one and the shield is unreadable in dark — cost if wrong: route shields absent at zoom 11+.
Task 1: minor polish 276b81e (controller-verified: no icon-image/airport/shield in assets; 11/11 tests)
Task 1: complete (commits f9feae5..276b81e, review clean)
Task 1: minor (deferred): ne2_shaded raster source still declared but unused
Task 2: base 276b81e
Task 2: implementer DONE (e7c6dd6); review dispatched
Task 2: review — Needs fixes (I1 notch base 17 px from centre overlaps 3-char badges at E/W headings — plan-mandated constants; I2 tests miss text/corner/star). Ruling: notchBox 64 with base at y 10.5 (21.5 px from centre) and a test, with app fonts loaded, that the base clears badgeSize('10A') half-width + 1 — the notch layer sits below the badge (Task 4), so an overlapping notch would simply vanish at E/W headings — cost if wrong: notch slightly further from short badges. Also take minors: fractional-ratio canvas scale, try/finally disposal, TextPainter dispose, sublistView.
Task 2: fix round 1 implementer DONE (8705d2b); re-review dispatched
Task 2: fix round 1/5 (2 addressed, 0 open; commits e7c6dd6..8705d2b) — probe: 0 overlap px at 8 headings
Task 2: complete (commits 276b81e..8705d2b, review clean)
Task 2: minor (deferred): clearance test hardcodes 10.5 base offset; staleFill/staleInk not dark-aware (eyeball at parity)
Task 3: base 8705d2b
Task 3: implementer DONE (02eda18); review dispatched
Task 3: review — Needs fixes (I1 NaN/inf target poisons state; I2 tests don't prove counter-clockwise path). Ruling: also take M3 (never return 360.0), M4 (backward clock re-anchors/snaps instead of freezing), M5 (2 s boundary + prune isolation tests) — all cheap — cost: none.
Task 3: fix round 1 implementer DONE (a91cc64); re-review dispatched
Task 3: fix round 1/5 (3 addressed, 2 open — I1 _state.remove regression (consecutive NaN → 0°); M5 2 s boundary untested; commits 02eda18..a91cc64)
Task 3: fix round 2 implementer DONE (9d06b4e); re-review dispatched
Task 3: fix round 2/5 (2 addressed, 0 open; commits a91cc64..9d06b4e)
Task 3: complete (commits 8705d2b..9d06b4e, review clean)
Task 3: minor (deferred): backward-clock test's second assertion snaps via >snapGap (misleading reason string)
Task 4: base 9d06b4e
Task 4: implementer DONE (772baa4, 31d213f); note: Task 7 creates a new MapLayers per style load (plan already does); review dispatched
Task 4: review — Needs fixes (I1 _images marked before addImage succeeds → bus badge missing all session after one failure). Ruling: also take M1 (busLabel: case-insensitive 'Rt', '?' unless ^[0-9]+[A-Za-z]?$), M3 (tapRadius 200/2^(zoom-13) clamped zoom 13–18; update tests), M4 (notch layer sort key) — cheap and rider-visible — cost: none. M2 (updateBuses re-entrancy) is covered by Task 7's _frameInFlight guard; verify in Task 7 review.
Task 4: fix round 1 implementer DONE (436547b); re-review dispatched
Task 4: fix round 1/5 (4 addressed, 0 open; commits 31d213f..436547b)
Task 4: complete (commits 9d06b4e..436547b, review clean)
Task 4: minor (deferred): no test asserts serialised layer props (rotation alignment, allow-overlap); updateBuses re-entrancy relies on Task 7 _frameInFlight guard (check in Task 7 review)
Task 5: base 436547b
Task 5: implementer DONE (9d11199); review dispatched
Task 5: review — Needs fixes (I1 Fleet View fallback maps NO DATA/unknown opStatus to 0 diff + 'ON TIME', so schedDiffMins reads on-time when unknown). Ruling: fix at the adapter — in _fleetRowToVehicle, delayMins = null unless opStatus is BEHIND/LATE/EARLY/AHEAD/ON TIME; correct the store comment; add a Fleet View NO DATA test expecting null — the store cannot tell unknown from on-time once the adapter writes 'ON TIME' — cost if wrong: Fleet View NO DATA rows lose their 'ON TIME' text on the board (they never had real data). Minor (deferred): cold-start extra fetch when stored interval ≠ 5 (same as tracking stream); no fakeAsync test of refresh/disposal; fetch logic duplicated with board screen.
Task 5: fix round 1 implementer DONE (575e7c0); re-review dispatched
Task 5: fix round 1/5 (1 addressed, 0 open; commits 9d11199..575e7c0)
Task 5: complete (commits 436547b..575e7c0, review clean)
Task 5: minor (deferred): legacy TimeTrack fallback mapper not audited for unknown-vs-on-time; mixed Fleet View duplicates now prefer known-status row
Task 6: base 575e7c0
Task 6: implementer DONE (ee5aa1a); review dispatched
Task 6: review — Approved (0 Critical/Important)
Task 6: complete (commits 575e7c0..ee5aa1a, review clean)
Task 6: minor (deferred, final-wave candidates): stale bus still shows last-fix lateness; loading vs vanished both say "no longer reporting"; toggle uses label not Semantics(expanded:); my-stop header keys on stopInfo while body keys on stopId (repo loading → mismatch); your-stop star not announced; thin tests for stale pill/null delay/alerts/disabled "Your stop"; kit BBButton label on child semantics node (device check)
Task 7: base ee5aa1a
Task 7: implementer DONE_WITH_CONCERNS (430ea6f)
Ruling: accept per-selection BBSheetController (Flutter's DraggableScrollableSheet attaches the new state before disposing the old, so one shared controller asserts "already attached") — cost: a controller allocation per selection, disposed post-frame.
Ruling: accept ref.listen(busTrackingStreamProvider) in build to keep the feed live before the first frame — the old screen watched it too — cost: none.
Task 7: review dispatched (review-task7.diff)
Task 7: review — Needs fixes (I1 credit link off-screen/landscape and far above peek at ×2, unbounded width, fixed 200 i-margin — plan-mandated formula; I2 first My location tap no-op; I3 _onStyleLoaded no mounted check, failed install leaves dead _layers; I4 no screen test of per-frame drawing)
Ruling: credit geometry from the sheet's real peek top (BBSheet insets + clamped fraction), credit text clamped to text scale 1.3, single line, bounded width (left..right margin) and its bottom clamped below the chip/pill column; MapLibre "i" x-margin = measured credit width + gap at the same baseline — spec §3.1 "always visible above the sheet" — cost if wrong: tiny credit at huge text sizes.
Ruling: My location after a fresh grant awaits the next frame and retries camera.myLocation() a few times, falling back to Geolocator.getCurrentPosition — cost: none.
Ruling: also take minors: clear _retiredSheets in dispose; try/catch updateMyStop; credit tap target ≥ 44 pt; chips and control pill in one Column so the pill always clears the chips; skip frames when TickerMode is disabled (map tab offstage); wrap _drawFrame body in try; watch stopInfo in build. Reword §3.1 amendment to match.
Task 7: fix round 1 implementer DONE (03d2e98); re-review dispatched
Task 7: fix round 1/5 (4 Important + 7 minors addressed, 0 open; commits 430ea6f..03d2e98)
Task 7: complete (commits ee5aa1a..03d2e98, review clean)
Task 7: minor (deferred): Geolocator.getCurrentPosition has no timeLimit; rapid double style switch can interleave native installs (layerAlreadyExists → _layers null until next load); "i" spacing only verifiable on device
Task 8: base 03d2e98
Task 8: implementer DONE (91f205a); review dispatched
Task 8: review — Approved
Task 8: complete (commits 03d2e98..91f205a, review clean)
Task 8: minor (deferred): dark test doesn't assert the foreground box wraps the ClipRRect; golden capture uses find.byType(Stack).first
Final review: dispatched (fable) on f9feae5..91f205a
Final review (fable): fix first — Important 4 (I1 credit BBPressable is a full-width 44 pt opaque band swallowing map taps above the sheet; I2 choosing a new stop no longer moves the map to it; I3 README describes the old map; I4 stopArrivalsProvider polls two feeds while backgrounded), Minor 5. Deferred-minor triage: none blocking.
Ruling: one fix wave for I1–I4 plus Minor 1 (serialise style installs), Minor 3 (bus card badge uses busLabel), Minor 5 (stop the ticker while TickerMode is disabled) — all small and rider-visible — cost: none.
Final fix: a5dc154 (DONE). Note: implementer used git stash briefly against the rules; verified stash list empty and pre-existing analysis_options.yaml change intact.
Final review: re-review clean (7/7 addressed). Out-of-scope minors: cold-start one recentre when settings load; superseded install on same native style.
Parity (iOS sim, 03:18 NDT, no live buses — feed empty overnight): Harbour light + dark styles render; theme switch reloads style and re-adds your-stop star; chips, control pill, credit link, peeking sheet OK; tap stop → stop card at half; tap empty → back to your stop. Finding: MapLibre "i" sits ~40 pt above the credit on iOS (MLNMapView adds the bottom safe-area inset to the margin). Watch: first tap after a screenshot sometimes ignored (likely simulator-tool focus, also on Settings) — check by hand. Android + live buses pending.
Ruling: on iOS subtract MediaQuery.padding.bottom from the attribution y margin — MLNMapView measures from the safe area — cost if wrong: "i" sits low by the inset.
Parity (iOS sim relaunch, build 1f372c5): 'i' now beside credit ✓. BUG: layers missing — log 'Could not install map layers: PlatformException(sourceAlreadyExists … bb-stops)'. onStyleLoaded fires twice for one native style; serialized second install collides and leaves _layers null. Ruling: make MapLayers.install idempotent on the same style (best-effort removeLayer/removeSource before each add, via MapSurface) and confirm the double-fire cause in maplibre_gl iOS source — cost if wrong: a few wasted platform calls per reload. Also noted: Kiosk HTTP 403 every 5 s from stopArrivalsProvider's stop-prediction fetch (Metrobus kiosk forbidden; board does the same) — deferred.
Parity fixes: 1f372c5 (iOS attribution margin), 11ddee4 (idempotent install; cause: iOS sets styleURL twice at init, both didFinishLoading emit onStyleLoaded). Relaunch verified: star + layers present, no install error in log. Scoped re-review dispatched.
Parity fixes re-review: clean. Phase 3b-2 complete; live-bus + Android parity pending (feed empty overnight).

## Live parity (iOS simulator, 2026-10-05 10:24 NDT, ~40 live buses)
- Badges + notches render in route colours; 19 s recording at 1 fps shows steady forward motion along roads, no jumps or backsteps; stopped buses hold.
- Bus card: "Route 16 · Bus 1628 · 4 min early · Live" — destination missing (GTFS-RT carries no headsign).
- Peek: your-stop header with 2 arrivals is taller than the fixed 168 pt peek, so the 2nd row is clipped.
- Returning from a bus card to your stop flashes the arrivals skeleton (stopArrivalsProvider auto-disposed while unwatched).
- Rush-hour monitor (scheduled task) restarted captures at 09:34; early finding: route 18 trip 262894 assigned to bus 1311 (live) and 1629 (frozen, 11+ min old) — the 3b-1 store drops fixes > 5 min old, so 1629 never reaches the map.
Ruling: polish round — peek fraction from the measured header height; bus card destination falls back to the GTFS trip headsign; keep the selected stop's arrivals alive across selection changes — all rider-visible, small — cost: none.
Live polish: f342f5f — re-review clean; verified on iOS sim (peek fits 2 rows; bus card "to AVALON MALL – MUN CENTRE…", 7 min late, route detour alert).
Minor (deferred): peek change mid-drag drops the gesture (rare); fallback→measured peek re-snap one frame after each selection; selection change refetches watched stop providers once (narrow the select to `== stopId`).
Android parity (emulator API 36, 11:16 NDT, live buses running): map tiles, your-stop star, chips, credit, peek with 2 live arrivals OK; NO BUSES drawn after >1 min; no MapLibre 'i' visible; logcat shows one '[Map] Live-data poll failed: All live feeds failed; legacy TimeTrack returned HTTP 404' at 11:15:06 then nothing. iOS draws buses fine. Root cause unknown — debugging dispatched.
Android root cause (d3a7d84): updateBuses published only after rendering every new marker image (1.5–3 s each on the emulator's software raster) → empty map for minutes; Android attribution margin double-scaled (plugin multiplies by density) → "i" off-screen. Fix: publish buses as their images become ready; margins in logical px. Re-review clean; full suite 508 pass (TZ=UTC and local). Android emulator now shows badges+notches and the "i" beside the credit.
Minor (deferred): an in-flight updateBuses across a style reload can publish old-instance image ids onto the new style until it finishes; a bus needing a new image (turned stale) blinks off until ready; failed image still referenced in the final publish (as before).
