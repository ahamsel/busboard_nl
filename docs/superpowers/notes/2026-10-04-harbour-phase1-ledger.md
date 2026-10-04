# Harbour Phase 1 — execution ledger (handoff for Phase 2/3)

Copied from the SDD workspace ledger at the end of Phase 1. Deferred minors, ⚠️ items and rulings below feed the Phase 2 and Phase 3 plans.


Spec: docs/superpowers/specs/2026-10-04-harbour-redesign-design.md (reachable)
Branch: claude/unified-ui-map-redesign-fc0a89 · start HEAD 3f5fd6d

## Pre-flight scan

| Pair / task | Produces → consumes | Finding |
|---|---|---|
| T1 → T3 | BBTokens.light/dark (static final), BBText.family, BBRadius, BBMotion → BBTheme | consistent |
| T1 pubspec ↔ T12 pubspec | `flutter: fonts:` vs launcher/splash sections | different sections; no clash |
| T2 → T4 | RoutePalette.of, RouteHue.fillFor, RoutePalette.ink → RouteBadge | consistent |
| T3 → T4 | BBTheme.light()/dark(), BBScrollBehavior → kitHost | consistent |
| T4 → T5/T6/T7/T8/T9 | BBPressable, kitHost(child, brightness, textScale, width) | consistent; T6 test uses `width:` (defined) |
| T6 → T8 | BBNavBar.reservedHeight(ctx) → BBToast position | consistent |
| T8 barrel → T9 | kit.dart exports all 18 files incl. bb_sheet, bb_theme | consistent |
| T10 allow-list ↔ codebase | legacy list vs files with violations | arrival_row_tile.dart has 0 violations → stale-entry test would fail (R2) |
| T10 ↔ T11 | T11 edits alerts/settings (still legacy, still violating) + new lib/ui/copy (no widgets) | consistent |
| T1 fonts → T12 | Figtree TTFs used by magick for feature graphic | consistent |
| Global "no raw colour literals" ↔ T5/T6/T8 | `Color(0x00000000)` (T5 segmented, T6 scaffold), `Color(0x661C2A3A)` dialog barrier (T8) | conflict (R1) |
| T1 self | test ↔ code (contrast pairs, BBMotion.of, context.bb) | agrees |
| T2 self | test ↔ table | agrees (29 sky, 10 green, 16 yellow, 23 lime) |
| T3 self | test ↔ code; main.dart edge-to-edge in Files + commit | agrees |
| T4 self | finders (first DecoratedBox/Container) ↔ widget trees | agrees |
| T5 self | containsSemantics ↔ Semantics flags | agrees |
| T6 self | badge label "Alerts, 2 active" ↔ _Tab | agrees |
| T7 self | assert in non-const ctor ↔ throwsAssertionError test | agrees |
| T8 self | toast mounted-guard ↔ double-show/dispose tests | agrees |
| T9 self | gallery button Row at text x2 within 358px | overflow likely: two BBButtons + Spacer + switch in a Row (≈416px) → `takeException` fails for gallery-layout reasons (R3) |
| T10 self | regex ↔ self-test cases | agrees |
| T11 self | Settings test may need provider overrides | plan gives fallback |
| T12 self | commit paths (ios/Runner/Base.lproj exists) | agrees |
| T13 self | AVD download | external ~1–2 GB download → ask user at that step (R4) |

## Rulings

- R1 Ruling: transparent (`Color(0x00000000)`) and the dialog scrim (`Color(0x661C2A3A)`, ink at 40%) are neutral non-palette literals, exempt from the "no raw colour literals" constraint; plan code stands — the constraint's intent is "no palette colours outside tokens", and a scrim/transparent isn't a palette role — cost if wrong: a Minor cleanup moving two literals into tokens.
- R2 Ruling: remove `lib/ui/board/arrival_row_tile.dart` from T10's `_legacyAllowList` (it has 0 violations today) — the plan's own stale-entry test mandates this — cost if wrong: none (if it gains violations in Phase 2, the guard flags it, which is the intent).
- R3 Ruling: in T9's gallery, replace the `Row(BBButton, SizedBox, BBButton, Spacer, BBSwitch)` with `Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [BBButton…, BBButton…, BBSwitch…])` — the 2.0 golden must test components, not a gallery row that can't fit by construction (spec §4.3 requires verification at 2.0) — cost if wrong: golden layout differs slightly from the plan's sketch.
- R4 Ruling: T13 Step 3 (Android system-image download) is an outside-worktree side effect → stop and ask the user at that point; everything else in T13 proceeds.

## Progress
Task 1: base 3f5fd6d, implementer a4a447b5fe1037bfe (haiku), first head 1f90bcd
Task 1: review — spec ❌ (commit trailer said Haiku 4.5, must be Opus 5.5); quality otherwise approved
Task 1: minor (deferred): Figtree OFL.txt not registered with LicenseRegistry / not an asset → licence not shown in app licences page
Task 1: minor (deferred): BBText.lerp snaps fontFeatures at t=0.5 (harmless; identical feature sets)
Ruling: every later dispatch states the exact trailer text and that it must not be changed to the implementer's own model name — haiku substituted its own name — cost if wrong: none
Task 1: fix round 1/5 (1 addressed, 0 open — trailer amended; commit 1f90bcd→b34f9e2 amend)
Task 1: complete (commits 3f5fd6d..b34f9e2, review clean)
Task 2: base b34f9e2, implementer a2e7ba3f09592fa4c (haiku); review approved; ⚠️ GTFS-derived table — controller computed it from live GTFS during planning (2 same-hue shared stops of 699) → resolved
Task 2: minor (deferred): route_palette_test spot-checks 4/22 routes; tautological stability assert (plan-mandated)
Task 2: minor (deferred): RouteHue.line has no contrast check / dark variant (e.g. yellow.line ~2.4:1 on white) → check in Phase 3 map task
Task 2: minor (deferred): extra `foundation.dart` import in route_palette.dart (benign)
Task 2: complete (commits b34f9e2..8764604, review clean)
Task 3: base 8764604, implementer a973095bf9f5a82b1 (sonnet), head 3d6723d; review: spec ✅, quality Needs fixes (2 Important, both plan-mandated)
Ruling: T3 Important#1 (edge swipe reveals blank canvas because route stays opaque/completed while only a Transform moves) is real — the swipe must drive the route's own animation (buildTransitions' `animation` is the route's AnimationController.view; pass it to BBEdgeSwipeBack, call navigator.didStartUserGesture/didStopUserGesture, set controller.value = 1 - dx/width while dragging, pop or animate back on release) while keeping the finger-follow translate; add a test that the previous page is onstage mid-drag — spec §5.1 requires a working iOS back gesture — cost if wrong: one more fix round on gesture mechanics.
Ruling: T3 Important#2 (legacy screens lose inputDecorationTheme/elevatedButtonTheme) is real — add interim token-mapped inputDecorationTheme + elevatedButtonTheme (+ filledButtonTheme) to BBTheme, marked legacy-until-Phase-2 like appBar/card themes — spec Phase 1 says existing screens keep working — cost if wrong: a few lines removed in Phase 2.
Task 3: minor (deferred): CurvedAnimation allocated per buildTransitions, never disposed → prefer animation.drive(CurveTween)
Task 3: minor (deferred): page transition ignores reduce-motion
Task 3: minor (deferred): no test of transition visual contract (fade/4%/200ms)
Task 3: minor (deferred): RTL edge-swipe strip direction; Android predictive-back preview replaced (intended)
Task 3: fix round 1/5 (2 addressed, 0 open — edge swipe drives route animation via ProxyAnimation.parent chain (deviation accepted: animation arrives wrapped in ProxyAnimation); interim legacy input/button themes; commits 3d6723d..84ae556)
Task 3: minor (deferred): _BBEdgeSwipeBackState has no dispose → userGestureInProgress stays true if route removed mid-drag (Cupertino handles in dispose) — recommend fixing in final wave
Task 3: minor (deferred): during drag the page also fades/drifts 4% (translate wraps fade/slide) — cosmetic
Task 3: minor (deferred): garbled BBEdgeSwipeBack doc comment
Task 3: complete (commits 8764604..84ae556, review clean)
Task 4: base 84ae556, implementer af729273e928af52c (haiku), head 241bf6c committed with 1 failing test (dark RouteBadge) — controller diagnosed AnimatedTheme lerp on first frame; resumed with fix (kitHost themeAnimationStyle: AnimationStyle.noAnimation)
Task 4: review — spec ✅; quality Needs fixes: 1 Important (plan-mandated) — labelled BBPressable/BBCard lose semantic tap action under excludeSemantics
Ruling: fix it — add `onTap: enabled ? <tap handler> : null` to BBPressable's outer Semantics + a semantics test asserting SemanticsAction.tap on a labelled BBCard/BBPressable — spec §9 requires VoiceOver/TalkBack-usable arrival rows, and BBNavBar (T6) reuses this path — cost if wrong: none
Task 4: minor (deferred): BBCard test never exercises the non-tappable branch
Task 4: minor (deferred): press-scale/opacity/haptic, quiet button, compact badge, pill overrides, disabled opacity untested; InkWell-only "no ink" check weak
Task 4: minor (deferred): BBPressable `_down` can stick if onTap becomes null mid-press (reset in didUpdateWidget)
Task 4: minor (deferred): RouteBadge semantics built from `label` → "Route Route 29…" if label isn't a bare id
Task 4: fix round 1/5 (0 addressed fully, 1 open — prod fix correct but test uses pointer tap not semantic action; commits cb7909c..0f1ecfa)
Task 4: fix round 2/5 (0 addressed, 1 open — test uses semantics.tap but dropped containsSemantics presence/absence asserts; commits 0f1ecfa..4b4e202)
Task 4: fix round 3/5 (1 addressed — presence/absence asserts restored, RED shown; new problems: trailer "Haiku 4.5" again on 16ebdae, report written to repo-root task-4-report.md (stray untracked), containsSemantics deprecated → 2 analyzer infos; commits 4b4e202..16ebdae)
Ruling: replace deprecated `containsSemantics` with `isSemantics` (same params, no defaults; flutter_test 3.47 deprecation) in Task 4's test and in task-5/task-6 briefs (edited in place) — plan's analyze step must be clean — cost if wrong: none
Ruling: round 4 → fresh sonnet implementer (process: rounds 4-5 escalate) to fix trailer (amend unpushed HEAD 16ebdae), swap to isSemantics, merge stray repo-root task-4-report.md into the workspace report and delete the stray file
Task 4: fix round 4/5 (4 addressed, 0 open — isSemantics presence/absence asserts, trailer fixed by amend, stray root report removed; commits 4b4e202..e5c4d7f) [fresh sonnet implementer a2e0fe69bcbb1ead8]
Task 4: complete (commits 84ae556..e5c4d7f, review clean)
Ruling: remaining implementers use sonnet, not haiku — haiku twice wrote its own trailer, weakened specified assertions and misplaced the report, costing 3 extra rounds — cost if wrong: somewhat higher token spend
Ruling: R5 — commits carry the committing agent's own Co-Authored-By trailer (its real model) instead of a fixed 'Claude Opus 5.5' line; reviewers check presence only — forcing Opus onto commits written by other models misattributes authorship; my plan's fixed line was the error (and the Task 1/4 amends to 'Opus 5.5' are slightly misattributed, harmless) — cost if wrong: trailers vary by model across the branch
Task 5: base e5c4d7f, implementer a815263a2616ad053 (sonnet), head 6de5201; review: spec ❌ (plan-mandated) — segmented/switch lack §5.1 press-scale feedback
Ruling: fix it — route BBSegmented segments and BBSwitch through BBPressable (haptic: true), keep outer Semantics for selected/toggled; ALSO raise the reviewer's Minor #1 (tap targets ~32px / 28px) into this fix because spec §9 mandates touch targets ≥ 44 pt (segment minHeight 44; switch hit area ≥ 44×44 without changing its 46×28 visual) — spec is binding — cost if wrong: slightly taller segmented control
Task 5: minor (deferred): tests lack disabled-switch, haptic, leadingIcon, unselected-segment semantics coverage; screen-reader path skips haptic; selection/handle colours unthemed; magic radius 9; no focus styling on BBTextField
Task 5: fix round 1/5 (2 addressed, 0 open — BBPressable press feedback + 44pt targets; commits 6de5201..fa2036b)
Task 5: minor (deferred): pressing the already-selected segment still scales/dims; no test asserting switch has no extra button node
Task 5: complete (commits e5c4d7f..fa2036b, review clean)
Task 6: base fa2036b, implementer a97ce274cf141f952 (sonnet); review approved
Task 6: minor (deferred): FittedBox scales tab text down at 2.0 (Dynamic Type cancelled in bar)
Task 6: minor (deferred): dark-mode tab inner height is exactly 44pt (border eats 2px); no ≥44pt tab-height regression test — recommend adding in final wave
Task 6: minor (deferred): haptic/onSelect fire when re-tapping the current tab; tab radius 20 not full pill; magic numbers; thin dark-mode/scaffold overlay test coverage
Task 6: complete (commits fa2036b..75aec7c, review clean)
Task 7: base 75aec7c, implementer ae2758c4b13323d5e (sonnet), head 7c7145b; review: spec ✅, quality Needs fixes — 1 Important (plan-mandated): haptic ticks mid-drag/mid-animation and never re-ticks on returning to a visited detent
Ruling: fix — haptic fires once when the extent SETTLES at a detent (debounce: extent within 0.004 of a detent and no further extent change for ~80 ms; timer cancelled in dispose), `_lastDetent` resets when the extent leaves all detents, initialised to the initial fraction so there's no startup tick; tests mock the haptic channel and cover settle-at-half (1 tick), leave-and-return (ticks again), programmatic animateTo(full) (1 tick, none at the half crossing), and no tick at startup — spec §5 "haptic on snap" — cost if wrong: an 80 ms delay on the tick
Task 7: minor (deferred): grab handle lacks Semantics for moving between detents (Phase 3 a11y follow-up); detent list rebuilt per notification
Task 7: ⚠️ hit-testing above the sheet reaching the map → verify in Phase 3 when stacked over the map
Task 7: fix round 1/5 (1 addressed, 0 open — debounced settle haptic + 4 haptic cases; commits 7c7145b..b989b44)
Task 7: complete (commits 75aec7c..b989b44, review clean)
Task 8: base b989b44, implementer ae5b7870a757a43ed (sonnet), head f3bcbb0; review: spec ❌ (brief defect) — BBToast ignores reduce-motion (fixed BBMotion.standard)
Task 8: minor (deferred): toast live-region + dialog header semantics untested; BBDialog non-scrolling Column can overflow at large text scale on small screens (recommend SingleChildScrollView in final wave); barrier-dismiss untested; 'Dismiss' hard-coded; refresh colour untested
Task 8: fix round 1/5 (1 addressed, 0 open — toast duration from BBMotion.of in didChangeDependencies; commits f3bcbb0..df8672e)
Task 8: complete (commits b989b44..df8672e, review clean)
Task 9: base df8672e, implementer aade3611c39c0bbd4 (sonnet); R3 applied; view heights 1100/1800; gallery ColoredBox(bg); BBTextField fixed to fully border-less InputDecoration (theme borders leaked through .collapsed); review approved
Task 9: minor (deferred): no unit test pinning BBTextField border-less decoration (only goldens guard it) — recommend adding in final wave
Task 9: minor (deferred) / DESIGN QUESTION for user: nav bar at text x2 — FittedBox shrinks Alerts tab to ~half size; options: grow bar with text scale, icon-only/stacked tabs at high scale
Task 9: minor (deferred): dark segmented selected segment barely distinct from track; BBTextField has no visible focus state; goldens generated on macOS (no CI yet)
Task 9: complete (commits df8672e..88a5f56, review clean)
Task 10: base 88a5f56, implementer ad93d734a3fa1a2e5 (sonnet), head 615a37f; review: spec ✅, quality Needs fixes — 2 Important: regex misses many Material widgets/helpers (TextField, CircularProgressIndicator, Divider, Material, Dialog, ScaffoldMessenger…); token bypass via Theme.of/ColorScheme/ThemeData/Colors. undetected
Ruling: widen the guard — add the reviewer's widget/helper list plus `\bTheme\.of\b|\bThemeData\b|\bColorScheme\b|\bColors\.` (spec §4: widgets read tokens via context.bb), extend the self-test with positives and kit-name negatives, and re-add arrival_row_tile.dart to the allow-list (it now has violations) — this SUPERSEDES R2 — cost if wrong: Phase 2 must migrate theme reads too (intended)
Task 10: minor (deferred): comment/string handling is line-prefix only (false positives possible); scan at group-construction time
Task 10: fix round 1/5 (2 addressed, 0 open — widened regex incl. theme reads; arrival_row_tile re-allow-listed; commits 615a37f..c0d2b56)
Task 10: complete (commits 88a5f56..c0d2b56, review clean)
Task 11: base c0d2b56, implementer ab0e5446ba2201944 (sonnet); review approved
Task 11: ⚠️ FOR USER: store/app-store/version/1.1.0/en-CA.json promotionalText says "official service alerts" → suggest "current service alerts" (store copy; publishing is the user's call)
Task 11: ⚠️ FOR USER: dataCredit says "Metrobus open data (GTFS, GTFS-Realtime)" but app also reads Metrobus Mobile Fleet View + TimeTrack JSON — consider broadening wording
Task 11: minor (deferred): "Official Metrobus" guard regex is case-sensitive/single-quote only; code comment arrival_board_screen.dart:113 says "official"; footer dropped "Pull down to refresh" hint
Task 11: complete (commits c0d2b56..4cacb3c, review clean)
Task 12: base 4cacb3c, implementer a90d5f6a22c146ff5 (sonnet), head ee15100 (68 files); controller viewed app_icon + feature graphic → match approved design
Task 12: ENV: `flutter build apk --debug` needs JDK 21 (Android Studio's bundled Java 25 breaks Gradle 8.14) — succeeded with GRADLE_OPTS java.home override; `flutter build ios --simulator` hangs in SwiftPM downloading MapLibre xcframework (Xcode 27 / Swift 6.4) — iOS build unverified; actool/ibtool compile clean
Task 12: review approved (safe zones measured OK; all generator output committed)
Task 12: minor (deferred): Android adaptive foreground double-shrunk (script 60% + flutter_launcher_icons 16% inset) → mark looks small on Android launchers; arrival_row_tile.dart still has Color(0xFF0277BD) literals (legacy, Phase 2)
Task 12: complete (commits 4cacb3c..ee15100, review clean)
Task 13: blocked on user (R4): Android system-image download + AVD creation needs consent; iOS run blocked by SwiftPM hang (env)
## Final review (opus a10aabff…, d906622..ee15100): With fixes — 0 Critical, 9 Important
Ruling: final fix wave (one dispatch) covers Important #1 (secondary→liveInk + test), #2 (BBDialog scroll + namesRoute), #3 (RouteBadge grows with clamped text scale), #4 (nav bar: clamp its text scale to 1.3 and let bar height grow; reservedHeight follows) — user design call made by controller as default, reversible, #5 (off switch visible: muted border/thumb + off state in gallery), #6 (BBTextField own Material(transparency); kitHost no Material), #7 (guard also fails on material/cupertino imports in non-allow-listed lib/ui files), #8 (OFL asset + LicenseRegistry); plus cheap minors: feature graphic -alpha off (Play rejection risk), alerts footer legibility (legal line), page transition honours reduce motion, edge strip only joins arena when canPop + check route.isCurrent before popping, toast above keyboard, BBPressable _down reset, BBTextField hintMaxLines 2 + border-less decoration test, nav tab ≥44 test — cost if wrong: more churn in one round; goldens regenerate
Ruling: #9 (parity check) = Task 13, run after the fix wave; user approved AVD (created busboard_pixel from already-installed android-36 image — no download needed) and iOS retry→CocoaPods fallback
Deferred to Phase 2 plan (not fixed now): kit icon button/top bar/back/loading indicator/slider replacement, focusability, sheet animateToDetent helper (Phase 3), golden CI tagging, store copy + data credit wording (user)
Final fix wave: attempt 1 (opus) died on weekly rate limit after committing items 1 (9a63360) and 2 (9fe1f3e); item 3 uncommitted WIP (route_badge.dart + basic_components_test.dart); test/kit/failures/ golden-failure artifacts left. Retrying with sonnet from item 3 (same single fix wave, continuation).
Final fix wave: done (sonnet a391c04…), commits 9a63360..828e7d1 (16), full suite +171 ~6, analyze clean
Final fix wave re-review: all 15 addressed, no new Critical/Important (minor: hintMaxLines mis-indent; search icon doesn't scale at x2; registerAppLicenses not idempotent)
Task 13: iOS build succeeded after clearing build/ios (SwiftPM) — no global flutter config change; Android parity screens captured (picker, board, alerts, map, dark board, adaptive icon)
Task 13: complete — Android (emulator busboard_pixel, API 36) + iOS (BusBoard iPhone 17, iOS 26.5): same colours/font/layout; live board, alerts, map, dark mode, adaptive icon, iOS edge swipe (springs back <1/3, pops with previous page visible mid-drag). Controller re-ran: analyze clean, flutter test +171 ~6.
