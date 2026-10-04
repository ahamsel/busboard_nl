# Harbour Phase 2 — execution ledger (handoff for Phase 3)

Copied from the SDD workspace ledger at the end of Phase 2. Deferred minors and rulings below feed the Phase 3 (map / follow mode) plan.

# SDD ledger — plan: docs/superpowers/plans/2026-10-04-harbour-phase2-screens.md

Spec: docs/superpowers/specs/2026-10-04-harbour-redesign-design.md (reachable). Phase 1 handoff: docs/superpowers/notes/2026-10-04-harbour-phase1-ledger.md
Branch: claude/unified-ui-map-redesign-fc0a89 (draft PR ahamSel/busboard_nl#1) · start HEAD 9534c98
Implementers: sonnet (Phase 1 ruling). Commit trailers: each agent's own model (Phase 1 R5).

## Pre-flight scan

| Pair / task | Produces → consumes | Finding |
|---|---|---|
| T1 → T5/T9 | BBTextField(inputFormatters, errorText, focusNode, textAlign, style); BBPill.wrap; BBThemeMode; BBIcons.* | consistent with uses in T5 (stop entry), T8 (stop pills wrap), T9 (BBThemeMode) |
| T2 → T4–T9 | BBIconButton, BBTopBar(large), BBLoading, BBEmptyState(tone), BBSectionHeader(countTone), BBStepper, BBDivider(indent), BBIconTile(tone,size) | signatures match all call sites |
| T3 → T5, T8 | routeShortNamesForStop, compareRouteNames | T5 near-me pills, T8 route sort — consistent |
| T6 → T7, T10 | ArrivalRowTile(arrival), statusOf, semanticsLabel | consistent |
| T7 ↔ T8 | board uses ServiceAlertCard (legacy until T8; API preserved by T8) | consistent; T7 test asserts title + "1 more relevant alert" which T8 keeps |
| T8 ↔ legacy map sheets / bus_bottom_sheet_test | ServiceAlertCard constructor unchanged | consistent; T8 may need bus_bottom_sheet_test theme |
| T4–T9 ↔ kit_boundary_test | each task removes its files from _legacyAllowList | T10 verifies only 3 map files remain |
| T1 self | test ↔ code | agrees |
| T2 self | BBStepper semantics: ± BBIconButtons (non-container Semantics) inside a container Semantics with label/value/actions may merge into the parent node → `bySemanticsLabel('Decrease …')` fails | defect (R1) |
| T3 self | test ↔ code | agrees |
| T4 self | test ↔ code | agrees (4th test weak but non-vacuous) |
| T5 self | tests use find.bySemanticsLabel without ensureSemantics (route-pill + loading/settings tests) | defect (R2) |
| T6 self | test ↔ code | agrees |
| T7 self | timer cleanup via _unmount | agrees |
| T8 self | test ↔ code; Iterable.firstOrNull is dart:core | agrees |
| T9 self | stepper test uses bySemanticsLabel without ensureSemantics; failed-refresh fake fixed during planning | defect (R2) |
| T10 self | goldens use far-future alert end + fixed fetchedAt → stable | agrees |

## Rulings
- R1 Ruling: BBStepper's container Semantics gets `explicitChildNodes: true` (brief edited) so the ± buttons stay separate labelled nodes — accessibility requires each button operable — cost if wrong: none.
- R2 Ruling: add `ensureSemantics()` (with addTearDown dispose) to T5's route-pill and loading/settings tests and T9's stepper test (briefs edited) — bySemanticsLabel requires semantics enabled — cost if wrong: none.

## Progress
Task 1: base 9534c98, implementer a2ec0842f101cc276 (sonnet); review approved
Task 1: minor (deferred): wrap pill not tested for actual multi-line render/radius; error not tied to field semantics (liveRegion only); errorText '' treated as error; BBTextField.style undocumented (also styles hint); default BBPill now single-line ellipsis (brief-mandated; previously could wrap)
Task 1: complete (commits 9534c98..f456d12, review clean)
Ruling: P2 T2 test 'BBIconButton is a 44pt labelled button' pumps kitHost(Center(child: BBIconButton(...))) — kitHost gives children a tight 390 width, so the size assertion needs a loose parent (same pattern as RouteBadge test); assertion unchanged — cost if wrong: none
Task 2: base f456d12, implementer afc7f9e9c56fe1a38 (sonnet), head 1201a09; review: spec ✅, Needs fixes — Important: disabled BBIconButton uses c.line (~1:1 contrast, vanishes, ignores color); missing tests for disabled state and BBLoading liveRegion (plan-mandated test gap)
Task 2: minor (deferred): section header count not part of header semantics; tone→colour mapping duplicated (BBIconTile/BBPill); BBEmptyState not scrollable at 2.0 (screens wrap it in lists); top bar subtitle maxLines 1; BBDivider/BBIconTile untested; stepper unguarded step<=0; spinner ignores reduce-motion
Task 2: fix round 1/5 (2 addressed, 0 open — disabled icon visible via Opacity 0.45 on ink; disabled + liveRegion tests; commits 1201a09..ca7088f)
Task 2: complete (commits f456d12..ca7088f, review clean)
Task 3: base ca7088f, implementer a36b191db85c97d0b (sonnet), head 055a1f2; review: Needs fixes — Important (plan-mandated): compareRouteNames not a strict total order ('010' vs '10' tie; int.tryParse accepts ' 10', '+5', '0x1A')
Ruling: fix — numeric only when ^\d+$, tie-break with a.compareTo(b); add tie/sign/hex/empty tests — spec requires stable consistent order — cost if wrong: none
Task 3: minor (deferred): empty routeShortName not filtered (would render empty chip; Metrobus data has none); cache clear placed before awaits (latent; new repo per load in prod); natural alphanumeric order; method placement/format
Task 3: fix round 1/5 (1 addressed, 1 new — int.parse overflow throws on >=19-digit names from external feed; commits 055a1f2..1c1349c)
Task 3: haiku re-reviewer violated read-only (left test/gtfs_overflow_test.dart, untracked) — controller deleted it after inspection
Ruling: all remaining reviews/re-reviews use sonnet, not haiku — haiku broke the read-only rule — cost if wrong: higher spend
Task 3: fix round 2/5 (1 addressed, 0 open — overflow-safe numeric via digits-only + tryParse; total order verified by probe; commits 1c1349c..b34f1e2)
Task 3: complete (commits ca7088f..b34f1e2, review clean)
Task 4: base b34f1e2, implementer a26b1dbaa4c44a773 (sonnet), head e9b71a0; review: approved but 2 Important (plan-mandated test gaps): map-padding test near-vacuous; no safe-area/keyboard tests
Ruling: Task 5 dispatch must add keyboard avoidance to the rebuilt picker (scroll view bottom padding includes MediaQuery.viewInsetsOf(context).bottom) — BBScaffold/shell don't resize for the keyboard — cost if wrong: lower near-me rows hidden under keyboard
Task 4: minor (deferred): _mapBranch magic index; map branch sees full bottom padding (double inset) — handle in Phase 3; semantics finder not isSemantics/no selected assert; no zero-alerts case
Task 4: fix round 1/5 (2 addressed, 0 open — keyed rect assertions, safe-area + keyboard tests; commits e9b71a0..3ddbb0b)
Task 4: complete (commits b34f1e2..3ddbb0b, review clean)
Task 5: base 3ddbb0b, implementer a3aa91cc7c0a238a1 (sonnet), head 03b92b0; deviations: brief fallback for route-pill semantics; handle.dispose() at test end instead of addTearDown (R2 pattern failed: "SemanticsHandle active at end of test"); ProviderScope UniqueKey for re-pump
Ruling: correct R2 in task-9 brief to call handle.dispose() at the end of the test (addTearDown runs after the active-handle check) — cost if wrong: none
Task 5: review approved
Task 5: minor (deferred): unlisted copy case changes (Near me/Last stop/Go/Try again/'Stop number' label, distance merged into caption, 0000 hint gone) — add to behaviour-change notes; alphanumeric routes all map to RoutePalette.of(0) via int.tryParse ?? 0 (affects T6/T8 too; all 22 current Metrobus routes numeric) — recommend label-based palette fallback in final wave; route pills capped at 6 without +N; loading/error slightly scrollable; untested: tap-outside dismiss, onSubmitted, retry/refresh invalidate paths; last-stop label duplication when name unknown
Task 5: complete (commits 3ddbb0b..03b92b0, review clean)
Task 6: base 03b92b0, implementer aec86fc50a0377ff8 (sonnet), head eeda416; deviation: minutes column wrapped in LayoutBuilder+ConstrainedBox(maxWidth 0.45*row) to pass 2.0/320 overflow test
Task 6: review approved (reviewer probe with real fonts: no overflow; 0.45 cap is Ahem-driven, net-neutral)
Task 6: minor (deferred): cap only needed for Ahem test — load fonts in overflow test or comment the cap; headsign maxLines 1 unreadable at 2.0 (consider 2 lines at large scale) — recommend final wave; semantics sentence drops vehicle/near/exp times vs legacy (a11y trade-off) — recommend adding delay/clock detail; route-colour test doesn't check colour; ' • '→' · ' separator; shared non-numeric route fallback helper
Task 6: complete (commits 03b92b0..eeda416, review clean)
Task 7: base eeda416, implementer acf927e3167a8fb7b (sonnet), head 453cd30; deviation: ref.listen(gtfsRepositoryProvider) in build triggers _refreshData when schedule first loads
Ruling: accept the gtfs listen — legacy board stayed on "Schedule data not loaded" until the next timer tick when opened before GTFS resolved (deep link / test); refreshing on first load is what a rider expects; add to behaviour-change notes — cost if wrong: one extra refresh on load
Task 7: review: Needs fixes — Important (plan-mandated): status liveRegion includes seconds timestamp → re-announced every refresh
Ruling: live region carries only the state ("Live" / "<issue> · showing schedule"); timestamp in a separate non-live text; ALSO silence kiosk HTTP-500 debug noise in tests by giving MetrobusMobileApi a 200 '{"arrivals":[]}' MockClient (pristine test output rule) — cost if wrong: none
Task 7: minor (deferred): pull-to-refresh only asserted by type; no isSemantics header/live-region assertions; no large-text pass on header row; transient "Live unavailable · showing schedule" before first load; listener type annotation
Task 7: fix round 1/5 (2 addressed, 0 open — live region state-only + separate timestamp; quiet kiosk fixture; commits 453cd30..31bcaef)
Task 7: complete (commits eeda416..31bcaef, review clean)
Task 8: base 31bcaef, implementer a9f8c615fdf316304 (sonnet), head 7b0c3a0; deviation: effect pill omitted when the title equals the effect label (header empty or same text)
Ruling: accept — a duplicate "Detour"/"Detour" pill adds nothing; the effect is still conveyed by the title and icon tile tone — cost if wrong: one fewer pill on header-less alerts
Task 8: review approved
Task 8: minor (deferred): _hasEnded duplicates ServiceAlert.hasEndedBefore (plan-mandated — controller's planning grep missed the alert-level getter); route sort order not asserted; no tests for settings button/pull-to-refresh/count tone/isSemantics on compact card; stray 5pt gap above empty Wrap; compact title fontSize 14 literal; ListView relies on global BBScrollBehavior for always-scrollable
Task 8: complete (commits 31bcaef..7b0c3a0, review clean)
Task 9: base 7b0c3a0, implementer ad607d04093705d43 (sonnet), head 9939c98; test-harness deviations: ensureVisible before tap (600pt view); ProviderContainer(retry: null) because Riverpod 3 auto-retries failed providers (~38 s)
Ruling: keep production retry — a failed schedule refresh shows "Downloading..." while Riverpod retries (~38 s) then the toast; that's truthful (still trying) and far better than legacy (stuck forever); changing gtfsRepositoryProvider retry affects the picker's auto-recovery — cost if wrong: slow failure feedback in Settings
Task 9: review: Needs fixes — Important (plan-mandated tests): 2.0 test vacuous below fold + real overflow in "Last updated:" Row (88px at 320/2.0, Ahem); missing tests for disabled-while-running, force-refresh flag, legacy system→Match app, stepper bounds/out-of-range, semantics
Task 9: minor (deferred): unlisted copy case changes & dropped icons/spinner/side safe areas; segment labels ellipsize at 2.0; segmented groups lack group label; out-of-range stored interval shown clamped but timer uses raw; toast lifted for nav bar on Settings (kit-wide); no busy spinner during retry window
Task 9: fix round 1/5 (2 addressed, 0 open — Text.rich last-updated; scroll-through 2.0 test; tests a–e; commits 9939c98..9681980)
Task 9: minor (deferred): invalidate not verified by success test; (c)/(e) weakly discriminating; stored interval not clamped in provider (display vs polling mismatch); ThemeMode.values[...] throws on corrupt pref
Task 9: complete (commits 7b0c3a0..9681980, review clean)
Task 10: base 9681980, implementer a86e66ba36d5db678 (sonnet), head 61cc8cb; review approved; Step 5 parity run = controller, after final review
Task 10: minor (deferred): dark selected segment faint (<3:1 indicator) — kit-level, recommend final wave; arrival-rows golden finder find.byType(Column).first fragile; goldens macOS-bound; no golden for Upcoming/board header/picker; brief said two alerts but code has one
Task 10: complete (commits 9681980..61cc8cb, review clean)
## Final review (fable a6865e30…, 9534c98..61cc8cb): With fixes — 0 Critical, 6 Important
Ruling: one fix wave covers Important #1 (alerts error/loading scrollable + refreshable), #2 (period row Flexible; use ServiceAlert.hasEndedBefore), #3 (board header Flexible), #4 ("Checking live data…" + silent live region while loading), #5 (show all route pills), #6 (selected segment brandSoft/brandInk or brand border, ≥3:1, both modes); plus minors #7 RoutePalette.ofName/RouteBadge.name (stable hash), #8 sentence adds expected time, #9 explicit AlwaysScrollable physics, #10 clamp stored interval in provider, #11 all-screens 320/360 ×2.0 overflow test, #12 behaviour-change doc — cost if wrong: goldens regenerate; small copy/visual changes
Deferred to Phase 3 plan: BBSheet pinned header + animateToDetent + grab-handle semantics; floating chips/controls; drop _mapBranch padding; BBScaffold(reserveNavBar); toast offset on Settings
Ruling: accept moving the board's relevant-alert block into the top of the scrolling list — found by the new overflow guard (93 px at 320/×2.0); header stays fixed, alerts scroll with departures — cost if wrong: alert scrolls away with the list
Final fix wave: sonnet fixer, commits 61cc8cb..dfb8391 (7 commits); scoped re-review (sonnet a0ccb5c6…): all 12 addressed, no new Critical/Important; analyze clean, flutter test +269 ~6 all passed
Final wave: minor (deferred): board "Schedule data not loaded" error state still says "Live unavailable · showing schedule" as a live region (pre-existing); first arrival row loses 8 px top gap under the board alert block; board overflow scenario has no arrival rows (fixture repo has no calendar)
Parity (controller): Android emulator — picker, board (live), alerts, settings OK; iOS simulator BusBoard iPhone 17 (dark) — picker, board (live; Early/On time/Late/Scheduled pills, alert card scrolls in list), settings (brand-outlined selected segment clearly visible), alerts, edge-swipe back OK
## Phase 2 complete (HEAD dfb8391)

## Rulings I made (summary)
- R1/R2: BBStepper explicitChildNodes; ensureSemantics + handle.dispose() at test end
- BBIconButton size tests wrap in Center (kitHost forces tight width)
- compareRouteNames: numeric only for ^\d+$, string tie-break (strict total order)
- reviewers on sonnet, not haiku (read-only rule broken); each agent uses its own model trailer
- picker keyboard avoidance via viewInsets padding
- board refreshes once when the schedule first loads (gtfs listen)
- board live region carries state only; timestamp separate and silent
- alert effect pill omitted when the title equals the effect label
- production Riverpod retry kept for the schedule refresh (tests opt out with retry: null)
- one final fix wave for 6 Important + 6 minor; board alert block moved into the scrolling list
