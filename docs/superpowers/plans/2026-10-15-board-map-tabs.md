# Two Tabs, Board and Map: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give BusBoard NL 1.5.0 two equal bottom tabs, a map-free **Board** ("when's my bus at my stop?") and today's **Map**, with the tab used last remembered, and every route into a stop or onto the map switching tabs for the rider.

**Architecture:** A new `HomeShell` (route `/`) stacks the two tabs over a kit `BBTabBar`. Both tabs stay mounted: the one not showing is `Offstage`, with tickers off, no touches and no semantics, so the map, its camera and follow, and the Board's scroll survive a switch. The Board fades over the map; the map never fades. The Map tab is today's `HomeScreen`, given the screen above the tab bar (`MediaQuery.removePadding(removeBottom: true)`), so its sheet's peek, half, full and tuck-away measure from the bar's top with no change to the sheet code. The Board tab (`BoardTab`) reuses the stop sheet's own widgets (`StopSheetContent.info`, `.body`, `.planFrom`) in a `BBScrollPage` with pull to refresh. Tab state lives in Riverpod: `homeTabProvider` (persisted as `home_tab.v1`, migrating 1.4's `board_open.v1`), `boardStopProvider` (the Board's picked stop) and `recentStopsProvider` (`recent_stops.v1`). The shell switches to the Map for what only the map shows (a follow, trip options or steps, choosing on the map); the stop line, Open board, notifications and `/board/:id` call `showBoard`.

**Tech Stack:** Flutter 3.47 / Dart 3.9, flutter_riverpod 3.4 (`Notifier`, `AsyncNotifier`, `ref.listenManual`), go_router 18, shared_preferences (`SharedPreferencesAsync`), flutter_test goldens.

**Spec:** `docs/superpowers/specs/2026-10-15-board-map-tabs-design.md` (binding). It builds on `docs/superpowers/specs/2026-10-14-neutral-blue-slim-sheet-design.md` and `docs/superpowers/specs/2026-10-12-map-first-redesign-design.md`. Read the binding spec before starting any task.

**Branch:** `claude/visual-refresh-spec` in `/Users/aham/projects/dev/busboard_nl/.claude/worktrees/unified-ui-map-redesign-fc0a89` (HEAD `5c49bfb` when this plan was written). Run every command from that directory.

**Dry run:** every task below was applied, in order, to a scratch copy of the repo at `5c49bfb` (with the developer's uncommitted `analysis_options.yaml`). After each task `flutter analyze` said `No issues found!` and the non-golden suite passed (1,505 tests at `5c49bfb`; 1,535 after Task 3, 1,557 after Task 4, 1,548 after Task 5, 1,556 after Task 6, 1,563 after Task 7, 1,567 after Task 8). After Task 9 the whole suite, goldens included, passed: 1,595 tests. The edits below were then re-applied mechanically from this document to a fresh copy of `5c49bfb` and reproduced every task's files exactly. Expect only small drift (another commit touching the same lines), not design surprises; if a "Find" block no longer matches, look for it a few lines away before changing anything else.

## Global Constraints

- **Accessibility, WCAG AA:** 4.5:1 for body text; 3:1 for large text (18.66 px bold or 24 px regular and up) and for non-text UI (icons, outlines, focus rings). Every control has a screen-reader label; the strings this plan pins (tab labels "Board, tab 1 of 2", chip labels, dialogs) are used exactly. Selection never rests on colour alone (the tab's pill and filled icon; the chip's fill and border). Nothing overflows at 2× text on 320 pt; light and dark both work.
- **Reduce Motion** (`MediaQuery.disableAnimations`, read through `BBMotion.reduced` / `BBMotion.of`): the tab switch is instant, the tab pill moves at once, nothing loops. Every new duration goes through `BBMotion.of(context, …)`.
- **No new dependencies.** Everything uses packages already in `pubspec.yaml`.
- **Kit boundary:** no Material or Cupertino widgets in screen code. `test/kit/kit_boundary_test.dart` enforces this for `lib/ui/**` outside `lib/ui/kit/`: screen files import `package:flutter/widgets.dart` and `../kit/kit.dart`, never `material.dart` or `cupertino.dart`. The tab bar is a kit widget (`lib/ui/kit/bb_tab_bar.dart`) for this reason, and is exported from `kit.dart`.
- **Staging:** stage explicit paths only (never `git add -A`, `git add .` or `git commit -a`). Never stage `analysis_options.yaml`, `tool/capture_raw_gtfsrt.dart`, `test/fixtures/timetrack/`, `build/`, `store/marketing/` or `.superpowers/`: they are the developer's local, uncommitted files. Check `git status --short` before every commit.
- **Never use bare `git stash`** (the stash is shared with other worktrees and sessions). To set work aside, make a WIP commit.
- **Commit trailer:** every commit message ends with exactly this line:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- **Devices:** subagents never touch a device, simulator or emulator, and never run `flutter run`, `flutter install` or `adb`. The controller (the session running this plan) does the simulator and Android checks in Task 9, Step 6.
- **Goldens fail by design until Task 9.** Tasks 5–8 change pixels (the tab bar, the map above it), so `test/ui/screen_golden_test.dart` fails until Task 9 regenerates the goldens. Don't update goldens before Task 9. At the end of Tasks 1–8 run:
  `flutter analyze` (expected: `No issues found!`) and
  `flutter test $(find test -name '*_test.dart' ! -name '*golden_test.dart' | sort)` (expected: `All tests passed!`).
- **Known flake:** `test/ui/stop_sheet_test.dart` "once the alert has fired, home stops polling its stop (F4)" has failed once under full-suite load and passed on every rerun. If it is the only failure, rerun that file alone before suspecting your change.
- **Formatting:** the code is written at 120 columns, as the repo is. Don't reformat files you only touch in places.

## Review Focus

Conditions the spec implies but its own test list doesn't name, most likely to bite a rider first. Each has a test in the task named.

1. **A rider with a saved stop, at launch, while the saved stop is still being read:** the Board must never flash "Choose your stop", and must never ask for the location for it (the nearby list asks). → Task 4, "while your stop is still being read, neither Choose your stop nor a location request".
2. **A notification or `/board/` link arriving before home is built** (a cold start, the schedule still loading, the stored tab "map"): it must land on the Board on that stop, and win over the stored tab and over a 1.4 Board left open. → Task 1, "a link that lands before the stored tab is read wins over it, and over the 1.4 Board"; Task 6, "a Board link at a cold start, before the schedule and the stored tab, shows that stop once loaded".
3. **Back on the Board with a card open on the hidden map:** back must leave the app, not close the hidden card, and never switch tabs. → Task 7, "on the Board, back leaves the app, even with a card open on the map behind it".
4. **The hidden map acting as if it were on screen:** its one-time bar lift must not play (and be marked seen) behind the Board. → Task 5, "the bar's one-time lift never plays behind the Board: it waits for the Map tab".
5. **A stop picked in a search opened from the Board** ("See its buses", or ＋): it must show on the Board, not open a card on the hidden map. → Task 6, "a stop's buses chosen in a search from the Board show on the Board" and "＋ on the Board: the stop picked becomes your stop, and the Board shows it".

## Spec gaps and ambiguities resolved here

- **What the Board shows (§3):** the stop last picked on it (a chip, Near me, a link, Open board, the stop line), else your stop (★), else the first saved place that is a stop, else "Choose your stop". The pick is kept for the session only; a cold start shows your stop again (or the 1.4 Board left open, once, on upgrade). Recent stops never become the default.
- **Recents (§3, `recent_stops.v1`):** the store keeps the last 8 stop ids, newest first, each once. The chip row shows at most 3 of them, skipping any stop that already has a ★ or saved-place chip, so the row never shows fewer recents just because you viewed your own stop. A stop's card on the map and any pick on the Board record a view.
- **Chip labels:** ★ your stop by stop name (read "Your stop, MUN Centre"); a saved place by its saved name with its icon (read "Home, Avalon Mall"); a recent stop by stop name with the history icon (read "Recent stop, …"); "Near me" (read "Near me, <stop>" while selected); ＋ is a chip labelled "Stop" with the add icon, read "Choose your stop". The spec says ＋ opens `/search?pickStop=1`, which makes the stop picked your stop; this plan keeps that, and the Board then shows it.
- **Near me without a stop (§3):** location refused, location off and "no stop within 800 m" give the same dialog: "Can't find a stop near you" / "Location may be off for BusBoard, or no stop is within 800 m. You can search for the number on the stop pole instead." with Cancel and "Search instead" (`/search?pickStop=1`). Each Near me tap asks for a fresh fix.
- **Choose your stop (§3):** a stop tapped in its nearby list becomes your stop and the Board shows it. With no location (or no stop near) it is an empty state with "Search for a stop".
- **Links:** `/board/:id` and arrival-alert notifications open the Board on that stop. `/stop/:id` stays a stop link: the stop's card on the Map tab (spec 2026-10-12 §3.6).
- **"Where to?" and "Plan a trip from here" on the Board (§2.3):** the switch to the Map happens when a destination opens the trip options (or when "Choose on map" starts a pick), not when the search opens; backing out of the search leaves the rider on the Board.
- **Search from the Board:** "See its buses" and the stop search show the stop on the Board; on the Map they open its card, as today.
- **Every switch is stored** as the tab used last, including the automatic ones (a follow, trip options).
- **The bell and gear (§3, §5):** the same `AlertsButton` and `SettingsButton` widgets (split out of `MapButtons`), at the top right of both tabs: in the Board's title row, and in the map's floating pill.
- **Tab bar size (§2.1):** at least 56 pt plus the bottom safe area. Labels grow with the text size and the bar grows with them (no cap). On a tablet the bar spans the screen but its two tabs keep to a centred 480 pt row.
- **Tablet (§3):** the same bottom tab bar; the Board is a centred column at most 640 pt wide; the Map keeps its side panel, which now ends just above the tab bar.
- **Removed with the toggle (§2.3):** `sheetAtFullProvider`, `sheetIdOf`, `boardRequestProvider`/`BoardRequest`, `HomeSheetNotifier.openBoard` and `.showMap`, `StopSheetContent.showMapKey`, and the home screen's "Board open" announcement. Removed with the restore (§2.2): `BoardOpenStore`, `launchLinkCheckedProvider`, the home screen's remember/forget/restore code and `test/ui/board_reopen_test.dart`. Nothing else used them.
- **The stop line's screen-reader string** still ends "Open board": it still opens the Board, now the tab.
- **Before the stored tab is read** (a frame or two at launch) the home is a plain `bg` box.

## Risks, and how this plan handles them

- **The sheet's measurement and peek with the tab bar below it.** The shell gives the Map tab only the screen above the tab bar and removes the bottom safe-area padding from it (the tab bar takes the home indicator). `HomeScreen` already measures everything from its own box and `media.padding.bottom`, so the peek, half, full, tuck-away, credit and camera fit all move up with no change to their code. Tests that computed the sheet's area as `844 - 2 * BBSpace.s` now call `homeSheetArea(tester)` (Task 5), and Task 7 pins the bar, full height and the tuck-away against the tab bar's top.
- **The follow chip and "Back to bus".** Both are positioned from `creditBottom`, which comes from the same box. Task 7 pins "Back to bus" above the follow card and clear of the tab bar.
- **iOS map attribution.** `HomeScreen` subtracts `media.padding.bottom` for MLNMapView on iOS; with the padding removed that is now 0, which matches the native view no longer touching the home indicator. The controller checks the (i) button on the simulator (Task 9, Step 6).
- **Deep links before home is mounted.** The redirects only change provider state (in a microtask, as today), and the tab notifier remembers that a tab was chosen while the stored one was still being read, so a link always wins (Task 1, Task 6).
- **State across switches.** Both tabs stay mounted in a `Stack` (never an `IndexedStack` rebuild): `Offstage` once hidden, `TickerMode(enabled: active)`, `IgnorePointer`, `ExcludeSemantics`. flutter_riverpod 3 pauses a consumer's `watch`es while its `TickerMode` is off, and replays the missed change on resume. So the hidden Board stops polling its stop, and a map that starts hidden is built the first time the Map shows; after that the same MapLibre view is kept (Task 5 checks the same `HomeScreen` state and the same map element). `ref.listen` callbacks are not paused, so the map still reacts to cards and follows opened while it is hidden.
- **A platform view under an opacity layer** can flicker on Android. Only the Board's layer fades; the map's layer is never wrapped in a non-1 opacity.
- **Finders and duplicates.** Both tabs contain "Where to?", Alerts, Settings and stop widgets. Offstage widgets are skipped by `find.*` by default, and `pumpPlannerApp` opens on the Map unless a test asks otherwise (`tab:`), so existing tests keep finding exactly one of each.
- **Tests that assumed the old toggle or `/board/` → card.** Task 5 deletes `board_reopen_test.dart` and moves area maths to `homeSheetArea`; Task 6 rewrites `board_button_test.dart`, removes the `sheetIdOf` unit test and the Show-map assertions in `home_screen_test.dart`, and changes every `/board/…` test link that meant "open the stop's card" to `/stop/…`.

## File Structure

| File | Responsibility |
|---|---|
| `lib/state/home_tab_provider.dart` (create) | `HomeTab`, `HomeTabStore` (`home_tab.v1`, the `board_open.v1` migration), `HomeTabNotifier` (`select`, `showBoard`, `openStop`), `BoardStop`, `BoardStopNotifier` |
| `lib/state/recent_stops_provider.dart` (create) | `RecentStopStore` (`recent_stops.v1`), `RecentStopsNotifier` |
| `lib/state/board_providers.dart` (create) | `BoardChip`, `boardStopChips`, `boardChipsProvider`, `boardShownStopProvider`, `boardReadyProvider` |
| `lib/state/providers.dart` (modify) | `SettingsNotifier.loaded`, `settingsLoadedProvider` |
| `lib/ui/kit/bb_tab_bar.dart` (create), `lib/ui/kit/kit.dart` (modify) | `BBTab`, `BBTabBar` |
| `lib/ui/kit/bb_chip.dart` (modify) | `BBChip.toggle`: a selected state screen readers always hear |
| `lib/ui/board/board_tab.dart` (create) | The Board tab |
| `lib/ui/home/stop_sheet.dart` (modify) | `StopSheetContent.info` / `.planFrom` split out of the card header; Open board switches tabs; no Show map |
| `lib/ui/home/map_buttons.dart` (modify) | `AlertsButton`, `SettingsButton` split out |
| `lib/ui/home/home_sheet.dart` (modify) | `WhereToField` public; Open board switches tabs |
| `lib/ui/stop_picker/near_me_list.dart` (modify) | `NearMeList.onPick` |
| `lib/ui/home/home_shell.dart` (create) | The two tabs, the cross-fade, the switches to the Map |
| `lib/ui/home/home_screen.dart` (modify) | `HomeScreen.active`; recents; no restore, no Board request; back leaves the app when hidden |
| `lib/ui/home/home_stop_line.dart`, `lib/ui/search/search_screen.dart` (modify) | The stop line opens the Board tab; search picks a stop where the rider is |
| `lib/state/home_sheet_provider.dart` (modify) | `openBoard`, `showMap`, Board requests and "sheet at full" removed |
| `lib/routing/router.dart`, `lib/app.dart` (modify) | `/` is the shell; `/board/:id` → Board, `/stop/:id` → card; no launch-link handshake |
| `lib/state/board_open_store.dart` (delete) | Replaced by the migration in `HomeTabStore` |
| `test/helpers/planner_app.dart` (modify) | `tab:` (defaults to the Map), `homeSheetArea` |
| `test/…` | One test file per behaviour, named in each task |

---

### Task 1: Tab state, the tab used last, and the `board_open.v1` migration

**Files:**
- Create: `lib/state/home_tab_provider.dart`
- Test: `test/state/home_tab_provider_test.dart`

**Interfaces:**
- Consumes: `homeSheetProvider`, `StopSheet` (`lib/state/home_sheet_provider.dart`, unchanged).
- Produces:
  - `enum HomeTab { board, map }` (index 0 is the Board: the tab bar's order).
  - `HomeTabStart(HomeTab tab, {String? boardStopId})`.
  - `HomeTabStore` with `static const key = 'home_tab.v1'`, `static const legacyBoardOpenKey = 'board_open.v1'`, `Future<HomeTabStart> readStart()`, `Future<void> save(HomeTab)`; `homeTabStoreProvider`.
  - `homeTabProvider = NotifierProvider<HomeTabNotifier, HomeTab?>`: null only while the stored tab is read. `HomeTabNotifier.fixed(HomeTab)` (tests: no read). Methods: `void select(HomeTab)` (shows and stores it), `void showBoard(String stopId)` (Board tab on that stop), `void openStop(String stopId)` (the Board when the Board is showing; else the stop's card and the Map).
  - `BoardStop(String stopId, {bool nearMe = false})` (value equality).
  - `boardStopProvider = NotifierProvider<BoardStopNotifier, BoardStop?>` with `void select(String stopId, {bool nearMe = false})` and `void restore(String stopId)` (only when nothing is picked).

- [ ] **Step 1: Write the failing test**

Create `test/state/home_tab_provider_test.dart`:

```dart
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A fresh app start over what the phone holds ([prefs]).
ProviderContainer _start([Map<String, Object> prefs = const {}]) {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(prefs);
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

/// The same phone, started again.
ProviderContainer _restart() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

Future<HomeTab?> _tabOnceRead(ProviderContainer c) async {
  c.read(homeTabProvider);
  await pumpEventQueue();
  return c.read(homeTabProvider);
}

void main() {
  test('a first launch opens on the Board (spec 2026-10-15 §2.2)', () async {
    final c = _start();
    expect(c.read(homeTabProvider), isNull, reason: 'nothing is shown until the stored tab is read');
    expect(await _tabOnceRead(c), HomeTab.board);
  });

  test('the tab used last is stored, and the next start opens on it', () async {
    final c = _start();
    await _tabOnceRead(c);
    c.read(homeTabProvider.notifier).select(HomeTab.map);
    expect(c.read(homeTabProvider), HomeTab.map);
    await pumpEventQueue();
    expect(await SharedPreferencesAsync().getString(HomeTabStore.key), 'map');
    expect(await _tabOnceRead(_restart()), HomeTab.map);
  });

  test('an upgrade with a Board left open in 1.4 opens the Board on that stop, and the old key goes', () async {
    final c = _start({HomeTabStore.legacyBoardOpenKey: 'C'});
    expect(await _tabOnceRead(c), HomeTab.board);
    expect(c.read(boardStopProvider), const BoardStop('C'));
    expect(await SharedPreferencesAsync().getString(HomeTabStore.legacyBoardOpenKey), isNull);
    expect(await SharedPreferencesAsync().getString(HomeTabStore.key), 'board');
    final next = _restart();
    expect(await _tabOnceRead(next), HomeTab.board);
    expect(next.read(boardStopProvider), isNull, reason: 'the migration runs once');
  });

  test('an empty 1.4 key is cleared and opens as a first launch would', () async {
    final c = _start({HomeTabStore.legacyBoardOpenKey: '', HomeTabStore.key: 'map'});
    expect(await _tabOnceRead(c), HomeTab.map);
    expect(c.read(boardStopProvider), isNull);
    expect(await SharedPreferencesAsync().getString(HomeTabStore.legacyBoardOpenKey), isNull);
  });

  test('a link that lands before the stored tab is read wins over it, and over the 1.4 Board', () async {
    final c = _start({HomeTabStore.key: 'map', HomeTabStore.legacyBoardOpenKey: 'C'});
    c.read(homeTabProvider);
    c.read(homeTabProvider.notifier).showBoard('A');
    await pumpEventQueue();
    expect(c.read(homeTabProvider), HomeTab.board);
    expect(c.read(boardStopProvider), const BoardStop('A'));
    expect(await SharedPreferencesAsync().getString(HomeTabStore.legacyBoardOpenKey), isNull);
  });

  test('a tab chosen before the stored one is read stays chosen', () async {
    final c = _start({HomeTabStore.key: 'board'});
    c.read(homeTabProvider);
    c.read(homeTabProvider.notifier).select(HomeTab.map);
    await pumpEventQueue();
    expect(c.read(homeTabProvider), HomeTab.map);
  });

  test('openStop shows the stop on the Board when the Board is showing, else opens its card on the map', () async {
    final c = _start({HomeTabStore.key: 'board'});
    await _tabOnceRead(c);
    c.read(homeTabProvider.notifier).openStop('B');
    expect(c.read(boardStopProvider), const BoardStop('B'));
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
    c.read(homeTabProvider.notifier).select(HomeTab.map);
    c.read(homeTabProvider.notifier).openStop('C');
    expect(c.read(homeSheetProvider), const StopSheet('C'));
    expect(c.read(boardStopProvider), const BoardStop('B'), reason: 'the Board keeps its own stop');
  });

  test('a fixed tab (tests) is there at once and reads nothing', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData({HomeTabStore.key: 'board'});
    final c = ProviderContainer(overrides: [homeTabProvider.overrideWith(() => HomeTabNotifier.fixed(HomeTab.map))]);
    addTearDown(c.dispose);
    expect(c.read(homeTabProvider), HomeTab.map);
  });

  test("restore never replaces a stop the rider picked", () {
    final c = _start();
    c.read(boardStopProvider.notifier).select('A', nearMe: true);
    c.read(boardStopProvider.notifier).restore('C');
    expect(c.read(boardStopProvider), const BoardStop('A', nearMe: true));
  });
}
```


- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/state/home_tab_provider_test.dart`
Expected: FAIL to compile: `Error: Error when reading 'lib/state/home_tab_provider.dart': No such file or directory`.

- [ ] **Step 3: Write the implementation**

Create `lib/state/home_tab_provider.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_sheet_provider.dart';

/// The home's two tabs (spec 2026-10-15 §2).
enum HomeTab { board, map }

/// Where a cold start opens: [tab], and on an upgrade from a Board left open in 1.4, that Board's stop.
@immutable
class HomeTabStart {
  const HomeTabStart(this.tab, {this.boardStopId});
  final HomeTab tab;
  final String? boardStopId;
}

/// The tab used last (spec §2.2), kept on the phone as `board` or `map`.
class HomeTabStore {
  const HomeTabStore();

  static const key = 'home_tab.v1';

  /// 1.4's "Board left open" (a stop id). Read once on upgrade, then cleared.
  static const legacyBoardOpenKey = 'board_open.v1';

  /// The tab used last; the Board on a first launch. An upgrade from 1.4 with a Board left open opens the Board on
  /// that stop: the old key is cleared and the Board is stored as the tab.
  Future<HomeTabStart> readStart() async {
    final prefs = SharedPreferencesAsync();
    final legacy = await prefs.getString(legacyBoardOpenKey);
    if (legacy != null) {
      await prefs.remove(legacyBoardOpenKey);
      if (legacy.isNotEmpty) {
        await prefs.setString(key, HomeTab.board.name);
        return HomeTabStart(HomeTab.board, boardStopId: legacy);
      }
    }
    final stored = await prefs.getString(key);
    return HomeTabStart(stored == HomeTab.map.name ? HomeTab.map : HomeTab.board);
  }

  Future<void> save(HomeTab tab) => SharedPreferencesAsync().setString(key, tab.name);
}

final homeTabStoreProvider = Provider<HomeTabStore>((ref) => const HomeTabStore());

/// The tab showing: null for the moment the stored one is being read at launch.
class HomeTabNotifier extends Notifier<HomeTab?> {
  HomeTabNotifier();

  /// Starts on [tab] without reading the phone (tests).
  factory HomeTabNotifier.fixed(HomeTab tab) = _FixedHomeTab;

  /// A tab was chosen (a tap, a link, a follow) while the stored one was still being read: the choice wins.
  bool _chosen = false;

  @override
  HomeTab? build() {
    _chosen = false;
    unawaited(_readStart());
    return null;
  }

  Future<void> _readStart() async {
    var start = const HomeTabStart(HomeTab.board);
    try {
      start = await ref.read(homeTabStoreProvider).readStart();
    } catch (_) {
      // Unreadable: a first launch.
    }
    if (!ref.mounted) return;
    final stop = start.boardStopId;
    if (stop != null) ref.read(boardStopProvider.notifier).restore(stop);
    if (!_chosen) state = start.tab;
  }

  /// Shows [tab] and stores it as the one to open on next time.
  void select(HomeTab tab) {
    _chosen = true;
    if (state == tab) return;
    state = tab;
    unawaited(ref.read(homeTabStoreProvider).save(tab).catchError((Object _) {}));
  }

  /// The Board tab, showing [stopId] (the stop line, Open board, a notification, a `/board/` link).
  void showBoard(String stopId) {
    ref.read(boardStopProvider.notifier).select(stopId);
    select(HomeTab.board);
  }

  /// [stopId]'s departures where the rider is: on the Board, the Board shows it; anywhere else, its card on the map.
  void openStop(String stopId) {
    if (state == HomeTab.board) return showBoard(stopId);
    ref.read(homeSheetProvider.notifier).open(StopSheet(stopId));
    select(HomeTab.map);
  }
}

class _FixedHomeTab extends HomeTabNotifier {
  _FixedHomeTab(this._tab);
  final HomeTab _tab;

  @override
  HomeTab? build() => _tab;
}

final homeTabProvider = NotifierProvider<HomeTabNotifier, HomeTab?>(HomeTabNotifier.new);

/// The stop the Board shows, as last picked. [nearMe]: picked by Near me (its chip is the selected one).
@immutable
class BoardStop {
  const BoardStop(this.stopId, {this.nearMe = false});
  final String stopId;
  final bool nearMe;

  @override
  bool operator ==(Object other) => other is BoardStop && other.stopId == stopId && other.nearMe == nearMe;
  @override
  int get hashCode => Object.hash(stopId, nearMe);
  @override
  String toString() => 'BoardStop($stopId${nearMe ? ', near me' : ''})';
}

/// The Board's picked stop, or null while none is (the Board then shows your stop). Kept for the session only.
class BoardStopNotifier extends Notifier<BoardStop?> {
  @override
  BoardStop? build() => null;

  /// The Board shows [stopId].
  void select(String stopId, {bool nearMe = false}) {
    state = BoardStop(stopId, nearMe: nearMe);
  }

  /// A Board left open in 1.4, unless something was picked first (a launch link wins).
  void restore(String stopId) => state ??= BoardStop(stopId);
}

final boardStopProvider = NotifierProvider<BoardStopNotifier, BoardStop?>(BoardStopNotifier.new);
```


- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/state/home_tab_provider_test.dart`
Expected: `All tests passed!` (9 tests).

- [ ] **Step 5: Analyze and run the non-golden suite**

Run: `flutter analyze` → `No issues found!`
Run: `flutter test $(find test -name '*_test.dart' ! -name '*golden_test.dart' | sort)` → `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/state/home_tab_provider.dart test/state/home_tab_provider_test.dart
git status --short
git commit -m "feat(state): the home's two tabs, the tab used last, and the 1.4 Board migration

home_tab.v1 holds board or map; a first launch opens on the Board. An
upgrade with board_open.v1 opens the Board on that stop once, then the
old key goes. A tab chosen while the stored one is read (a link) wins.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


---

### Task 2: The kit's tab bar

**Files:**
- Create: `lib/ui/kit/bb_tab_bar.dart`
- Modify: `lib/ui/kit/kit.dart` (export it)
- Test: `test/kit/tab_bar_test.dart`

**Interfaces:**
- Consumes: `BBPressable(exposeSemantics: false, haptic: true)`, `BBMotion`, `context.bb` tokens (`surface`, `line`, `muted`, `brandInk`, `brandSoft`, `text.label`).
- Produces:
  - `BBTab({required String label, required IconData icon, required IconData activeIcon, Key? key})`.
  - `BBTabBar({required List<BBTab> tabs, required int index, required ValueChanged<int> onSelect})`; `static const double height = 56`. Semantics: a `SemanticsRole.tabBar` container whose children are `SemanticsRole.tab` buttons labelled `'<label>, tab <i> of <n>'` with a selected state and a tap action. (Task 8 adds `maxRowWidth`.)

- [ ] **Step 1: Write the failing test**

Create `test/kit/tab_bar_test.dart`:

```dart
import 'dart:ui' show SemanticsRole;

import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderDecoratedBox, RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'contrast_test.dart' show contrast;
import 'kit_test_helpers.dart';

const _tabs = [
  BBTab(label: 'Board', icon: BBIcons.board, activeIcon: BBIcons.boardFill, key: ValueKey('t-board')),
  BBTab(label: 'Map', icon: BBIcons.map, activeIcon: BBIcons.mapFill, key: ValueKey('t-map')),
];

/// The bar at the bottom of a phone screen, with [bottomInset] of safe area under it.
Widget _host(int index, ValueChanged<int> onSelect,
        {double bottomInset = 0, Brightness brightness = Brightness.light, double textScale = 1, double width = 390}) =>
    kitHost(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: EdgeInsets.only(bottom: bottomInset)),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: BBTabBar(tabs: _tabs, index: index, onSelect: onSelect),
          ),
        ),
      ),
      brightness: brightness,
      textScale: textScale,
      width: width,
    );

/// The icon a tab shows.
Icon _icon(WidgetTester tester, String key) =>
    tester.widget<Icon>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Icon)));

Text _label(WidgetTester tester, String label) => tester.widget<Text>(find.text(label));

void main() {
  setUpAll(loadAppFonts);

  testWidgets('56 pt tall plus the bottom safe area, on surface with a line hairline on top (spec 2026-10-15 §2.1)',
      (tester) async {
    await tester.pumpWidget(_host(0, (_) {}, bottomInset: 34));
    expect(tester.getSize(find.byType(BBTabBar)).height, BBTabBar.height + 34);
    final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(BBTabBar), matching: find.byType(DecoratedBox)).first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.color, BBColors.light.surface);
    expect((deco.border! as Border).top.color, BBColors.light.line);
  });

  for (final b in Brightness.values) {
    testWidgets('the active tab is brandInk with its filled icon on a brandSoft pill; the other is muted (${b.name})',
        (tester) async {
      final colors = b == Brightness.dark ? BBColors.dark : BBColors.light;
      await tester.pumpWidget(_host(0, (_) {}, brightness: b));
      await tester.pumpAndSettle();
      expect(_icon(tester, 't-board').icon, BBIcons.boardFill);
      expect(_icon(tester, 't-board').color, colors.brandInk);
      expect(_label(tester, 'Board').style!.color, colors.brandInk);
      expect(_icon(tester, 't-map').icon, BBIcons.map);
      expect(_label(tester, 'Map').style!.color, colors.muted);
      final pill = tester.widget<AnimatedContainer>(
          find.descendant(of: find.byKey(const ValueKey('t-board')), matching: find.byType(AnimatedContainer)));
      expect((pill.decoration! as BoxDecoration).color, colors.brandSoft);
      // WCAG AA: labels are text (4.5:1) on the bar, and the active icon sits on its pill.
      expect(contrast(colors.muted, colors.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(colors.brandInk, colors.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(colors.brandInk, colors.brandSoft), greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('a tap anywhere on a tab selects it', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(_host(0, picked.add));
    final map = tester.getRect(find.byKey(const ValueKey('t-map')));
    expect(map.height, greaterThanOrEqualTo(BBTabBar.height), reason: 'the whole height is the target');
    await tester.tapAt(map.topRight + const Offset(-4, 4));
    expect(picked, [1]);
  });

  testWidgets('each tab is a selectable tab button: "Board, tab 1 of 2", selected', (tester) async {
    final handle = tester.ensureSemantics();
    final picked = <int>[];
    await tester.pumpWidget(_host(0, picked.add));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Board, tab 1 of 2')),
      isSemantics(label: 'Board, tab 1 of 2', isButton: true, hasSelectedState: true, isSelected: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Map, tab 2 of 2')),
      isSemantics(label: 'Map, tab 2 of 2', isButton: true, hasSelectedState: true, isSelected: false, hasTapAction: true),
    );
    expect(tester.getSemantics(find.bySemanticsLabel('Map, tab 2 of 2')).role, SemanticsRole.tab);
    tester.semantics.tap(find.semantics.byLabel('Map, tab 2 of 2'));
    expect(picked, [1]);
    handle.dispose();
  });

  testWidgets('under Reduce Motion the pill moves at once', (tester) async {
    Widget host(int i) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _host(i, (_) {}),
        );
    await tester.pumpWidget(host(0));
    await tester.pumpWidget(host(1));
    await tester.pump();
    final pill = tester.renderObject<RenderDecoratedBox>(find.descendant(
        of: find.byKey(const ValueKey('t-map')), matching: find.byType(DecoratedBox)).first);
    expect((pill.decoration as BoxDecoration).color, BBColors.light.brandSoft);
  });

  for (final b in Brightness.values) {
    testWidgets('at 2x text on a 320 pt phone the labels read in full and the bar grows (${b.name})', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(1, (_) {}, textScale: 2, width: 320, brightness: b));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['Board', 'Map']) {
        final p = tester.renderObject<RenderParagraph>(find.text(label));
        expect(p.size.width, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.5),
            reason: '$label is cut short');
      }
      expect(tester.getSize(find.byType(BBTabBar)).height, greaterThan(BBTabBar.height));
    });
  }
}
```


- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/kit/tab_bar_test.dart`
Expected: FAIL to compile: `BBTab` and `BBTabBar` aren't defined.

- [ ] **Step 3: Write the tab bar**

Create `lib/ui/kit/bb_tab_bar.dart`:

```dart
import 'dart:ui' show SemanticsRole;

import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

/// One tab of a [BBTabBar]: its [label], its [icon], and the [activeIcon] it shows while selected.
@immutable
class BBTab {
  const BBTab({required this.label, required this.icon, required this.activeIcon, this.key});

  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// The tab's own key, for tests.
  final Key? key;
}

/// The bottom tab bar (spec 2026-10-15 §2.1): at least [height] pt tall plus the bottom safe area, on `surface` with a
/// `line` hairline on top. Inactive tabs are `muted`; the active one is `brandInk`, its filled icon on a `brandSoft`
/// pill, so the selection never rests on colour alone. Each tab is a button with a selected state that screen readers
/// read as "Board, tab 1 of 2, selected". The pill cross-fades over [BBMotion.standard], at once under Reduce Motion.
/// Labels grow with the text size, and the bar grows with them.
class BBTabBar extends StatelessWidget {
  const BBTabBar({super.key, required this.tabs, required this.index, required this.onSelect});

  final List<BBTab> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  /// The bar's height above the bottom safe area, at 1x text.
  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bb.colors.surface,
        border: Border(top: BorderSide(color: bb.colors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Semantics(
          role: SemanticsRole.tabBar,
          container: true,
          explicitChildNodes: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: height),
            // Both tabs as tall as the taller one, and the whole height theirs to tap.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, tab) in tabs.indexed)
                    Expanded(
                      child: _TabButton(
                        key: tab.key,
                        tab: tab,
                        active: i == index,
                        semanticLabel: '${tab.label}, tab ${i + 1} of ${tabs.length}',
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.tab,
    required this.active,
    required this.semanticLabel,
    required this.onTap,
  });

  final BBTab tab;
  final bool active;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final fg = active ? bb.colors.brandInk : bb.colors.muted;
    return Semantics(
      role: SemanticsRole.tab,
      button: true,
      selected: active,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: BBPressable(
        exposeSemantics: false,
        haptic: true,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: BBSpace.xs),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: BBMotion.of(context, BBMotion.standard),
                curve: BBMotion.curve,
                width: 56,
                height: 28,
                decoration: BoxDecoration(
                  color: active ? bb.colors.brandSoft : bb.colors.brandSoft.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(active ? tab.activeIcon : tab.icon, size: 22, color: fg),
              ),
              const SizedBox(height: 2),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bb.text.label.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```


In `lib/ui/kit/kit.dart`:

Edit 1 of 1 (near line 28 before the edit). Find:

```dart
export 'bb_skeleton.dart';
export 'bb_stepper.dart';
export 'bb_switch.dart';
export 'bb_text_field.dart';
export 'bb_time.dart';
export 'bb_theme.dart';
```

Replace with:

```dart
export 'bb_skeleton.dart';
export 'bb_stepper.dart';
export 'bb_switch.dart';
export 'bb_tab_bar.dart';
export 'bb_text_field.dart';
export 'bb_time.dart';
export 'bb_theme.dart';
```


The bar is sized by its content: `IntrinsicHeight` lets both tabs be as tall as the taller one without the `Row` stretching to its parent's height (the shell puts the bar in a `Column`, where a stretching row would get an unbounded height).

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/kit/tab_bar_test.dart`
Expected: `All tests passed!` (8 tests). The Reduce Motion test fails if the pill's `AnimatedContainer` uses `BBMotion.standard` directly instead of `BBMotion.of(context, BBMotion.standard)`.

- [ ] **Step 5: Analyze and run the non-golden suite**

Run: `flutter analyze` → `No issues found!`
Run: `flutter test $(find test -name '*_test.dart' ! -name '*golden_test.dart' | sort)` → `All tests passed!` (`kit_boundary_test.dart` included: the bar is in the kit).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/kit/bb_tab_bar.dart lib/ui/kit/kit.dart test/kit/tab_bar_test.dart
git status --short
git commit -m "feat(kit): BBTabBar, the home's bottom tab bar

56 pt plus the bottom safe area on surface with a line hairline; the
active tab is brandInk with its filled icon on a brandSoft pill. Each tab
is a tab-role button with a selected state, read as \"Board, tab 1 of 2\".

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


---

### Task 3: Recent stops, the Board's chips, and which stop it shows

**Files:**
- Create: `lib/state/recent_stops_provider.dart`, `lib/state/board_providers.dart`
- Modify: `lib/state/providers.dart` (`SettingsNotifier.loaded`, `settingsLoadedProvider`)
- Modify: `lib/state/home_tab_provider.dart` (a Board pick is a recent view)
- Modify: `lib/ui/home/home_screen.dart` (a stop's card is a recent view)
- Test: `test/state/board_providers_test.dart`, `test/ui/recent_stops_test.dart`

**Interfaces:**
- Consumes: `boardStopProvider`, `BoardStop` (Task 1); `settingsProvider`, `savedPlacesProvider`, `SavedPlace`, `StopPlace` (unchanged).
- Produces:
  - `const maxRecentStops = 8`; `RecentStopStore([SharedPreferencesAsync?])` with `static const key = 'recent_stops.v1'`, `Future<List<String>> read()`, `Future<void> push(String stopId)`; `recentStopStoreProvider`.
  - `recentStopsProvider = AsyncNotifierProvider<RecentStopsNotifier, List<String>>` (newest first) with `Future<void> push(String stopId)` (serial; never throws).
  - `enum BoardChipKind { yours, saved, recent }`; `BoardChip(BoardChipKind kind, String stopId, {SavedPlace? place})`; `const maxRecentChips = 3`; `List<BoardChip> boardStopChips({String? yourStopId, List<SavedPlace> saved, List<String> recent})`.
  - `boardChipsProvider` (`Provider<List<BoardChip>>`), `boardShownStopProvider` (`Provider<BoardStop?>`), `boardReadyProvider` (`Provider<bool>`).
  - `SettingsNotifier.loaded` (`Future<void>`, completes when the saved settings are in; at once for a test notifier that overrides `build`), `settingsLoadedProvider` (`FutureProvider<void>`).
  - `BoardStopNotifier.select` now also pushes the stop to the recents; `HomeScreen` pushes a stop whose card opens.

- [ ] **Step 1: Write the failing tests**

Create `test/state/board_providers_test.dart`:

```dart
import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/board_providers.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/recent_stops_provider.dart';
import 'package:busboard_nl/state/saved_place_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

SavedPlace _saved(String id, Place place, {SavedPlaceIcon icon = SavedPlaceIcon.star}) =>
    SavedPlace(id: id, name: id, icon: icon, place: place);

final _home = _saved('Home', StopPlace(stopId: 'H', name: 'Harbour'), icon: SavedPlaceIcon.home);
final _work = _saved('Work', StopPlace(stopId: 'W', name: 'Water St'), icon: SavedPlaceIcon.work);
final _pin = _saved('Gym', PinPlace(lat: 47.5, lon: -52.7, label: 'Gym'));

class _Mine extends SettingsNotifier {
  _Mine(this.stopId);
  final String? stopId;
  @override
  AppSettings build() => AppSettings(selectedStopId: stopId);
}

class _Saved extends SavedPlacesNotifier {
  _Saved(this.places);
  final List<SavedPlace> places;
  @override
  Future<List<SavedPlace>> build() async => places;
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  group('recent stops (recent_stops.v1)', () {
    test('newest first, each stop once', () async {
      final s = RecentStopStore();
      for (final id in ['A', 'B', 'A', 'C']) {
        await s.push(id);
      }
      expect(await s.read(), ['C', 'A', 'B']);
    });

    test('keeps the last $maxRecentStops only', () async {
      final s = RecentStopStore();
      for (var i = 0; i < maxRecentStops + 3; i++) {
        await s.push('$i');
      }
      final read = await s.read();
      expect(read, hasLength(maxRecentStops));
      expect(read.first, '${maxRecentStops + 2}');
    });

    test('a malformed entry reads as none', () async {
      for (final raw in ['not json', '{"a":1}', '[1, "", "A", "A"]']) {
        await SharedPreferencesAsync().setString(RecentStopStore.key, raw);
        expect(await RecentStopStore().read(), raw.startsWith('[') ? ['A'] : isEmpty, reason: raw);
      }
    });

    test('picking a stop on the Board records it, newest first', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(boardStopProvider.notifier).select('A');
      c.read(boardStopProvider.notifier).select('B');
      c.read(boardStopProvider.notifier).select('A');
      await pumpEventQueue();
      expect(c.read(recentStopsProvider).value, ['A', 'B']);
      expect(await RecentStopStore().read(), ['A', 'B']);
    });

    test('a store that fails to write loses only the recent', () async {
      final c = ProviderContainer(overrides: [recentStopStoreProvider.overrideWithValue(_FailingStore())]);
      addTearDown(c.dispose);
      await expectLater(c.read(recentStopsProvider.notifier).push('A'), completes);
    });
  });

  group('the Board chips (spec 2026-10-15 §3)', () {
    test('your stop, then saved stops, then up to 3 recent stops; places that are not stops have none', () {
      expect(
        boardStopChips(yourStopId: 'Y', saved: [_home, _pin, _work], recent: ['R1', 'R2', 'R3', 'R4']),
        [
          const BoardChip(BoardChipKind.yours, 'Y'),
          BoardChip(BoardChipKind.saved, 'H', place: _home),
          BoardChip(BoardChipKind.saved, 'W', place: _work),
          const BoardChip(BoardChipKind.recent, 'R1'),
          const BoardChip(BoardChipKind.recent, 'R2'),
          const BoardChip(BoardChipKind.recent, 'R3'),
        ],
      );
    });

    test('a stop has one chip, the first it earns, and recents skip the ones already there', () {
      final chips = boardStopChips(
        yourStopId: 'H',
        saved: [_home, _work, _saved('Work again', StopPlace(stopId: 'W', name: 'Water St'))],
        recent: ['W', 'H', 'R1', 'R2', 'R3'],
      );
      expect(chips.map((c) => '${c.kind.name}:${c.stopId}'),
          ['yours:H', 'saved:W', 'recent:R1', 'recent:R2', 'recent:R3']);
    });

    test('with nothing chosen, nothing saved and nothing viewed, there are none', () {
      expect(boardStopChips(), isEmpty);
    });
  });

  group('the stop the Board shows', () {
    ProviderContainer container({String? mine, List<SavedPlace> saved = const []}) {
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith(() => _Mine(mine)),
        savedPlacesProvider.overrideWith(() => _Saved(saved)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('the stop picked, over your stop', () async {
      final c = container(mine: 'Y', saved: [_home]);
      await c.read(savedPlacesProvider.future);
      expect(c.read(boardShownStopProvider), const BoardStop('Y'));
      c.read(boardStopProvider.notifier).select('R', nearMe: true);
      expect(c.read(boardShownStopProvider), const BoardStop('R', nearMe: true));
    });

    test('with no stop chosen, the first saved place that is a stop', () async {
      final c = container(saved: [_pin, _work, _home]);
      await c.read(savedPlacesProvider.future);
      expect(c.read(boardShownStopProvider), const BoardStop('W'));
    });

    test('none at all: null, and the Board asks you to choose', () async {
      final c = container(saved: [_pin]);
      await c.read(savedPlacesProvider.future);
      expect(c.read(boardShownStopProvider), isNull);
    });

    test('not ready until your stop and your saved places are read', () async {
      final c = container(mine: 'Y');
      expect(c.read(boardReadyProvider), isFalse);
      await c.read(savedPlacesProvider.future);
      await c.read(settingsLoadedProvider.future);
      expect(c.read(boardReadyProvider), isTrue);
    });
  });
}

class _FailingStore extends RecentStopStore {
  @override
  Future<void> push(String stopId) async => throw StateError('disk full');
}
```


Create `test/ui/recent_stops_test.dart`:

```dart
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/recent_stops_provider.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

void main() {
  testWidgets("a stop's card on the map counts as viewing the stop (spec 2026-10-15 §3)", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: DateTime(2026, 10, 12, 13));
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    c.read(homeSheetProvider.notifier).open(const StopSheet('B'));
    await tester.pumpAndSettle();
    c.read(homeSheetProvider.notifier).open(const StopSheet('C'));
    await tester.pumpAndSettle();
    expect(c.read(recentStopsProvider).value, ['C', 'B']);
  });
}
```


- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/state/board_providers_test.dart test/ui/recent_stops_test.dart`
Expected: FAIL to compile: `Error when reading 'lib/state/board_providers.dart'` and `'lib/state/recent_stops_provider.dart'`.

- [ ] **Step 3: Write the recent stops store**

Create `lib/state/recent_stops_provider.dart`:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How many recently viewed stops are kept. The Board shows at most three of them, after your stop and your saved
/// stops, so a few more are kept than it shows.
const maxRecentStops = 8;

/// The stops viewed lately, on the Board or in a stop's card (spec 2026-10-15 §3): stop ids, newest first, each once.
/// Kept on the phone only.
class RecentStopStore {
  RecentStopStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _prefs;

  static const key = 'recent_stops.v1';

  /// Newest first; an unreadable or malformed entry reads as none.
  Future<List<String>> read() async {
    final raw = await _prefs.getString(key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return {for (final id in decoded) if (id is String && id.isNotEmpty) id}.take(maxRecentStops).toList();
    } on FormatException {
      return const [];
    }
  }

  /// [stopId] becomes the newest; an older visit to it is dropped.
  Future<void> push(String stopId) async {
    final next = [stopId, for (final id in await read()) if (id != stopId) id].take(maxRecentStops).toList();
    await _prefs.setString(key, jsonEncode(next));
  }
}

final recentStopStoreProvider = Provider<RecentStopStore>((ref) => RecentStopStore());

/// The recently viewed stops, newest first.
class RecentStopsNotifier extends AsyncNotifier<List<String>> {
  Future<void> _queue = Future.value();

  @override
  Future<List<String>> build() => ref.read(recentStopStoreProvider).read();

  /// Records a view of [stopId]. One at a time (the store reads, changes and writes the whole list), and it never
  /// throws: a view that can't be stored (a full disk) is only a recent lost.
  Future<void> push(String stopId) => _queue = _queue.then((_) async {
        try {
          final store = ref.read(recentStopStoreProvider);
          await store.push(stopId);
          final next = await store.read();
          if (ref.mounted) state = AsyncData(next);
        } catch (_) {
          // Not stored.
        }
      });
}

final recentStopsProvider = AsyncNotifierProvider<RecentStopsNotifier, List<String>>(RecentStopsNotifier.new);
```


- [ ] **Step 4: Write the chips and the shown stop**

Create `lib/state/board_providers.dart`:

```dart
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/trip_planner/saved_place_store.dart';
import '../domain/trip_planner/place.dart';
import 'home_tab_provider.dart';
import 'providers.dart';
import 'recent_stops_provider.dart';
import 'saved_place_providers.dart';

/// What a Board stop chip stands for (spec 2026-10-15 §3).
enum BoardChipKind { yours, saved, recent }

/// One of the Board's stop chips: [stopId], and for a saved place the [place] it was saved as (its name and icon).
@immutable
class BoardChip {
  const BoardChip(this.kind, this.stopId, {this.place});
  final BoardChipKind kind;
  final String stopId;
  final SavedPlace? place;

  @override
  bool operator ==(Object other) =>
      other is BoardChip && other.kind == kind && other.stopId == stopId && other.place?.id == place?.id;
  @override
  int get hashCode => Object.hash(kind, stopId, place?.id);
  @override
  String toString() => 'BoardChip(${kind.name}, $stopId)';
}

/// The most recently viewed stops the Board shows as chips.
const maxRecentChips = 3;

/// The Board's stop chips in order: your stop, then saved places that are stops, then up to [maxRecentChips] recently
/// viewed stops (newest first). Each stop has one chip, the first it earns. Near me and ＋ always follow them.
List<BoardChip> boardStopChips({
  String? yourStopId,
  List<SavedPlace> saved = const [],
  List<String> recent = const [],
}) {
  // Elements are built in order, so by the recents every stop chip before them is in [seen].
  final seen = <String>{};
  return [
    if (yourStopId != null && seen.add(yourStopId)) BoardChip(BoardChipKind.yours, yourStopId),
    for (final p in saved)
      if (p.place case StopPlace(:final stopId) when seen.add(stopId)) BoardChip(BoardChipKind.saved, stopId, place: p),
    ...[
      for (final id in recent)
        if (seen.add(id)) BoardChip(BoardChipKind.recent, id),
    ].take(maxRecentChips),
  ];
}

/// The Board's stop chips for the rider's stop, saved places and recent stops.
final boardChipsProvider = Provider<List<BoardChip>>(
  (ref) => boardStopChips(
    yourStopId: ref.watch(settingsProvider.select((s) => s.selectedStopId)),
    saved: ref.watch(savedPlacesProvider).value ?? const [],
    recent: ref.watch(recentStopsProvider).value ?? const [],
  ),
);

/// The stop the Board shows: the one picked, else your stop, else the first saved place that is a stop. Null when
/// there is none: the Board asks you to choose your stop.
final boardShownStopProvider = Provider<BoardStop?>((ref) {
  final picked = ref.watch(boardStopProvider);
  if (picked != null) return picked;
  final mine = ref.watch(settingsProvider.select((s) => s.selectedStopId));
  if (mine != null) return BoardStop(mine);
  for (final p in ref.watch(savedPlacesProvider).value ?? const <SavedPlace>[]) {
    if (p.place case StopPlace(:final stopId)) return BoardStop(stopId);
  }
  return null;
});

/// Your stop and your saved places have been read from the phone. Until then "no stop" may only mean "not read yet",
/// so the Board shows neither its empty state nor a nearby-stops list that would ask for the location.
final boardReadyProvider = Provider<bool>(
  (ref) => !ref.watch(settingsLoadedProvider).isLoading && !ref.watch(savedPlacesProvider).isLoading,
);
```


In `lib/state/providers.dart`:

Edit 1 of 2 (near line 59 before the edit). Find:

```dart
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    _loadFromPrefs();
    return const AppSettings();
  }

```

Replace with:

```dart
}

class SettingsNotifier extends Notifier<AppSettings> {
  /// Completes once the saved settings are read: at once for a notifier that reads none (tests).
  Future<void> get loaded => _loaded;
  Future<void> _loaded = Future.value();

  @override
  AppSettings build() {
    _loaded = _loadFromPrefs();
    return const AppSettings();
  }

```

Edit 2 of 2 (near line 132 before the edit). Find:

```dart
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
```

Replace with:

```dart
  }
}

/// Done once [settingsProvider] holds the saved settings, not the defaults it starts with.
final settingsLoadedProvider = FutureProvider<void>((ref) => ref.watch(settingsProvider.notifier).loaded);

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
```


In `lib/state/home_tab_provider.dart`:

Edit 1 of 2 (near line 5 before the edit). Find:

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'home_sheet_provider.dart';

/// The home's two tabs (spec 2026-10-15 §2).
enum HomeTab { board, map }
```

Replace with:

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'home_sheet_provider.dart';
import 'recent_stops_provider.dart';

/// The home's two tabs (spec 2026-10-15 §2).
enum HomeTab { board, map }
```

Edit 2 of 2 (near line 129 before the edit). Find:

```dart
  @override
  BoardStop? build() => null;

  /// The Board shows [stopId].
  void select(String stopId, {bool nearMe = false}) {
    state = BoardStop(stopId, nearMe: nearMe);
  }

  /// A Board left open in 1.4, unless something was picked first (a launch link wins).
```

Replace with:

```dart
  @override
  BoardStop? build() => null;

  /// The Board shows [stopId], which becomes the most recently viewed stop.
  void select(String stopId, {bool nearMe = false}) {
    state = BoardStop(stopId, nearMe: nearMe);
    unawaited(ref.read(recentStopsProvider.notifier).push(stopId));
  }

  /// A Board left open in 1.4, unless something was picked first (a launch link wins).
```


In `lib/ui/home/home_screen.dart`:

Edit 1 of 2 (near line 27 before the edit). Find:

```dart
import '../../state/map_pick_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../../state/seen_flags.dart';
import '../../state/trip_planner_providers.dart';
import '../arrival_alerts/alert_bell.dart';
```

Replace with:

```dart
import '../../state/map_pick_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../../state/recent_stops_provider.dart';
import '../../state/seen_flags.dart';
import '../../state/trip_planner_providers.dart';
import '../arrival_alerts/alert_bell.dart';
```

Edit 2 of 2 (near line 793 before the edit). Find:

```dart
      case StopSheet(:final stopId):
        _toHalfAfterBuild();
        _centreOnStop(stopId);
      case BusSheet() || OptionsSheet() || JourneySheet():
        _centrePending = null;
        _toHalfAfterBuild();
```

Replace with:

```dart
      case StopSheet(:final stopId):
        _toHalfAfterBuild();
        _centreOnStop(stopId);
        // A stop's card counts as viewing it: it joins the Board's recent stops (spec 2026-10-15 §3).
        unawaited(ref.read(recentStopsProvider.notifier).push(stopId));
      case BusSheet() || OptionsSheet() || JourneySheet():
        _centrePending = null;
        _toHalfAfterBuild();
```


- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/state/board_providers_test.dart test/ui/recent_stops_test.dart test/state/home_tab_provider_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Analyze and run the non-golden suite**

Run: `flutter analyze` → `No issues found!`
Run: `flutter test $(find test -name '*_test.dart' ! -name '*golden_test.dart' | sort)` → `All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add lib/state/recent_stops_provider.dart lib/state/board_providers.dart lib/state/providers.dart \
  lib/state/home_tab_provider.dart lib/ui/home/home_screen.dart \
  test/state/board_providers_test.dart test/ui/recent_stops_test.dart
git status --short
git commit -m "feat(state): recent stops and the Board's stop chips

recent_stops.v1 keeps the last 8 stops viewed (a Board pick or a stop's
card), newest first, each once. The chips are your stop, saved stops,
then up to 3 recents, each stop once. The Board shows the stop picked,
else your stop, else the first saved stop; it waits until both are read.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


---

### Task 4: The Board tab

**Files:**
- Create: `lib/ui/board/board_tab.dart`
- Modify: `lib/ui/home/stop_sheet.dart` (split `info` and `planFrom` out of the card header)
- Modify: `lib/ui/home/map_buttons.dart` (split `AlertsButton` and `SettingsButton` out)
- Modify: `lib/ui/home/home_sheet.dart` (`_WhereTo` becomes the public `WhereToField`)
- Modify: `lib/ui/stop_picker/near_me_list.dart` (`onPick`)
- Modify: `lib/ui/kit/bb_chip.dart` (`toggle`)
- Test: `test/ui/board_tab_test.dart`

**Interfaces:**
- Consumes: `boardStopProvider`, `BoardStop` (Task 1); `boardChipsProvider`, `boardShownStopProvider`, `boardReadyProvider`, `BoardChip`, `BoardChipKind` (Task 3); `nearestStopsProvider`, `stopArrivalsProvider`, `settingsProvider` (unchanged).
- Produces:
  - `BoardTab()` (`ConsumerStatefulWidget`, `lib/ui/board/board_tab.dart`) with `static const whereToKey = ValueKey('board-where-to')`, `nearMeKey = ValueKey('board-chip-near-me')`, `findStopKey = ValueKey('board-chip-find-stop')`, `chipsKey = ValueKey('board-chips')`, `maxWidth = 640.0`, and `static ValueKey<String> chipKey(BoardChip)` = `ValueKey('board-chip-<kind>-<stopId>')`. It expects a page around it (`BBScaffold`, Task 5) and brings its own top `SafeArea`.
  - `StopSheetContent.info(String stopId)` (the stop's number, star, refresh, name, live state; no Close) and `StopSheetContent.planFrom(String stopId)` (the "Plan a trip from here" button, key `planFromKey`). `StopSheetContent.header` keeps its look and keys.
  - `AlertsButton()` and `SettingsButton()` in `lib/ui/home/map_buttons.dart`; `MapButtons` is built from them (same semantics and badge).
  - `WhereToField({Key? key})` in `lib/ui/home/home_sheet.dart`; the map's instances carry `HomeSheetContent.whereToKey` as their widget key.
  - `NearMeList({ValueChanged<String>? onPick})`: null keeps today's "open the stop's card".
  - `BBChip(toggle: true)`: `Semantics(selected: selected)` always (false when not selected).

- [ ] **Step 1: Write the failing test**

Create `test/ui/board_tab_test.dart`:

```dart
import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/recent_stops_provider.dart';
import 'package:busboard_nl/state/saved_place_providers.dart';
import 'package:busboard_nl/state/seen_flags.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/alerts/service_alert_card.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/board/board_tab.dart';
import 'package:busboard_nl/ui/home/follow_tip.dart';
import 'package:busboard_nl/ui/home/stop_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_alerts.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/test_network.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.mine);
  final String? mine;
  @override
  AppSettings build() => AppSettings(selectedStopId: mine);
}

/// Settings still being read from the phone until [gate] completes; then your stop is A.
class _SlowSettings extends SettingsNotifier {
  _SlowSettings(this.gate);
  final Completer<void> gate;
  @override
  Future<void> get loaded => gate.future;
  @override
  AppSettings build() {
    gate.future.then((_) => state = const AppSettings(selectedStopId: 'A'));
    return const AppSettings();
  }
}

class _Saved extends SavedPlacesNotifier {
  _Saved(this.places);
  final List<SavedPlace> places;
  @override
  Future<List<SavedPlace>> build() async => places;
}

final _homeC = SavedPlace(id: 'h', name: 'Home', icon: SavedPlaceIcon.home, place: StopPlace(stopId: 'C', name: 'Stop C'));
final _gymPin = SavedPlace(id: 'g', name: 'Gym', icon: SavedPlaceIcon.star, place: PinPlace(lat: 47.5, lon: -52.7, label: 'Gym'));

ArrivalRow _row(int minutes, {String? vehicle}) => ArrivalRow(
      routeShortName: '1',
      headsign: 'Downtown',
      scheduledTime: GtfsTime.parse('13:05:00'),
      minutesAway: minutes,
      isLive: vehicle != null,
      vehicleNumber: vehicle,
      tripId: '1-$minutes',
    );

NearbyStop _near(String id, double m) =>
    NearbyStop(stop: StopInfo(stopId: id, stopName: 'Stop $id', stopLat: 47.5, stopLon: -52.7), distanceMeters: m);

/// Where the Board's routes went.
final _went = <String>[];

/// How often each stop's departures were loaded.
final _loads = <String, int>{};

/// The Board alone, under a router whose other pages only say where they are.
Future<ProviderContainer> _pumpBoard(
  WidgetTester tester, {
  String? mine = 'A',
  List<SavedPlace> saved = const [],
  List<String> recent = const [],
  List<ArrivalRow> rows = const [],
  Future<List<ArrivalRow>> Function(String stopId)? arrivals,
  Object nearby = const <NearbyStop>[],
  Future<List<NearbyStop>> Function()? findNearby,
  SettingsNotifier Function()? settings,
  List<ServiceAlert> alerts = const [],
  double textScale = 1,
  Size size = const Size(390, 844),
  ThemeData? theme,
  bool followTipSeen = true,
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  useInMemoryAlertStore();
  if (recent.isNotEmpty) await SharedPreferencesAsync().setString(RecentStopStore.key, '["${recent.join('","')}"]');
  _went.clear();
  _loads.clear();
  Widget page(GoRouterState s) => Text('PAGE ${s.uri}');
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const BBScaffold(safeTop: false, body: BoardTab())),
    for (final p in ['/search', '/alerts', '/settings'])
      GoRoute(path: p, builder: (_, s) {
        _went.add(s.uri.toString());
        return page(s);
      }),
  ]);
  addTearDown(router.dispose);
  final net = TestNetwork();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => net.repo),
      settingsProvider.overrideWith(settings ?? () => _Settings(mine)),
      savedPlacesProvider.overrideWith(() => _Saved(saved)),
      stopArrivalsProvider.overrideWith((ref, id) async {
        _loads.update(id, (n) => n + 1, ifAbsent: () => 1);
        return arrivals == null ? rows : arrivals(id);
      }),
      nearestStopsProvider.overrideWith((ref) async {
        if (findNearby != null) return findNearby();
        if (nearby is List<NearbyStop>) return nearby;
        throw nearby;
      }),
      serviceUpdatesProvider.overrideWith((ref) => Stream.value(
          ServiceUpdates(alerts: alerts, serviceStatus: null, fetchedAt: DateTime(2026, 10, 12), feedTimestamp: null))),
      if (followTipSeen) followTipSeenProvider.overrideWith(() => SeenFlagNotifier.seen(followTipSeenKey)),
      ...fakeAlertOverrides,
      ...overrides,
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: theme ?? BBTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  if (settle) await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(BoardTab)));
}

/// The chips in the row, left to right, by key.
List<String> _chipOrder(WidgetTester tester) => [
      for (final e in find.descendant(of: find.byKey(BoardTab.chipsKey), matching: find.byType(BBChip)).evaluate())
        ((e.widget.key! as ValueKey<String>).value),
    ];

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the header: Board, with Alerts (and its count) and Settings at the top right', (tester) async {
    final alert = ServiceAlert(
      sourceIds: const {'a'},
      header: 'Water Street Detour',
      description: 'Use Harbour Drive.',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
      targets: const [ServiceAlertTarget(routeId: '3')],
    );
    await _pumpBoard(tester, alerts: [alert]);
    final title = tester.widget<Text>(find.text('Board'));
    expect(DefaultTextStyle.of(tester.element(find.text('Board'))).style.fontSize ?? title.style?.fontSize,
        BBTokens.light.text.display.fontSize);
    final bell = tester.getRect(find.bySemanticsLabel('Alerts, 1 active'));
    final gear = tester.getRect(find.bySemanticsLabel('Settings'));
    expect(bell.right, lessThanOrEqualTo(gear.left), reason: 'the bell, then the gear');
    expect(gear.right, closeTo(390, BBSpace.l), reason: 'at the top right');
    await tester.tap(find.bySemanticsLabel('Alerts, 1 active'));
    await tester.pumpAndSettle();
    expect(_went, ['/alerts']);
  });

  testWidgets('Where to? opens the search', (tester) async {
    await _pumpBoard(tester);
    await tester.tap(find.byKey(BoardTab.whereToKey));
    await tester.pumpAndSettle();
    expect(_went, ['/search']);
  });

  testWidgets('the chips: your stop, saved stops, up to 3 recent stops, Near me and ＋, in that order',
      (tester) async {
    await _pumpBoard(tester, saved: [_gymPin, _homeC], recent: ['E', 'C', 'B', 'A', 'D']);
    expect(_chipOrder(tester), [
      'board-chip-yours-A',
      'board-chip-saved-C',
      'board-chip-recent-E',
      'board-chip-recent-B',
      'board-chip-recent-D',
      'board-chip-near-me',
      'board-chip-find-stop',
    ]);
    expect(find.descendant(of: find.byKey(const ValueKey('board-chip-saved-C')), matching: find.text('Home')),
        findsOneWidget, reason: 'a saved place is named as it was saved');
  });

  testWidgets('your stop shows first and its chip is the selected one; each chip has a selected state',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpBoard(tester, saved: [_homeC], rows: [_row(4)]);
    expect(find.text('Stop A'), findsWidgets);
    expect(find.text('STOP A'), findsOneWidget);
    expect(tester.widget<BBChip>(find.byKey(const ValueKey('board-chip-yours-A'))).selected, isTrue);
    expect(tester.getSemantics(find.bySemanticsLabel('Your stop, Stop A')),
        isSemantics(isButton: true, hasSelectedState: true, isSelected: true));
    expect(tester.getSemantics(find.bySemanticsLabel('Home, Stop C')),
        isSemantics(isButton: true, hasSelectedState: true, isSelected: false));
    handle.dispose();
  });

  testWidgets('a chip shows its stop, which becomes the most recent stop', (tester) async {
    final c = await _pumpBoard(tester, saved: [_homeC], rows: [_row(4)]);
    await tester.tap(find.byKey(const ValueKey('board-chip-saved-C')));
    await tester.pumpAndSettle();
    expect(find.text('STOP C'), findsOneWidget);
    expect(tester.widget<BBChip>(find.byKey(const ValueKey('board-chip-saved-C'))).selected, isTrue);
    expect(tester.widget<BBChip>(find.byKey(const ValueKey('board-chip-yours-A'))).selected, isFalse);
    expect(c.read(recentStopsProvider).value, ['C']);
  });

  testWidgets('Near me shows the nearest stop and is the selected chip', (tester) async {
    await _pumpBoard(tester, nearby: [_near('D', 60), _near('E', 200)]);
    await tester.tap(find.byKey(BoardTab.nearMeKey));
    await tester.pumpAndSettle();
    expect(find.text('STOP D'), findsOneWidget);
    expect(tester.widget<BBChip>(find.byKey(BoardTab.nearMeKey)).selected, isTrue);
    expect(tester.widget<BBChip>(find.byKey(const ValueKey('board-chip-yours-A'))).selected, isFalse);
  });

  for (final (what, nearby) in [('location refused', <NearbyStop>[]), ('location off', StateError('off'))]) {
    testWidgets('Near me with $what explains, and offers a search instead', (tester) async {
      await _pumpBoard(tester, nearby: nearby);
      await tester.tap(find.byKey(BoardTab.nearMeKey));
      await tester.pumpAndSettle();
      expect(find.text("Can't find a stop near you"), findsOneWidget);
      expect(find.text('STOP A'), findsOneWidget, reason: 'the Board keeps its stop');
      await tester.tap(find.text('Search instead'));
      await tester.pumpAndSettle();
      expect(_went, ['/search?pickStop=1']);
    });
  }

  testWidgets('＋ opens the stop search', (tester) async {
    await _pumpBoard(tester);
    await tester.tap(find.byKey(BoardTab.findStopKey));
    await tester.pumpAndSettle();
    expect(_went, ['/search?pickStop=1']);
  });

  testWidgets('no stop chosen and none saved: Choose your stop, with the stops near you', (tester) async {
    final c = await _pumpBoard(tester, mine: null, saved: [_gymPin], nearby: [_near('D', 60)]);
    expect(find.text('Choose your stop'), findsOneWidget);
    await tester.tap(find.text('Stop D'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).selectedStopId, 'D', reason: 'chosen here, it is your stop');
    expect(find.text('STOP D'), findsOneWidget);
  });

  testWidgets('no stop chosen and no location: Choose your stop offers a search', (tester) async {
    await _pumpBoard(tester, mine: null, nearby: StateError('off'));
    expect(find.text('Choose your stop'), findsOneWidget);
    await tester.tap(find.text('Search for a stop'));
    await tester.pumpAndSettle();
    expect(_went, ['/search?pickStop=1']);
  });

  testWidgets('no saved stop yet: the first saved place that is a stop shows', (tester) async {
    await _pumpBoard(tester, mine: null, saved: [_gymPin, _homeC]);
    expect(find.text('STOP C'), findsOneWidget);
  });

  testWidgets('while your stop is still being read, neither Choose your stop nor a location request', (tester) async {
    final gate = Completer<void>();
    var asked = 0;
    await _pumpBoard(
      tester,
      mine: null,
      settle: false,
      settings: () => _SlowSettings(gate),
      findNearby: () async {
        asked++;
        return [_near('D', 60)];
      },
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Choose your stop'), findsNothing);
    expect(asked, 0, reason: 'a rider with a stop is never asked for the location for it');
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('STOP A'), findsOneWidget);
    expect(asked, 0);
  });

  testWidgets("the stop's alerts come first, then its departures", (tester) async {
    final alert = ServiceAlert(
      sourceIds: const {'a'},
      header: 'Stop A moved',
      description: 'Use the pole across the street.',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.stopMoved,
      severity: ServiceAlertSeverity.warning,
      activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
      targets: const [ServiceAlertTarget(stopId: 'A')],
    );
    await _pumpBoard(tester, rows: [_row(4), _row(12)], alerts: [alert]);
    final card = tester.getRect(find.byType(ServiceAlertCard));
    expect(card.bottom, lessThanOrEqualTo(tester.getRect(find.byType(ArrivalRowTile).first).top));
  });

  testWidgets('a live row follows its bus', (tester) async {
    final c = await _pumpBoard(tester, rows: [_row(4, vehicle: '2573')]);
    await tester.tap(find.byType(ArrivalRowTile).first);
    await tester.pump();
    expect(c.read(followProvider)?.vehicleId, '2573');
  });

  testWidgets('the follow tip shows here too while a bus is live', (tester) async {
    await _pumpBoard(tester, rows: [_row(4, vehicle: '2573')], followTipSeen: false);
    expect(find.text(FollowTip.text), findsOneWidget);
  });

  testWidgets('pull to refresh loads the departures again (screen readers: the Refresh action)', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpBoard(tester, rows: [_row(4)]);
    final before = _loads['A']!;
    final id = CustomSemanticsAction.getIdentifier(BBRefresh.refreshAction);
    tester.semantics.customAction(
      find.semantics.byPredicate((n) => n.getSemanticsData().customSemanticsActionIds?.contains(id) ?? false),
      BBRefresh.refreshAction,
    );
    await tester.pumpAndSettle();
    expect(_loads['A'], before + 1);
    handle.dispose();
  });

  testWidgets('loading and error read as on the stop sheet', (tester) async {
    await _pumpBoard(tester, arrivals: (_) async => throw StateError('offline'));
    expect(find.text("Couldn't load departures"), findsOneWidget);
    expect(find.text('Showing schedule'), findsOneWidget);
  });

  testWidgets('Plan a trip from here starts a trip from the stop and opens the search', (tester) async {
    final c = await _pumpBoard(tester, rows: [_row(4)]);
    await tester.ensureVisible(find.byKey(StopSheetContent.planFromKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StopSheetContent.planFromKey));
    await tester.pumpAndSettle();
    expect(_went, ['/search?keep=1']);
    expect(c.read(planQueryProvider).from, StopPlace(stopId: 'A', name: 'Stop A'));
  });

  testWidgets('on a tablet the Board is a centred column at most 640 pt wide (spec §3)', (tester) async {
    await _pumpBoard(tester, size: const Size(1024, 768), rows: [_row(4)]);
    final row = tester.getRect(find.byType(ArrivalRowTile).first);
    expect(row.width, lessThanOrEqualTo(BoardTab.maxWidth));
    expect(row.center.dx, closeTo(512, 1));
  });

  for (final b in Brightness.values) {
    testWidgets('at 2x text on a 320 pt phone nothing overflows and the chips read in full (${b.name})',
        (tester) async {
      await _pumpBoard(
        tester,
        size: const Size(320, 640),
        textScale: 2,
        theme: b == Brightness.dark ? BBTheme.dark() : BBTheme.light(),
        saved: [_homeC],
        rows: [_row(4, vehicle: '2573'), _row(12)],
      );
      expect(tester.takeException(), isNull);
      final p = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.byKey(BoardTab.nearMeKey), matching: find.text('Near me')));
      expect(p.didExceedMaxLines, isFalse);
      expect(p.size.width, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.5));
    });
  }
}
```


- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/ui/board_tab_test.dart`
Expected: FAIL to compile: `Error when reading 'lib/ui/board/board_tab.dart'`.

- [ ] **Step 3: Split the stop sheet's header**

`_StopHeader` becomes `_StopInfo` (reused by the Board) plus the card's own Open board/Show map and Plan buttons; "Plan a trip from here" becomes `_PlanFrom`. The card looks exactly as before (Show map goes in Task 6).

In `lib/ui/home/stop_sheet.dart`:

Edit 1 of 4 (near line 18 before the edit). Find:

```dart
import '../kit/kit.dart';
import 'follow_tip.dart';

/// A stop's sheet: everything the Board showed (spec 2026-10-12 §3.2).
abstract final class StopSheetContent {
  static const starKey = ValueKey('stop-star');
  static const refreshKey = ValueKey('stop-refresh');
```

Replace with:

```dart
import '../kit/kit.dart';
import 'follow_tip.dart';

/// A stop's sheet: everything the Board showed (spec 2026-10-12 §3.2). The Board tab shows the same stop with
/// [info], [body] and [planFrom] (spec 2026-10-15 §3).
abstract final class StopSheetContent {
  static const starKey = ValueKey('stop-star');
  static const refreshKey = ValueKey('stop-refresh');
```

Edit 2 of 4 (near line 26 before the edit). Find:

```dart
  static const closeKey = ValueKey('stop-close');
  static const openBoardKey = ValueKey('stop-open-board');
  static const showMapKey = ValueKey('stop-show-map');
  static Widget header(String stopId) => _StopHeader(stopId: stopId);
  static Widget body(String stopId) => _StopBody(stopId: stopId);
}

class _StopHeader extends ConsumerWidget {
```

Replace with:

```dart
  static const closeKey = ValueKey('stop-close');
  static const openBoardKey = ValueKey('stop-open-board');
  static const showMapKey = ValueKey('stop-show-map');

  /// The card's header: [info], Close, Open board and Plan a trip from here.
  static Widget header(String stopId) => _StopHeader(stopId: stopId);

  /// The stop's number, name and live state, with its star and refresh: the Board tab's header for the stop.
  static Widget info(String stopId) => _StopInfo(stopId: stopId, closable: false);

  /// Alerts for the stop, then its departures.
  static Widget body(String stopId) => _StopBody(stopId: stopId);

  /// "Plan a trip from here": a new trip from [stopId], leaving now, and a search for where to.
  static Widget planFrom(String stopId) => _PlanFrom(stopId: stopId);
}

class _StopHeader extends ConsumerWidget {
```

Edit 3 of 4 (near line 36 before the edit). Find:

```dart

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final stop = ref.watch(stopInfoProvider(stopId));
    final name = stop?.stopName ?? 'Stop $stopId';
    final arrivals = ref.watch(stopArrivalsProvider(stopId));
    final rows = arrivals.value;
    final checking = rows == null && !arrivals.hasError;
    final live = rows != null && rows.any((r) => r.isLive);
    final updatedAt = ref.watch(stopArrivalsUpdatedAtProvider.select((m) => m[stopId]));
    final mine = ref.watch(settingsProvider.select((s) => s.selectedStopId)) == stopId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.s, BBSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            BBPill(label: 'STOP $stopId', background: bb.colors.ink, foreground: bb.colors.bg),
            const Spacer(),
            BBIconButton(
              key: StopSheetContent.starKey,
              icon: mine ? BBIcons.star : BBIcons.starOutline,
              semanticLabel: mine ? 'Your stop' : 'Set as my stop',
              onPressed: mine ? null : () => ref.read(settingsProvider.notifier).setSelectedStop(stopId),
            ),
            // The sheet owns the drag, so there is no pull to refresh: this button does it.
            BBIconButton(
              key: StopSheetContent.refreshKey,
              icon: BBIcons.refresh,
              semanticLabel: 'Refresh departures',
              onPressed: () => ref.invalidate(stopArrivalsProvider(stopId)),
            ),
            // Back to what was under the sheet: the way out for a screen reader, the side panel (no drag) and
            // iPhone (no system back), as well as a swipe down (spec §3.2).
            BBIconButton(
              key: StopSheetContent.closeKey,
              icon: BBIcons.close,
              semanticLabel: 'Close',
              onPressed: () => ref.read(homeSheetProvider.notifier).back(),
            ),
          ]),
          Semantics(
            header: true,
            child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: bb.text.headline),
          ),
          const SizedBox(height: BBSpace.xs),
          Row(children: [
            BBLiveDot(color: live ? bb.colors.live : bb.colors.muted, breathing: live),
            const SizedBox(width: BBSpace.s),
            Flexible(
              child: Semantics(
                // Silent while the first load is in flight so assistive tech never hears a provisional negative state.
                liveRegion: !checking,
                child: Text(
                  checking
                      ? 'Checking live data…'
                      : live
                          ? 'Live'
                          : 'Showing schedule',
                  style: bb.text.caption,
                ),
              ),
            ),
            // Outside the live region, so assistive tech hears live <-> schedule changes, not every refresh time.
            // Flexible too, so at large text the pair shares the row and wraps instead of crushing the state label.
            if (live && updatedAt != null)
              Flexible(
                child: Text(
                  ' · updated ${BBTime.of(updatedAt, use24h: BBTime.use24h(context), seconds: true)}',
                  style: bb.text.caption,
                ),
              ),
          ]),
          const SizedBox(height: BBSpace.s),
          // For riders used to the Board tab: the whole Board in one tap (the sheet at full height; on the tablet panel,
          // its departures). With the Board open it turns into the way back: "Show map" brings the sheet to half over
```

Replace with:

```dart

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(stopInfoProvider(stopId))?.stopName ?? 'Stop $stopId';
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.s, BBSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StopInfo(stopId: stopId, closable: true),
          const SizedBox(height: BBSpace.s),
          // For riders used to the Board tab: the whole Board in one tap (the sheet at full height; on the tablet panel,
          // its departures). With the Board open it turns into the way back: "Show map" brings the sheet to half over
```

Edit 4 of 4 (near line 135 before the edit). Find:

```dart
                    onPressed: () => ref.read(homeSheetProvider.notifier).openBoard(stopId),
                  ),
          ),
          BBButton(
            key: StopSheetContent.planFromKey,
            label: 'Plan a trip from here',
            icon: BBIcons.plan,
            kind: BBButtonKind.quiet,
            expand: true,
            wrap: true,
            onPressed: () {
              // A new trip from this stop, leaving now; the search's pick keeps this start (Ruling 14).
              ref.read(planQueryProvider.notifier).startFrom(StopPlace(stopId: stopId, name: name));
              context.push('/search?keep=1');
            },
          ),
        ],
      ),
    );
  }
}

class _StopBody extends ConsumerWidget {
  const _StopBody({required this.stopId});
  final String stopId;
```

Replace with:

```dart
                    onPressed: () => ref.read(homeSheetProvider.notifier).openBoard(stopId),
                  ),
          ),
          _PlanFrom(stopId: stopId),
        ],
      ),
    );
  }
}

/// The stop's number, star, refresh (and on a card, Close), then its name and whether its times are live.
class _StopInfo extends ConsumerWidget {
  const _StopInfo({required this.stopId, required this.closable});
  final String stopId;
  final bool closable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final stop = ref.watch(stopInfoProvider(stopId));
    final name = stop?.stopName ?? 'Stop $stopId';
    final arrivals = ref.watch(stopArrivalsProvider(stopId));
    final rows = arrivals.value;
    final checking = rows == null && !arrivals.hasError;
    final live = rows != null && rows.any((r) => r.isLive);
    final updatedAt = ref.watch(stopArrivalsUpdatedAtProvider.select((m) => m[stopId]));
    final mine = ref.watch(settingsProvider.select((s) => s.selectedStopId)) == stopId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          BBPill(label: 'STOP $stopId', background: bb.colors.ink, foreground: bb.colors.bg),
          const Spacer(),
          BBIconButton(
            key: StopSheetContent.starKey,
            icon: mine ? BBIcons.star : BBIcons.starOutline,
            semanticLabel: mine ? 'Your stop' : 'Set as my stop',
            onPressed: mine ? null : () => ref.read(settingsProvider.notifier).setSelectedStop(stopId),
          ),
          // A card's sheet owns the drag, so it has no pull to refresh: this button does it (the Board has both).
          BBIconButton(
            key: StopSheetContent.refreshKey,
            icon: BBIcons.refresh,
            semanticLabel: 'Refresh departures',
            onPressed: () => ref.invalidate(stopArrivalsProvider(stopId)),
          ),
          // Back to what was under the sheet: the way out for a screen reader, the side panel (no drag) and
          // iPhone (no system back), as well as a swipe down (spec §3.2).
          if (closable)
            BBIconButton(
              key: StopSheetContent.closeKey,
              icon: BBIcons.close,
              semanticLabel: 'Close',
              onPressed: () => ref.read(homeSheetProvider.notifier).back(),
            ),
        ]),
        Semantics(
          header: true,
          child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: bb.text.headline),
        ),
        const SizedBox(height: BBSpace.xs),
        Row(children: [
          BBLiveDot(color: live ? bb.colors.live : bb.colors.muted, breathing: live),
          const SizedBox(width: BBSpace.s),
          Flexible(
            child: Semantics(
              // Silent while the first load is in flight so assistive tech never hears a provisional negative state.
              liveRegion: !checking,
              child: Text(
                checking
                    ? 'Checking live data…'
                    : live
                        ? 'Live'
                        : 'Showing schedule',
                style: bb.text.caption,
              ),
            ),
          ),
          // Outside the live region, so assistive tech hears live <-> schedule changes, not every refresh time.
          // Flexible too, so at large text the pair shares the row and wraps instead of crushing the state label.
          if (live && updatedAt != null)
            Flexible(
              child: Text(
                ' · updated ${BBTime.of(updatedAt, use24h: BBTime.use24h(context), seconds: true)}',
                style: bb.text.caption,
              ),
            ),
        ]),
      ],
    );
  }
}

class _PlanFrom extends ConsumerWidget {
  const _PlanFrom({required this.stopId});
  final String stopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(stopInfoProvider(stopId))?.stopName ?? 'Stop $stopId';
    return BBButton(
      key: StopSheetContent.planFromKey,
      label: 'Plan a trip from here',
      icon: BBIcons.plan,
      kind: BBButtonKind.quiet,
      expand: true,
      wrap: true,
      onPressed: () {
        // A new trip from this stop, leaving now; the search's pick keeps this start (Ruling 14).
        ref.read(planQueryProvider.notifier).startFrom(StopPlace(stopId: stopId, name: name));
        context.push('/search?keep=1');
      },
    );
  }
}

class _StopBody extends ConsumerWidget {
  const _StopBody({required this.stopId});
  final String stopId;
```


- [ ] **Step 4: Split the map's Alerts and Settings buttons**

Replace the whole of `lib/ui/home/map_buttons.dart` with:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../kit/kit.dart';

/// Alerts (with the active count) and Settings, floating on the map (spec 2026-10-12 §3.1).
class MapButtons extends StatelessWidget {
  const MapButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return DecoratedBox(
      decoration: bb.mapControl(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AlertsButton(),
          Container(width: 28, height: 1, color: bb.colors.line),
          const SettingsButton(),
        ],
      ),
    );
  }
}

/// Opens Service alerts, with the number of active alerts on the bell: the same button on the map and in the Board's
/// header (spec 2026-10-15 §5).
class AlertsButton extends ConsumerWidget {
  const AlertsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final count = ref.watch(serviceUpdatesProvider).value?.activeAlertsAt(DateTime.now()).length ?? 0;
    final alertsLabel = count > 0 ? 'Alerts, $count active' : 'Alerts';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        BBIconButton(
          icon: BBIcons.alerts,
          semanticLabel: alertsLabel,
          onPressed: () => context.push('/alerts'),
        ),
        if (count > 0)
          Positioned(
            top: 4,
            right: 4,
            // The count grows with the text only so far: at large sizes it would cover the bell.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: bb.colors.dangerInk,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: bb.text.caption.copyWith(
                        color: bb.colors.surface,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Opens Settings: on the map and in the Board's header.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => BBIconButton(
        icon: BBIcons.settings,
        semanticLabel: 'Settings',
        onPressed: () => context.push('/settings'),
      );
}
```


- [ ] **Step 5: Make Where to? public, give the nearby list a pick, and give BBChip a toggle state**

In `lib/ui/home/home_sheet.dart`:

Edit 1 of 4 (near line 61 before the edit). Find:

```dart
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeTip(),
          const _WhereTo(),
          const SizedBox(height: BBSpace.s),
          HomeStopLine(onChooseStop: onChooseStop),
          if (hasAlert) ...[const SizedBox(height: BBSpace.s), const AlertStrip()],
```

Replace with:

```dart
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeTip(),
          const WhereToField(key: HomeSheetContent.whereToKey),
          const SizedBox(height: BBSpace.s),
          HomeStopLine(onChooseStop: onChooseStop),
          if (hasAlert) ...[const SizedBox(height: BBSpace.s), const AlertStrip()],
```

Edit 2 of 4 (near line 71 before the edit). Find:

```dart
  }
}

/// "Where to?": the search field, at least 48 pt tall.
class _WhereTo extends StatefulWidget {
  const _WhereTo();

  @override
  State<_WhereTo> createState() => _WhereToState();
}

class _WhereToState extends State<_WhereTo> {
  /// The search this opened is still open: a second tap (a quick double tap, both before the next frame builds the
  /// search page) must not push another.
  bool _open = false;
```

Replace with:

```dart
  }
}

/// "Where to?": the search field, at least 48 pt tall. On the map's bar and on the Board.
class WhereToField extends StatefulWidget {
  const WhereToField({super.key});

  @override
  State<WhereToField> createState() => _WhereToFieldState();
}

class _WhereToFieldState extends State<WhereToField> {
  /// The search this opened is still open: a second tap (a quick double tap, both before the next frame builds the
  /// search page) must not push another.
  bool _open = false;
```

Edit 3 of 4 (near line 110 before the edit). Find:

```dart
  Widget build(BuildContext context) {
    final bb = context.bb;
    return BBPressable(
      key: HomeSheetContent.whereToKey,
      semanticLabel: 'Where to? Search for a place or a stop',
      onTap: _openSearch,
      child: ConstrainedBox(
```

Replace with:

```dart
  Widget build(BuildContext context) {
    final bb = context.bb;
    return BBPressable(
      semanticLabel: 'Where to? Search for a place or a stop',
      onTap: _openSearch,
      child: ConstrainedBox(
```

Edit 4 of 4 (near line 164 before the edit). Find:

```dart
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!belowBar) ...[const HomeTip(), const _WhereTo()],
          const SizedBox(height: BBSpace.s),
          Wrap(
            spacing: BBSpace.s,
```

Replace with:

```dart
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!belowBar) ...[const HomeTip(), const WhereToField(key: HomeSheetContent.whereToKey)],
          const SizedBox(height: BBSpace.s),
          Wrap(
            spacing: BBSpace.s,
```


In `lib/ui/stop_picker/near_me_list.dart`:

Edit 1 of 4 (near line 8 before the edit). Find:

```dart
import '../kit/kit.dart';

class NearMeList extends ConsumerWidget {
  const NearMeList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
```

Replace with:

```dart
import '../kit/kit.dart';

class NearMeList extends ConsumerWidget {
  const NearMeList({super.key, this.onPick});

  /// What a tap on a stop does with its id; by default its card opens on the map.
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
```

Edit 2 of 4 (near line 68 before the edit). Find:

```dart
                    index: i,
                    child: Column(children: [
                      if (i > 0) const BBDivider(indent: 52),
                      _NearbyStopTile(nearby: stops[i]),
                    ]),
                  ),
              ]),
```

Replace with:

```dart
                    index: i,
                    child: Column(children: [
                      if (i > 0) const BBDivider(indent: 52),
                      _NearbyStopTile(nearby: stops[i], onPick: onPick),
                    ]),
                  ),
              ]),
```

Edit 3 of 4 (near line 81 before the edit). Find:

```dart
}

class _NearbyStopTile extends ConsumerWidget {
  const _NearbyStopTile({required this.nearby});

  final NearbyStop nearby;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
```

Replace with:

```dart
}

class _NearbyStopTile extends ConsumerWidget {
  const _NearbyStopTile({required this.nearby, this.onPick});

  final NearbyStop nearby;
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
```

Edit 4 of 4 (near line 94 before the edit). Find:

```dart
    final routesText = routes.isEmpty ? '' : ', routes ${routes.map(_spokenDirections).join(', ')}';
    return BBPressable(
      semanticLabel: '${stop.stopName}, stop ${stop.stopId}, ${nearby.distanceDisplay} away$routesText',
      onTap: () => ref.read(homeSheetProvider.notifier).open(StopSheet(stop.stopId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BBSpace.m),
        child: Row(children: [
```

Replace with:

```dart
    final routesText = routes.isEmpty ? '' : ', routes ${routes.map(_spokenDirections).join(', ')}';
    return BBPressable(
      semanticLabel: '${stop.stopName}, stop ${stop.stopId}, ${nearby.distanceDisplay} away$routesText',
      onTap: () {
        final pick = onPick;
        if (pick != null) return pick(stop.stopId);
        ref.read(homeSheetProvider.notifier).open(StopSheet(stop.stopId));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BBSpace.m),
        child: Row(children: [
```


In `lib/ui/kit/bb_chip.dart`:

Edit 1 of 3 (near line 21 before the edit). Find:

```dart
    this.selected = false,
    this.onTap,
    this.semanticLabel,
  });

  final String label;
```

Replace with:

```dart
    this.selected = false,
    this.onTap,
    this.semanticLabel,
    this.toggle = false,
  });

  final String label;
```

Edit 2 of 3 (near line 31 before the edit). Find:

```dart
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const surfaceKey = ValueKey('bb-chip-surface');

  @override
```

Replace with:

```dart
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// One of a set the rider picks from (the Board's stop chips): screen readers hear "selected" or "not selected".
  /// An ordinary chip is a plain button, with no selected state until it is selected.
  final bool toggle;

  static const surfaceKey = ValueKey('bb-chip-surface');

  @override
```

Edit 3 of 3 (near line 40 before the edit). Find:

```dart
    final lead = leading ?? (icon == null ? null : Icon(icon, size: 18, color: selected ? fg : bb.colors.brandInk));
    // Null (not false) when unselected: an ordinary button is not a toggle.
    return Semantics(
      selected: selected ? true : null,
      child: BBPressable(
        onTap: onTap,
        semanticLabel: semanticLabel ?? label,
```

Replace with:

```dart
    final lead = leading ?? (icon == null ? null : Icon(icon, size: 18, color: selected ? fg : bb.colors.brandInk));
    // Null (not false) when unselected: an ordinary button is not a toggle.
    return Semantics(
      selected: toggle ? selected : (selected ? true : null),
      child: BBPressable(
        onTap: onTap,
        semanticLabel: semanticLabel ?? label,
```


- [ ] **Step 6: Write the Board tab**

Create `lib/ui/board/board_tab.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/location/nearest_stop_service.dart';
import '../../state/board_providers.dart';
import '../../state/home_tab_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../home/home_sheet.dart' show WhereToField, savedPlaceIconData;
import '../home/map_buttons.dart';
import '../home/stop_sheet.dart';
import '../kit/kit.dart';
import '../stop_picker/near_me_list.dart';

/// The Board tab (spec 2026-10-15 §3): "when's my bus at my stop?" without the map. Its title with Alerts and
/// Settings, Where to?, a row of stop chips, then the chosen stop's board: the stop sheet's own header, alerts and
/// departures, and Plan a trip from here. Pull to refresh. On a tablet it is a centred column [maxWidth] wide.
class BoardTab extends ConsumerStatefulWidget {
  const BoardTab({super.key});

  static const whereToKey = ValueKey('board-where-to');
  static const nearMeKey = ValueKey('board-chip-near-me');
  static const findStopKey = ValueKey('board-chip-find-stop');
  static const chipsKey = ValueKey('board-chips');
  static const maxWidth = 640.0;

  /// The chip for [chip]'s stop.
  static ValueKey<String> chipKey(BoardChip chip) => ValueKey('board-chip-${chip.kind.name}-${chip.stopId}');

  @override
  ConsumerState<BoardTab> createState() => _BoardTabState();
}

class _BoardTabState extends ConsumerState<BoardTab> {
  /// Near me is waiting for a fix.
  bool _locating = false;

  /// Near me: the nearest stop by GPS. None (location off or refused, or no stop near): why, and a search instead.
  Future<void> _nearMe() async {
    if (_locating) return;
    setState(() => _locating = true);
    // A fresh fix every time: the rider may have walked since. Listened to while awaited, so it is not disposed.
    ref.invalidate(nearestStopsProvider);
    final keep = ref.listenManual(nearestStopsProvider, (_, _) {});
    List<NearbyStop> stops = const [];
    try {
      stops = await ref.read(nearestStopsProvider.future);
    } catch (_) {
      // No location: as none near.
    } finally {
      keep.close();
      if (mounted) setState(() => _locating = false);
    }
    if (!mounted) return;
    if (stops.isNotEmpty) {
      ref.read(boardStopProvider.notifier).select(stops.first.stop.stopId, nearMe: true);
      return;
    }
    final search = await BBDialog.show<bool>(
      context,
      title: "Can't find a stop near you",
      message: 'Location may be off for BusBoard, or no stop is within 800 m. '
          'You can search for the number on the stop pole instead.',
      actions: const [
        BBDialogAction(label: 'Cancel', value: false),
        BBDialogAction(label: 'Search instead', value: true, primary: true),
      ],
    );
    if (search == true && mounted) unawaited(context.push('/search?pickStop=1'));
  }

  Future<void> _refresh(String? stopId) async {
    if (stopId == null) return;
    ref.invalidate(stopArrivalsProvider(stopId));
    try {
      await ref.read(stopArrivalsProvider(stopId).future);
    } catch (_) {
      // The board shows the error itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(boardReadyProvider);
    final shown = ref.watch(boardShownStopProvider);
    final stopId = shown?.stopId;
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BoardTab.maxWidth),
          child: BBScrollPage(
            title: 'Board',
            large: true,
            actions: const [AlertsButton(), SettingsButton()],
            body: (context, inset) => BBRefresh(
              semanticLabel: 'Departures',
              topInset: inset,
              onRefresh: () => _refresh(stopId),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: inset)),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: BBSpace.l),
                      child: WhereToField(key: BoardTab.whereToKey),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _StopChips(shown: shown, locating: _locating, onNearMe: _nearMe),
                  ),
                  if (!ready)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(BBSpace.l),
                        child: BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: 4, label: 'Loading your stop'),
                      ),
                    )
                  else if (stopId == null)
                    const SliverToBoxAdapter(child: _ChooseYourStop())
                  else ...[
                    SliverToBoxAdapter(
                      key: ValueKey('board-stop-$stopId'),
                      child: Padding(
                        // The icon buttons bring their own hit area on the right.
                        padding: const EdgeInsets.fromLTRB(BBSpace.l, BBSpace.s, BBSpace.s, BBSpace.s),
                        child: StopSheetContent.info(stopId),
                      ),
                    ),
                    SliverToBoxAdapter(child: StopSheetContent.body(stopId)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: BBSpace.l),
                        child: StopSheetContent.planFrom(stopId),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: BBSpace.xxl)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One scrollable row: your stop, saved stops, recent stops, Near me and ＋ (spec §3). The chip of the stop showing
/// is selected (brand fill); each is a button with a selected state.
class _StopChips extends ConsumerWidget {
  const _StopChips({required this.shown, required this.locating, required this.onNearMe});

  final BoardStop? shown;
  final bool locating;
  final VoidCallback onNearMe;

  /// A chip in the row: as wide as its label up to a limit, past which the label ellipsizes.
  static Widget _bounded(Widget chip) =>
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240), child: chip);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chips = ref.watch(boardChipsProvider);
    final shown = this.shown;
    final selectedIndex =
        shown == null || shown.nearMe ? -1 : chips.indexWhere((c) => c.stopId == shown.stopId);
    String nameOf(String stopId) => ref.watch(stopInfoProvider(stopId))?.stopName ?? 'Stop $stopId';
    final nearMe = shown?.nearMe ?? false;
    return SingleChildScrollView(
      key: BoardTab.chipsKey,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(BBSpace.l, BBSpace.m, BBSpace.l, BBSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, chip) in chips.indexed) ...[
            _bounded(BBChip(
              key: BoardTab.chipKey(chip),
              toggle: true,
              selected: i == selectedIndex,
              label: switch (chip.kind) {
                BoardChipKind.saved => chip.place!.name,
                _ => nameOf(chip.stopId),
              },
              icon: switch (chip.kind) {
                BoardChipKind.yours => BBIcons.star,
                BoardChipKind.saved => savedPlaceIconData(chip.place!.icon),
                BoardChipKind.recent => BBIcons.history,
              },
              semanticLabel: switch (chip.kind) {
                BoardChipKind.yours => 'Your stop, ${nameOf(chip.stopId)}',
                BoardChipKind.saved => '${chip.place!.name}, ${nameOf(chip.stopId)}',
                BoardChipKind.recent => 'Recent stop, ${nameOf(chip.stopId)}',
              },
              onTap: () => ref.read(boardStopProvider.notifier).select(chip.stopId),
            )),
            const SizedBox(width: BBSpace.s),
          ],
          _bounded(BBChip(
            key: BoardTab.nearMeKey,
            toggle: true,
            selected: nearMe,
            label: locating ? 'Finding you…' : 'Near me',
            icon: BBIcons.nearMe,
            semanticLabel: nearMe ? 'Near me, ${nameOf(shown!.stopId)}' : 'Near me',
            onTap: onNearMe,
          )),
          const SizedBox(width: BBSpace.s),
          BBChip(
            key: BoardTab.findStopKey,
            label: 'Stop',
            icon: BBIcons.add,
            semanticLabel: 'Choose your stop',
            onTap: () => context.push('/search?pickStop=1'),
          ),
        ],
      ),
    );
  }
}

/// No stop chosen and none saved (spec §3): "Choose your stop" with the nearby stops, as the map's sheet has them; with
/// no location, or no stop near, a search for the number on the pole instead.
class _ChooseYourStop extends ConsumerWidget {
  const _ChooseYourStop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final nearby = ref.watch(nearestStopsProvider);
    final none = nearby.hasError || (nearby.hasValue && nearby.value!.isEmpty);
    if (none) {
      return Padding(
        padding: const EdgeInsets.all(BBSpace.l),
        child: BBEmptyState(
          icon: BBIcons.stop,
          title: 'Choose your stop',
          message: 'Search for the number on the stop pole.',
          action: BBButton(
            label: 'Search for a stop',
            icon: BBIcons.search,
            onPressed: () => context.push('/search?pickStop=1'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, BBSpace.l, BBSpace.l, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Choose your stop', style: bb.text.title)),
          const SizedBox(height: BBSpace.s),
          NearMeList(
            onPick: (stopId) {
              // Chosen here, it is your stop from now on, and the Board shows it.
              unawaited(ref.read(settingsProvider.notifier).setSelectedStop(stopId));
              ref.read(boardStopProvider.notifier).select(stopId);
            },
          ),
        ],
      ),
    );
  }
}
```


Notes for the reviewer:
- The Board reads `nearestStopsProvider` only in "Choose your stop" (and when Near me is tapped). "Choose your stop" waits for `boardReadyProvider`, so a rider whose stop is still being read never triggers the location prompt.
- Near me keeps `nearestStopsProvider` (auto-dispose) alive with `ref.listenManual` while it awaits the fix, and invalidates it first for a fresh fix.
- The chips sit in a horizontal `SingleChildScrollView`; each chip is capped at 240 pt so the label ellipsizes (a `BBChip` must have a bounded width).

- [ ] **Step 7: Run the test to verify it passes**

Run: `flutter test test/ui/board_tab_test.dart`
Expected: `All tests passed!` (22 tests).

- [ ] **Step 8: Analyze and run the non-golden suite**

Run: `flutter analyze` → `No issues found!`
Run: `flutter test $(find test -name '*_test.dart' ! -name '*golden_test.dart' | sort)` → `All tests passed!` (the stop sheet, the map buttons' badge test in `home_routes_test.dart` and the home sheet tests all still pass: their widgets look and read the same).

- [ ] **Step 9: Commit**

```bash
git add lib/ui/board/board_tab.dart lib/ui/home/stop_sheet.dart lib/ui/home/map_buttons.dart \
  lib/ui/home/home_sheet.dart lib/ui/stop_picker/near_me_list.dart lib/ui/kit/bb_chip.dart \
  test/ui/board_tab_test.dart
git status --short
git commit -m "feat(board): the Board tab

Title with the bell and gear, Where to?, a row of stop chips (your stop,
saved stops, recents, Near me, ＋), then the stop sheet's own header,
alerts and departures and Plan a trip from here, with pull to refresh.
Choose your stop with the nearby stops, or a search without location.
A centred 640 pt column on a tablet.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


---

### Task 5: The home shell: two tabs, the cross-fade, and the map above the tab bar

**Files:**
- Create: `lib/ui/home/home_shell.dart`
- Modify: `lib/routing/router.dart` (`/` is the shell)
- Modify: `lib/ui/home/home_screen.dart` (`active`; the 1.4 restore goes)
- Modify: `lib/app.dart` (no launch-link handshake)
- Delete: `lib/state/board_open_store.dart`, `test/ui/board_reopen_test.dart`
- Modify: `test/helpers/planner_app.dart` (`tab:`, `homeSheetArea`), `test/ui/home_sheet_test.dart`, `test/ui/board_button_test.dart` (area maths)
- Test: `test/ui/home_shell_test.dart`

**Interfaces:**
- Consumes: `homeTabProvider`, `HomeTab`, `HomeTabStore` (Task 1); `BBTabBar`, `BBTab` (Task 2); `BoardTab` (Task 4).
- Produces:
  - `HomeShell()` (`lib/ui/home/home_shell.dart`) with `static const boardTabKey = ValueKey('home-tab-board')`, `mapTabKey = ValueKey('home-tab-map')`, `boardLayerKey = ValueKey('home-layer-board')`, `mapLayerKey = ValueKey('home-layer-map')`.
  - `HomeScreen({Key? key, bool active = true})`: false while the Map tab is hidden (no one-time lift).
  - `pumpPlannerApp(..., HomeTab? tab = HomeTab.map)`: a fixed tab; `null` reads the stored one as a real launch does. `launchLinkChecked:` is gone.
  - `double homeSheetArea(WidgetTester)` in `test/helpers/planner_app.dart`: the Map tab's height less the sheet's two `BBSpace.s` gaps.
  - Removed: `BoardOpenStore`, `boardOpenStoreProvider`, `launchLinkCheckedProvider`.

- [ ] **Step 1: Give the test helper a tab, and the sheet's area**

In `test/helpers/planner_app.dart`:

Edit 1 of 4 (near line 8 before the edit). Find:

```dart
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/platform/alert_runner.dart';
import 'package:busboard_nl/routing/router.dart';
import 'package:busboard_nl/state/board_open_store.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/seen_flags.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/home/home_tip.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_view.dart';
```

Replace with:

```dart
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/platform/alert_runner.dart';
import 'package:busboard_nl/routing/router.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/seen_flags.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_tip.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_view.dart';
```

Edit 2 of 4 (near line 104 before the edit). Find:

```dart
  void longPress(double lat, double lon) => config!.onLongPress!(LatLng(lat, lon));
}

/// An element under the router and the providers, for `GoRouter.of` and `ProviderScope.containerOf`.
Element routerElement(WidgetTester tester) => tester.element(find.byType(Navigator).first);

/// Pumps the app's route tree on [net] at [now] ([clock], when given, tells the time instead), starting at [initial].
/// [use24h], when given, sets the device's clock format. [alertRunner], when given, takes the arrival alerts (a quiet one otherwise).
/// [asyncPrefs] is what SharedPreferencesAsync holds at launch. [launchLinkChecked], when given, is the app's check for
/// a notification that launched it (already done, with no link, otherwise). [reduceMotion] turns on the OS Reduce Motion setting.
/// The one-time home tip is already seen unless [homeTipSeen] is false (it sits above "Where to?" and moves the peek),
/// and so are the bar's one-time lift unless [barHintSeen] is false and the stop sheet's follow tip unless
/// [followTipSeen] is false.
/// The live feed answers 503, so plans use timetable times; the map is a plain box ([mapView], when given, builds it).
Future<void> pumpPlannerApp(
  WidgetTester tester, {
```

Replace with:

```dart
  void longPress(double lat, double lon) => config!.onLongPress!(LatLng(lat, lon));
}

/// The height the map's pull-up sheet moves in: the map tab's (the screen above the tab bar) less the sheet's gaps.
double homeSheetArea(WidgetTester tester) => tester.getSize(find.byType(HomeScreen)).height - 2 * BBSpace.s;

/// An element under the router and the providers, for `GoRouter.of` and `ProviderScope.containerOf`.
Element routerElement(WidgetTester tester) => tester.element(find.byType(Navigator).first);

/// Pumps the app's route tree on [net] at [now] ([clock], when given, tells the time instead), starting at [initial].
/// [use24h], when given, sets the device's clock format. [alertRunner], when given, takes the arrival alerts (a quiet one otherwise).
/// [asyncPrefs] is what SharedPreferencesAsync holds at launch. [reduceMotion] turns on the OS Reduce Motion setting.
/// The one-time home tip is already seen unless [homeTipSeen] is false (it sits above "Where to?" and moves the peek),
/// and so are the bar's one-time lift unless [barHintSeen] is false and the stop sheet's follow tip unless
/// [followTipSeen] is false.
/// The home opens on [tab] (the Map, where most of these tests live); null reads the tab used last from the phone, as
/// a real launch does (the Board on a first launch).
/// The live feed answers 503, so plans use timetable times; the map is a plain box ([mapView], when given, builds it).
Future<void> pumpPlannerApp(
  WidgetTester tester, {
```

Edit 3 of 4 (near line 137 before the edit). Find:

```dart
  bool barHintSeen = true,
  bool followTipSeen = true,
  Map<String, Object> asyncPrefs = const {},
  Completer<bool>? launchLinkChecked,
  bool reduceMotion = false,
}) async {
  // flutter_test's own 800x600 is a tablet to the home screen (its side panel starts at 700): a test that has not
  // picked a size gets a phone, so the sheet is a pull-up sheet. A test that sets its own size keeps it.
```

Replace with:

```dart
  bool barHintSeen = true,
  bool followTipSeen = true,
  Map<String, Object> asyncPrefs = const {},
  bool reduceMotion = false,
  HomeTab? tab = HomeTab.map,
}) async {
  // flutter_test's own 800x600 is a tablet to the home screen (its side panel starts at 700): a test that has not
  // picked a size gets a phone, so the sheet is a pull-up sheet. A test that sets its own size keeps it.
```

Edit 4 of 4 (near line 177 before the edit). Find:

```dart
        mapViewBuilderProvider.overrideWithValue(mapView ?? StubMap().build),
        // No live buses unless a test overrides this: the real poll's timer would outlive the test.
        busTrackingStreamProvider.overrideWith((ref) => Stream.value(const <String, BusTrackingState>{})),
        launchLinkCheckedProvider.overrideWithValue(launchLinkChecked ?? (Completer<bool>()..complete(false))),
        if (homeTipSeen) homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen()),
        if (barHintSeen) barHintSeenProvider.overrideWith(() => SeenFlagNotifier.seen(barHintSeenKey)),
        if (followTipSeen) followTipSeenProvider.overrideWith(() => SeenFlagNotifier.seen(followTipSeenKey)),
```

Replace with:

```dart
        mapViewBuilderProvider.overrideWithValue(mapView ?? StubMap().build),
        // No live buses unless a test overrides this: the real poll's timer would outlive the test.
        busTrackingStreamProvider.overrideWith((ref) => Stream.value(const <String, BusTrackingState>{})),
        if (tab != null) homeTabProvider.overrideWith(() => HomeTabNotifier.fixed(tab)),
        if (homeTipSeen) homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen()),
        if (barHintSeen) barHintSeenProvider.overrideWith(() => SeenFlagNotifier.seen(barHintSeenKey)),
        if (followTipSeen) followTipSeenProvider.overrideWith(() => SeenFlagNotifier.seen(followTipSeenKey)),
```


- [ ] **Step 2: Write the failing test**

Create `test/ui/home_shell_test.dart`:

```dart
import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/seen_flags.dart';
import 'package:busboard_nl/ui/board/board_tab.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_shell.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/planner_app.dart';
import '../map/support/fake_map_surface.dart';
import '../trip_planner/test_network.dart';

final _now = DateTime(2026, 10, 12, 13, 0);

class _StopC extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(selectedStopId: 'C');
}

/// Your stop is C, with a long list of departures.
final _longBoard = [
  settingsProvider.overrideWith(_StopC.new),
  stopArrivalsProvider.overrideWith((ref, id) async => [
        for (var m = 2; m < 90; m += 6)
          ArrivalRow(
            routeShortName: '1',
            headsign: 'Downtown',
            scheduledTime: GtfsTime.parse('13:05:00'),
            minutesAway: m,
            isLive: false,
            tripId: '1-$m',
          ),
      ]),
];

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeShell)));

/// The tab showing, as the rider sees it: the one whose layer is on stage.
bool _showing(Type screen) => find.byType(screen).evaluate().isNotEmpty;

/// The Board's layer opacity (1 with the Board showing).
double _boardOpacity(WidgetTester tester) => tester
    .widget<Opacity>(find.descendant(of: find.byKey(HomeShell.boardLayerKey), matching: find.byType(Opacity)).first)
    .opacity;

/// A map that becomes ready once [ready] completes (at once by default), so the screen gets a camera (and could
/// play the bar's one-time lift).
class _ReadyMap {
  _ReadyMap([Future<void>? ready]) : ready = ready ?? Future.value();
  final Future<void> ready;
  final surface = FakeMapSurface();
  Widget build(MapViewConfig c) {
    unawaited(ready.then((_) => c.onReady(surface, surface)));
    return const ColoredBox(key: ValueKey('stub-map'), color: Color(0xFFEEF0F2));
  }
}

void main() {
  testWidgets('a first launch opens on the Board, with the tab bar under it (spec 2026-10-15 §2.2)', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: null);
    expect(_showing(BoardTab), isTrue);
    expect(_showing(HomeScreen), isFalse);
    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget, reason: 'the map is kept, offstage');
    expect(find.byType(BBTabBar), findsOneWidget);
    expect(tester.getRect(find.byType(BBTabBar)).bottom, 844);
  });

  testWidgets('the tab used last opens next time', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: null, asyncPrefs: {HomeTabStore.key: 'map'});
    expect(_showing(HomeScreen), isTrue);
    expect(_showing(BoardTab), isFalse);
  });

  testWidgets('an upgrade from a Board left open in 1.4 opens the Board on that stop', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: null,
        asyncPrefs: {HomeTabStore.legacyBoardOpenKey: 'C'});
    expect(_showing(BoardTab), isTrue);
    expect(find.text('STOP C'), findsOneWidget);
    expect(await tester.runAsync(() => SharedPreferencesAsync().getString(HomeTabStore.legacyBoardOpenKey)), isNull);
  });

  testWidgets('tapping a tab switches to it and stores it', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: null);
    await tester.tap(find.byKey(HomeShell.mapTabKey));
    await tester.pumpAndSettle();
    expect(_showing(HomeScreen), isTrue);
    expect(_showing(BoardTab), isFalse);
    expect(_c(tester).read(homeTabProvider), HomeTab.map);
    expect(await tester.runAsync(() => SharedPreferencesAsync().getString(HomeTabStore.key)), 'map');
    await tester.tap(find.byKey(HomeShell.boardTabKey));
    await tester.pumpAndSettle();
    expect(_showing(BoardTab), isTrue);
    expect(_showing(HomeScreen), isFalse);
  });

  testWidgets('both tabs stay alive: switching never makes the map afresh or loses the Board scroll', (tester) async {
    final map = _ReadyMap();
    await pumpPlannerApp(tester,
        net: TestNetwork(), now: _now, tab: HomeTab.board, mapView: map.build, overrides: _longBoard);
    final scroll = tester
        .state<ScrollableState>(find.descendant(of: find.byType(BoardTab), matching: find.byType(Scrollable)).first)
        .position;
    scroll.jumpTo(40);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeShell.mapTabKey));
    await tester.pumpAndSettle();
    final mapState = tester.state(find.byType(HomeScreen));
    final mapView = tester.element(find.byKey(const ValueKey('stub-map')));
    await tester.tap(find.byKey(HomeShell.boardTabKey));
    await tester.pumpAndSettle();
    expect(scroll.pixels, 40, reason: 'the Board is where the rider left it');
    await tester.tap(find.byKey(HomeShell.mapTabKey));
    await tester.pumpAndSettle();
    expect(identical(tester.state(find.byType(HomeScreen)), mapState), isTrue);
    expect(identical(tester.element(find.byKey(const ValueKey('stub-map'))), mapView), isTrue,
        reason: 'the map view (MapLibre in the app) is the same one, never made afresh');
  });

  testWidgets('switching cross-fades: the Board fades in over the map, which stays until it is covered',
      (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map);
    await tester.tap(find.byKey(HomeShell.boardTabKey));
    await tester.pump();
    await tester.pump(BBMotion.standard ~/ 2);
    expect(_boardOpacity(tester), inExclusiveRange(0, 1));
    expect(_showing(HomeScreen), isTrue, reason: 'the map shows through until the fade is done');
    await tester.pumpAndSettle();
    expect(_boardOpacity(tester), 1);
    expect(_showing(HomeScreen), isFalse);
  });

  testWidgets('under Reduce Motion the switch is instant', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map, reduceMotion: true);
    await tester.tap(find.byKey(HomeShell.boardTabKey));
    await tester.pump();
    expect(_boardOpacity(tester), 1);
    expect(_showing(HomeScreen), isFalse);
    await tester.tap(find.byKey(HomeShell.mapTabKey));
    await tester.pump();
    expect(_showing(BoardTab), isFalse);
    expect(_showing(HomeScreen), isTrue);
  });

  testWidgets('screen readers hear the tabs, and only the tab showing', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.board);
    expect(tester.getSemantics(find.bySemanticsLabel('Board, tab 1 of 2')), isSemantics(isSelected: true));
    expect(tester.getSemantics(find.bySemanticsLabel('Map, tab 2 of 2')), isSemantics(isSelected: false));
    expect(find.bySemanticsLabel('Where to? Search for a place or a stop'), findsOneWidget,
        reason: "the Board's Where to?, not the map's as well");
    await tester.tap(find.byKey(HomeShell.mapTabKey));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.bySemanticsLabel('Map, tab 2 of 2')), isSemantics(isSelected: true));
    expect(find.bySemanticsLabel('Where to? Search for a place or a stop'), findsOneWidget);
    handle.dispose();
  });

  testWidgets("the bar's one-time lift never plays behind the Board: it waits for the Map tab", (tester) async {
    final ready = Completer<void>();
    final map = _ReadyMap(ready.future);
    await pumpPlannerApp(tester,
        net: TestNetwork(), now: _now, tab: HomeTab.map, mapView: map.build, barHintSeen: false);
    // The rider is on the Board before the map is ready.
    await tester.tap(find.byKey(HomeShell.boardTabKey));
    await tester.pumpAndSettle();
    ready.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(await tester.runAsync(() => SharedPreferencesAsync().getBool(barHintSeenKey)), isNull,
        reason: 'not played behind the Board');
    await tester.tap(find.byKey(HomeShell.mapTabKey));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => SharedPreferencesAsync().getBool(barHintSeenKey)), isTrue);
  });
}
```


- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/ui/home_shell_test.dart`
Expected: FAIL to compile: `Error when reading 'lib/ui/home/home_shell.dart'`.

- [ ] **Step 4: Write the shell**

Create `lib/ui/home/home_shell.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/home_tab_provider.dart';
import '../board/board_tab.dart';
import '../kit/kit.dart';
import 'home_screen.dart';

/// The home (spec 2026-10-15 §2): two tabs, Board and Map, over a bottom tab bar. Both stay mounted, so a switch
/// keeps the map, its camera and follow, and the Board's scroll, as they were; the tab not showing is offstage, its
/// tickers off. The Board cross-fades in over the map, or out to show it, over [BBMotion.standard] (at once under
/// Reduce Motion); the map itself never fades, as a platform view under an opacity layer can flicker. Each tab sits
/// above the tab bar: the bar takes the bottom safe area, so the map's sheet measures its stops from the bar's top.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  static const boardTabKey = ValueKey('home-tab-board');
  static const mapTabKey = ValueKey('home-tab-map');
  static const boardLayerKey = ValueKey('home-layer-board');
  static const mapLayerKey = ValueKey('home-layer-map');

  static const _tabs = [
    BBTab(label: 'Board', icon: BBIcons.board, activeIcon: BBIcons.boardFill, key: boardTabKey),
    BBTab(label: 'Map', icon: BBIcons.map, activeIcon: BBIcons.mapFill, key: mapTabKey),
  ];

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with SingleTickerProviderStateMixin {
  /// 1 with the Board showing, 0 with the map; in between while they cross-fade.
  late final AnimationController _board = AnimationController(vsync: this, duration: BBMotion.standard);

  @override
  void initState() {
    super.initState();
    final tab = ref.read(homeTabProvider);
    if (tab != null) _board.value = tab == HomeTab.board ? 1 : 0;
    // The first tab (read from the phone) shows at once; a switch after that cross-fades.
    ref.listenManual<HomeTab?>(homeTabProvider, (previous, next) {
      if (next == null || !mounted) return;
      final target = next == HomeTab.board ? 1.0 : 0.0;
      final duration = BBMotion.of(context, BBMotion.standard);
      if (previous == null || duration == Duration.zero) {
        _board.value = target;
      } else {
        _board.animateTo(target, duration: duration, curve: BBMotion.curve);
      }
    });
  }

  @override
  void dispose() {
    _board.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final tab = ref.watch(homeTabProvider);
    // The tab used last is still being read (a frame or two at launch).
    if (tab == null) return ColoredBox(color: bb.colors.bg);
    // No page scaffold around both: the map runs under the status bar and handles the side insets itself (the tablet
    // panel clears a notch); the Board brings its own.
    return ColoredBox(
      color: bb.colors.bg,
      child: Column(
        children: [
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _TabLayer(
                    key: HomeShell.mapLayerKey,
                    board: _board,
                    isBoard: false,
                    active: tab == HomeTab.map,
                    child: HomeScreen(active: tab == HomeTab.map),
                  ),
                  _TabLayer(
                    key: HomeShell.boardLayerKey,
                    board: _board,
                    isBoard: true,
                    active: tab == HomeTab.board,
                    // Its own page: opaque bg over the map, status-bar icons for the theme, clear of a side notch.
                    child: const BBScaffold(safeTop: false, body: BoardTab()),
                  ),
                ],
              ),
            ),
          ),
          BBTabBar(
            tabs: HomeShell._tabs,
            index: tab.index,
            onSelect: (i) => ref.read(homeTabProvider.notifier).select(HomeTab.values[i]),
          ),
        ],
      ),
    );
  }
}

/// One tab's layer. Offstage once fully hidden (not painted, not hit, not read, and skipped by finders); while it
/// is not the active tab it takes no touches, says nothing to screen readers and runs no tickers. The Board's layer
/// fades with [board]; the map's stays opaque under it.
class _TabLayer extends AnimatedWidget {
  const _TabLayer({
    super.key,
    required Animation<double> board,
    required this.isBoard,
    required this.active,
    required this.child,
  }) : super(listenable: board);

  final bool isBoard;
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final board = (listenable as Animation<double>).value;
    final visible = active || (isBoard ? board > 0 : board < 1);
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: active,
        child: IgnorePointer(
          ignoring: !active,
          child: ExcludeSemantics(
            excluding: !active,
            child: Opacity(opacity: isBoard ? board : 1, child: child),
          ),
        ),
      ),
    );
  }
}
```


In `lib/routing/router.dart`:

Edit 1 of 2 (near line 5 before the edit). Find:

```dart
import '../state/home_sheet_provider.dart';
import '../state/map_pick_provider.dart';
import '../ui/alerts/alerts_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/kit/kit.dart';
import '../ui/search/search_screen.dart';
import '../ui/settings/settings_screen.dart';
```

Replace with:

```dart
import '../state/home_sheet_provider.dart';
import '../state/map_pick_provider.dart';
import '../ui/alerts/alerts_screen.dart';
import '../ui/home/home_shell.dart';
import '../ui/kit/kit.dart';
import '../ui/search/search_screen.dart';
import '../ui/settings/settings_screen.dart';
```

Edit 2 of 2 (near line 41 before the edit). Find:

```dart
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _page(state, const HomeScreen()),
      ),
      GoRoute(path: '/stop/:stopId', redirect: _toStopSheet),
      GoRoute(path: '/board/:stopId', redirect: _toStopSheet),
```

Replace with:

```dart
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _page(state, const HomeShell()),
      ),
      GoRoute(path: '/stop/:stopId', redirect: _toStopSheet),
      GoRoute(path: '/board/:stopId', redirect: _toStopSheet),
```


- [ ] **Step 5: The Map tab knows when it is hidden; the 1.4 restore goes**

The migration in `HomeTabStore` (Task 1) replaces the home screen's "Board left open" restore.

In `lib/ui/home/home_screen.dart`:

Edit 1 of 10 (near line 20 before the edit). Find:

```dart
import '../../domain/map/heading_smoother.dart';
import '../../domain/trip_planner/journey.dart';
import '../../state/arrival_alert_providers.dart';
import '../../state/board_open_store.dart';
import '../../state/follow_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/journey_on_map_provider.dart';
```

Replace with:

```dart
import '../../domain/map/heading_smoother.dart';
import '../../domain/trip_planner/journey.dart';
import '../../state/arrival_alert_providers.dart';
import '../../state/follow_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/journey_on_map_provider.dart';
```

Edit 2 of 10 (near line 87 before the edit). Find:

```dart
/// follows the selection. A long-press plans from or to that point; while [mapPickProvider] is set the next
/// tap chooses that end of the trip; a journey from the trip options is drawn on top.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
```

Replace with:

```dart
/// follows the selection. A long-press plans from or to that point; while [mapPickProvider] is set the next
/// tap chooses that end of the trip; a journey from the trip options is drawn on top.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.active = true});

  /// The Map tab is the one showing (spec 2026-10-15 §2). The home shell keeps this screen mounted behind the Board,
  /// where it plays no one-time hint. Always true where the screen stands alone.
  final bool active;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
```

Edit 3 of 10 (near line 240 before the edit). Find:

```dart
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enableMyLocation(request: false));
    unawaited(_restoreBoard());
    _journeyFitPending = ref.read(journeyOnMapProvider) != null;
    // A follow set before the map existed (the Board's live row): its card
    // replaces any selection.
```

Replace with:

```dart
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enableMyLocation(request: false));
    _journeyFitPending = ref.read(journeyOnMapProvider) != null;
    // A follow set before the map existed (the Board's live row): its card
    // replaces any selection.
```

Edit 4 of 10 (near line 283 before the edit). Find:

```dart
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
```

Replace with:

```dart
    );
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The Map tab has just come into view: the bar's one-time lift, if it has not played yet.
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_hintBar()));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
```

Edit 5 of 10 (near line 327 before the edit). Find:

```dart
      _appResumed = true;
      _resumeTicker();
    }
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) _rememberBoard();
    if (state == AppLifecycleState.paused) {
      _appResumed = false;
      _ticker?.stop();
```

Replace with:

```dart
      _appResumed = true;
      _resumeTicker();
    }
    if (state == AppLifecycleState.paused) {
      _appResumed = false;
      _ticker?.stop();
```

Edit 6 of 10 (near line 880 before the edit). Find:

```dart
    _sheetExtent = n.extent;
    final wasAtFull = _sheetAtFull;
    _sheetAtFull = n.extent >= n.maxExtent - 0.004;
    // Collapsed below full: the Board is no longer open.
    if (wasAtFull && !_sheetAtFull) _forgetBoard();
    final abovePeek = n.extent > n.minExtent + 0.02;
    if (wasAtFull != _sheetAtFull || abovePeek != _sheetAbovePeek) {
      // The notification can come mid-layout: what it changes is built on the next frame.
```

Replace with:

```dart
    _sheetExtent = n.extent;
    final wasAtFull = _sheetAtFull;
    _sheetAtFull = n.extent >= n.maxExtent - 0.004;
    final abovePeek = n.extent > n.minExtent + 0.02;
    if (wasAtFull != _sheetAtFull || abovePeek != _sheetAbovePeek) {
      // The notification can come mid-layout: what it changes is built on the next frame.
```

Edit 7 of 10 (near line 905 before the edit). Find:

```dart

  /// The first time the bar shows with the map ready, the sheet lifts [_barHintLift] and settles back, once ever
  /// (spec 2026-10-14 §3.6). Not under Reduce Motion (nothing is stored then, so it can play once motion is back), on
  /// the tablet panel, while following or choosing on the map, with a card open, or while the Board left open may
  /// still be restored over the bar (final review M11: it is tried again once the restore is done).
  Future<void> _hintBar() async {
    if (_barHintTried || !mounted || _camera == null || BBMotion.reduced(context)) return;
    if (_wide || _follow != null || ref.read(mapPickProvider) != null || _restoringBoard) return;
    if (ref.read(homeSheetProvider) is! HomeSheetHome) return;
    final sheet = _sheet;
    if (!sheet.isAttached) return;
```

Replace with:

```dart

  /// The first time the bar shows with the map ready, the sheet lifts [_barHintLift] and settles back, once ever
  /// (spec 2026-10-14 §3.6). Not under Reduce Motion (nothing is stored then, so it can play once motion is back), on
  /// the tablet panel, while following or choosing on the map, with a card open, or while the Map tab is not the one
  /// showing (it is tried again when it is).
  Future<void> _hintBar() async {
    if (_barHintTried || !mounted || _camera == null || BBMotion.reduced(context)) return;
    if (!widget.active || _wide || _follow != null || ref.read(mapPickProvider) != null) return;
    if (ref.read(homeSheetProvider) is! HomeSheetHome) return;
    final sheet = _sheet;
    if (!sheet.isAttached) return;
```

Edit 8 of 10 (near line 922 before the edit). Find:

```dart
      return;
    }
    if (seen || !mounted) return;
    // Something took the bar's place while the flag was read (a card, a follow, a map pick): try again once it is back.
    if (!identical(sheet, _sheet) ||
        !sheet.isAttached ||
        _follow != null ||
        ref.read(mapPickProvider) != null ||
        _restoringBoard) {
      _barHintTried = false;
      return;
    }
```

Replace with:

```dart
      return;
    }
    if (seen || !mounted) return;
    // Something took the bar's place while the flag was read (a card, a follow, a map pick, the Board tab): try again
    // once it is back.
    if (!identical(sheet, _sheet) ||
        !sheet.isAttached ||
        !widget.active ||
        _follow != null ||
        ref.read(mapPickProvider) != null) {
      _barHintTried = false;
      return;
    }
```

Edit 9 of 10 (near line 935 before the edit). Find:

```dart
    await sheet.nudge(_barHintLift);
  }

  // ─── Reopen the way the rider left it ─────────────────────

  /// The stop id saved as the open Board ([BoardOpenStore]), as far as this screen knows.
  String? _savedBoard;

  /// A cold start's restore of the Board left open has not finished: it may still open the Board over the bar.
  bool _restoringBoard = true;

  /// The stop whose Board is showing: its sheet at full height, or in the side panel (which has no detents).
  String? get _boardShowing {
    final sheet = ref.read(homeSheetProvider);
    return sheet is StopSheet && (_wide || _sheetAtFull) ? sheet.stopId : null;
  }

  /// The app is going to the background: remember the Board if one is open, else forget any. With none open the
  /// store is cleared whatever this screen thinks it holds: a restore that failed may have left an id there.
  void _rememberBoard() {
    final id = _boardShowing;
    if (id == null) {
      _savedBoard = null;
      unawaited(ref.read(boardOpenStoreProvider).clear().catchError((Object e) => _log('Board not cleared: $e')));
      return;
    }
    if (id == _savedBoard) return;
    _savedBoard = id;
    unawaited(ref.read(boardOpenStoreProvider).save(id).catchError((Object e) => _log('Board not saved: $e')));
  }

  /// The rider collapsed, closed or left the Board.
  void _forgetBoard() {
    if (_savedBoard == null) return;
    _savedBoard = null;
    unawaited(ref.read(boardOpenStoreProvider).clear().catchError((Object e) => _log('Board not cleared: $e')));
  }

  /// A cold start: the Board left open is opened again, at full height, once the app has checked for a notification
  /// that launched it and the schedule says the stop still exists. A link or a notification opened at launch wins,
  /// and the Board is forgotten.
  Future<void> _restoreBoard() async {
    try {
      await _restoreBoardIfLeftOpen();
    } finally {
      _restoringBoard = false;
      // The bar's one-time lift waited for this; with the bar still showing (no Board opened) it plays now.
      if (mounted) unawaited(_hintBar());
    }
  }

  Future<void> _restoreBoardIfLeftOpen() async {
    final store = ref.read(boardOpenStoreProvider);
    final launchChecked = ref.read(launchLinkCheckedProvider).future;
    String? id;
    try {
      id = await store.read();
      if (id == null || !mounted) return;
      // A notification plugin that never answers must not hold the Board back: after 3 s, no launch link.
      final launchLink = await launchChecked.timeout(const Duration(seconds: 3), onTimeout: () => false);
      final repo = await ref.read(gtfsRepositoryProvider.future);
      if (!mounted) return;
      final stillThere = repo.stopsById[id] != null;
      if (launchLink ||
          !stillThere ||
          ref.read(homeSheetProvider) is! HomeSheetHome ||
          ref.read(followProvider) != null) {
        await store.clear();
        return;
      }
      ref.read(homeSheetProvider.notifier).openBoard(id);
      // Written back: a background while this waited (no Board showing then) cleared the store.
      _savedBoard = id;
      await store.save(id);
    } catch (e) {
      // The id is still stored: the next background, or a collapse, must clear it.
      if (mounted) _savedBoard ??= id;
      _log('Board not restored: $e');
    }
  }

  /// Whether system back may leave the app: only from the resting home, at the bar with nothing followed, no card
  /// open and no map pick under way (Android back, Google Maps style). On the tablet panel the sheet has no bar.
  bool _backLeavesApp(HomeSheet sheet, MapPick? pick) =>
```

Replace with:

```dart
    await sheet.nudge(_barHintLift);
  }

  /// Whether system back may leave the app: only from the resting home, at the bar with nothing followed, no card
  /// open and no map pick under way (Android back, Google Maps style). On the tablet panel the sheet has no bar.
  bool _backLeavesApp(HomeSheet sheet, MapPick? pick) =>
```

Edit 10 of 10 (near line 1196 before the edit). Find:

```dart
    // Every card opens at half, however it was reached; a stop's brings the map to it (spec §3.2, §3.4).
    ref.listen<HomeSheet>(homeSheetProvider, (prev, next) {
      if (prev == next) return;
      // Closed, back, or another card: the Board left open is no longer the one showing.
      _forgetBoard();
      _onSheetOpened(next);
      // Back at the bar (a card opened at launch has closed): the one-time lift, if it has not played yet.
      if (next is HomeSheetHome) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_hintBar()));
```

Replace with:

```dart
    // Every card opens at half, however it was reached; a stop's brings the map to it (spec §3.2, §3.4).
    ref.listen<HomeSheet>(homeSheetProvider, (prev, next) {
      if (prev == next) return;
      _onSheetOpened(next);
      // Back at the bar (a card opened at launch has closed): the one-time lift, if it has not played yet.
      if (next is HomeSheetHome) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_hintBar()));
```


In `lib/app.dart`:

Edit 1 of 2 (near line 8 before the edit). Find:

```dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state/arrival_alert_providers.dart';
import 'state/board_open_store.dart';
import 'state/providers.dart';

class BusboardApp extends ConsumerStatefulWidget {
```

Replace with:

```dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state/arrival_alert_providers.dart';
import 'state/providers.dart';

class BusboardApp extends ConsumerStatefulWidget {
```

Edit 2 of 2 (near line 36 before the edit). Find:

```dart
  /// alert notification that launched the app (spec §2.2).
  Future<void> _startArrivalAlerts() async {
    ref.read(arrivalAlertProvider);
    var opened = false;
    try {
      opened = openAlertRoute(await ref.read(alertNotificationsProvider).launchRoute());
    } catch (_) {
    } finally {
      // The home screen reopens the Board left open only now, and not at all after a launch link.
      final checked = ref.read(launchLinkCheckedProvider);
      if (!checked.isCompleted) checked.complete(opened);
    }
  }

```

Replace with:

```dart
  /// alert notification that launched the app (spec §2.2).
  Future<void> _startArrivalAlerts() async {
    ref.read(arrivalAlertProvider);
    try {
      openAlertRoute(await ref.read(alertNotificationsProvider).launchRoute());
    } catch (_) {
      // No launch notification to open.
    }
  }

```


```bash
git rm lib/state/board_open_store.dart test/ui/board_reopen_test.dart
```

- [ ] **Step 6: Measure the sheet above the tab bar in the existing tests**

The Map tab is now 56 pt shorter (the tab bar), so the tests that worked out the sheet's area from the screen height use `homeSheetArea`.

In `test/ui/home_sheet_test.dart`:

Edit 1 of 5 (near line 259 before the edit). Find:

```dart
    await tester.tap(find.byKey(BBSheet.handleKey));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * (844 - 2 * BBSpace.s), 1));
    expect(tester.getSemantics(find.byKey(BBSheet.handleKey)), isSemantics(label: 'Show less', isButton: true));
    tester.semantics.tap(find.semantics.byLabel('Show less'));
    await tester.pumpAndSettle();
```

Replace with:

```dart
    await tester.tap(find.byKey(BBSheet.handleKey));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * homeSheetArea(tester), 1));
    expect(tester.getSemantics(find.byKey(BBSheet.handleKey)), isSemantics(label: 'Show less', isButton: true));
    tester.semantics.tap(find.semantics.byLabel('Show less'));
    await tester.pumpAndSettle();
```

Edit 2 of 5 (near line 469 before the edit). Find:

```dart
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.fullFraction * (844 - 2 * BBSpace.s), 1));
  });

  testWidgets('pulled up, Your stop opens its sheet', (tester) async {
```

Replace with:

```dart
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.fullFraction * homeSheetArea(tester), 1));
  });

  testWidgets('pulled up, Your stop opens its sheet', (tester) async {
```

Edit 3 of 5 (near line 506 before the edit). Find:

```dart
    await tester.tap(find.text('Stop C · 80m'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    final area = 844 - 2 * BBSpace.s;
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * area, 1));
  });

```

Replace with:

```dart
    await tester.tap(find.text('Stop C · 80m'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    final area = homeSheetArea(tester);
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * area, 1));
  });

```

Edit 4 of 5 (near line 556 before the edit). Find:

```dart
      _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
      final area = 844 - 2 * BBSpace.s;
      final half = tester.getRect(find.byKey(BBSheet.cardKey)).height;
      // A short, slow drag: from half to a little above peek, where it snaps to peek and stays open.
      await tester.timedDrag(find.text('STOP C'), Offset(0, half - (sheet.peekFraction + 0.02) * area),
```

Replace with:

```dart
      _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
      final area = homeSheetArea(tester);
      final half = tester.getRect(find.byKey(BBSheet.cardKey)).height;
      // A short, slow drag: from half to a little above peek, where it snaps to peek and stays open.
      await tester.timedDrag(find.text('STOP C'), Offset(0, half - (sheet.peekFraction + 0.02) * area),
```

Edit 5 of 5 (near line 573 before the edit). Find:

```dart
      _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
      final area = 844 - 2 * BBSpace.s;
      final half = tester.getRect(find.byKey(BBSheet.cardKey)).height;
      await tester.timedDrag(find.text('STOP C'), Offset(0, half - (sheet.peekFraction + 0.02) * area),
          const Duration(seconds: 2));
```

Replace with:

```dart
      _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
      final area = homeSheetArea(tester);
      final half = tester.getRect(find.byKey(BBSheet.cardKey)).height;
      await tester.timedDrag(find.text('STOP C'), Offset(0, half - (sheet.peekFraction + 0.02) * area),
          const Duration(seconds: 2));
```


In `test/ui/board_button_test.dart` (rewritten in Task 6; this keeps it passing until then):

Edit 1 of 3 (near line 48 before the edit). Find:

```dart
/// The sheet card's height against its full detent.
void _expectAtFull(WidgetTester tester) {
  final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
  final area = tester.view.physicalSize.height / tester.view.devicePixelRatio - 2 * BBSpace.s;
  expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.fullFraction * area, 1),
      reason: 'the sheet is at full height');
}
```

Replace with:

```dart
/// The sheet card's height against its full detent.
void _expectAtFull(WidgetTester tester) {
  final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
  final area = homeSheetArea(tester);
  expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.fullFraction * area, 1),
      reason: 'the sheet is at full height');
}
```

Edit 2 of 3 (near line 95 before the edit). Find:

```dart
  testWidgets("a stop sheet's header has Open board, which pulls the sheet from half to full", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/board/C', overrides: _overrides);
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    final area = 844 - 2 * BBSpace.s;
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * area, 1));
    expect(_openBoard, findsOneWidget);
    await tester.tap(_openBoard);
```

Replace with:

```dart
  testWidgets("a stop sheet's header has Open board, which pulls the sheet from half to full", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/board/C', overrides: _overrides);
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    final area = homeSheetArea(tester);
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * area, 1));
    expect(_openBoard, findsOneWidget);
    await tester.tap(_openBoard);
```

Edit 3 of 3 (near line 120 before the edit). Find:

```dart
    await tester.tap(showMap);
    await tester.pumpAndSettle();
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    final area = tester.view.physicalSize.height / tester.view.devicePixelRatio - 2 * BBSpace.s;
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * area, 1),
        reason: 'the sheet is back at half, the map above it');
    expect(_openBoard, findsOneWidget, reason: 'and the button is Open board again');
```

Replace with:

```dart
    await tester.tap(showMap);
    await tester.pumpAndSettle();
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    final area = homeSheetArea(tester);
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * area, 1),
        reason: 'the sheet is back at half, the map above it');
    expect(_openBoard, findsOneWidget, reason: 'and the button is Open board again');
```


- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/ui/home_shell_test.dart test/ui/home_sheet_test.dart test/ui/board_button_test.dart test/ui/home_tablet_test.dart`
Expected: `All tests passed!` ("the panel stands clear of a notch at the left" passes because the shell has no page `SafeArea` around the map: only the Board's own `BBScaffold` clears side insets).

- [ ] **Step 8: Analyze and run the non-golden suite**

Run: `flutter analyze` → `No issues found!`
Run: `flutter test $(find test -name '*_test.dart' ! -name '*golden_test.dart' | sort)` → `All tests passed!`

- [ ] **Step 9: Commit**

```bash
git add lib/ui/home/home_shell.dart lib/routing/router.dart lib/ui/home/home_screen.dart lib/app.dart \
  test/helpers/planner_app.dart test/ui/home_shell_test.dart test/ui/home_sheet_test.dart \
  test/ui/board_button_test.dart
git status --short   # also shows the two deletions staged by git rm
git commit -m "feat(home): two tabs, Board and Map, over a bottom tab bar

Both tabs stay mounted; the hidden one is offstage with its tickers off,
so the map and the Board's scroll survive a switch. The Board fades over
the map (at once under Reduce Motion). The map tab ends at the tab bar,
so its sheet measures from the bar's top. The 1.4 Board restore is
replaced by the home_tab.v1 migration.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


---

### Task 6: Switching tabs from elsewhere, and no more "Show map"

**Files:**
- Modify: `lib/routing/router.dart` (`/board/:id` → Board, `/stop/:id` → card)
- Modify: `lib/ui/home/home_shell.dart` (switch to the Map for a follow, trip options and steps, a map pick)
- Modify: `lib/ui/home/home_stop_line.dart`, `lib/ui/home/home_sheet.dart`, `lib/ui/home/stop_sheet.dart` (Open board → Board tab; Show map removed)
- Modify: `lib/ui/search/search_screen.dart` (a stop picked shows where the rider is)
- Modify: `lib/state/home_sheet_provider.dart` (remove `openBoard`, `showMap`, Board requests, sheet-at-full)
- Modify: `lib/ui/home/home_screen.dart` (remove the Board request and sheet-at-full code)
- Modify tests: `test/state/home_sheet_provider_test.dart`, `test/ui/home_screen_test.dart`, `test/ui/home_sheet_test.dart`, `test/ui/reduce_motion_test.dart`, `test/routing/home_routes_test.dart`, `test/routing/swipe_back_test.dart`, `test/ui/stop_sheet_test.dart`, `test/ui/search_screen_test.dart`, `test/ui/screen_overflow_test.dart`, `test/ui/screen_golden_test.dart`
- Rewrite: `test/ui/board_button_test.dart`
- Test: `test/ui/tab_switching_test.dart`

**Interfaces:**
- Consumes: `homeTabProvider.notifier` `select`, `showBoard`, `openStop` (Task 1); `HomeShell` keys (Task 5); `BoardTab` keys (Task 4).
- Produces: the switching rules of spec §2.3:
  - To the Board: `HomeStopLine` tap, every "Open board" (`StopSheetContent.openBoardKey`, `HomeSheetContent.openBoardKey`), `/board/:stopId`, `openAlertRoute`.
  - To the Map: a new follow (`followProvider` vehicle changes to non-null), `OptionsSheet` or `JourneySheet` on top of `homeSheetProvider`, a `mapPickProvider` pick, `/stop/:stopId`.
  - Removed: `HomeSheetNotifier.openBoard`, `.showMap`, `BoardRequest`, `boardRequestProvider`, `sheetAtFullProvider`, `SheetAtFullNotifier`, `sheetIdOf`, `StopSheetContent.showMapKey`.

- [ ] **Step 1: Write the failing tests**

Create `test/ui/tab_switching_test.dart`:

```dart
import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/routing/notification_route.dart';
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/map_pick_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/board/board_tab.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_shell.dart';
import 'package:busboard_nl/ui/home/stop_sheet.dart';
import 'package:busboard_nl/ui/search/search_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

/// Switching tabs from elsewhere (spec 2026-10-15 §2.3): to the Board for a stop, to the Map for what only the map
/// shows.
final _now = DateTime(2026, 10, 12, 13, 0);

const _mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.5720, stopLon: -52.7480);

TestNetwork _network() => TestNetwork()..repo.stopsById[_mun.stopId] = _mun;

class _StopC extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(selectedStopId: 'C');
}

ArrivalRow _row(int minutes, {String? vehicle}) => ArrivalRow(
      routeShortName: '1',
      headsign: 'Downtown',
      scheduledTime: GtfsTime.parse('13:05:00'),
      minutesAway: minutes,
      isLive: vehicle != null,
      vehicleNumber: vehicle,
      tripId: '1-$minutes',
    );

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeShell)));

/// Your stop is C; its first departure is live (bus 2573).
Future<void> _pumpOnBoard(WidgetTester tester, {HomeTab tab = HomeTab.board}) => pumpPlannerApp(
      tester,
      net: _network(),
      now: _now,
      tab: tab,
      overrides: [
        settingsProvider.overrideWith(_StopC.new),
        stopArrivalsProvider.overrideWith((ref, id) async => [_row(4, vehicle: '2573'), _row(12)]),
      ],
    );

void _expectBoardOn(WidgetTester tester, String stopId) {
  expect(_c(tester).read(homeTabProvider), HomeTab.board);
  expect(find.byType(BoardTab), findsOneWidget);
  expect(find.text('STOP $stopId'), findsOneWidget);
}

void _expectMap(WidgetTester tester) {
  expect(_c(tester).read(homeTabProvider), HomeTab.map);
  expect(find.byType(HomeScreen), findsOneWidget);
  expect(find.byType(BoardTab), findsNothing);
}

void main() {
  testWidgets("an arrival alert's notification opens the Board on its stop, from the Map tab", (tester) async {
    await _pumpOnBoard(tester, tab: HomeTab.map);
    expect(openNotificationRoute('/board/B', GoRouter.of(routerElement(tester)).go), isTrue);
    await tester.pumpAndSettle();
    _expectBoardOn(tester, 'B');
  });

  testWidgets('a notification while a page is pushed over home lands on the Board too', (tester) async {
    await _pumpOnBoard(tester, tab: HomeTab.map);
    unawaited(GoRouter.of(routerElement(tester)).push('/settings'));
    await tester.pumpAndSettle();
    openNotificationRoute('/board/B', GoRouter.of(routerElement(tester)).go);
    await tester.pumpAndSettle();
    _expectBoardOn(tester, 'B');
  });

  testWidgets('a Board link at a cold start, before the schedule and the stored tab, shows that stop once loaded',
      (tester) async {
    final net = _network();
    final schedule = Completer<GtfsRepository>();
    await pumpPlannerApp(tester,
        net: net, now: _now, tab: null, initial: '/board/B', repoFuture: schedule.future, settle: false,
        asyncPrefs: {HomeTabStore.key: 'map'});
    await tester.pump();
    schedule.complete(net.repo);
    await tester.pumpAndSettle();
    _expectBoardOn(tester, 'B');
  });

  testWidgets("a stop link from the Board opens the stop's card on the Map tab", (tester) async {
    await _pumpOnBoard(tester);
    GoRouter.of(routerElement(tester)).go('/stop/B');
    await tester.pumpAndSettle();
    _expectMap(tester);
    expect(_c(tester).read(homeSheetProvider), const StopSheet('B'));
  });

  testWidgets('Follow on the Board switches to the Map and follows the bus', (tester) async {
    await _pumpOnBoard(tester);
    await tester.tap(find.byType(ArrivalRowTile).first);
    await tester.pumpAndSettle();
    _expectMap(tester);
    expect(_c(tester).read(followProvider)?.vehicleId, '2573');
    expect(find.text('Following bus 2573'), findsOneWidget);
  });

  testWidgets('Where to? on the Board: a destination opens its trip options on the Map tab', (tester) async {
    await _pumpOnBoard(tester);
    await tester.tap(find.byKey(BoardTab.whereToKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SearchScreen.fieldKey), '1150');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('MUN Centre').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    _expectMap(tester);
    expect(_c(tester).read(homeSheetProvider), isA<OptionsSheet>());
    expect(_c(tester).read(planQueryProvider).to, StopPlace(stopId: '1150', name: 'MUN Centre'));
  });

  testWidgets('Where to? on the Board, then back without a destination: still the Board', (tester) async {
    await _pumpOnBoard(tester);
    await tester.tap(find.byKey(BoardTab.whereToKey));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    _expectBoardOn(tester, 'C');
  });

  testWidgets('Plan a trip from here on the Board: the trip from that stop opens on the Map tab', (tester) async {
    await _pumpOnBoard(tester);
    await tester.ensureVisible(find.byKey(StopSheetContent.planFromKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(StopSheetContent.planFromKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SearchScreen.fieldKey), '1150');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('MUN Centre').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go here'));
    await tester.pumpAndSettle();
    _expectMap(tester);
    expect(_c(tester).read(homeSheetProvider), isA<OptionsSheet>());
    expect(_c(tester).read(planQueryProvider).from, StopPlace(stopId: 'C', name: 'Stop C'));
  });

  testWidgets("a stop's buses chosen in a search from the Board show on the Board", (tester) async {
    await _pumpOnBoard(tester);
    await tester.tap(find.byKey(BoardTab.whereToKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SearchScreen.fieldKey), '1150');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('MUN Centre').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('See its buses'));
    await tester.pumpAndSettle();
    _expectBoardOn(tester, '1150');
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>(), reason: 'no card opened behind the Board');
  });

  testWidgets('＋ on the Board: the stop picked becomes your stop, and the Board shows it', (tester) async {
    await _pumpOnBoard(tester);
    await tester.tap(find.byKey(BoardTab.findStopKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SearchScreen.fieldKey), '1150');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('MUN Centre').first);
    await tester.pumpAndSettle();
    _expectBoardOn(tester, '1150');
    expect(_c(tester).read(settingsProvider).selectedStopId, '1150');
  });

  testWidgets('Choose on map, from a search opened on the Board, switches to the Map to choose', (tester) async {
    await _pumpOnBoard(tester);
    await tester.tap(find.byKey(BoardTab.whereToKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose on map'));
    await tester.pumpAndSettle();
    _expectMap(tester);
    expect(_c(tester).read(mapPickProvider), MapPick.to);
  });
}
```


Replace the whole of `test/ui/board_button_test.dart` with:

```dart
import 'package:busboard_nl/data/trip_planner/saved_place_store.dart' show SavedPlaceIcon;
import 'package:busboard_nl/ui/home/home_sheet.dart' show HomeSheetContent, savedPlaceIconData;
import 'package:busboard_nl/ui/home/home_stop_line.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/ui/board/board_tab.dart';
import 'package:busboard_nl/ui/home/home_shell.dart';
import 'package:busboard_nl/ui/home/stop_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/test_network.dart';

/// "Open board" (spec 2026-10-15 §2.3): on home's Your stop, on the bar's stop line and in every stop card's header,
/// it switches to the Board tab, showing that stop. The card's old "Show map" is gone.
final _now = DateTime(2026, 10, 12, 13, 0);

class _FixedSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(selectedStopId: 'C');
}

ArrivalRow _arrival(int minutes) => ArrivalRow(
      routeShortName: '1',
      headsign: 'Downtown',
      scheduledTime: GtfsTime.parse('13:05:00'),
      minutesAway: minutes,
      isLive: false,
      tripId: '1-$minutes',
    );

final List<Override> _overrides = [
  settingsProvider.overrideWith(_FixedSettings.new),
  stopArrivalsProvider.overrideWith((ref, id) async => [for (var m = 2; m < 60; m += 6) _arrival(m)]),
];

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeShell)));

final _openBoard = find.bySemanticsLabel('Open board, Stop C');

/// The Board tab is showing [stopId].
void _expectBoardOn(WidgetTester tester, String stopId) {
  expect(_c(tester).read(homeTabProvider), HomeTab.board);
  expect(find.byType(BoardTab), findsOneWidget, reason: 'the Board is the tab showing');
  expect(find.text('STOP $stopId'), findsOneWidget);
}

void main() {
  // The app's own fonts, for the large-text check.
  setUpAll(loadAppFonts);

  test("a saved place's icon never looks like Open board's, and each kind has its own", () {
    final icons = [for (final i in SavedPlaceIcon.values) savedPlaceIconData(i)];
    expect(icons, isNot(contains(BBIcons.board)));
    expect(icons.toSet(), hasLength(icons.length));
  });

  testWidgets('Open board looks the same on home as in the stop sheet: the filled button', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    final onHome = tester.widget<BBButton>(find.ancestor(of: _openBoard, matching: find.byType(BBButton)).first);
    expect(onHome.kind, BBButtonKind.primary, reason: 'not a text-only link');
    _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
    await tester.pumpAndSettle();
    final inSheet = tester.widget<BBButton>(find.ancestor(of: _openBoard, matching: find.byType(BBButton)).first);
    expect(inSheet.kind, onHome.kind);
  });

  testWidgets("the bar's stop line switches to the Board, on your stop", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await tester.tap(find.byKey(HomeStopLine.lineKey));
    await tester.pumpAndSettle();
    _expectBoardOn(tester, 'C');
  });

  testWidgets("pulled up, home's Your stop has Open board, which switches to the Board on it", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_openBoard.hitTestable(), findsOneWidget);
    await tester.tap(_openBoard);
    await tester.pumpAndSettle();
    _expectBoardOn(tester, 'C');
  });

  testWidgets("a stop card's Open board switches to the Board on that stop; the card stays on the map",
      (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/stop/B', overrides: _overrides);
    await tester.tap(find.bySemanticsLabel('Open board, Stop B'));
    await tester.pumpAndSettle();
    _expectBoardOn(tester, 'B');
    expect(_c(tester).read(homeSheetProvider), const StopSheet('B'), reason: 'back on the map, the card is there');
  });

  testWidgets('pulled up to full, a stop card still says Open board: there is no Show map', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/stop/C', overrides: _overrides);
    await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.fullFraction * homeSheetArea(tester), 1));
    expect(find.byKey(StopSheetContent.openBoardKey), findsOneWidget);
    expect(find.text('Show map'), findsNothing);
  });

  testWidgets('at 2x text on a 320 wide phone, Open board reads in full, light and dark', (tester) async {
    for (final theme in [BBTheme.light(), BBTheme.dark()]) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpPlannerApp(tester,
          net: TestNetwork(), now: _now, textScale: 2, theme: theme, initial: '/stop/C', overrides: _overrides);
      await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final label = find.descendant(of: find.byKey(StopSheetContent.openBoardKey), matching: find.text('Open board'));
      expect(label, findsOneWidget, reason: 'Open board reads in full');
      await tester.tap(find.byKey(StopSheetContent.openBoardKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _expectBoardOn(tester, 'C');
    }
  });

  testWidgets("on the tablet panel, home's Open board switches to the Board", (tester) async {
    tester.view.physicalSize = const Size(1024, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await tester.tap(_openBoard);
    await tester.pumpAndSettle();
    _expectBoardOn(tester, 'C');
  });
}
```


- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/ui/tab_switching_test.dart test/ui/board_button_test.dart`
Expected: 15 of the 19 fail. Among them: "an arrival alert's notification opens the Board on its stop" (`Expected: HomeTab.board, Actual: HomeTab.map`: `/board/` still opens the card), "Follow on the Board switches to the Map" (still the Board), "the bar's stop line switches to the Board" (it pulls the card to full), "pulled up to full, a stop card still says Open board" (`Show map` found). The four that already pass ("Where to? … then back", "＋ on the Board", the icon test and "looks the same") pin behaviour that must not change.

- [ ] **Step 3: Route links, and switch to the Map for what only it shows**

In `lib/routing/router.dart`:

Edit 1 of 3 (near line 3 before the edit). Find:

```dart
import 'package:go_router/go_router.dart';

import '../state/home_sheet_provider.dart';
import '../state/map_pick_provider.dart';
import '../ui/alerts/alerts_screen.dart';
import '../ui/home/home_shell.dart';
```

Replace with:

```dart
import 'package:go_router/go_router.dart';

import '../state/home_sheet_provider.dart';
import '../state/home_tab_provider.dart';
import '../state/map_pick_provider.dart';
import '../ui/alerts/alerts_screen.dart';
import '../ui/home/home_shell.dart';
```

Edit 2 of 3 (near line 13 before the edit). Find:

```dart
/// The app's router.
final appRouter = buildAppRouter();

/// Opens [stopId]'s sheet on home: links and notifications for a stop land here (spec 2026-10-12 §3.6).
String _toStopSheet(BuildContext context, GoRouterState state) {
  final id = state.pathParameters['stopId']!;
  final container = ProviderScope.containerOf(context, listen: false);
  // A redirect can run while the widget tree builds (the first route), when a provider may not change.
  Future.microtask(() => container.read(homeSheetProvider.notifier).open(StopSheet(id)));
  return '/';
}

```

Replace with:

```dart
/// The app's router.
final appRouter = buildAppRouter();

/// A Board link, and an arrival alert's notification (spec 2026-10-15 §2.3): the Board tab, showing [stopId].
String _toBoard(BuildContext context, GoRouterState state) {
  final id = state.pathParameters['stopId']!;
  final container = ProviderScope.containerOf(context, listen: false);
  // A redirect can run while the widget tree builds (the first route), when a provider may not change. The tab is
  // state, so a link that lands before home is built is shown once it is.
  Future.microtask(() => container.read(homeTabProvider.notifier).showBoard(id));
  return '/';
}

/// A stop link: the stop's card on the Map tab (spec 2026-10-12 §3.6).
String _toStopCard(BuildContext context, GoRouterState state) {
  final id = state.pathParameters['stopId']!;
  final container = ProviderScope.containerOf(context, listen: false);
  Future.microtask(() {
    container.read(homeSheetProvider.notifier).open(StopSheet(id));
    container.read(homeTabProvider.notifier).select(HomeTab.map);
  });
  return '/';
}

```

Edit 3 of 3 (near line 43 before the edit). Find:

```dart
        path: '/',
        pageBuilder: (context, state) => _page(state, const HomeShell()),
      ),
      GoRoute(path: '/stop/:stopId', redirect: _toStopSheet),
      GoRoute(path: '/board/:stopId', redirect: _toStopSheet),
      GoRoute(path: '/map', redirect: (_, _) => '/'),
      GoRoute(
        path: '/plan',
```

Replace with:

```dart
        path: '/',
        pageBuilder: (context, state) => _page(state, const HomeShell()),
      ),
      GoRoute(path: '/stop/:stopId', redirect: _toStopCard),
      GoRoute(path: '/board/:stopId', redirect: _toBoard),
      GoRoute(path: '/map', redirect: (_, _) => '/'),
      GoRoute(
        path: '/plan',
```


In `lib/ui/home/home_shell.dart`:

Edit 1 of 2 (near line 1 before the edit). Find:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/home_tab_provider.dart';
import '../board/board_tab.dart';
import '../kit/kit.dart';
import 'home_screen.dart';
```

Replace with:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/follow_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/home_tab_provider.dart';
import '../../state/map_pick_provider.dart';
import '../board/board_tab.dart';
import '../kit/kit.dart';
import 'home_screen.dart';
```

Edit 2 of 2 (near line 48 before the edit). Find:

```dart
        _board.animateTo(target, duration: duration, curve: BBMotion.curve);
      }
    });
  }

  @override
  void dispose() {
    _board.dispose();
```

Replace with:

```dart
        _board.animateTo(target, duration: duration, curve: BBMotion.curve);
      }
    });
    // What only the map can show switches to it (spec 2026-10-15 §2.3), from the Board or anywhere else: a bus
    // followed, a trip's options or steps (Where to? or Plan a trip from here on the Board), and choosing on the map.
    ref.listenManual<String?>(followProvider.select((f) => f?.vehicleId), (previous, next) {
      if (next != null && next != previous) _toMap();
    });
    ref.listenManual<HomeSheet>(homeSheetProvider, (_, next) {
      if (next is OptionsSheet || next is JourneySheet) _toMap();
    });
    ref.listenManual<MapPick?>(mapPickProvider, (_, next) {
      if (next != null) _toMap();
    });
  }

  void _toMap() => ref.read(homeTabProvider.notifier).select(HomeTab.map);

  @override
  void dispose() {
    _board.dispose();
```


- [ ] **Step 4: Open board opens the Board tab; Show map goes**

In `lib/ui/home/stop_sheet.dart`:

Edit 1 of 3 (near line 8 before the edit). Find:

```dart
import '../../state/arrival_alert_providers.dart';
import '../../state/follow_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
```

Replace with:

```dart
import '../../state/arrival_alert_providers.dart';
import '../../state/follow_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/home_tab_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
```

Edit 2 of 3 (near line 26 before the edit). Find:

```dart
  static const planFromKey = ValueKey('stop-plan-from');
  static const closeKey = ValueKey('stop-close');
  static const openBoardKey = ValueKey('stop-open-board');
  static const showMapKey = ValueKey('stop-show-map');

  /// The card's header: [info], Close, Open board and Plan a trip from here.
  static Widget header(String stopId) => _StopHeader(stopId: stopId);
```

Replace with:

```dart
  static const planFromKey = ValueKey('stop-plan-from');
  static const closeKey = ValueKey('stop-close');
  static const openBoardKey = ValueKey('stop-open-board');

  /// The card's header: [info], Close, Open board and Plan a trip from here.
  static Widget header(String stopId) => _StopHeader(stopId: stopId);
```

Edit 3 of 3 (near line 55 before the edit). Find:

```dart
        children: [
          _StopInfo(stopId: stopId, closable: true),
          const SizedBox(height: BBSpace.s),
          // For riders used to the Board tab: the whole Board in one tap (the sheet at full height; on the tablet panel,
          // its departures). With the Board open it turns into the way back: "Show map" brings the sheet to half over
          // the stop. One button either way, so the header keeps one height and the detents never move under a drag.
          Padding(
            // The header is padded l on the left but s on the right (for the icon buttons' own hit area): this evens
            // the filled button's sides.
            padding: const EdgeInsets.only(right: BBSpace.l - BBSpace.s),
            child: ref.watch(sheetAtFullProvider) == sheetIdOf(StopSheet(stopId))
                ? BBButton(
                    key: StopSheetContent.showMapKey,
                    label: 'Show map',
                    semanticLabel: 'Show the map, $name',
                    icon: BBIcons.map,
                    expand: true,
                    wrap: true,
                    onPressed: () => ref.read(homeSheetProvider.notifier).showMap(),
                  )
                : BBButton(
                    key: StopSheetContent.openBoardKey,
                    label: 'Open board',
                    semanticLabel: 'Open board, $name',
                    icon: BBIcons.board,
                    expand: true,
                    wrap: true,
                    onPressed: () => ref.read(homeSheetProvider.notifier).openBoard(stopId),
                  ),
          ),
          _PlanFrom(stopId: stopId),
        ],
```

Replace with:

```dart
        children: [
          _StopInfo(stopId: stopId, closable: true),
          const SizedBox(height: BBSpace.s),
          // The stop's departures on the Board tab (spec 2026-10-15 §2.3), however far the card is pulled up.
          Padding(
            // The header is padded l on the left but s on the right (for the icon buttons' own hit area): this evens
            // the filled button's sides.
            padding: const EdgeInsets.only(right: BBSpace.l - BBSpace.s),
            child: BBButton(
              key: StopSheetContent.openBoardKey,
              label: 'Open board',
              semanticLabel: 'Open board, $name',
              icon: BBIcons.board,
              expand: true,
              wrap: true,
              onPressed: () => ref.read(homeTabProvider.notifier).showBoard(stopId),
            ),
          ),
          _PlanFrom(stopId: stopId),
        ],
```


In `lib/ui/home/home_sheet.dart`:

Edit 1 of 3 (near line 10 before the edit). Find:

```dart
import '../../state/alerts_for_you_provider.dart';
import '../../state/arrival_alert_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/providers.dart';
import '../../state/saved_place_providers.dart';
import '../../state/trip_planner_providers.dart';
```

Replace with:

```dart
import '../../state/alerts_for_you_provider.dart';
import '../../state/arrival_alert_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/home_tab_provider.dart';
import '../../state/providers.dart';
import '../../state/saved_place_providers.dart';
import '../../state/trip_planner_providers.dart';
```

Edit 2 of 3 (near line 238 before the edit). Find:

```dart
                ],
              ),
            ),
            // For riders used to the Board tab: their stop's whole Board in one tap. The same filled button as in
            // the stop's own sheet, so it reads as the way in, not a link.
            const SizedBox(height: BBSpace.s),
            BBButton(
              key: HomeSheetContent.openBoardKey,
```

Replace with:

```dart
                ],
              ),
            ),
            // Their stop on the Board tab in one tap (spec 2026-10-15 §2.3). The same filled button as in the stop's
            // own sheet, so it reads as the way in, not a link.
            const SizedBox(height: BBSpace.s),
            BBButton(
              key: HomeSheetContent.openBoardKey,
```

Edit 3 of 3 (near line 248 before the edit). Find:

```dart
              icon: BBIcons.board,
              expand: true,
              wrap: true,
              onPressed: () => ref.read(homeSheetProvider.notifier).openBoard(stop.stopId),
            ),
            ArrivalsPreview(stopId: stop.stopId, max: 3),
          ],
```

Replace with:

```dart
              icon: BBIcons.board,
              expand: true,
              wrap: true,
              onPressed: () => ref.read(homeTabProvider.notifier).showBoard(stop.stopId),
            ),
            ArrivalsPreview(stopId: stop.stopId, max: 3),
          ],
```


In `lib/ui/home/home_stop_line.dart`:

Edit 1 of 2 (near line 8 before the edit). Find:

```dart
import '../../data/realtime/service_alert_models.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival/first_bus.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
```

Replace with:

```dart
import '../../data/realtime/service_alert_models.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival/first_bus.dart';
import '../../state/home_tab_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
```

Edit 2 of 2 (near line 226 before the edit). Find:

```dart
    return BBPressable(
      key: lineKey,
      semanticLabel: info.semantics(use24h: use24h),
      onTap: () => ref.read(homeSheetProvider.notifier).openBoard(stop.stopId),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: LayoutBuilder(
```

Replace with:

```dart
    return BBPressable(
      key: lineKey,
      semanticLabel: info.semantics(use24h: use24h),
      onTap: () => ref.read(homeTabProvider.notifier).showBoard(stop.stopId),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: LayoutBuilder(
```


In `lib/ui/search/search_screen.dart`:

Edit 1 of 4 (near line 9 before the edit). Find:

```dart
import '../../domain/location/locate_me.dart';
import '../../domain/trip_planner/place.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/map_pick_provider.dart';
import '../../state/providers.dart';
import '../../state/saved_place_providers.dart';
```

Replace with:

```dart
import '../../domain/location/locate_me.dart';
import '../../domain/trip_planner/place.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/home_tab_provider.dart';
import '../../state/map_pick_provider.dart';
import '../../state/providers.dart';
import '../../state/saved_place_providers.dart';
```

Edit 2 of 4 (near line 117 before the edit). Find:

```dart
    final query = ref.read(planQueryProvider.notifier);
    final recent = ref.read(recentPlacesProvider.notifier);
    final sheet = ref.read(homeSheetProvider.notifier);
    // A fresh trip has no start; a changed destination keeps the trip's start (fillStart keeps one chosen meanwhile).
    final needsStart = !widget.keepStart || ref.read(planQueryProvider).from == null;
    _busy = true;
```

Replace with:

```dart
    final query = ref.read(planQueryProvider.notifier);
    final recent = ref.read(recentPlacesProvider.notifier);
    final sheet = ref.read(homeSheetProvider.notifier);
    final tabs = ref.read(homeTabProvider.notifier);
    // A fresh trip has no start; a changed destination keeps the trip's start (fillStart keeps one chosen meanwhile).
    final needsStart = !widget.keepStart || ref.read(planQueryProvider).from == null;
    _busy = true;
```

Edit 3 of 4 (near line 125 before the edit). Find:

```dart
      if (widget.pickStop) {
        if (place is! StopPlace) return;
        final settings = ref.read(settingsProvider.notifier);
        sheet.open(StopSheet(place.stopId));
        _leave(router);
        await recent.push(place);
        await settings.setSelectedStop(place.stopId);
```

Replace with:

```dart
      if (widget.pickStop) {
        if (place is! StopPlace) return;
        final settings = ref.read(settingsProvider.notifier);
        // On the Board, the Board shows it; on the map, its card (spec 2026-10-15 §2.3).
        tabs.openStop(place.stopId);
        _leave(router);
        await recent.push(place);
        await settings.setSelectedStop(place.stopId);
```

Edit 4 of 4 (near line 147 before the edit). Find:

```dart
        );
        if (goHere == null) return;
        if (!goHere) {
          sheet.open(StopSheet(place.stopId));
          if (mounted) _leave(router);
          return;
        }
```

Replace with:

```dart
        );
        if (goHere == null) return;
        if (!goHere) {
          tabs.openStop(place.stopId);
          if (mounted) _leave(router);
          return;
        }
```


- [ ] **Step 5: Remove the Board request and "sheet at full"**

In `lib/state/home_sheet_provider.dart`:

Edit 1 of 2 (near line 94 before the edit). Find:

```dart
    state = _stack.last;
  }

  /// "Open board": [stopId]'s sheet, pulled up to full height (its Board); on the tablet panel, scrolled to its
  /// departures. A sheet already showing the stop stays as it is in the stack.
  void openBoard(String stopId) {
    final sheet = StopSheet(stopId);
    if (_stack.last != sheet) open(sheet);
    ref.read(boardRequestProvider.notifier)._request(stopId);
  }

  /// "Show map", from a Board at full height: the card on top back to half, its stop centred on the map.
  void showMap() => ref.read(homeSheetReopenedProvider.notifier)._bump();

  /// False when already home (the caller lets the system leave the app).
  bool back() {
    if (_stack.length <= 1) return false;
```

Replace with:

```dart
    state = _stack.last;
  }

  /// False when already home (the caller lets the system leave the app).
  bool back() {
    if (_stack.length <= 1) return false;
```

Edit 2 of 2 (near line 132 before the edit). Find:

```dart

  void _bump() => state++;
}

/// A request to show [stopId]'s Board: its sheet at full height. A new object every time, so asking twice is two
/// requests.
final class BoardRequest {
  BoardRequest(this.stopId);
  final String stopId;
}

/// The latest "Open board" (or a cold start reopening the Board left open); the home screen moves the sheet.
final boardRequestProvider = NotifierProvider<BoardRequestNotifier, BoardRequest?>(BoardRequestNotifier.new);

class BoardRequestNotifier extends Notifier<BoardRequest?> {
  @override
  BoardRequest? build() => null;

  void _request(String stopId) => state = BoardRequest(stopId);
}

/// Which sheet the phone's pull-up sheet is showing at its full height, by [sheetIdOf], or null when none is: a stop's
/// sheet there is its Board, and its header button turns from "Open board" into "Show map". A sheet compares the id
/// with its own, so a value left by the sheet it replaced never matches. Always null on the tablet panel, which has no
/// detents.
final sheetAtFullProvider = NotifierProvider<SheetAtFullNotifier, String?>(SheetAtFullNotifier.new);

class SheetAtFullNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// [sheetId] is at full height; null when no sheet is.
  void set(String? sheetId) {
    if (state != sheetId) state = sheetId;
  }
}

/// The id [sheetAtFullProvider] holds for the pull-up sheet showing [sheetKey]: a [HomeSheet], or the follow card's
/// own key (`follow:2573`).
String sheetIdOf(Object sheetKey) => switch (sheetKey) {
      HomeSheetHome() => 'home',
      StopSheet(:final stopId) => 'stop:$stopId',
      BusSheet(:final vehicleId) => 'bus:$vehicleId',
      OptionsSheet() => 'options',
      JourneySheet(:final journey) => 'journey:${identityHashCode(journey)}',
      _ => '$sheetKey',
    };
```

Replace with:

```dart

  void _bump() => state++;
}
```


In `lib/ui/home/home_screen.dart` (the `semantics.dart` and `services.dart` imports go with `_sayBoardOpen`, their last users):

Edit 1 of 6 (near line 3 before the edit). Find:

```dart

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
```

Replace with:

```dart

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
```

Edit 2 of 6 (near line 217 before the edit). Find:

```dart
  final _retiredSheets = <BBSheetController>[];

  // A newly opened card goes to half once its sheet is built (it may not be yet: a link opened before the schedule
  // loaded), and a stop's card brings the camera to its stop once there is a camera. "Open board" asks for full.
  BBSheetDetent? _detentPending;

  /// The last layout's: the side panel (a tablet) rather than the pull-up sheet.
```

Replace with:

```dart
  final _retiredSheets = <BBSheetController>[];

  // A newly opened card goes to half once its sheet is built (it may not be yet: a link opened before the schedule
  // loaded), and a stop's card brings the camera to its stop once there is a camera.
  BBSheetDetent? _detentPending;

  /// The last layout's: the side panel (a tablet) rather than the pull-up sheet.
```

Edit 3 of 6 (near line 656 before the edit). Find:

```dart
  /// lowest stop, once per gesture (spec 2026-10-14 §3.4): the home sheet to its bar, a stop, bus, options or trip card
  /// to its own peek. Only the map's Listener calls it, so the sheet's own drags and scrolls never do. Not while
  /// following (the follow card keeps its place), on the tablet panel, while choosing on the map, or at full height
  /// (the Board, opened on purpose: a pan in the strip above it must not close it). Under Reduce Motion the sheet's
  /// 1 ms snap makes it a jump.
  void _tuckSheet() {
    if (_tucked) return;
    _tucked = true;
```

Replace with:

```dart
  /// lowest stop, once per gesture (spec 2026-10-14 §3.4): the home sheet to its bar, a stop, bus, options or trip card
  /// to its own peek. Only the map's Listener calls it, so the sheet's own drags and scrolls never do. Not while
  /// following (the follow card keeps its place), on the tablet panel, while choosing on the map, or at full height
  /// (pulled up on purpose: a pan in the strip above it must not close it). Under Reduce Motion the sheet's 1 ms snap
  /// makes it a jump.
  void _tuckSheet() {
    if (_tucked) return;
    _tucked = true;
```

Edit 4 of 6 (near line 850 before the edit). Find:

```dart
      }
      if (!_sheet.isAttached) return;
      _detentPending = null;
      if (detent == BBSheetDetent.full && _sheetAtFull) {
        // Already the Board: back up to the next buses, just under the pinned header; already there, say so.
        if (!_scrollSheetToTop()) _sayBoardOpen();
      } else {
        unawaited(_sheet.animateToDetent(detent));
      }
    });
  }

  /// "Open board" (a stop's sheet just opened, or already showing): full height, or the panel's departures.
  void _onBoardRequest(BoardRequest? request) {
    if (request == null || ref.read(homeSheetProvider) != StopSheet(request.stopId)) return;
    _toDetentAfterBuild(BBSheetDetent.full);
  }

  /// The pull-up sheet's list back to its top. False when it is there already.
  bool _scrollSheetToTop() {
    final header = _headerKey.currentContext;
    final scrollable = header == null ? null : Scrollable.maybeOf(header);
    if (scrollable == null || !scrollable.position.hasPixels || scrollable.position.pixels <= 0) return false;
    unawaited(scrollable.position.animateTo(0, duration: BBMotion.of(context, BBMotion.emphasis), curve: BBMotion.curve));
    return true;
  }

  /// "Open board" on the Board itself, with nothing to move: a tick, and a word for screen readers.
  void _sayBoardOpen() {
    unawaited(HapticFeedback.selectionClick());
    unawaited(SemanticsService.sendAnnouncement(View.of(context), 'Board open', Directionality.of(context)));
  }

  /// The pull-up sheet is at its full height.
  bool _sheetAtFull = false;

  /// The id of the sheet now showing, for [sheetAtFullProvider].
  String get _sheetId => sheetIdOf(_sheetKey ?? const HomeSheetHome());

  bool _onSheetExtent(DraggableScrollableNotification n) {
    _sheetExtent = n.extent;
    final wasAtFull = _sheetAtFull;
    _sheetAtFull = n.extent >= n.maxExtent - 0.004;
    final abovePeek = n.extent > n.minExtent + 0.02;
    if (wasAtFull != _sheetAtFull || abovePeek != _sheetAbovePeek) {
      // The notification can come mid-layout: what it changes is built on the next frame.
      void apply() {
        if (!mounted) return;
        ref.read(sheetAtFullProvider.notifier).set(_sheetAtFull ? _sheetId : null);
        if (abovePeek != _sheetAbovePeek) setState(() => _sheetAbovePeek = abovePeek);
      }
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
        apply();
```

Replace with:

```dart
      }
      if (!_sheet.isAttached) return;
      _detentPending = null;
      unawaited(_sheet.animateToDetent(detent));
    });
  }

  /// The pull-up sheet is at its full height.
  bool _sheetAtFull = false;

  bool _onSheetExtent(DraggableScrollableNotification n) {
    _sheetExtent = n.extent;
    _sheetAtFull = n.extent >= n.maxExtent - 0.004;
    final abovePeek = n.extent > n.minExtent + 0.02;
    if (abovePeek != _sheetAbovePeek) {
      // The notification can come mid-layout: what it changes is built on the next frame.
      void apply() {
        if (mounted && abovePeek != _sheetAbovePeek) setState(() => _sheetAbovePeek = abovePeek);
      }
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
        apply();
```

Edit 5 of 6 (near line 1043 before the edit). Find:

```dart
      _sheetExtent = 0;
      _headerKey = GlobalKey();
      _headerHeight = null;
      // Its header is measured once laid out (a first layout sends no size-changed notification). The last sheet's
      // "at full" names that sheet, so this one never reads it as its own; it is cleared once the frame is done
      // (provider changes wait for the frame).
      _scheduleHeaderMeasure();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(sheetAtFullProvider.notifier).set(_sheetAtFull ? _sheetId : null);
      });
      _actionsKey = GlobalKey();
      _actionsBottom = null;
      _retiredSheets.add(_sheet);
```

Replace with:

```dart
      _sheetExtent = 0;
      _headerKey = GlobalKey();
      _headerHeight = null;
      // Its header is measured once laid out (a first layout sends no size-changed notification).
      _scheduleHeaderMeasure();
      _actionsKey = GlobalKey();
      _actionsBottom = null;
      _retiredSheets.add(_sheet);
```

Edit 6 of 6 (near line 1132 before the edit). Find:

```dart
      if (next is HomeSheetHome) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_hintBar()));
    });
    ref.listen<int>(homeSheetReopenedProvider, (_, _) => _onSheetOpened(ref.read(homeSheetProvider), again: true));
    ref.listen<BoardRequest?>(boardRequestProvider, (_, next) => _onBoardRequest(next));
    final journey = ref.watch(journeyOnMapProvider);
    final pick = ref.watch(mapPickProvider);
    _syncFollow(ref.watch(followProvider));
```

Replace with:

```dart
      if (next is HomeSheetHome) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_hintBar()));
    });
    ref.listen<int>(homeSheetReopenedProvider, (_, _) => _onSheetOpened(ref.read(homeSheetProvider), again: true));
    final journey = ref.watch(journeyOnMapProvider);
    final pick = ref.watch(mapPickProvider);
    _syncFollow(ref.watch(followProvider));
```


- [ ] **Step 6: Bring the existing tests up to date**

The unit test of `sheetIdOf` goes with it.

In `test/state/home_sheet_provider_test.dart`:

Edit 1 of 1 (near line 74 before the edit). Find:

```dart
    n().home();
    expect(n().stack, hasLength(1));
  });

  test('every sheet has its own id, so the sheet at full is never mistaken for another', () {
    final j1 = Journey(serviceDate: DateTime(2026, 10, 7), legs: const []);
    final j2 = Journey(serviceDate: DateTime(2026, 10, 7), legs: const []);
    final ids = [
      sheetIdOf(const HomeSheetHome()),
      sheetIdOf(const StopSheet('1150')),
      sheetIdOf(const StopSheet('1151')),
      sheetIdOf(const BusSheet('1150')),
      sheetIdOf(const OptionsSheet()),
      sheetIdOf(JourneySheet(j1)),
      sheetIdOf(JourneySheet(j2)),
      sheetIdOf('follow:2573'),
    ];
    expect(ids.toSet(), hasLength(ids.length));
    expect(sheetIdOf(const StopSheet('1150')), sheetIdOf(const StopSheet('1150')));
  });
}
```

Replace with:

```dart
    n().home();
    expect(n().stack, hasLength(1));
  });
}
```


In `test/ui/home_screen_test.dart` (the tuck-away test reaches full height with a drag; the "opened after full" test no longer checks for Show map):

Edit 1 of 2 (near line 1014 before the edit). Find:

```dart
      expect(top(tester), closeTo(bar, 1));
    });

    testWidgets('not when the sheet is at full: a pan in the strip above the Board leaves it open', (tester) async {
      await _pump(tester, prefs: {'selectedStopId': '1150'});
      container(tester).read(homeSheetProvider.notifier).openBoard('1150');
      await frames(tester);
      final full = top(tester);
      final board = tester.widget<BBSheet>(find.byType(BBSheet));
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(board.fullFraction * (844 - 2 * BBSpace.s), 1));
      expect(container(tester).read(sheetAtFullProvider), sheetIdOf(const StopSheet('1150')));
      // Bare map above the card's top (about 91 pt) and below the chips.
      expect(full, greaterThan(86));
      await tester.dragFrom(const Offset(60, 58), const Offset(0, 26));
      await frames(tester);
      expect(top(tester), full, reason: 'the Board stays open');
      expect(container(tester).read(sheetAtFullProvider), sheetIdOf(const StopSheet('1150')));
      expect(find.byKey(StopSheetContent.showMapKey), findsOneWidget);
    });
  });

```

Replace with:

```dart
      expect(top(tester), closeTo(bar, 1));
    });

    testWidgets('not when the sheet is at full: a pan in the strip above the card leaves it there', (tester) async {
      await _pump(tester, prefs: {'selectedStopId': '1150'});
      container(tester).read(homeSheetProvider.notifier).open(const StopSheet('1150'));
      await frames(tester);
      await tester.drag(find.text('STOP 1150'), const Offset(0, -600));
      await frames(tester);
      final full = top(tester);
      final card = tester.widget<BBSheet>(find.byType(BBSheet));
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(card.fullFraction * (844 - 2 * BBSpace.s), 1));
      // Bare map above the card's top (about 91 pt) and below the chips.
      expect(full, greaterThan(86));
      await tester.dragFrom(const Offset(60, 58), const Offset(0, 26));
      await frames(tester);
      expect(top(tester), full, reason: 'the card stays up');
      expect(find.byKey(StopSheetContent.openBoardKey), findsOneWidget, reason: 'at full it is still Open board');
    });
  });

```

Edit 2 of 2 (near line 1087 before the edit). Find:

```dart
      expect(top(tester), closeTo(bar, 1));
    });

    testWidgets('a stop card opened after home was pulled to full opens at half with Open board, not Show map',
        (tester) async {
      await _pump(tester, prefs: {'selectedStopId': '1150'},
          overrides: [homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen())]);
      await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
      await frames(tester);
      await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -400));
      await frames(tester);
      expect(container(tester).read(sheetAtFullProvider), sheetIdOf(const HomeSheetHome()), reason: 'home is at full');
      container(tester).read(homeSheetProvider.notifier).open(const StopSheet('1150'));
      // Not even for the card's first frame: the home sheet's "at full" is not the card's.
      for (var i = 0; i < 6; i++) {
        await tester.pump(i == 0 ? Duration.zero : const Duration(milliseconds: 16));
        expect(find.byKey(StopSheetContent.showMapKey), findsNothing, reason: 'frame $i says Show map');
      }
      await frames(tester);
      final card = tester.widget<BBSheet>(find.byType(BBSheet));
      expect(height(tester), closeTo(card.halfFraction * area, 1), reason: 'the card opens at half');
      expect(container(tester).read(sheetAtFullProvider), isNull);
      expect(find.byKey(StopSheetContent.openBoardKey), findsOneWidget);
      expect(find.byKey(StopSheetContent.showMapKey), findsNothing);
    });
  });

```

Replace with:

```dart
      expect(top(tester), closeTo(bar, 1));
    });

    testWidgets('a stop card opened after home was pulled to full opens at half, with Open board', (tester) async {
      await _pump(tester, prefs: {'selectedStopId': '1150'},
          overrides: [homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen())]);
      await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
      await frames(tester);
      await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -400));
      await frames(tester);
      final home = tester.widget<BBSheet>(find.byType(BBSheet));
      expect(height(tester), closeTo(home.fullFraction * area, 1), reason: 'home is at full');
      container(tester).read(homeSheetProvider.notifier).open(const StopSheet('1150'));
      await frames(tester);
      final card = tester.widget<BBSheet>(find.byType(BBSheet));
      expect(height(tester), closeTo(card.halfFraction * area, 1), reason: 'the card opens at half');
      expect(find.byKey(StopSheetContent.openBoardKey), findsOneWidget);
    });
  });

```


In `test/ui/home_sheet_test.dart` (the stop line now opens the Board tab; the "opened again" test uses a stop link):

Edit 1 of 3 (near line 11 before the edit). Find:

```dart
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/saved_place_providers.dart';
```

Replace with:

```dart
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/saved_place_providers.dart';
```

Edit 2 of 3 (near line 463 before the edit). Find:

```dart
    handle.dispose();
  });

  testWidgets("the stop line opens your stop's Board, at full height (spec 2026-10-14 §3.2)", (tester) async {
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    await tester.tap(find.byKey(HomeStopLine.lineKey));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.fullFraction * homeSheetArea(tester), 1));
  });

  testWidgets('pulled up, Your stop opens its sheet', (tester) async {
```

Replace with:

```dart
    handle.dispose();
  });

  testWidgets('the stop line opens your stop on the Board tab (spec 2026-10-15 §2.3)', (tester) async {
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    final c = _c(tester);
    await tester.tap(find.byKey(HomeStopLine.lineKey));
    await tester.pumpAndSettle();
    expect(c.read(homeTabProvider), HomeTab.board);
    expect(c.read(boardStopProvider), const BoardStop('C'));
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>(), reason: 'the map is left as it was');
  });

  testWidgets('pulled up, Your stop opens its sheet', (tester) async {
```

Edit 3 of 3 (near line 580 before the edit). Find:

```dart
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.peekFraction * area, 1));

      // A notification for the stop opens its Board link.
      GoRouter.of(routerElement(tester)).go('/board/C');
      await tester.pumpAndSettle();
      expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
      expect(_c(tester).read(homeSheetProvider.notifier).stack, hasLength(2), reason: 'still one card over home');
```

Replace with:

```dart
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.peekFraction * area, 1));

      // A link to the stop opens it again.
      GoRouter.of(routerElement(tester)).go('/stop/C');
      await tester.pumpAndSettle();
      expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
      expect(_c(tester).read(homeSheetProvider.notifier).stack, hasLength(2), reason: 'still one card over home');
```


In `test/ui/reduce_motion_test.dart` (the stop line is a tab switch now; the card is opened directly):

Edit 1 of 2 (near line 8 before the edit). Find:

```dart
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_stop_line.dart';
import 'package:busboard_nl/ui/home/options_sheet.dart';
import 'package:busboard_nl/ui/home/stop_sheet.dart';
```

Replace with:

```dart
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_shell.dart';
import 'package:busboard_nl/ui/home/home_stop_line.dart';
import 'package:busboard_nl/ui/home/options_sheet.dart';
import 'package:busboard_nl/ui/home/stop_sheet.dart';
```

Edit 2 of 2 (near line 69 before the edit). Find:

```dart
    );
    await settlesWithin100ms(tester, 'home at rest');

    // A stop's Board, from the bar's stop line.
    await tester.tap(find.byKey(HomeStopLine.lineKey));
    await settlesWithin100ms(tester, 'opening the stop sheet');
    expect(find.byType(BBLiveDot), findsWidgets, reason: 'the live dot is there, but still');
    await tester.tap(find.byKey(StopSheetContent.refreshKey));
    await settlesWithin100ms(tester, 'refreshing the stop');
    await tester.tap(find.byKey(StopSheetContent.closeKey));
    await settlesWithin100ms(tester, 'closing the stop sheet');

    // Options.
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    c.read(planQueryProvider.notifier).setTrip(
          StopPlace(stopId: 'A', name: 'Stop A'),
          StopPlace(stopId: 'C', name: 'Stop C'),
```

Replace with:

```dart
    );
    await settlesWithin100ms(tester, 'home at rest');

    // The bar's stop line switches to the Board tab, on your stop (spec 2026-10-15 §2.1: instant).
    await tester.tap(find.byKey(HomeStopLine.lineKey));
    await settlesWithin100ms(tester, 'switching to the Board');
    expect(find.byType(BBLiveDot), findsWidgets, reason: 'the live dot is there, but still');
    await tester.tap(find.byKey(StopSheetContent.refreshKey));
    await settlesWithin100ms(tester, 'refreshing the stop');
    await tester.tap(find.byKey(HomeShell.mapTabKey));
    await settlesWithin100ms(tester, 'back to the map');

    // A stop's card.
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    c.read(homeSheetProvider.notifier).open(const StopSheet('A'));
    await settlesWithin100ms(tester, 'opening the stop sheet');
    await tester.tap(find.byKey(StopSheetContent.closeKey));
    await settlesWithin100ms(tester, 'closing the stop sheet');

    // Options.
    c.read(planQueryProvider.notifier).setTrip(
          StopPlace(stopId: 'A', name: 'Stop A'),
          StopPlace(stopId: 'C', name: 'Stop C'),
```


In `test/routing/home_routes_test.dart`:

Edit 1 of 5 (near line 6 before the edit). Find:

```dart
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/map_buttons.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
```

Replace with:

```dart
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_shell.dart';
import 'package:busboard_nl/ui/home/map_buttons.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
```

Edit 2 of 5 (near line 67 before the edit). Find:

```dart
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
  });

  for (final path in ['/board/1150', '/stop/1150']) {
    testWidgets('$path opens home with that stop\'s sheet', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: path);
      expect(_c(tester).read(homeSheetProvider), const StopSheet('1150'));
    });
  }

  testWidgets('a board link opens the stop sheet at half, with its next buses in view (F1, spec §3.2)', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/board/C', overrides: [_rows]);
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    _expectInView(tester, find.byType(ArrivalRowTile).first, 'the next bus');
  });
```

Replace with:

```dart
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
  });

  testWidgets("/stop/1150 opens home on the Map tab with that stop's sheet", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/stop/1150', tab: HomeTab.board);
    expect(_c(tester).read(homeSheetProvider), const StopSheet('1150'));
    expect(_c(tester).read(homeTabProvider), HomeTab.map);
  });

  testWidgets('/board/1150 opens home on the Board tab, showing that stop (spec 2026-10-15 §2.3)', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/board/1150');
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    expect(c.read(homeTabProvider), HomeTab.board);
    expect(c.read(boardStopProvider), const BoardStop('1150'));
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
  });

  testWidgets('a stop link opens the stop sheet at half, with its next buses in view (F1, spec §3.2)', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/stop/C', overrides: [_rows]);
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    _expectInView(tester, find.byType(ArrivalRowTile).first, 'the next bus');
  });
```

Edit 3 of 5 (near line 119 before the edit). Find:

```dart
  });

  testWidgets('system back walks the sheet stack, then leaves (Review Focus 2)', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/board/1150');
    expect(_c(tester).read(homeSheetProvider), const StopSheet('1150'));
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
```

Replace with:

```dart
  });

  testWidgets('system back walks the sheet stack, then leaves (Review Focus 2)', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/stop/1150');
    expect(_c(tester).read(homeSheetProvider), const StopSheet('1150'));
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
```

Edit 4 of 5 (near line 176 before the edit). Find:

```dart
    expect(tester.takeException(), isNull);
  });

  testWidgets('a board link before the schedule loads shows the stop sheet loading, then its rows (Review Focus 1)',
      (tester) async {
    // 'C' is a stop of TestNetwork; 1150 is not, and an unknown stop shows no card.
    final net = TestNetwork();
```

Replace with:

```dart
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stop link before the schedule loads shows the stop sheet loading, then its rows (Review Focus 1)',
      (tester) async {
    // 'C' is a stop of TestNetwork; 1150 is not, and an unknown stop shows no card.
    final net = TestNetwork();
```

Edit 5 of 5 (near line 185 before the edit). Find:

```dart
      tester,
      net: net,
      now: now,
      initial: '/board/C',
      repoFuture: schedule.future,
      settle: false,
      overrides: [_rows],
```

Replace with:

```dart
      tester,
      net: net,
      now: now,
      initial: '/stop/C',
      repoFuture: schedule.future,
      settle: false,
      overrides: [_rows],
```


Every other test link that meant "open the stop's card" becomes a stop link.

In `test/routing/swipe_back_test.dart`:

Edit 1 of 1 (near line 46 before the edit). Find:

```dart
  }

  testWidgets('Android: system back closes a pushed page, then walks the sheet stack as before', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/board/C');
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    GoRouter.of(routerElement(tester)).push('/settings');
    await tester.pumpAndSettle();
```

Replace with:

```dart
  }

  testWidgets('Android: system back closes a pushed page, then walks the sheet stack as before', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/stop/C');
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    GoRouter.of(routerElement(tester)).push('/settings');
    await tester.pumpAndSettle();
```


In `test/ui/stop_sheet_test.dart`:

Edit 1 of 3 (near line 167 before the edit). Find:

```dart
  Future<void> stop() async {}
}

/// The real app at [initial] (a stop's Board link), with the stop's sheet pulled to full.
Future<void> _pump(
  WidgetTester tester, {
  GtfsRepository? repo,
```

Replace with:

```dart
  Future<void> stop() async {}
}

/// The real app at [initial] (a stop's link), with the stop's sheet pulled to full.
Future<void> _pump(
  WidgetTester tester, {
  GtfsRepository? repo,
```

Edit 2 of 3 (near line 176 before the edit). Find:

```dart
  double textScale = 1.0,
  bool settle = true,
  bool pullUp = true,
  String initial = '/board/1150',
  List<Override> overrides = const [],
  AlertRunner? alertRunner,
  bool use24h = true,
```

Replace with:

```dart
  double textScale = 1.0,
  bool settle = true,
  bool pullUp = true,
  String initial = '/stop/1150',
  List<Override> overrides = const [],
  AlertRunner? alertRunner,
  bool use24h = true,
```

Edit 3 of 3 (near line 309 before the edit). Find:

```dart
  });

  testWidgets('an unknown stop still gets a sheet: "Stop 9999" and the empty state', (tester) async {
    await _pump(tester, repo: _repo(), initial: '/board/9999');
    expect(_c(tester).read(homeSheetProvider), const StopSheet('9999'));
    expect(find.text('STOP 9999'), findsOneWidget);
    expect(find.text('Stop 9999'), findsOneWidget);
```

Replace with:

```dart
  });

  testWidgets('an unknown stop still gets a sheet: "Stop 9999" and the empty state', (tester) async {
    await _pump(tester, repo: _repo(), initial: '/stop/9999');
    expect(_c(tester).read(homeSheetProvider), const StopSheet('9999'));
    expect(find.text('STOP 9999'), findsOneWidget);
    expect(find.text('Stop 9999'), findsOneWidget);
```


In `test/ui/search_screen_test.dart`:

Edit 1 of 1 (near line 378 before the edit). Find:

```dart
  });

  testWidgets('the stop sheet\'s Plan a trip from here starts the search from that stop', (tester) async {
    await pumpPlannerApp(tester, net: _network(), now: _now, initial: '/board/C');
    // The sheet's header holds the button; bring the sheet up so it is on screen.
    await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
    await tester.pumpAndSettle();
```

Replace with:

```dart
  });

  testWidgets('the stop sheet\'s Plan a trip from here starts the search from that stop', (tester) async {
    await pumpPlannerApp(tester, net: _network(), now: _now, initial: '/stop/C');
    // The sheet's header holds the button; bring the sheet up so it is on screen.
    await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
    await tester.pumpAndSettle();
```


In `test/ui/screen_overflow_test.dart`:

Edit 1 of 1 (near line 416 before the edit). Find:

```dart
          tester,
          net: TestNetwork(),
          now: DateTime(2026, 10, 12, 13, 0),
          initial: '/board/1150',
          textScale: 2.0,
          use24h: false,
          theme: dark ? BBTheme.dark() : BBTheme.light(),
```

Replace with:

```dart
          tester,
          net: TestNetwork(),
          now: DateTime(2026, 10, 12, 13, 0),
          initial: '/stop/1150',
          textScale: 2.0,
          use24h: false,
          theme: dark ? BBTheme.dark() : BBTheme.light(),
```


In `test/ui/screen_golden_test.dart` (the golden itself is regenerated in Task 9):

Edit 1 of 1 (near line 148 before the edit). Find:

```dart
    });

    testWidgets('stop sheet at full ${b.name}', (tester) async {
      await _pumpApp(tester, b, initial: '/board/1150');
      await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
```

Replace with:

```dart
    });

    testWidgets('stop sheet at full ${b.name}', (tester) async {
      await _pumpApp(tester, b, initial: '/stop/1150');
      await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
```


- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/ui/tab_switching_test.dart test/ui/board_button_test.dart test/routing test/ui/home_sheet_test.dart test/ui/home_screen_test.dart test/ui/reduce_motion_test.dart test/state/home_sheet_provider_test.dart`
Expected: `All tests passed!`

- [ ] **Step 8: Analyze and run the non-golden suite**

Run: `flutter analyze` → `No issues found!` (a leftover `sheetAtFullProvider`, `openBoard` or `showMapKey` anywhere is an error here: grep for them).
Run: `flutter test $(find test -name '*_test.dart' ! -name '*golden_test.dart' | sort)` → `All tests passed!`

- [ ] **Step 9: Commit**

```bash
git add lib/routing/router.dart lib/ui/home/home_shell.dart lib/ui/home/stop_sheet.dart lib/ui/home/home_sheet.dart \
  lib/ui/home/home_stop_line.dart lib/ui/search/search_screen.dart lib/state/home_sheet_provider.dart \
  lib/ui/home/home_screen.dart test/ui/tab_switching_test.dart test/ui/board_button_test.dart \
  test/state/home_sheet_provider_test.dart test/ui/home_screen_test.dart test/ui/home_sheet_test.dart \
  test/ui/reduce_motion_test.dart test/routing/home_routes_test.dart test/routing/swipe_back_test.dart \
  test/ui/stop_sheet_test.dart test/ui/search_screen_test.dart test/ui/screen_overflow_test.dart \
  test/ui/screen_golden_test.dart
git status --short
git commit -m "feat(home): switch tabs for the rider; Open board is the Board tab

The stop line, Open board, notifications and /board/ links show the stop
on the Board; a follow, trip options and choosing on the map switch to
the Map. /stop/ links open the card on the Map. The card's Show map
toggle and the sheet-at-full state behind it are gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


---

### Task 7: Back across the tabs, and the Map tab on the tab bar

**Files:**
- Modify: `lib/ui/home/home_screen.dart` (`PopScope` lets back through while the Map is hidden)
- Test: `test/ui/tab_back_test.dart`

**Interfaces:**
- Consumes: `HomeScreen.active` (Task 5), `HomeShell` keys (Task 5), `BBTabBar.height` (Task 2).
- Produces: spec §2.4. On the Board, back leaves the app at its top level (pushed pages pop first). On the Map, back steps down card → pulled-up sheet → follow, then leaves. Back never switches tabs.

- [ ] **Step 1: Write the failing test**

Create `test/ui/tab_back_test.dart`:

```dart
import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/home/home_shell.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

/// Android back across the two tabs (spec 2026-10-15 §2.4), and the Map tab's sheet sitting on the tab bar (§4).
final _now = DateTime(2026, 10, 12, 13, 0);

class _StopC extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(selectedStopId: 'C');
}

final _overrides = [
  settingsProvider.overrideWith(_StopC.new),
  stopArrivalsProvider.overrideWith((ref, id) async => [
        ArrivalRow(
          routeShortName: '1',
          headsign: 'Downtown',
          scheduledTime: GtfsTime.parse('13:05:00'),
          minutesAway: 4,
          isLive: true,
          vehicleNumber: '2573',
          tripId: '1-4',
        ),
      ]),
];

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeShell)));

/// System back, as Android sends it. True when the app handled it; false lets the system leave the app.
Future<bool> _back(WidgetTester tester) async {
  final handled = await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  return handled;
}

Rect _rect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

void main() {
  testWidgets('on the Board, back leaves the app, even with a card open on the map behind it', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map, overrides: _overrides);
    _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeShell.boardTabKey));
    await tester.pumpAndSettle();
    expect(await _back(tester), isFalse, reason: 'the system leaves the app');
    expect(_c(tester).read(homeTabProvider), HomeTab.board, reason: 'back never switches tabs');
    expect(_c(tester).read(homeSheetProvider), const StopSheet('B'), reason: "the map's card is left alone");
  });

  testWidgets('on the Map, back steps down one level, then leaves; it never switches to the Board', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map, overrides: _overrides);
    _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('B'));
    await tester.pumpAndSettle();
    expect(await _back(tester), isTrue);
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
    await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(await _back(tester), isTrue, reason: 'the pulled-up sheet comes down to its bar');
    expect(await _back(tester), isFalse);
    expect(_c(tester).read(homeTabProvider), HomeTab.map);
  });

  testWidgets('a follow started on the Board: back on the Map stops it, then leaves', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.board, overrides: _overrides);
    await tester.tap(find.byType(ArrivalRowTile).first);
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeTabProvider), HomeTab.map);
    expect(await _back(tester), isTrue);
    expect(_c(tester).read(followProvider), isNull);
    expect(await _back(tester), isFalse);
    expect(_c(tester).read(homeTabProvider), HomeTab.map, reason: 'not back to the Board');
  });

  testWidgets('over the Board, a pushed page pops first, then back leaves', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.board, overrides: _overrides);
    unawaited(GoRouter.of(routerElement(tester)).push('/settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(await _back(tester), isTrue);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(_c(tester).read(homeTabProvider), HomeTab.board);
    expect(await _back(tester), isFalse);
  });

  group('the Map tab sits on the tab bar (spec 2026-10-15 §4)', () {
    testWidgets('the bar rests on the tab bar, and pulled to full it stays above it', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPadding);
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map, overrides: _overrides);
      final tabBar = tester.getRect(find.byType(BBTabBar));
      expect(tabBar.height, BBTabBar.height + 34, reason: 'the tab bar takes the home indicator');
      expect(_rect(tester, BBSheet.cardKey).bottom, closeTo(tabBar.top - BBSpace.s, 1),
          reason: 'the bar rests just above the tab bar');
      await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -800));
      await tester.pumpAndSettle();
      final card = _rect(tester, BBSheet.cardKey);
      expect(card.bottom, closeTo(tabBar.top - BBSpace.s, 1));
      expect(card.top, greaterThanOrEqualTo(47), reason: 'full height stays under the status bar');
    });

    testWidgets('a pan tucks a card down to its peek, still above the tab bar', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map, overrides: _overrides);
      _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('B'));
      await tester.pumpAndSettle();
      final half = _rect(tester, BBSheet.cardKey).top;
      await tester.dragFrom(const Offset(60, 200), const Offset(0, 40));
      await tester.pumpAndSettle();
      final card = _rect(tester, BBSheet.cardKey);
      expect(card.top, greaterThan(half + 100), reason: 'tucked down');
      expect(card.bottom, closeTo(tester.getRect(find.byType(BBTabBar)).top - BBSpace.s, 1));
      expect(_c(tester).read(homeSheetProvider), const StopSheet('B'));
    });

    testWidgets('following and panned: Back to bus sits above the follow card, clear of the tab bar', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map, overrides: _overrides);
      _c(tester).read(followProvider.notifier).follow('2573');
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(60, 300), const Offset(0, 60));
      await tester.pumpAndSettle();
      final back = tester.getRect(find.text('Back to bus 2573'));
      expect(back.bottom, lessThanOrEqualTo(_rect(tester, BBSheet.cardKey).top), reason: 'above the follow card');
      expect(back.bottom, lessThan(tester.getRect(find.byType(BBTabBar)).top));
      expect(tester.getRect(find.text('Following bus 2573')).top, greaterThanOrEqualTo(0));
    });
  });
}
```


- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/ui/tab_back_test.dart`
Expected: one failure, "on the Board, back leaves the app, even with a card open on the map behind it": `Expected: false, Actual: <true>` (the hidden map's `PopScope` still takes back to close its card). The other six pass already: they pin the Map tab's back steps and its positions on the tab bar.

- [ ] **Step 3: Let back through while the Map is hidden**

In `lib/ui/home/home_screen.dart`:

Edit 1 of 2 (near line 87 before the edit). Find:

```dart
  const HomeScreen({super.key, this.active = true});

  /// The Map tab is the one showing (spec 2026-10-15 §2). The home shell keeps this screen mounted behind the Board,
  /// where it plays no one-time hint. Always true where the screen stands alone.
  final bool active;

  @override
```

Replace with:

```dart
  const HomeScreen({super.key, this.active = true});

  /// The Map tab is the one showing (spec 2026-10-15 §2). The home shell keeps this screen mounted behind the Board,
  /// where it plays no one-time hint and leaves system back alone. Always true where the screen stands alone.
  final bool active;

  @override
```

Edit 2 of 2 (near line 1231 before the edit). Find:

```dart
      );

      return PopScope(
        canPop: _backLeavesApp(sheet, pick),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBack();
        },
```

Replace with:

```dart
      );

      return PopScope(
        // Behind the Board, back is the Board's: at its top level the app leaves, and back never switches tabs
        // (spec 2026-10-15 §2.4).
        canPop: !widget.active || _backLeavesApp(sheet, pick),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBack();
        },
```


- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/tab_back_test.dart`
Expected: `All tests passed!` (7 tests).

- [ ] **Step 5: Analyze and run the non-golden suite**

Run: `flutter analyze` → `No issues found!`
Run: `flutter test $(find test -name '*_test.dart' ! -name '*golden_test.dart' | sort)` → `All tests passed!` (`home_screen_test.dart`'s "Android back steps down one level at a time" group still passes: a standalone `HomeScreen` is always active).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/home/home_screen.dart test/ui/tab_back_test.dart
git status --short
git commit -m "fix(home): on the Board, back leaves the app; back never switches tabs

The hidden map's PopScope lets back through, so a card left open on the
map no longer swallows it. The Map tab still steps down one level at a
time. Tests pin its sheet, tuck-away and Back to bus above the tab bar.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


---

### Task 8: Tablet layout

**Files:**
- Modify: `lib/ui/kit/bb_tab_bar.dart` (`maxRowWidth`: the tabs keep to a centred row)
- Test: `test/kit/tab_bar_test.dart`, `test/ui/home_tablet_test.dart`

**Interfaces:**
- Consumes: `BoardTab.maxWidth` (Task 4), `HomeShell` keys (Task 5).
- Produces: `BBTabBar.maxRowWidth = 480`. On a tablet: the bar spans the screen, its tabs centred under the Board's 640 pt column; the Map's side panel ends `BBSpace.s` above the tab bar.

- [ ] **Step 1: Write the failing tests**

In `test/kit/tab_bar_test.dart`:

Edit 1 of 1 (near line 128 before the edit). Find:

```dart
      expect(tester.getSize(find.byType(BBTabBar)).height, greaterThan(BBTabBar.height));
    });
  }
}
```

Replace with:

```dart
      expect(tester.getSize(find.byType(BBTabBar)).height, greaterThan(BBTabBar.height));
    });
  }

  testWidgets('on a wide screen the bar spans it, and its tabs keep to a centred row', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(0, (_) {}, width: 1024));
    expect(tester.getSize(find.byType(BBTabBar)).width, 1024);
    final board = tester.getRect(find.byKey(const ValueKey('t-board')));
    final map = tester.getRect(find.byKey(const ValueKey('t-map')));
    expect(map.right - board.left, BBTabBar.maxRowWidth);
    expect((board.left + map.right) / 2, 512, reason: 'centred');
  });
}
```


In `test/ui/home_tablet_test.dart`:

Edit 1 of 2 (near line 1 before the edit). Find:

```dart
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

Replace with:

```dart
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/ui/board/board_tab.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/home/home_shell.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

Edit 2 of 2 (near line 169 before the edit). Find:

```dart
    expect(panel.left, 40 + BBSpace.s);
    expect(tester.getRect(find.text('All routes')).left, greaterThan(panel.right));
  });
}
```

Replace with:

```dart
    expect(panel.left, 40 + BBSpace.s);
    expect(tester.getRect(find.text('All routes')).left, greaterThan(panel.right));
  });

  group('the two tabs on a tablet (spec 2026-10-15 §3)', () {
    testWidgets('the Map keeps its side panel, which ends above the tab bar', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 20);
      addTearDown(tester.view.reset);
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/');
      final panel = tester.getRect(find.byKey(const ValueKey('home-side-panel')));
      final tabBar = tester.getRect(find.byType(BBTabBar));
      expect(tabBar.width, 1024, reason: 'the tab bar spans the screen');
      expect(tabBar.bottom, 768);
      expect(panel.bottom, closeTo(tabBar.top - BBSpace.s, 1), reason: 'the panel sits on the tab bar');
    });

    testWidgets('the Board is a centred column at most 640 pt wide, and the tabs are under it', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/', tab: HomeTab.board);
      final board = tester.getRect(find.descendant(of: find.byType(BoardTab), matching: find.byType(BBScrollPage)));
      expect(board.width, BoardTab.maxWidth);
      expect(board.center.dx, 512);
      final where = tester.getRect(find.byKey(BoardTab.whereToKey));
      expect(where.left, greaterThanOrEqualTo(board.left));
      expect(where.right, lessThanOrEqualTo(board.right));
      final tabs = tester.getRect(find.byKey(HomeShell.boardTabKey)).expandToInclude(
          tester.getRect(find.byKey(HomeShell.mapTabKey)));
      expect(tabs.center.dx, 512);
      expect(tabs.width, lessThanOrEqualTo(board.width));
    });

    testWidgets("the panel's Open board shows the stop on the Board, and the panel keeps its card", (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/stop/B');
      await tester.tap(find.bySemanticsLabel('Open board, Stop B'));
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
      expect(c.read(homeTabProvider), HomeTab.board);
      expect(find.text('STOP B'), findsOneWidget);
      await tester.tap(find.byKey(HomeShell.mapTabKey));
      await tester.pumpAndSettle();
      expect(c.read(homeSheetProvider), const StopSheet('B'));
      expect(find.byKey(const ValueKey('home-side-panel')), findsOneWidget);
    });
  });
}
```


- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/kit/tab_bar_test.dart test/ui/home_tablet_test.dart`
Expected: FAIL to compile: `maxRowWidth` isn't defined for `BBTabBar`. (Without the centred row, the two new layout tests would fail on the tabs' span: 1024 instead of 480.)

- [ ] **Step 3: Keep the tabs to a centred row**

Replace the whole of `lib/ui/kit/bb_tab_bar.dart` with:

```dart
import 'dart:ui' show SemanticsRole;

import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

/// One tab of a [BBTabBar]: its [label], its [icon], and the [activeIcon] it shows while selected.
@immutable
class BBTab {
  const BBTab({required this.label, required this.icon, required this.activeIcon, this.key});

  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// The tab's own key, for tests.
  final Key? key;
}

/// The bottom tab bar (spec 2026-10-15 §2.1): at least [height] pt tall plus the bottom safe area, on `surface` with a
/// `line` hairline on top. Inactive tabs are `muted`; the active one is `brandInk`, its filled icon on a `brandSoft`
/// pill, so the selection never rests on colour alone. Each tab is a button with a selected state that screen readers
/// read as "Board, tab 1 of 2, selected". The pill cross-fades over [BBMotion.standard], at once under Reduce Motion.
/// Labels grow with the text size, and the bar grows with them. On a wide screen the bar still spans it, but its tabs
/// keep to a centred row [maxRowWidth] wide, so the two never sit half a tablet apart.
class BBTabBar extends StatelessWidget {
  const BBTabBar({super.key, required this.tabs, required this.index, required this.onSelect});

  final List<BBTab> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  /// The bar's height above the bottom safe area, at 1x text.
  static const double height = 56;

  /// The widest the row of tabs gets (a tablet, a phone on its side).
  static const double maxRowWidth = 480;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bb.colors.surface,
        border: Border(top: BorderSide(color: bb.colors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Semantics(
          role: SemanticsRole.tabBar,
          container: true,
          explicitChildNodes: true,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: height, maxWidth: maxRowWidth),
              // Both tabs as tall as the taller one, and the whole height theirs to tap.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, tab) in tabs.indexed)
                      Expanded(
                        child: _TabButton(
                          key: tab.key,
                          tab: tab,
                          active: i == index,
                          semanticLabel: '${tab.label}, tab ${i + 1} of ${tabs.length}',
                          onTap: () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.tab,
    required this.active,
    required this.semanticLabel,
    required this.onTap,
  });

  final BBTab tab;
  final bool active;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final fg = active ? bb.colors.brandInk : bb.colors.muted;
    return Semantics(
      role: SemanticsRole.tab,
      button: true,
      selected: active,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: BBPressable(
        exposeSemantics: false,
        haptic: true,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: BBSpace.xs),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: BBMotion.of(context, BBMotion.standard),
                curve: BBMotion.curve,
                width: 56,
                height: 28,
                decoration: BoxDecoration(
                  color: active ? bb.colors.brandSoft : bb.colors.brandSoft.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(active ? tab.activeIcon : tab.icon, size: 22, color: fg),
              ),
              const SizedBox(height: 2),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bb.text.label.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/kit/tab_bar_test.dart test/ui/home_tablet_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Analyze and run the non-golden suite**

Run: `flutter analyze` → `No issues found!`
Run: `flutter test $(find test -name '*_test.dart' ! -name '*golden_test.dart' | sort)` → `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/ui/kit/bb_tab_bar.dart test/kit/tab_bar_test.dart test/ui/home_tablet_test.dart
git status --short
git commit -m "feat(home): the two tabs on a tablet

The tab bar spans the screen with its tabs in a centred 480 pt row under
the Board's 640 pt column; the Map keeps its side panel, which ends just
above the tab bar.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


---

### Task 9: Goldens, the 2× pass, stale words, and the device checks

**Files:**
- Modify: `test/ui/screen_golden_test.dart` (`board_tab_light`/`dark`; `_pumpApp(tab:)`)
- Create (generated): `test/ui/goldens/board_tab_light.png`, `test/ui/goldens/board_tab_dark.png`
- Modify (regenerated): `test/ui/goldens/home_bar_*.png`, `home_half_dark.png`, `options_*.png`, `stop_sheet_*.png` (the tab bar is in them now). `test/kit/goldens/` does not change.
- Modify: `test/ui/screen_overflow_test.dart` (the Board at 2×)
- Modify: `lib/state/home_sheet_provider.dart`, `lib/ui/home/home_stop_line.dart` (two stale comments)

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces: reviewed goldens; a 2× pass of the Board and the tab bar on 320 pt and 360 pt phones; the controller's device report.

- [ ] **Step 1: Add the Board goldens**

In `test/ui/screen_golden_test.dart`:

Edit 1 of 4 (near line 9 before the edit). Find:

```dart
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart' show PlanMode;
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/saved_place_providers.dart';
```

Replace with:

```dart
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart' show PlanMode;
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/saved_place_providers.dart';
```

Edit 2 of 4 (near line 99 before the edit). Find:

```dart
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

/// The real app at [initial] on a 390x844 phone at 3x: stop 1150 is the rider's stop, one saved place, one alert
/// that applies to routes 29 and 23 and to the stop, and four fixed departures (so the picture does not move).
Future<void> _pumpApp(WidgetTester tester, Brightness b, {String initial = '/'}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
```

Replace with:

```dart
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

/// The real app at [initial] on a 390x844 phone at 3x, on [tab]: stop 1150 is the rider's stop, one saved place, one
/// alert that applies to routes 29 and 23 and to the stop, and four fixed departures (so the picture does not move).
Future<void> _pumpApp(WidgetTester tester, Brightness b, {String initial = '/', HomeTab tab = HomeTab.map}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
```

Edit 3 of 4 (near line 110 before the edit). Find:

```dart
    net: _munToAvalon(),
    now: DateTime(testDay.year, testDay.month, testDay.day, 8, 1),
    initial: initial,
    mapView: StubMap(color: _land(b)).build,
    theme: b == Brightness.dark ? BBTheme.dark() : BBTheme.light(),
    alerts: [
```

Replace with:

```dart
    net: _munToAvalon(),
    now: DateTime(testDay.year, testDay.month, testDay.day, 8, 1),
    initial: initial,
    tab: tab,
    mapView: StubMap(color: _land(b)).build,
    theme: b == Brightness.dark ? BBTheme.dark() : BBTheme.light(),
    alerts: [
```

Edit 4 of 4 (near line 147 before the edit). Find:

```dart
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/home_bar_${b.name}.png'));
    });

    testWidgets('stop sheet at full ${b.name}', (tester) async {
      await _pumpApp(tester, b, initial: '/stop/1150');
      await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
```

Replace with:

```dart
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/home_bar_${b.name}.png'));
    });

    // The Board tab (spec 2026-10-15 §3): your stop's chip selected, the saved place's chip, Near me and ＋; the
    // stop's alert first, then its departures.
    testWidgets('board tab ${b.name}', (tester) async {
      await _pumpApp(tester, b, tab: HomeTab.board);
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/board_tab_${b.name}.png'));
    });

    testWidgets('stop sheet at full ${b.name}', (tester) async {
      await _pumpApp(tester, b, initial: '/stop/1150');
      await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
```


- [ ] **Step 2: Add the Board to the 2× pass**

In `test/ui/screen_overflow_test.dart`:

Edit 1 of 4 (near line 13 before the edit). Find:

```dart
import 'package:busboard_nl/domain/map/follow_tracker.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
```

Replace with:

```dart
import 'package:busboard_nl/domain/map/follow_tracker.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
```

Edit 2 of 4 (near line 23 before the edit). Find:

```dart
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/home/home_stop_line.dart';
```

Replace with:

```dart
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/board/board_tab.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/home/home_stop_line.dart';
```

Edit 3 of 4 (near line 235 before the edit). Find:

```dart
  Map<String, DateTime> build() => {'1150': DateTime(2026, 10, 12, 21, 52, 4)};
}

class _StopCSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(selectedStopId: 'C');
```

Replace with:

```dart
  Map<String, DateTime> build() => {'1150': DateTime(2026, 10, 12, 21, 52, 4)};
}

class _Stop1150Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(selectedStopId: '1150');
}

class _StopCSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(selectedStopId: 'C');
```

Edit 4 of 4 (near line 668 before the edit). Find:

```dart
      expect(tester.takeException(), isNull, reason: 'scrolled to the button');
    });
  }
}
```

Replace with:

```dart
      expect(tester.takeException(), isNull, reason: 'scrolled to the button');
    });
  }

  // The Board tab at 2x text (spec 2026-10-15 §6): the long stop name, its chip and a long saved place's, an alert,
  // live rows with Follow and bells, and the tab bar, scrolled to the end; then its Choose your stop.
  for (final size in _sizes) {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('the Board tab at ${size.width.toInt()}x${size.height.toInt()}, 2.0x text, $theme', (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await pumpPlannerApp(
          tester,
          net: TestNetwork(),
          now: DateTime(2026, 10, 12, 13, 0),
          tab: HomeTab.board,
          textScale: 2.0,
          use24h: false,
          theme: dark ? BBTheme.dark() : BBTheme.light(),
          repoFuture: Future.value(_repo()),
          alerts: [_alert('Water Street detour', description: 'Routes 10 and 10A use Harbour Drive.')],
          overrides: [
            settingsProvider.overrideWith(_Stop1150Settings.new),
            savedPlacesProvider.overrideWith(_Places.new),
            stopArrivalsProvider.overrideWith((ref, id) async => _arrivals),
            stopArrivalsUpdatedAtProvider.overrideWith(_UpdatedAt.new),
            metrobusMobileApiProvider.overrideWithValue(MetrobusMobileApi(client: _emptyKiosk)),
          ],
        );
        expect(tester.takeException(), isNull, reason: 'the Board at rest');
        for (final label in ['Board', 'Map']) {
          final p = tester.renderObject<RenderParagraph>(
              find.descendant(of: find.byType(BBTabBar), matching: find.text(label)));
          expect(p.didExceedMaxLines, isFalse, reason: 'the $label tab reads in full');
        }
        final chips = find.byKey(BoardTab.chipsKey);
        await tester.drag(chips, const Offset(-600, 0));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the chips scrolled to their end');
        expect(find.byKey(BoardTab.findStopKey).hitTestable(), findsOneWidget, reason: '＋ is reachable');
        final board = find.descendant(of: find.byType(BoardTab), matching: find.byType(CustomScrollView));
        for (var i = 0; i < 12; i++) {
          await tester.drag(board, const Offset(0, -400));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'scrolling the Board');
        }
        expect(find.text('Plan a trip from here').hitTestable(), findsOneWidget, reason: 'the end is reachable');
      });
    }
  }

  testWidgets("the Board's Choose your stop at 320x568, 2.0x text", (tester) async {
    tester.view.physicalSize = const Size(320, 568) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(
      tester,
      net: TestNetwork(),
      now: DateTime(2026, 10, 12, 13, 0),
      tab: HomeTab.board,
      textScale: 2.0,
      repoFuture: Future.value(_repo()),
      nearby: const [NearbyStop(stop: _stop, distanceMeters: 80), NearbyStop(stop: _stop2, distanceMeters: 640)],
    );
    expect(find.text('Choose your stop'), findsOneWidget);
    final board = find.descendant(of: find.byType(BoardTab), matching: find.byType(CustomScrollView));
    for (var i = 0; i < 8; i++) {
      await tester.drag(board, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'scrolling Choose your stop');
    }
  });
}
```


Run: `flutter test test/ui/screen_overflow_test.dart`
Expected: `All tests passed!` (the five new tests: the Board at 320x568 and 360x640, light and dark, scrolled to its end with its chips scrolled too; and Choose your stop at 320x568).

- [ ] **Step 3: Fix two stale comments**

In `lib/state/home_sheet_provider.dart`:

Edit 1 of 1 (near line 16 before the edit). Find:

```dart
  int get hashCode => (HomeSheetHome).hashCode;
}

/// A stop's sheet: its Board.
final class StopSheet extends HomeSheet {
  const StopSheet(this.stopId);
  final String stopId;
```

Replace with:

```dart
  int get hashCode => (HomeSheetHome).hashCode;
}

/// A stop's card on the map: its departures, with Open board for the Board tab.
final class StopSheet extends HomeSheet {
  const StopSheet(this.stopId);
  final String stopId;
```


In `lib/ui/home/home_stop_line.dart`:

Edit 1 of 1 (near line 147 before the edit). Find:

```dart
  }
}

/// The bar's second row (spec 2026-10-14 §3.1, §3.2): your stop and its next bus, one tap from its Board. With no
/// stop chosen it is "Choose your stop", which pulls the sheet up to the nearby stops ([onChooseStop]) or, with none
/// to show, opens a stop search.
class HomeStopLine extends ConsumerWidget {
```

Replace with:

```dart
  }
}

/// The bar's second row (spec 2026-10-14 §3.1, §3.2): your stop and its next bus, one tap from the Board tab. With no
/// stop chosen it is "Choose your stop", which pulls the sheet up to the nearby stops ([onChooseStop]) or, with none
/// to show, opens a stop search.
class HomeStopLine extends ConsumerWidget {
```


Then check nothing else still talks about the old toggle or restore: `grep -rn "Show map\|showMap\|openBoard\|sheetAtFull\|board_open\|BoardOpenStore\|launchLinkChecked" lib test`. Expected: only `HomeSheetContent.openBoardKey` / `StopSheetContent.openBoardKey` (the Open board buttons), `HomeTabStore.legacyBoardOpenKey`'s `board_open.v1`, and the Show map assertions in `test/ui/board_button_test.dart` that check it is gone.

- [ ] **Step 4: Regenerate the goldens**

Run: `flutter test --update-goldens test/ui/screen_golden_test.dart test/kit/kit_golden_test.dart`
Expected: `All tests passed!`; `git status --short test` shows two new `test/ui/goldens/board_tab_*.png` and modified `home_bar_dark`, `home_bar_light`, `home_half_dark`, `options_dark`, `options_light`, `stop_sheet_dark`, `stop_sheet_light`; nothing under `test/kit/goldens/`.

- [ ] **Step 5: Look at every changed golden**

Open each new or changed PNG in `test/ui/goldens/` with the Read tool. Check:
- **Board (`board_tab_light/dark`):** "Board" large at the top left, the alerts megaphone with a red "1" and the gear at the top right; Where to?; the chips "★ MUN Centre" (blue fill, white text: selected), "Home", "Near me" and the edge of "＋ Stop"; then "STOP 1150", "MUN Centre", "● Live"; the Water Street Detour card before the departures; four rows (29 with "Follow 2134", 23 with "Follow 1207" and a bell, 10, 16 "Now" in orange); "Plan a trip from here" in blue; the tab bar at the bottom with Board active (blue filled icon on a pale blue pill, blue label) and Map grey. Dark: neutral greys, the selected chip `#5EA2F0` with dark text, the active tab's pill `#16304A`.
- **Home bar (`home_bar_light/dark`):** the map with the route chip and the bell/gear pill; the slim bar (Where to? and "★ MUN Centre ⚠ · [29] 4 min ●") resting just above the tab bar; Map active, Board grey. The credit sits just above the bar.
- **Home at half, options, stop sheet:** as before, but every sheet ends above the tab bar, and the tab bar shows Map active.

If anything is off, fix the code (not the golden) and regenerate. Then run `flutter test` (the whole suite, goldens included). Expected: `All tests passed!`

- [ ] **Step 6: The 2× pass**

Run: `flutter test test/ui/screen_overflow_test.dart test/ui/board_tab_test.dart test/kit/tab_bar_test.dart test/ui/board_button_test.dart test/ui/home_stop_line_test.dart`
Expected: PASS. Together they cover the Board (header, chips, alert, live rows, Plan, Choose your stop) at 2× on 320x568 and 360x640 light and dark, the tab bar's labels at 2× on 320 pt, Open board at 2× on 320x640, and the stop line at 2× and 3×.

- [ ] **Step 7: Commit**

```bash
git add test/ui/screen_golden_test.dart test/ui/screen_overflow_test.dart test/ui/goldens \
  lib/state/home_sheet_provider.dart lib/ui/home/home_stop_line.dart
git status --short
git commit -m "test: Board goldens, the Board at 2x text, and goldens with the tab bar

board_tab_light/dark are new; the home, options and stop sheet goldens
now show the tab bar. Every golden was looked at by eye.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Device checks (the controller only)**

Subagents stop at Step 7 and report. The controller runs the developer's `.dev` build on the iOS simulator "BusBoard iPhone 17" (`0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54`) and on the Android phone `RFCRA1CK68W` (spec §6), screenshots each item, and reports pass or fail:

1. **First launch.** Uninstall first (`xcrun simctl uninstall 0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54 com.ahamsel.busboardNl`; on Android, clear the app's storage). The app opens on the Board; with no stop chosen it asks you to choose one, with the nearby stops (or a search with location off). Choose one: the Board shows it, its chip selected.
2. **Upgrade.** Install the 1.4.x build, open a stop's Board (sheet at full), background the app, install this build over it, cold start: the Board tab on that stop.
3. **Switching tabs.** Tap Map and Board: a short cross-fade, the map exactly where it was (zoom, camera, any card), the Board at the same scroll. With Reduce Motion on, the switch is instant. VoiceOver/TalkBack reads "Board, tab 1 of 2, selected".
4. **Follow from the Board.** Tap a live row's Follow pill: the Map tab, following the bus, the follow card at its peek above the tab bar; pan: "Back to bus" sits above the card, clear of the tab bar.
5. **Planning from the Board.** Where to? → a place → the trip options open on the Map tab. "Plan a trip from here" → a destination → options from that stop. Back out of a search instead: still the Board.
6. **The Map tab on the tab bar.** The slim bar rests on the tab bar; Show more / full height / a pan's tuck-away all stay above it; the map's (i) attribution button sits right after "© OpenStreetMap · OpenFreeMap" on iOS and Android.
7. **Back (Android).** On the Board: back leaves the app, even with a card open on the map. On the Map: card → pulled-up sheet → follow → leaves. Back never switches tabs. Over the Board, Settings and Alerts pop first.
8. **Notification deep link,** if one can be triggered (arm an arrival alert for a near bus): tapping it opens the Board on that stop, from either tab and from a cold start.

Report each item with its screenshot paths. The developer's own approval on their iPhone is theirs to give: say so in the final report.


---

## Spec coverage (self-review)

| Spec | Task |
|---|---|
| §2.1 tab bar on every phone screen of the home: 56 pt + safe area, surface + line hairline, muted / brandInk on brandSoft, `BBIcons.board` / `BBIcons.map`, "Board, tab 1 of 2, selected", cross-fade, instant under Reduce Motion | 2 (`tab_bar_test.dart`), 5 (`home_shell_test.dart`) |
| §2.2 opens on the tab used last (`home_tab.v1`), Board on first launch, `board_open.v1` upgrade then cleared | 1 (`home_tab_provider_test.dart`), 5 (shell tests with `tab: null`) |
| §2.3 to the Board: stop line, Open board (home sheet and map card), notification, `/board/:id`; each selects the stop | 6 (`tab_switching_test.dart`, `board_button_test.dart`, `home_routes_test.dart`, `home_sheet_test.dart`) |
| §2.3 to the Map: Follow, a destination from Where to?, Plan a trip from here | 6 (`tab_switching_test.dart`) |
| §2.3 Show map removed; Open board always; `sheetAtFullProvider` and its tests gone | 6 |
| §2.4 back: Map steps down; top level of either tab leaves; never switches tabs; pushed pages over the Board pop | 7 (`tab_back_test.dart`), existing `home_screen_test.dart` back group |
| §3 header (Board, bell with badge, gear), Where to?, chips (★, saved stops, ≤3 recents from `recent_stops.v1`, Near me, ＋), selected chip brand fill, chips are selectable buttons | 3 (`board_providers_test.dart`), 4 (`board_tab_test.dart`) |
| §3 the stop's board: header, alerts first, departures with Follow, toast, bells, rolling minutes, Now pulse, Plan a trip from here, pull to refresh, follow tip | 4 (the stop sheet's own widgets reused; `board_tab_test.dart`) |
| §3 empty and edge states: Choose your stop with nearby stops / search without location; Near me with location denied; loading, error, offline as the stop sheet | 4 |
| §3 tablet: centred column ≤ 640 pt; Map keeps its side panel | 4, 8 (`home_tablet_test.dart`) |
| §3 the Board reuses the stop sheet's body, not a copy | 4 (`StopSheetContent.info` / `.body` / `.planFrom`) |
| §4 Map tab unchanged except: stop line and Open board switch tabs; sheet positions and tuck-away above the tab bar; route chip, My location, follow and options Map-only | 5, 6, 7 (`tab_back_test.dart` position group) |
| §5 bell in the same top-right spot on both tabs; alerts in context on the Board and the Map | 4 (`AlertsButton`), existing stop line and home sheet alert tests |
| §6 testing list, goldens `board_tab_light`/`dark` and the rest regenerated, checked by eye | 1–8, 9 |
| §6 simulator and Android checks | 9, Step 8 (controller) |
| §7 out of scope: nothing here adds more "your stops", chip reordering, widgets or a Board-only setting | — |
