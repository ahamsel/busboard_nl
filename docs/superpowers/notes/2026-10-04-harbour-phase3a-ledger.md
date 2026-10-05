# Harbour Phase 3a — execution ledger (handoff for Phase 3b)

Copied from the SDD workspace ledger at the end of Phase 3a (kit polish + toolchain upgrade). Deferred minors and rulings below feed the Phase 3b (map) plan.

# SDD ledger — plan: docs/superpowers/plans/2026-10-04-harbour-phase3a-kit-polish.md

Spec: docs/superpowers/specs/2026-10-04-harbour-phase3-design.md §2 (reachable)
Branch: claude/unified-ui-map-redesign-fc0a89 · start HEAD f40e4f4
Models: implementers sonnet; reviewers sonnet; escalation (rounds 4-5) + final review fable (opus rate-limited until 2026-10-07)

## Pre-flight scan

| Pair / task | Produces → consumes | Finding |
|---|---|---|
| T1 ↔ T8 | BBIcons names (chevronDown, star, location, layers) → BBChip/BBControlPill tests | names exist in T1 mapping; OK |
| T1 ↔ T7 | bb_nav_bar.dart: BBNavItem.activeIcon (T1) / BBNavBarScope appended (T7) | disjoint edits; OK |
| T1 ↔ T7 | app_shell.dart: nav items (T1) / BBNavBarScope wrap (T7) | disjoint; OK |
| T3 ↔ T4 | BBRouteDots({progress, dotSize}) → BBRefresh indicator + tests find.byType(BBRouteDots) | signatures match; OK |
| T2 ↔ T5 | arrival_board_screen.dart status dot (T2) / loading state (T5); alerts_screen.dart dot (T2) / loading (T5) | disjoint regions; OK |
| T2/T3/T5/T8 | kit.dart exports | separate lines; OK |
| T2/T5/T8 | kit_golden_test.dart gallery inserts + view-height guard (T2 adds the guard) | T5/T8 may need to raise heights; plan says so; OK |
| T4 ↔ T7 | feedback_components_test.dart new tests | additive; T4 adds dart:async/services imports; OK |
| T1/T2/T3/T5/T8 | goldens regenerated per task | each task regenerates what it changes; OK |
| T1 | icons_test list vs bb_icons mapping (44 names, regular codepoints unique) | consistent |
| T2 | glyph tests vs BBGlyph code (ExcludeSemantics when unlabelled; image when labelled) | consistent |
| T3 | dot scale math (0.4+0.6f), keys bb-route-dot-$i, reduce motion identity | consistent |
| T4 | trigger 72, refreshAction, live region 1x1, error reported via FlutterError | consistent; tests avoid pumpAndSettle while dots loop |
| T5 | skeleton key bb-skeleton-item, label live region; screen edits; alerts_test update listed as behaviour change 5 | consistent |
| T6 | BBSheetController/BBSheetDetent/cardKey/handleKey/sideMargin; existing tests switch controller type | consistent |
| T7 | BBToast.cardKey, scope detection at show(); bottom math matches tests (34+16+8; 72+8) | consistent |
| T8 | BBChip.surfaceKey, 44 pt, ellipsis; control pill Opacity via BBIconButton | consistent |

Ruling: Task 1 stages pubspec.lock including the SDK-pinned matcher 0.12.20 / meta 1.19.0 bumps already in the working tree — they come from the installed Flutter SDK and a phosphor_flutter lock can't be committed without them — cost if wrong: two transitive version bumps in the history
Ruling: implementers on sonnet (plan carries full code, but tasks span several files plus golden inspection) — cost if wrong: a few extra turns
Task 1: base f40e4f4
Task 1: implementer a09209cd… (sonnet) dispatched
Task 1: NEEDS_CONTEXT — phosphor_flutter 2.1.0 (latest) does not compile on Flutter 3.47: `class PhosphorIconData extends IconData` but IconData is final
Ruling: vendor Phosphor's Regular + Fill fonts (MIT) as app assets (assets/fonts/phosphor/), declare families PhosphorRegular/PhosphorFill in pubspec, define BBIcons as const IconData(codepoint, fontFamily: ...) with codepoints taken from the package tables, register the Phosphor MIT licence in registerAppLicenses() (like Figtree), and drop the phosphor_flutter dependency — avoids a dependency whose Dart code can't compile and ships 2 fonts instead of 6 — cost if wrong: manual font upgrades later
Ruling: icons_test assertion `fontPackage == 'phosphor_flutter'` changes to `fontFamily in {PhosphorRegular, PhosphorFill}` and `fontPackage == null` (plan defect caused by the incompatible package); add a licence-registry test — cost if wrong: none
Ruling (supersedes the pubspec.lock ruling): with no new package, Task 1 does not stage pubspec.lock — cost if wrong: none
Task 1: resumed implementer with vendoring ruling; controller TODO after T1 commit: amend spec §2.1 (vendored Phosphor fonts, licence registered)
User request (2026-10-04): update anything outdated to the latest stable, incl. Flutter and the project.
Ruling: insert "Task U — toolchain + dependency upgrade" after Task 1 completes, before Task 2: flutter upgrade 3.47.5 → 3.47.6 (latest stable), then pub major upgrades + Android/iOS build tooling to current stable, as its own implementer dispatch + review; later tasks build on the new stack — cost if wrong: one extra review cycle; goldens regenerate once more
Task 1: head 8656bdd (8656bdd); vendored-font ruling applied
Task 1: review approved (sonnet a2bd8688…): 44/44 codepoints verified, fonts byte-identical
Task 1: minor (deferred): matchTextDirection dropped (chevronRight/back/nearMe/history won't mirror in RTL; English-only app); FontManifest test matches raw substring instead of json.decode; tree-shake size of the 940 KB vendored fonts unverified; fonts permanently in git history
Task 1: complete (commits f40e4f4..8656bdd, review clean)
Task U: controller ran flutter upgrade → 3.47.6 (Dart 3.13.5); base 1f09b5d
Task U: implementer a857b890… (sonnet) dispatched
Task U: head 1e55a55 (7c9e414,3bc07a6,1e55a55); DONE_WITH_CONCERNS: maplibre 0.27 runtime unverified; CocoaPods integration still present though plugins are SwiftPM; disk-full retries
Task U: controller smoke test iOS sim (build 1e55a55): picker shows Phosphor icons + filled Board tab; legacy map renders tiles/stops/live buses with maplibre_gl 0.27 — OK. Android runtime check deferred to end-of-3a parity.
Task U: review approved (sonnet a61c4bde…); AGP 9.1.0 (template/full-Kotlin) chosen over max-known 9.2 — accepted
Task U: minor (deferred, surface to user): release build (minify+shrink, proguard-rules.pro missing, key.properties absent — pre-existing) not verified under AGP 9/Gradle 9/R8; iOS minimum is now 15.0 (Flutter 3.47 Flutter.podspec requires it; drops iOS 13/14); Java 21 now required for Android builds (maplibre_gl 0.27) — undocumented; GTFS parsing lacks fixture coverage (csv 8 verified by source diff only); pubspec floors not raised to locked versions; CocoaPods integration still present though all plugins are SwiftPM
Task U: complete (commits 1f09b5d..1e55a55, review clean)
Task 2: base 1e55a55
Task 2: implementer a1c4c128… (sonnet) dispatched
Task 2: head a3bb83d
Task 2: review approved (sonnet a5b7f034…)
Task 2: minor (deferred): Board status dot has no golden/visual check (arrival_rows goldens omit the status line); liveDot core is smaller than the old dots (Board 5.5 px vs 7, Alerts ~6.4 px vs 10) — plan-mandated sizes, may read faint; kit.dart export order (plan-mandated position) breaks alphabetical order; bus/stopPole glyphs unused until 3b; raw BoxShape.circle dots remain in bb_pill.dart:54 and legacy map files
Task 2: complete (commits 1e55a55..a3bb83d, review clean)
Task 3: base a3bb83d
Task 3: implementer a26c25f2… (sonnet) dispatched
Task 3: head ad1f53e; deviation diagonal3Values(s,s,s) instead of (s,s,1)
Ruling: accept z=s in the dot scale matrix — getMaxScaleOnAxis includes z; a z scale has no visual effect on a flat 2D widget — cost if wrong: none
Task 3: review approved (sonnet ae3e949f…)
Task 3: minor (deferred): hop translates up to 0.7×dotSize outside the layout box (clipping risk — carried to Task 4 dispatch); comment says 130 ms stagger but it is ~117 ms; tests miss null↔progress ticker switching, clamping, dark colours, non-zero-index hop; test name "no longer uses a Material spinner" overclaims; per-dot Opacity + duplicated f computation; 0.3×dotSize side padding per dot
Task 3: complete (commits a3bb83d..ad1f53e, review clean)
Task 4: base ad1f53e
Task 4: implementer a51fec13… (sonnet) dispatched (carried Task 3 minor #1: hop overshoot / no clipping)
Task 4: head 91346a8
Task 4: review Needs fixes (sonnet a1bb2b3d…): Important (plan-mandated): throwing onRefresh still announces "Updated"
Ruling: on failure announce "Couldn't refresh" (still clear _refreshing, still report the error once); success keeps "Updated" — spec §2.2 wants a truthful status line; announcing success after a failure misleads screen-reader users — cost if wrong: one string
Task 4: minor (deferred): no tests for slow no-fling release, pull-back disarm, semantics action during refresh, unmount while pending (all verified by reviewer probe); "reports once" test doesn't assert call count; empty 1x1 live region stays in tree; arming after refresh ends mid-drag fires haptic without fresh crossing
Task 4: fix round 1/5 (1 addressed, 0 open — failure announces "Couldn't refresh"; commits 91346a8..f0ea3f5)
Task 4: complete (commits ad1f53e..f0ea3f5, review clean)
Task 5: base f0ea3f5
Task 5: implementer ae52edd8… (sonnet) dispatched
Task 5: head dc1de94; DONE_WITH_CONCERNS: 3 screen tests needed explicit pump(1 min) (no ticker to advance fake time); dark skeleton subtle
Task 5: review approved (sonnet addc2893…): the 3 out-of-list test edits only advance fake time; assertions unchanged
Ruling: accept the three test-harness pump additions (alerts error, stop-picker near-me error, board first-load) — the static skeleton schedules no frames, so pumpAndSettle no longer drives Riverpod retry/feed timeouts; no assertion changed — cost if wrong: none
Task 5: minor (deferred, final wave candidate): dark-mode skeleton blocks 1.08:1 on card (fainter than the card hairline) — consider a dark-only block colour (~1.4:1); board test pump(1 min) could be ~21 s to document the two-feed timeout; literal sizes in bb_skeleton (plan-mandated); stale "BBLoading announces its own spinner" comment in board test
Task 5: complete (commits f0ea3f5..dc1de94, review clean)
Task 6: base dc1de94
Task 6: implementer a8169e1d… (sonnet) dispatched
Task 6: head db2a88b; DONE_WITH_CONCERNS (4 brief-code adaptations, no assertion edited)
Ruling: accept increasedValue/decreasedValue on the handle Semantics (Flutter asserts increase/decrease actions need them), unawaited(animateToDetent) in tests (animateTo awaits an AnimationController that only advances when the test pumps), and a 390x800 test surface for the card-geometry test (default 800x600 centres the 390 host) — framework requirements, not behaviour changes — cost if wrong: none
Task 6: review Needs fixes (sonnet acec1b0f…): Important (plan-mandated): fresh snapSizes list each build + post-frame setState → DraggableScrollableSheet._replaceExtent (identity compare) re-snaps mid-drag; held-finger drag hijacked at the 0.325 midpoint (regression vs BASE, invisible to tester.drag)
Ruling: fix with a cached, stable snapSizes list (recomputed only when dismissible/peek/half change) + a held-finger regression test — plan-mandated code is wrong; the sheet is 3b's core interaction — cost if wrong: none
Ruling: include in the same fix round, as load-bearing for 3b: reset the _dismissed latch when the extent rises above tolerance again; handle a controller swap in didUpdateWidget (detach old internal/external, attach new); pass increasedValue/decreasedValue only when the matching action exists — 3b keeps one sheet mounted across selections and may swap controllers — cost if wrong: small extra diff
Task 6: minor (deferred): awaiting collapse() can hang if the sheet unmounts mid-animation (3b: call unawaited); drag held at 0 for 80 ms dismisses with finger still down; doc comments should say fractions are of the inset area; dark-mode hairline border may be covered by the header ColoredBox/ClipRRect (no golden); coverage gaps (internal controller, status-bar inset, Collapse from full, onDecrease at peek, no Close when not dismissible)
Task 6: fix round 1/5 (4 addressed, 0 open — stable snapSizes + held-finger test; dismiss latch re-arms; controller swap; increased/decreasedValue only with actions; commits db2a88b..1110c2d)
Task 6: minor (deferred): internal→external controller swap untested; semantic close at peek re-arms only on next extent notification
Task 6: complete (commits dc1de94..1110c2d, review clean)
Task 7: base 1110c2d
Task 7: implementer a85a82e4… (sonnet) dispatched
Task 7: head 5720652; DONE_WITH_CONCERNS: added pump() before the 250 ms pump in the two new toast-position tests (first frame starts the slide animation)
Ruling: accept the extra pump() — the overlay's first frame only starts the slide-in, so a single 250 ms pump measured the start offset; assertions unchanged — cost if wrong: none
Task 7: review approved (sonnet a5558d8e…): the only real caller (Settings) sits outside the scope; all shell branches inside
Task 7: minor (deferred): scope reflects ancestry not visibility (a toast from a root-navigator BBDialog over the shell would sit low; no caller today); reserve frozen at show time across a navigation within 3 s; stale doc comment "Floating message above the nav bar" in bb_toast.dart; no test pins AppShell providing the scope / Settings outside it
Task 7: complete (commits 1110c2d..5720652, review clean)
Task 8: base 5720652
Task 8: implementer a0ca177f… (sonnet) dispatched
Task 8: head 2ac6099
Task 8: review approved (sonnet aba72e80…)
Task 8: minor (deferred): chip ellipsis test width assertion vacuous (no Center, plan-mandated); disabled-pill test relies on .last and doesn't assert enabled:false; pill divider/selected item never rendered in gallery or tested; selected-chip test lacks isButton/hasTapAction; Semantics(selected:false) emitted on non-toggle controls; chip with onTap null has no disabled look; dark selected chip keeps line hairline; x2 gallery truncates stop number; dartdoc [BBGlyph] unresolved, BBControlPillItem undocumented
Task 8: complete (commits 5720652..2ac6099, review clean)
## Final review: range f40e4f4..2ac6099 (Phase 3a + Task U)
Parity (controller, iOS sim, HEAD 2ac6099): picker skeleton + Phosphor icons; board skeleton + 'Checking live data…' then live (green liveDot); pull-to-refresh route dots captured mid-pull; settings Phosphor icons; Settings toast only appears on failure (pre-existing) — not observed
Parity (controller, Android emulator API 36, HEAD 2ac6099 debug APK under AGP 9.1/Gradle 9.3.1): picker with Phosphor icons OK; map froze on the very first cold-boot launch (232× "dequeueBuffer failed" for flutter-vd) — after a clean relaunch the map renders stops, live bus, selected stop and pans. Treated as an emulator surface glitch; watch item for 3b.
Disk: filled again during the emulator check (Gradle cache 16 GB after the upgrade); user approved deleting the old Gradle 8.14.3 cache/wrapper; deleted build/app + build/ios; 14 GB free.
Final review (fable add9fa74…): With fixes — 1 Critical, 3 Important, 7 Minor
Ruling: one fix wave covers Critical #1 (add android/app/proguard-rules.pro; verify `flutter build apk --release` passes R8 — signing stays the user's; README notes Java 21 + iOS 15), Important #2 (new BBColors.skeleton token: light = surfaceSunken value, dark ≈ #2A3746, ≥1.35:1 on surface, tested; regenerate dark goldens), Important #3 (BBRefresh semanticLabel; Board 'Departures', Alerts 'Service alerts'), Important #4 (chip ellipsis test under loose constraints + doc that the parent must bound width; no API change), Minor #6 (doc: unmount on onDismiss; call collapse/animateToDetent unawaited), Minor #7 (selected: selected ? true : null), Minor #11 (stale comments) — cost if wrong: small diff, goldens regenerate
Ruling: defer to the 3b plan: sheet dark hairline as foreground border (#5) with a dark sheet golden; refresh release-without-drag-end edge (#8); bus glyph three-quarter view vs front view (#9, spec §2.1 deviation, glyph unused until 3b); skeleton text-scale sizing (#10) — cost if wrong: revisited in 3b
Final fix wave: fixer a252be16… (sonnet) dispatched; base 2ac6099
Final fix wave: head a248067 (b402ba7..a248067); release APK past R8, stops at signing (storeFile missing — user's keystore); skeleton dark #2C3A4A (1.39:1); chip tests' semantics lookup switched to find.semantics.byLabel (selected:null no longer creates a node)
Final fix wave: re-review (sonnet aca5d6e6…) all 7 addressed, no new breakage; accepted deviations: release build verified past R8 (stops at signing — user's keystore), skeleton dark #2C3A4A (1.39:1), chip tests look up by semantics label
Ruling: accept the three fix-wave deviations above — each follows the finding's own instruction or is a framework consequence — cost if wrong: none
## Phase 3a complete (HEAD a248067)
