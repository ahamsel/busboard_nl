# Map-first home (P1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four-tab app with one map-first home screen: the map with a pull-up sheet holding "Where to?", saved places, alerts for you, your stop, saved trips and nearby stops; any stop's sheet acts as its Board; trip options and steps live in the same sheet; Alerts and Settings are floating buttons.

**Architecture:** One `HomeScreen` (today's `MapScreen`, moved and renamed) hosts the map and a single `BBSheet`. What the sheet shows is a back stack held in `homeSheetProvider` (home → stop / bus → options → journey), so the map never rebuilds when the sheet changes. Old routes redirect onto home and set the sheet state. The planner, Follow, the bell, saved trips and the arrival feeds are reused unchanged. Their screens become sheet bodies.

**Tech Stack:** Flutter (Dart 3.9), Riverpod 3.4.3 (`Notifier`/`AsyncNotifier`, no codegen), go_router, shared_preferences (`SharedPreferencesAsync`), maplibre_gl through the existing `mapViewBuilderProvider` seam, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-12-map-first-redesign-design.md`, sections 3–5 (P1). Read §1 (intent, constraints) and §3.6 (what moves where) before Task 1.

## Global Constraints

- Free app: no ads, no account, no server, no paid map or search service, no API keys. No new network calls.
- Nothing about the rider leaves the phone. Saved places and recent destinations live in shared preferences only.
- Every control has a screen-reader label (`semanticLabel` or `Semantics(label:)`). Nothing overflows at 2× text (`test/ui/screen_overflow_test.dart` style).
- Light and dark themes, 24-hour times (`BBTime.use24h(context)`), phones and tablets.
- Every feature the app has today is reachable within two taps of the home screen.
- Old links keep working: `/board/:stopId`, `/map`, `/plan`, `/plan/journey`, `/alerts`, `/settings`, and arrival-alert notification payloads (`ArrivalAlert.boardRoute` = `/board/<id>`).
- Opening the app always starts with the sheet at peek, showing "Where to?", the saved-place chips, alerts for you and your stop.
- Never stage `analysis_options.yaml`, `tool/capture_raw_gtfsrt.dart`, `test/fixtures/timetrack/`, `build/` or `store/marketing/`. Never use bare `git stash`.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Run `flutter analyze` and the task's tests before each commit. Run the full `flutter test` at the end of every task that deletes a screen (Tasks 5, 6, 7, 8, 11).

## Review Focus

1. **Cold start from a notification:** `/board/1150` arrives before the GTFS bundle has loaded. Home must open with stop 1150's sheet, showing a skeleton and then the arrivals, not an empty or blank sheet. (Task 4 test: "a board link before the schedule loads".)
2. **Android back button through the sheet stack:** journey → options → home, and from home the app is left. Back must never pop the home route itself while a sheet is open. (Task 2 provider test plus Task 4 widget test "system back walks the sheet stack".)
3. **Following a bus while the rider opens a stop, search or a saved trip:** the follow keeps running and its chip stays. The opened sheet shows, and back returns to the follow card. (Task 2 test "a follow sits under any sheet".)
4. **2× text at peek on a small phone (360×640):** "Where to?", the chips and the first line of your stop are visible without overflow. Further rows scroll. (Task 5 overflow test.)
5. **Corrupt or old saved data:** garbage in `saved_places.v1` or `recent_places.v1`, or an entry whose `Place` kind is unknown, is skipped. The app never throws. (Task 3 store tests.)

---

## File structure

**Create**
- `lib/state/home_sheet_provider.dart`: `HomeSheet` sealed states and the back-stack notifier.
- `lib/state/map_pick_provider.dart`: "the next map tap chooses the start / destination" (replaces `/map?pick=`).
- `lib/data/trip_planner/saved_place_store.dart`: `SavedPlace`, `SavedPlaceStore`, `RecentPlaceStore`.
- `lib/state/saved_place_providers.dart`: the `savedPlacesProvider` and `recentPlacesProvider` notifiers.
- `lib/state/alerts_for_you_provider.dart`: the active alerts touching your stop, its routes and your saved trips' routes.
- `lib/ui/home/home_screen.dart`: today's `map_screen.dart`, moved and renamed (Task 1).
- `lib/ui/home/sheet_content.dart`: maps a `HomeSheet` to the sheet's header and slivers.
- `lib/ui/home/map_buttons.dart`: floating Alerts (with badge) and Settings buttons.
- `lib/ui/home/home_sheet.dart`: the home sheet's header (Where to, chips, alerts, your stop) and body.
- `lib/ui/home/stop_sheet.dart`: a stop's sheet (today's Board content).
- `lib/ui/home/options_sheet.dart`: trip options (today's Plan form and results).
- `lib/ui/home/journey_sheet.dart`: a journey's steps (today's Journey detail).
- `lib/ui/home/home_tip.dart`: the one-time "Everything's on the map now" tip.
- `lib/ui/search/search_screen.dart`: the "Where to?" screen.
- `lib/domain/location/locate_me.dart`: one shared "find me" (moved out of `place_picker_sheet.dart`).
- Tests: `test/state/home_sheet_provider_test.dart`, `test/state/saved_place_store_test.dart`, `test/state/alerts_for_you_test.dart`, `test/routing/home_routes_test.dart`, `test/ui/home_sheet_test.dart`, `test/ui/stop_sheet_test.dart`, `test/ui/search_screen_test.dart`, `test/ui/options_sheet_test.dart`, `test/ui/home_tablet_test.dart`.

**Delete (by the end)**
- `lib/ui/shell/app_shell.dart`, `lib/ui/stop_picker/stop_picker_screen.dart`, `lib/ui/board/arrival_board_screen.dart`, `lib/ui/trip_planner/plan_screen.dart`, `lib/ui/trip_planner/journey_detail_screen.dart`, `lib/ui/map/my_stop_card.dart`, `lib/ui/trip_planner/map_plan_sheet.dart`'s `context.go('/plan')` path, and `test/ui/app_shell_test.dart`. Each one's tests move with its widget.

**Keep unchanged**
- `BBSheet`, `map_layers.dart`, `journey_lines.dart`, `follow_camera.dart`, `follow_card.dart`, `bus_card.dart` (apart from the import of the selection provider), `ArrivalsList`, `ArrivalRowTile`, `AlertBell`, the planner engine and its providers, `SavedTripStore`, `NearMeList`'s rows, `AlertsScreen`'s content and `SettingsScreen`.

---

### Task 1: Move the map screen to `HomeScreen` and pull the sheet content out (no behaviour change)

**Files:**
- Move: `lib/ui/map/map_screen.dart` → `lib/ui/home/home_screen.dart` (`git mv`), renaming the class `MapScreen` → `HomeScreen`.
- Create: `lib/ui/home/sheet_content.dart`
- Modify: `lib/routing/router.dart` (import and class name), `test/ui/map_screen_test.dart` → `test/ui/home_screen_test.dart` (`git mv`, rename the references)

**Interfaces:**
- Produces: `class HomeScreen extends ConsumerStatefulWidget { const HomeScreen({super.key, this.pick}); final String? pick; }` (the `pick` parameter goes in Task 8). Also `Widget selectionHeader(MapSelection? selection, StopInfo? stop)` and `Widget selectionBody(MapSelection? selection, StopInfo? stop)` in `sheet_content.dart`, which `home_screen.dart` calls where it had the two `switch` expressions (lines 965–969 and 974–978 of the old file).

- [ ] **Step 1: Move the file and rename the class**

```bash
mkdir -p lib/ui/home
git mv lib/ui/map/map_screen.dart lib/ui/home/home_screen.dart
git mv test/ui/map_screen_test.dart test/ui/home_screen_test.dart
```

In `lib/ui/home/home_screen.dart`:
- replace `class MapScreen` with `class HomeScreen`, `ConsumerState<MapScreen>` with `ConsumerState<HomeScreen>`, and `_MapScreenState` with `_HomeScreenState` (every occurrence);
- fix the relative imports, since the file is now one folder over: `'bus_card.dart'` → `'../map/bus_card.dart'`. Do the same for `follow_camera.dart`, `follow_card.dart`, `journey_lines.dart`, `map_hit_test.dart`, `map_layers.dart`, `map_style.dart`, `map_surface.dart`, `map_view.dart`, `my_stop_card.dart`, `route_filter_card.dart` and `stop_card.dart`;
- keep the `../../` imports as they are.

Change the doc comment above the class to:

```dart
/// The app's home (spec 2026-10-12 §3): the map, the floating controls and one sheet whose content
/// follows the selection. A long-press plans from or to that point; [pick] ('from' or 'to') makes the next
/// tap choose that end of the trip; a journey shown from the planner is drawn on top.
```

In `lib/routing/router.dart`, change `import '../ui/map/map_screen.dart';` to `import '../ui/home/home_screen.dart';` and `MapScreen(` to `HomeScreen(`. In `test/ui/home_screen_test.dart`, replace `MapScreen` with `HomeScreen` and fix the import path the same way. Run `grep -rn "MapScreen\|ui/map/map_screen" lib test` and fix every remaining hit.

- [ ] **Step 2: Extract the sheet content switch**

Create `lib/ui/home/sheet_content.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../state/map_providers.dart';
import '../map/bus_card.dart';
import '../map/my_stop_card.dart';
import '../map/stop_card.dart';

/// The sheet's header for what is selected on the map (nothing = your stop).
Widget selectionHeader(MapSelection? selection, StopInfo? stop) => switch (selection) {
      null => MyStopCard.header(),
      StopSelection() => stop == null ? const SizedBox.shrink() : StopCardHeader(stop: stop),
      BusSelection(:final vehicleId) => BusCardHeader(vehicleId: vehicleId),
    };

/// The sheet's body under [selectionHeader].
Widget selectionBody(MapSelection? selection, StopInfo? stop) => switch (selection) {
      null => MyStopCard.body(),
      StopSelection() => stop == null ? const SizedBox.shrink() : StopCardBody(stop: stop),
      BusSelection(:final vehicleId) => BusCardBody(vehicleId: vehicleId),
    };
```

In `home_screen.dart`'s `build`, replace the `header:` switch with `selectionHeader(selection, selectedStop)` and the body's switch with `selectionBody(selection, selectedStop)`. Keep the follow branches exactly as they are. Drop the now-unused imports of `bus_card.dart`, `my_stop_card.dart` and `stop_card.dart` from `home_screen.dart` only if the analyzer reports them unused.

- [ ] **Step 3: Run the existing tests (behaviour must be identical)**

Run: `flutter analyze && flutter test test/ui/home_screen_test.dart test/ui/map_cards_test.dart test/ui/plan_screen_test.dart test/ui/journey_detail_test.dart`
Expected: no analyzer issues, all PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/home lib/routing/router.dart test/ui/home_screen_test.dart
git commit -m "refactor(home): move the map screen to HomeScreen and pull out the sheet content

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `homeSheetProvider`, a back stack for the sheet

**Files:**
- Create: `lib/state/home_sheet_provider.dart`
- Modify: `lib/state/map_providers.dart` (remove `MapSelection`, `StopSelection`, `BusSelection`, `MapSelectionNotifier`, `mapSelectionProvider`), `lib/ui/home/home_screen.dart`, `lib/ui/home/sheet_content.dart`, `lib/ui/map/stop_card.dart`, `lib/ui/map/bus_card.dart`, and every file `grep -rln mapSelectionProvider lib test` lists.
- Test: `test/state/home_sheet_provider_test.dart` (new). Update `test/state/map_providers_test.dart` and `test/ui/map_cards_test.dart` to the new names.

**Interfaces:**
- Produces:
  ```dart
  sealed class HomeSheet { const HomeSheet(); }
  final class HomeSheetHome extends HomeSheet { const HomeSheetHome(); }
  final class StopSheet extends HomeSheet { const StopSheet(this.stopId); final String stopId; }
  final class BusSheet extends HomeSheet { const BusSheet(this.vehicleId); final String vehicleId; }
  final class OptionsSheet extends HomeSheet { const OptionsSheet(); }
  final class JourneySheet extends HomeSheet { const JourneySheet(this.journey); final Journey journey; }
  class HomeSheetNotifier extends Notifier<HomeSheet> {
    void open(HomeSheet sheet);   // see rules below
    bool back();                  // false when already home (the caller lets the system leave the app)
    void home();                  // clears the stack
    List<HomeSheet> get stack;    // for tests, oldest first, always starts with HomeSheetHome
  }
  final homeSheetProvider = NotifierProvider<HomeSheetNotifier, HomeSheet>(HomeSheetNotifier.new);
  ```
- Stack rules (spec §3.2–§3.4):
  - `open(HomeSheetHome())` is the same as `home()`.
  - Opening a `StopSheet` or `BusSheet` while the top of the stack is a `StopSheet` or `BusSheet` **replaces** that top entry, so a tap on another stop doesn't stack. Otherwise it pushes.
  - `OptionsSheet` replaces any `OptionsSheet` or `JourneySheet` above it: everything from the first `OptionsSheet` up is dropped, then it pushes.
  - `JourneySheet` replaces a `JourneySheet` on top, otherwise it pushes.
  - Opening the sheet that is already on top changes nothing.
  - The follow is **not** in the stack. `followProvider` still decides when the follow card shows, and only while the top is `HomeSheetHome`. That gives Review Focus 3.

- [ ] **Step 1: Write the failing provider test**

Create `test/state/home_sheet_provider_test.dart`:

```dart
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Journey _journey(int departs) => Journey(serviceDate: DateTime(2026, 10, 12), legs: const [], departs: departs, arrives: departs + 600);

void main() {
  late ProviderContainer c;
  HomeSheetNotifier n() => c.read(homeSheetProvider.notifier);
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('starts home with a one-entry stack', () {
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
    expect(n().stack, hasLength(1));
    expect(n().back(), isFalse);
  });

  test('a stop then another stop replaces, back goes home', () {
    n().open(const StopSheet('1150'));
    n().open(const StopSheet('1600'));
    expect((c.read(homeSheetProvider) as StopSheet).stopId, '1600');
    expect(n().stack, hasLength(2));
    expect(n().back(), isTrue);
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
  });

  test('a bus replaces a stop on top', () {
    n().open(const StopSheet('1150'));
    n().open(const BusSheet('1524'));
    expect(n().stack.map((s) => s.runtimeType), [HomeSheetHome, BusSheet]);
  });

  test('journey → options → home on back (Review Focus 2)', () {
    n().open(const OptionsSheet());
    n().open(JourneySheet(_journey(1000)));
    expect(n().back(), isTrue);
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
    expect(n().back(), isTrue);
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
    expect(n().back(), isFalse);
  });

  test('a stop opened over options stacks, and back returns to the options', () {
    n().open(const OptionsSheet());
    n().open(const StopSheet('1150'));
    expect(n().back(), isTrue);
    expect(c.read(homeSheetProvider), isA<OptionsSheet>());
  });

  test('opening options again drops a journey above the old options', () {
    n().open(const OptionsSheet());
    n().open(JourneySheet(_journey(1000)));
    n().open(const OptionsSheet());
    expect(n().stack.map((s) => s.runtimeType), [HomeSheetHome, OptionsSheet]);
  });

  test('a second journey replaces the first', () {
    n().open(const OptionsSheet());
    n().open(JourneySheet(_journey(1000)));
    n().open(JourneySheet(_journey(2000)));
    expect(n().stack, hasLength(3));
    expect((c.read(homeSheetProvider) as JourneySheet).journey.departs, 2000);
  });

  test('home() clears everything; opening the top again is a no-op', () {
    n().open(const StopSheet('1150'));
    n().open(const StopSheet('1150'));
    expect(n().stack, hasLength(2));
    n().home();
    expect(n().stack, hasLength(1));
  });
}
```

Check `Journey`'s constructor in `lib/domain/trip_planner/journey.dart` first. If it differs (for example, `legs` must be non-empty), build the test journey with the same helper `test/trip_planner/` uses (`grep -rn "Journey(" test/trip_planner | head`) and keep the `departs` values.

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/state/home_sheet_provider_test.dart`
Expected: FAIL. Compilation error: `home_sheet_provider.dart` doesn't exist.

- [ ] **Step 3: Implement the provider**

Create `lib/state/home_sheet_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/trip_planner/journey.dart';

/// What the home screen's sheet shows (spec 2026-10-12 §3). The follow card is not a state: it shows over
/// [HomeSheetHome] while a bus is followed.
sealed class HomeSheet {
  const HomeSheet();
}

final class HomeSheetHome extends HomeSheet {
  const HomeSheetHome();
  @override
  bool operator ==(Object other) => other is HomeSheetHome;
  @override
  int get hashCode => (HomeSheetHome).hashCode;
}

/// A stop's sheet: its Board.
final class StopSheet extends HomeSheet {
  const StopSheet(this.stopId);
  final String stopId;
  @override
  bool operator ==(Object other) => other is StopSheet && other.stopId == stopId;
  @override
  int get hashCode => Object.hash(StopSheet, stopId);
}

/// A bus tapped on the map.
final class BusSheet extends HomeSheet {
  const BusSheet(this.vehicleId);
  final String vehicleId;
  @override
  bool operator ==(Object other) => other is BusSheet && other.vehicleId == vehicleId;
  @override
  int get hashCode => Object.hash(BusSheet, vehicleId);
}

/// Trip options for [planQueryProvider]'s draft.
final class OptionsSheet extends HomeSheet {
  const OptionsSheet();
  @override
  bool operator ==(Object other) => other is OptionsSheet;
  @override
  int get hashCode => (OptionsSheet).hashCode;
}

/// One journey's steps.
final class JourneySheet extends HomeSheet {
  const JourneySheet(this.journey);
  final Journey journey;
  @override
  bool operator ==(Object other) => other is JourneySheet && identical(other.journey, journey);
  @override
  int get hashCode => identityHashCode(journey);
}

/// The sheet's back stack. Back walks it down; from home the system leaves the app.
class HomeSheetNotifier extends Notifier<HomeSheet> {
  final _stack = <HomeSheet>[const HomeSheetHome()];

  List<HomeSheet> get stack => List.unmodifiable(_stack);

  @override
  HomeSheet build() {
    _stack
      ..clear()
      ..add(const HomeSheetHome());
    return const HomeSheetHome();
  }

  void open(HomeSheet sheet) {
    if (sheet is HomeSheetHome) return home();
    if (_stack.last == sheet) return;
    final top = _stack.last;
    switch (sheet) {
      case StopSheet() || BusSheet() when top is StopSheet || top is BusSheet:
        _stack[_stack.length - 1] = sheet;
      case OptionsSheet():
        final first = _stack.indexWhere((s) => s is OptionsSheet);
        if (first != -1) _stack.removeRange(first, _stack.length);
        _stack.add(sheet);
      case JourneySheet() when top is JourneySheet:
        _stack[_stack.length - 1] = sheet;
      default:
        _stack.add(sheet);
    }
    state = _stack.last;
  }

  bool back() {
    if (_stack.length <= 1) return false;
    _stack.removeLast();
    state = _stack.last;
    return true;
  }

  void home() {
    _stack
      ..clear()
      ..add(const HomeSheetHome());
    state = const HomeSheetHome();
  }
}

final homeSheetProvider = NotifierProvider<HomeSheetNotifier, HomeSheet>(HomeSheetNotifier.new);
```

- [ ] **Step 4: Run the provider test**

Run: `flutter test test/state/home_sheet_provider_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Replace `mapSelectionProvider` everywhere**

In `lib/state/map_providers.dart`, delete `MapSelection`, `StopSelection`, `BusSelection`, `MapSelectionNotifier` and `mapSelectionProvider` (the old lines 12–44). Then make these exact replacements:
- `ref.read(mapSelectionProvider.notifier).select(StopSelection(id))` → `ref.read(homeSheetProvider.notifier).open(StopSheet(id))`.
- `ref.read(mapSelectionProvider.notifier).select(BusSelection(id))` → `ref.read(homeSheetProvider.notifier).open(BusSheet(id))`.
- `ref.read(mapSelectionProvider.notifier).clear()`:
  - in `stop_card.dart`'s `ArrivalsList._followable`, and in `home_screen.dart`'s `initState` and `_onFollowChanged` (all three start a follow) → `ref.read(homeSheetProvider.notifier).home()`;
  - in `home_screen.dart`'s `_onTap` empty-map branch → `ref.read(homeSheetProvider.notifier).back()`.
- In `home_screen.dart`:
  - `final selection = ref.watch(mapSelectionProvider);` becomes `final sheet = ref.watch(homeSheetProvider);`;
  - `selection is StopSelection` becomes `sheet is StopSheet`, reading `sheet.stopId`;
  - the `_select(MapSelection)` method becomes `_open(HomeSheet sheet)`, with the same body but calling `.open(sheet)`;
  - the empty-map test `ref.read(mapSelectionProvider) == null` becomes `ref.read(homeSheetProvider) is HomeSheetHome`;
  - the sheet key `follow == null ? selection : 'follow:${follow.vehicleId}'` becomes `follow != null && sheet is HomeSheetHome ? 'follow:${follow.vehicleId}' : sheet`. The follow card now only covers home, which gives Review Focus 3;
  - the header and body conditions `follow != null ? <follow…> : …` become `follow != null && sheet is HomeSheetHome ? <follow…> : …`.
- In `sheet_content.dart`, change both functions to take `(HomeSheet sheet, StopInfo? stop)`, with cases `HomeSheetHome()` (your-stop card), `StopSheet()` (stop card), `BusSheet(:final vehicleId)` (bus card), and `OptionsSheet()` / `JourneySheet()` returning `const SizedBox.shrink()` for now. Tasks 7 and 8 fill those two in.

Then run `grep -rn "mapSelectionProvider\|MapSelection\|StopSelection\|BusSelection" lib test` and convert each test hit the same way, so it uses `homeSheetProvider` with `StopSheet` or `BusSheet`.

- [ ] **Step 6: Add the follow-under-a-sheet test (Review Focus 3)**

In `test/ui/home_screen_test.dart`, add this using the file's existing pump helper (its follow tests already build a followed bus; copy their setup lines verbatim):

```dart
testWidgets('a follow sits under any sheet: open a stop, back returns to the follow card', (tester) async {
  // Same setup as the existing "follows a bus" test in this file: pump, then start a follow on bus 1524.
  // …existing setup lines…
  final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  container.read(homeSheetProvider.notifier).open(const StopSheet('1150'));
  await tester.pumpAndSettle();
  expect(find.textContaining('Following bus 1524'), findsOneWidget); // the chip stays
  expect(find.byType(StopCardHeader), findsOneWidget);
  container.read(homeSheetProvider.notifier).back();
  await tester.pumpAndSettle();
  expect(find.byType(FollowCardHeader), findsOneWidget);
});
```

Replace `// …existing setup lines…` with the literal setup lines from the existing follow test in the same file (pump call, fake feed, `followProvider` start). Don't leave the comment in.

- [ ] **Step 7: Run the affected tests**

Run: `flutter analyze && flutter test test/state test/ui/home_screen_test.dart test/ui/map_cards_test.dart test/ui/follow_card_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/state lib/ui test/state test/ui
git commit -m "feat(home): a back stack for the home sheet replaces the map selection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Saved places and recent destinations, stored on the phone

**Files:**
- Create: `lib/data/trip_planner/saved_place_store.dart`, `lib/state/saved_place_providers.dart`
- Test: `test/state/saved_place_store_test.dart`

**Interfaces:**
- Consumes: `Place`, `Place.fromJson`, `StopPlace`, `PinPlace` (`lib/domain/trip_planner/place.dart`).
- Produces:
  ```dart
  enum SavedPlaceIcon { home, work, school, star }
  class SavedPlace { const SavedPlace({required this.id, required this.name, required this.icon, required this.place});
    final String id; final String name; final SavedPlaceIcon icon; final Place place;
    Map<String, Object?> toJson(); static SavedPlace? fromJson(Object? json); }
  const maxSavedPlaces = 12; const maxRecentPlaces = 10;
  class SavedPlaceStore { SavedPlaceStore([SharedPreferencesAsync? prefs]);
    Future<List<SavedPlace>> read(); Future<bool> put(SavedPlace p); Future<void> remove(String id); }
  class RecentPlaceStore { RecentPlaceStore([SharedPreferencesAsync? prefs]);
    Future<List<Place>> read(); Future<void> push(Place p); }
  final savedPlaceStoreProvider = Provider<SavedPlaceStore>(...);
  final recentPlaceStoreProvider = Provider<RecentPlaceStore>(...);
  final savedPlacesProvider = AsyncNotifierProvider<SavedPlacesNotifier, List<SavedPlace>>(...); // put(), remove()
  final recentPlacesProvider = AsyncNotifierProvider<RecentPlacesNotifier, List<Place>>(...);    // push()
  ```
- Rules:
  - `put` replaces an entry with the same `id`.
  - A `home` or `work` icon is unique: putting a second Home turns the old Home's icon into `star`.
  - `put` returns false when the list is full and the id is new.
  - `push` moves an equal `Place` to the front, then keeps the newest 10.

- [ ] **Step 1: Write the failing store tests**

Create `test/state/saved_place_store_test.dart`:

```dart
import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  final mun = StopPlace(stopId: '1150', name: 'MUN Centre');
  final pin = PinPlace(lat: 47.56, lon: -52.71, label: 'Dropped pin');

  test('put, read back, replace by id', () async {
    final s = SavedPlaceStore();
    expect(await s.put(SavedPlace(id: 'a', name: 'MUN', icon: SavedPlaceIcon.school, place: mun)), isTrue);
    expect(await s.put(SavedPlace(id: 'a', name: 'Campus', icon: SavedPlaceIcon.school, place: mun)), isTrue);
    final all = await s.read();
    expect(all, hasLength(1));
    expect(all.single.name, 'Campus');
    expect(all.single.place, mun);
  });

  test('a second Home demotes the first to a star', () async {
    final s = SavedPlaceStore();
    await s.put(SavedPlace(id: 'a', name: 'Home', icon: SavedPlaceIcon.home, place: mun));
    await s.put(SavedPlace(id: 'b', name: 'New home', icon: SavedPlaceIcon.home, place: pin));
    final byId = {for (final p in await s.read()) p.id: p};
    expect(byId['a']!.icon, SavedPlaceIcon.star);
    expect(byId['b']!.icon, SavedPlaceIcon.home);
  });

  test('full list refuses a new id', () async {
    final s = SavedPlaceStore();
    for (var i = 0; i < maxSavedPlaces; i++) {
      await s.put(SavedPlace(id: '$i', name: '$i', icon: SavedPlaceIcon.star, place: StopPlace(stopId: '$i', name: '$i')));
    }
    expect(await s.put(SavedPlace(id: 'x', name: 'x', icon: SavedPlaceIcon.star, place: mun)), isFalse);
  });

  test('remove', () async {
    final s = SavedPlaceStore();
    await s.put(SavedPlace(id: 'a', name: 'MUN', icon: SavedPlaceIcon.star, place: mun));
    await s.remove('a');
    expect(await s.read(), isEmpty);
  });

  test('corrupt or unknown entries are skipped (Review Focus 5)', () async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString('saved_places.v1', 'not json');
    expect(await SavedPlaceStore().read(), isEmpty);
    await prefs.setString('saved_places.v1',
        '[{"id":"a","name":"x","icon":"home","place":{"kind":"spaceship"}},{"id":"b","name":"MUN","icon":"nope","place":{"kind":"stop","stopId":"1150","name":"MUN Centre"}}]');
    final all = await SavedPlaceStore().read();
    expect(all.map((p) => p.id), ['b']);
    expect(all.single.icon, SavedPlaceIcon.star); // unknown icon falls back to star
    await prefs.setString('recent_places.v1', '{"oops":1}');
    expect(await RecentPlaceStore().read(), isEmpty);
  });

  test('recent: newest first, deduplicated, at most 10', () async {
    final r = RecentPlaceStore();
    for (var i = 0; i < 12; i++) {
      await r.push(StopPlace(stopId: '$i', name: '$i'));
    }
    await r.push(StopPlace(stopId: '5', name: '5'));
    final all = await r.read();
    expect(all, hasLength(maxRecentPlaces));
    expect((all.first as StopPlace).stopId, '5');
    expect(all.whereType<StopPlace>().where((p) => p.stopId == '5'), hasLength(1));
  });
}
```

If `InMemorySharedPreferencesAsync` isn't importable, check how `test/trip_planner/saved_trip_store_test.dart` (or `grep -rln SavedTripStore test`) sets up preferences and use the same setup line.

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/state/saved_place_store_test.dart`
Expected: FAIL. `saved_place_store.dart` doesn't exist.

- [ ] **Step 3: Implement the stores**

Create `lib/data/trip_planner/saved_place_store.dart`:

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/trip_planner/place.dart';

const maxSavedPlaces = 12;
const maxRecentPlaces = 10;

enum SavedPlaceIcon { home, work, school, star }

/// A place the rider named: Home, Work, a school or a favourite (spec 2026-10-12 §3.5).
class SavedPlace {
  const SavedPlace({required this.id, required this.name, required this.icon, required this.place});
  final String id;
  final String name;
  final SavedPlaceIcon icon;
  final Place place;

  SavedPlace withIcon(SavedPlaceIcon i) => SavedPlace(id: id, name: name, icon: i, place: place);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'icon': icon.name, 'place': place.toJson()};

  /// Null for a malformed entry; an unknown icon reads as a star.
  static SavedPlace? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || json['name'] is! String) return null;
    final place = Place.fromJson(json['place']);
    if (place == null) return null;
    final icon = SavedPlaceIcon.values.where((i) => i.name == json['icon']).firstOrNull ?? SavedPlaceIcon.star;
    return SavedPlace(id: json['id'] as String, name: json['name'] as String, icon: icon, place: place);
  }
}

List<Object?> _list(String? raw) {
  if (raw == null) return const [];
  try {
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded : const [];
  } on FormatException {
    return const [];
  }
}

/// Saved places, on the phone only.
class SavedPlaceStore {
  SavedPlaceStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _prefs;
  static const _key = 'saved_places.v1';

  Future<List<SavedPlace>> read() async => [for (final e in _list(await _prefs.getString(_key))) ?SavedPlace.fromJson(e)];

  Future<void> _write(List<SavedPlace> all) => _prefs.setString(_key, jsonEncode([for (final p in all) p.toJson()]));

  /// Adds or replaces [p] by id. Home and Work are unique: an older one becomes a star.
  Future<bool> put(SavedPlace p) async {
    final all = await read();
    final exists = all.any((e) => e.id == p.id);
    if (!exists && all.length >= maxSavedPlaces) return false;
    final unique = p.icon == SavedPlaceIcon.home || p.icon == SavedPlaceIcon.work;
    final next = [
      for (final e in all)
        if (e.id == p.id) p else if (unique && e.icon == p.icon) e.withIcon(SavedPlaceIcon.star) else e,
      if (!exists) p,
    ];
    await _write(next);
    return true;
  }

  Future<void> remove(String id) async => _write([for (final e in await read()) if (e.id != id) e]);
}

/// The last destinations, newest first.
class RecentPlaceStore {
  RecentPlaceStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _prefs;
  static const _key = 'recent_places.v1';

  Future<List<Place>> read() async => [for (final e in _list(await _prefs.getString(_key))) ?Place.fromJson(e)];

  Future<void> push(Place p) async {
    final next = [p, for (final e in await read()) if (e != p) e].take(maxRecentPlaces);
    await _prefs.setString(_key, jsonEncode([for (final e in next) e.toJson()]));
  }
}
```

Create `lib/state/saved_place_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/trip_planner/saved_place_store.dart';
import '../domain/trip_planner/place.dart';

final savedPlaceStoreProvider = Provider<SavedPlaceStore>((ref) => SavedPlaceStore());
final recentPlaceStoreProvider = Provider<RecentPlaceStore>((ref) => RecentPlaceStore());

/// Changes run one at a time (the stores read, change and write the whole list), like saved trips.
mixin _Serial {
  Future<void> _queue = Future.value();
  Future<T> serial<T>(Future<T> Function() op) {
    final run = _queue.catchError((_) {}).then((_) => op());
    _queue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}

class SavedPlacesNotifier extends AsyncNotifier<List<SavedPlace>> with _Serial {
  SavedPlaceStore get _store => ref.read(savedPlaceStoreProvider);
  @override
  Future<List<SavedPlace>> build() => _store.read();

  Future<bool> put(SavedPlace p) => serial(() async {
        final ok = await _store.put(p);
        state = AsyncData(await _store.read());
        return ok;
      });

  Future<void> remove(String id) => serial(() async {
        await _store.remove(id);
        state = AsyncData(await _store.read());
      });
}

class RecentPlacesNotifier extends AsyncNotifier<List<Place>> with _Serial {
  RecentPlaceStore get _store => ref.read(recentPlaceStoreProvider);
  @override
  Future<List<Place>> build() => _store.read();

  Future<void> push(Place p) => serial(() async {
        await _store.push(p);
        state = AsyncData(await _store.read());
      });
}

final savedPlacesProvider = AsyncNotifierProvider<SavedPlacesNotifier, List<SavedPlace>>(SavedPlacesNotifier.new);
final recentPlacesProvider = AsyncNotifierProvider<RecentPlacesNotifier, List<Place>>(RecentPlacesNotifier.new);
```

- [ ] **Step 4: Run the tests**

Run: `flutter analyze && flutter test test/state/saved_place_store_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/trip_planner/saved_place_store.dart lib/state/saved_place_providers.dart test/state/saved_place_store_test.dart
git commit -m "feat(home): saved places and recent destinations, stored on the phone

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: One home route, old links redirected, floating Alerts and Settings, tab bar gone

**Files:**
- Modify: `lib/routing/router.dart`, `lib/ui/home/home_screen.dart`, `lib/ui/alerts/alerts_screen.dart`, `lib/ui/settings/settings_screen.dart` (only if it uses `BBNavBar.reservedHeight`).
- Create: `lib/ui/home/map_buttons.dart`
- Delete: `lib/ui/shell/app_shell.dart`, `test/ui/app_shell_test.dart`
- Test: `test/routing/home_routes_test.dart` (new). Update `test/helpers/planner_app.dart`: its default `initial: '/plan'` keeps working through the redirect, so only change the doc comment ("the app's real route tree").

**Interfaces:**
- Consumes: `homeSheetProvider`, `HomeSheet` and its subclasses (Task 2).
- Produces:
  - routes: `/` (HomeScreen); `/board/:stopId` and `/stop/:stopId` (redirect to `/`, after opening `StopSheet(stopId)`); `/map`, `/plan` and `/plan/journey` (redirect to `/`); `/alerts` (AlertsScreen, pushed on the root navigator, with a back button); `/settings` (unchanged); `/search` (Task 7 adds it).
  - `class MapButtons extends ConsumerWidget`: a column with the Alerts button (bell, badge = active alert count, semantic label `Alerts, N active` or `Alerts`) and the Settings button (gear, `Settings`).

Redirects open the sheet through the root `ProviderContainer`: `ProviderScope.containerOf(context, listen: false).read(homeSheetProvider.notifier).open(StopSheet(id))`, then they return `'/'`. GoRouter's redirect gets a `BuildContext` under the `ProviderScope`.

- [ ] **Step 1: Write the failing routing tests**

Create `test/routing/home_routes_test.dart`. It uses `pumpPlannerApp` from `test/helpers/planner_app.dart` (real router, stub map) and the planner test network from `test/trip_planner/test_network.dart` (`grep -n "TestNetwork\b" test/trip_planner/test_network.dart` for its constructor; existing planner UI tests show how to build one):

```dart
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeScreen)));

void main() {
  final now = DateTime(2026, 10, 12, 13, 0);

  for (final path in ['/', '/map', '/plan', '/plan/journey']) {
    testWidgets('$path opens home at its home sheet', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork.standard(), now: now, initial: path);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
      expect(find.byType(BBNavBar), findsNothing);
    });
  }

  for (final path in ['/board/1150', '/stop/1150']) {
    testWidgets('$path opens home with that stop\'s sheet', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork.standard(), now: now, initial: path);
      expect(_c(tester).read(homeSheetProvider), const StopSheet('1150'));
    });
  }

  testWidgets('/alerts pushes the Alerts screen over home, and its back returns', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork.standard(), now: now, initial: '/');
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Alerts')));
    await tester.pumpAndSettle();
    expect(find.text('Service alerts'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the gear opens Settings', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork.standard(), now: now, initial: '/');
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('system back walks the sheet stack, then leaves (Review Focus 2)', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork.standard(), now: now, initial: '/board/1150');
    expect(_c(tester).read(homeSheetProvider), const StopSheet('1150'));
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue); // handled: the sheet went back
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a board link before the schedule loads shows the stop sheet loading, then its rows (Review Focus 1)',
      (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork.standard(), now: now, initial: '/board/1150', settle: false);
    expect(_c(tester).read(homeSheetProvider), const StopSheet('1150'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1150'), findsWidgets);
  });
}
```

`TestNetwork.standard()` stands for whichever named constructor or factory `test_network.dart` provides. Use the one the existing planner tests use, verbatim. `settle: false` is a new optional parameter on `pumpPlannerApp` (default `true`). When false, it calls `tester.pump()` instead of `pumpAndSettle()`; add it in this step. The Alerts screen title string must match `AlertsScreen`'s `BBTopBar(title:)`, so check that file and use its literal.

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/routing/home_routes_test.dart`
Expected: FAIL. `BBNavBar` is still found, and `/stop/1150` isn't a route.

- [ ] **Step 3: Replace the router**

Rewrite `buildAppRouter` in `lib/routing/router.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/home_sheet_provider.dart';
import '../ui/alerts/alerts_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/settings/settings_screen.dart';

/// The app's router.
final appRouter = buildAppRouter();

/// Opens [stopId]'s sheet on home: links and notifications for a stop land here (spec 2026-10-12 §3.6).
String _toStopSheet(BuildContext context, GoRouterState state) {
  final id = state.pathParameters['stopId']!;
  ProviderScope.containerOf(context, listen: false).read(homeSheetProvider.notifier).open(StopSheet(id));
  return '/';
}

/// A fresh router over the app's route tree (tests build their own so no state carries between them).
GoRouter buildAppRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/stop/:stopId', redirect: _toStopSheet),
      GoRoute(path: '/board/:stopId', redirect: _toStopSheet),
      GoRoute(path: '/map', redirect: (_, _) => '/'),
      GoRoute(path: '/plan', redirect: (_, _) => '/', routes: [GoRoute(path: 'journey', redirect: (_, _) => '/')]),
      GoRoute(path: '/alerts', builder: (context, state) => const AlertsScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    ],
  );
}
```

All callers that did `context.go('/alerts')` now use `context.push('/alerts')`, so back returns home. Find them with `grep -rn "go('/alerts')" lib`: `arrival_board_screen.dart` (deleted in Task 6, so leave it), `bus_card.dart` and `stop_card.dart`. Every `context.go('/map')` and `context.go('/plan')` left in `lib` keeps working through the redirects. Tasks 6–8 remove them.

- [ ] **Step 4: Home handles system back for the sheet**

In `home_screen.dart`'s `build`, wrap the returned `ColoredBox` in a `PopScope`:

```dart
final atHome = ref.watch(homeSheetProvider) is HomeSheetHome;
return PopScope(
  canPop: atHome,
  onPopInvokedWithResult: (didPop, _) {
    if (!didPop) ref.read(homeSheetProvider.notifier).back();
  },
  child: ColoredBox(/* …unchanged… */),
);
```

Put this inside the `LayoutBuilder`'s builder, around the `ColoredBox` it returns.

- [ ] **Step 5: The floating buttons, no nav-bar inset**

Create `lib/ui/home/map_buttons.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../kit/kit.dart';

/// Alerts (with the active count) and Settings, floating on the map (spec 2026-10-12 §3.1).
class MapButtons extends ConsumerWidget {
  const MapButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final count = ref.watch(serviceUpdatesProvider).value?.activeAlertsAt(DateTime.now()).length ?? 0;
    final alertsLabel = count > 0 ? 'Alerts, $count active' : 'Alerts';
    return DecoratedBox(
      decoration: bb.floating(radius: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: alertsLabel,
            excludeSemantics: true,
            onTap: () => context.push('/alerts'),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                BBIconButton(icon: BBIcons.alerts, semanticLabel: alertsLabel, onPressed: () => context.push('/alerts')),
                if (count > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: bb.colors.danger, borderRadius: BorderRadius.circular(999)),
                        child: Text('$count', style: bb.text.caption.copyWith(color: bb.colors.bg, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(width: 28, height: 1, color: bb.colors.line),
          BBIconButton(icon: BBIcons.settings, semanticLabel: 'Settings', onPressed: () => context.push('/settings')),
        ],
      ),
    );
  }
}
```

If `bb.colors.danger` doesn't exist, use the colour `BBNavBar` paints its badge with (see `lib/ui/kit/bb_nav_bar.dart` around line 107) and the same text style.

In `home_screen.dart`:
- `final navInset = BBNavBar.reservedHeight(context);` → `final navInset = media.padding.bottom;` (move the line below `final media = MediaQuery.of(context);`).
- In the top controls `Row` (the one holding the my-location `BBControlPill`), put `const MapButtons()` above the pill. Change that right-hand side to a `Column(mainAxisSize: MainAxisSize.min, children: [const MapButtons(), const SizedBox(height: BBSpace.s), BBControlPill(…unchanged…)])`.
- Remove the "your stop" `BBChip` (old lines 873–882) and keep the follow chip. When not following, that slot shows nothing: the `Flexible(flex: 3, …)` becomes `follow != null ? Flexible(flex: 3, child: _followChip(follow)) : const Spacer(flex: 3)`.

In `alerts_screen.dart`:
- replace each `BBNavBar.reservedHeight(context)` with `MediaQuery.paddingOf(context).bottom`;
- give its `BBTopBar` `onBack: () => context.canPop() ? context.pop() : context.go('/')`.

Do the same in `settings_screen.dart` if `grep -n reservedHeight lib/ui/settings/settings_screen.dart` finds anything.

Delete the shell and its test:

```bash
git rm lib/ui/shell/app_shell.dart test/ui/app_shell_test.dart
```

`BBNavBar` stays in the kit for now (`test/kit/nav_bar_test.dart` still covers it). Task 11 removes it.

- [ ] **Step 6: Run the tests**

Run: `flutter analyze && flutter test test/routing test/ui/home_screen_test.dart test/ui/alerts_test.dart test/ui/settings_screen_test.dart test/ui/map_cards_test.dart`
Expected: PASS. Any test that tapped the "Board", "Map" or "Plan" tab must now reach that screen through the flow that replaces it (§3.6 of the spec). Fix such tests in this step. `grep -rn "'Board'\|'Plan'\|BBNavBar" test/ui` finds them.

- [ ] **Step 7: Commit**

```bash
git add -A lib/routing lib/ui test/routing test/ui test/helpers
git commit -m "feat(home): one home route, old links redirected, Alerts and Settings float on the map

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The home sheet: Where to, saved places, alerts for you, your stop, saved trips, nearby

**Files:**
- Create: `lib/state/alerts_for_you_provider.dart`, `lib/ui/home/home_sheet.dart`
- Modify: `lib/ui/home/sheet_content.dart` (the `HomeSheetHome` case), `lib/ui/stop_picker/near_me_list.dart` (a tap opens the stop sheet), `lib/ui/trip_planner/saved_trips_section.dart` (a tap opens options).
- Delete: `lib/ui/map/my_stop_card.dart`, `lib/ui/stop_picker/stop_picker_screen.dart` and its test `test/ui/stop_picker_test.dart`. Move that test's assertions about the near-me list and the stop-number entry into `test/ui/home_sheet_test.dart`.
- Test: `test/state/alerts_for_you_test.dart`, `test/ui/home_sheet_test.dart`, plus two cases added to `test/ui/screen_overflow_test.dart`.

**Interfaces:**
- Consumes: `homeSheetProvider` (T2), `savedPlacesProvider` and `SavedPlace` (T3), `savedTripsProvider` and `savedTripNextProvider` (existing), `stopArrivalsProvider` (existing), `ArrivalsPreview` and `ArrivalsList` (in `lib/ui/map/stop_card.dart`), `NearMeList` (existing), `ServiceAlert.appliesTo` (existing), `GtfsRepository.routeShortNamesForStop` (existing).
- Produces:
  - `final alertsForYouProvider = Provider.autoDispose<List<ServiceAlert>>(...)`: the active alerts that apply to your stop (`stopId:` plus `routeIds:` the stop's routes) or to any route of your saved trips' next departures.
  - `abstract final class HomeSheetContent { static Widget header(); static Widget body(); }`
  - `HomeSheetContent.whereToKey = ValueKey('where-to')`
- Behaviour:
  - "Where to?" pushes `/search` (Task 7 adds the route; until then the tap does `context.push('/search')` and Task 7's tests cover it).
  - A saved-place chip sets `planQueryProvider` to (`from`: null, `to`: the place) and opens `OptionsSheet`. Task 8 resolves "My location" for a null start.
  - The "+" chip pushes `/search?save=1` (Task 7).
  - A long-press on a chip offers Rename / Remove, the way `saved_trips_section.dart`'s `_editTrip` does. Reuse that dialog shape.
  - A saved-trip card tap does `planQuery.setTrip(from, to)` and then `homeSheet.open(OptionsSheet())`.
  - A nearby-stop tap opens `StopSheet(id)` instead of pushing `/board/…`. It no longer sets "your stop"; ★ on the stop sheet does that (Task 6).

- [ ] **Step 1: Write the failing alerts-for-you test**

Create `test/state/alerts_for_you_test.dart`. Build alerts like `test/ui/app_shell_test.dart` did (`ServiceAlert(...)` with `targets`). `grep -n "class ServiceAlertTarget\|ServiceAlertTarget(" lib/data/realtime/service_alert_models.dart` shows the target constructor. Then:

```dart
test('only alerts on your stop, its routes or your saved trips\' routes', () async {
  final container = ProviderContainer(overrides: [
    serviceUpdatesProvider.overrideWith((ref) => Stream.value(ServiceUpdates(
          alerts: [onRoute10, onStop1150, onRoute99],
          serviceStatus: null,
          fetchedAt: DateTime(2026, 10, 12),
          feedTimestamp: null,
        ))),
    gtfsRepositoryProvider.overrideWith((ref) async => repoWhere1150Serves10),
    settingsProvider.overrideWith(() => FixedSettings(selectedStopId: '1150')),
    savedTripsProvider.overrideWith(() => FixedSavedTrips(const [])),
  ]);
  addTearDown(container.dispose);
  await container.read(serviceUpdatesProvider.future);
  await container.read(gtfsRepositoryProvider.future);
  expect(container.read(alertsForYouProvider).map((a) => a.header), ['Detour on 10', 'Stop 1150 closed']);
});
```

Use the repo builder and settings and saved-trips fakes that exist in `test/helpers/` or `test/state/` (`grep -rn "overrideWith(() =>" test/state | head`). If there's no settings fake, override `settingsProvider` the way `test/ui/arrival_board_screen_test.dart` does. Name the three alerts by header: `'Detour on 10'`, `'Stop 1150 closed'` and `'Detour on 99'`.

- [ ] **Step 2: Implement `alertsForYouProvider`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/realtime/service_alert_models.dart';
import '../domain/trip_planner/journey.dart';
import 'providers.dart';
import 'trip_planner_providers.dart';

/// Active alerts that touch the rider: their stop, the routes serving it, or the routes of their saved
/// trips' next buses (spec 2026-10-12 §3.1).
final alertsForYouProvider = Provider.autoDispose<List<ServiceAlert>>((ref) {
  final updates = ref.watch(serviceUpdatesProvider).value;
  final repo = ref.watch(gtfsRepositoryProvider).value;
  if (updates == null || repo == null) return const [];
  final stopId = ref.watch(settingsProvider.select((s) => s.selectedStopId));
  final routes = <String>{if (stopId != null) ...repo.routeShortNamesForStop(stopId)};
  for (final trip in ref.watch(savedTripsProvider).value ?? const []) {
    for (final j in ref.watch(savedTripNextProvider(trip.id)).value ?? const <Journey>[]) {
      for (final ride in j.legs.whereType<RideLeg>()) {
        final name = repo.routesById[ride.routeId]?.routeShortName;
        if (name != null) routes.add(name);
      }
    }
  }
  if (stopId == null && routes.isEmpty) return const [];
  return updates
      .activeAlertsAt(DateTime.now())
      .where((a) => a.appliesTo(routeIds: routes, stopId: stopId))
      .toList();
});
```

Check `appliesTo`'s parameter names against `lib/data/realtime/service_alert_models.dart:153` before running.

Run: `flutter test test/state/alerts_for_you_test.dart`. Expected: PASS.

- [ ] **Step 3: Write the failing home-sheet widget tests**

Create `test/ui/home_sheet_test.dart` with `pumpPlannerApp(initial: '/')`, the stop selected through `SharedPreferences.setMockInitialValues` the way existing tests choose a stop (`grep -rn "selected_stop\|selectedStopId" test/helpers test/ui | head`), and a saved place put through `savedPlacesProvider` before pumping. Test:

```dart
testWidgets('at peek: Where to, saved places, alerts for you and your stop, with no taps', (tester) async {
  // pump with stop 1150 selected, one saved place "Home" (StopPlace 1600) and an alert on route 10
  expect(find.byKey(HomeSheetContent.whereToKey), findsOneWidget);
  expect(find.text('Where to?'), findsOneWidget);
  expect(find.text('Home'), findsOneWidget);
  expect(find.textContaining('Detour on 10'), findsOneWidget);
  expect(find.text('MUN Centre'), findsWidgets);
  expect(find.byType(ArrivalsPreview), findsOneWidget);
});

testWidgets('a saved place opens trip options to it', (tester) async {
  // same pump
  await tester.tap(find.text('Home'));
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  expect(c.read(homeSheetProvider), isA<OptionsSheet>());
  expect(c.read(planQueryProvider).to, StopPlace(stopId: '1600', name: 'Avalon Mall'));
});

testWidgets('a nearby stop opens its sheet', (tester) async {
  // pump with nearestStopsProvider overridden to [NearbyStop for 1150]
  await tester.drag(find.byType(HomeScreen), const Offset(0, -400)); // pull the sheet up
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('MUN Centre').last);
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  expect(c.read(homeSheetProvider), const StopSheet('1150'));
});

testWidgets('no stop chosen: "Choose your stop" opens nearby stops', (tester) async {
  // pump with no stop selected
  expect(find.text('Choose your stop'), findsOneWidget);
});
```

Replace each `// pump …` comment with the literal pump call and overrides. Copy the overrides from the existing tests that set those states (`grep -rn "nearestStopsProvider.overrideWith" test`). The stop names come from the test network's GTFS; use the names it actually has.

- [ ] **Step 4: Implement `home_sheet.dart`**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/trip_planner/saved_place_store.dart';
import '../../state/alerts_for_you_provider.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/providers.dart';
import '../../state/saved_place_providers.dart';
import '../../state/trip_planner_providers.dart';
import '../alerts/service_alert_card.dart';
import '../kit/kit.dart';
import '../map/stop_card.dart';
import '../stop_picker/near_me_list.dart';
import '../trip_planner/saved_trips_section.dart';

/// The home sheet (spec 2026-10-12 §3.1). The header is what peeks: Where to, saved places, alerts for you,
/// your stop's next buses. The body: the rest of your stop, saved trips, nearby stops.
abstract final class HomeSheetContent {
  static const whereToKey = ValueKey('where-to');
  static Widget header({VoidCallback? onChooseStop}) => _Header(onChooseStop: onChooseStop);
  static Widget body() => const _Body();
}

IconData _iconOf(SavedPlaceIcon i) => switch (i) {
      SavedPlaceIcon.home => BBIcons.board,
      SavedPlaceIcon.work => BBIcons.schedule,
      SavedPlaceIcon.school => BBIcons.info,
      SavedPlaceIcon.star => BBIcons.star,
    };

class _Header extends ConsumerWidget {
  const _Header({this.onChooseStop});

  /// Pulls the sheet up to the nearby stops (home_screen.dart passes its sheet controller's full detent).
  final VoidCallback? onChooseStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final places = ref.watch(savedPlacesProvider).value ?? const <SavedPlace>[];
    final alerts = ref.watch(alertsForYouProvider);
    final stopId = ref.watch(settingsProvider.select((s) => s.selectedStopId));
    final stop = stopId == null ? null : ref.watch(stopInfoProvider(stopId));
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BBPressable(
            key: HomeSheetContent.whereToKey,
            semanticLabel: 'Where to? Search for a place or a stop',
            onTap: () => context.push('/search'),
            child: DecoratedBox(
              decoration: bb.card(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: BBSpace.m),
                child: Row(children: [
                  Icon(BBIcons.search, size: 20, color: bb.colors.muted),
                  const SizedBox(width: BBSpace.s),
                  Expanded(child: Text('Where to?', style: bb.text.title.copyWith(color: bb.colors.muted))),
                ]),
              ),
            ),
          ),
          const SizedBox(height: BBSpace.s),
          Wrap(
            spacing: BBSpace.s,
            runSpacing: BBSpace.s,
            children: [
              for (final p in places)
                GestureDetector(
                  onLongPress: () => _editPlace(context, ref, p),
                  child: BBChip(
                    label: p.name,
                    icon: _iconOf(p.icon),
                    semanticLabel: 'Go to ${p.name}',
                    onTap: () {
                      ref.read(planQueryProvider.notifier).setDestination(p.place);
                      ref.read(homeSheetProvider.notifier).open(const OptionsSheet());
                    },
                  ),
                ),
              BBChip(
                label: places.isEmpty ? 'Save a place' : 'Add',
                icon: BBIcons.add,
                semanticLabel: 'Save a place',
                onTap: () => context.push('/search?save=1'),
              ),
            ],
          ),
          for (final a in alerts.take(2)) ...[
            const SizedBox(height: BBSpace.s),
            ServiceAlertCard(alert: a, compact: true, onTap: () => context.push('/alerts')),
          ],
          const SizedBox(height: BBSpace.m),
          if (stop == null)
            BBButton(
              label: 'Choose your stop',
              icon: BBIcons.nearMe,
              kind: BBButtonKind.quiet,
              expand: true,
              onPressed: onChooseStop,
            )
          else ...[
            BBPressable(
              semanticLabel: 'Your stop, ${stop.stopName}. Open its buses',
              onTap: () => ref.read(homeSheetProvider.notifier).open(StopSheet(stop.stopId)),
              child: Row(children: [
                Icon(BBIcons.star, size: 18, color: bb.colors.brand),
                const SizedBox(width: BBSpace.s),
                Expanded(child: Text(stop.stopName, style: bb.text.headline, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('#${stop.stopId}', style: bb.text.caption),
              ]),
            ),
            const SizedBox(height: BBSpace.s),
            ArrivalsPreview(stopId: stop.stopId, max: 3),
          ],
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) => const Padding(
        padding: EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: BBSpace.m),
            SavedTripsSection(),
            NearMeList(),
          ],
        ),
      );
}

Future<void> _editPlace(BuildContext context, WidgetRef ref, SavedPlace p) async {
  final remove = await BBDialog.show<bool>(
    context,
    title: p.name,
    actions: const [
      BBDialogAction(label: 'Cancel', value: false),
      BBDialogAction(label: 'Remove', value: true, primary: true),
    ],
  );
  if (remove == true) await ref.read(savedPlacesProvider.notifier).remove(p.id);
}
```

Add `setDestination` to `PlanQueryNotifier` in `lib/state/trip_planner_providers.dart`, next to `setTrip`:

```dart
/// A destination from home (a saved place, a search result): the start stays as it was, or empty.
void setDestination(Place to) => state = PlanDraft(from: state.from, to: to, mode: state.mode, time: state.time);
```

In `home_screen.dart`, pass `onChooseStop: () => unawaited(_sheet.animateToDetent(BBSheetDetent.full))` through `selectionHeader(..., onChooseStop: ...)`. Nearby stops are at the bottom of the full sheet.

Rename and the Home/Work icon choice are in the long-press dialog's P2 follow-up. P1's long-press offers Remove only, as the code above shows. Spec §3.5's Rename comes with the `/search?save=1` flow in Task 7, which re-saves under a new name.

In `sheet_content.dart`, `HomeSheetHome()` maps to `HomeSheetContent.header(onChooseStop: onChooseStop)` for the header and `HomeSheetContent.body()` for the body. The `selectionHeader` and `selectionBody` functions gain a named `VoidCallback? onChooseStop`.

In `near_me_list.dart`'s `_NearbyStopTile.onTap`, replace the two lines with `ref.read(homeSheetProvider.notifier).open(StopSheet(stop.stopId));`.

In `saved_trips_section.dart`'s `_SavedTripCard`, replace `onTap: () => ref.read(planQueryProvider.notifier).setTrip(trip.from, trip.to),` with:

```dart
onTap: () {
  ref.read(planQueryProvider.notifier).setTrip(trip.from, trip.to);
  ref.read(homeSheetProvider.notifier).open(const OptionsSheet());
},
```

Delete `lib/ui/map/my_stop_card.dart` and `lib/ui/stop_picker/stop_picker_screen.dart`. `stop_id_entry.dart` stays: Task 7's search screen uses its validation. Move `stop_picker_test.dart`'s near-me and stop-number cases into `home_sheet_test.dart` (near-me) and `search_screen_test.dart` (Task 7, stop number). Delete the rest of `stop_picker_test.dart` with `git rm`.

- [ ] **Step 5: Add the overflow cases (Review Focus 4)**

In `test/ui/screen_overflow_test.dart`, follow its existing pattern (`grep -n "testWidgets" test/ui/screen_overflow_test.dart`) and add home at peek on a 360×640 surface at text scale 2.0, light and dark. Assert:
- no overflow (`tester.takeException()` is null, as that file does);
- `find.byKey(HomeSheetContent.whereToKey)` is hit-testable at peek (`tester.getRect(...)` is inside the visible sheet area).

- [ ] **Step 6: Run the tests**

Run: `flutter analyze && flutter test test/state test/ui`
Expected: PASS. Fix any test that pushed `/board/…` from the stop picker by opening the stop sheet instead.

- [ ] **Step 7: Commit**

```bash
git add -A lib test
git commit -m "feat(home): the home sheet with Where to, saved places, alerts for you, your stop, saved trips and nearby

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: A stop's sheet is its Board

**Files:**
- Create: `lib/ui/home/stop_sheet.dart`
- Modify: `lib/ui/home/sheet_content.dart` (the `StopSheet` case uses `StopSheetContent`), `lib/ui/map/stop_card.dart` (keep `ArrivalsPreview`, `ArrivalsList` and `StopCardHeader`; delete `StopCardBody`, which `StopSheetContent.body` replaces)
- Delete: `lib/ui/board/arrival_board_screen.dart`. Move `test/ui/arrival_board_screen_test.dart` → `test/ui/stop_sheet_test.dart` (`git mv`, then adapt), and update `test/ui/arrival_alerts_ui_test.dart` wherever it pumps the Board.

**Interfaces:**
- Consumes: `stopArrivalsProvider(stopId)` (polls at the settings interval, pauses in the background), `arrivalAlertProvider.notifier.onBoardArrivals(stopId, rows)` (must be called with every new list, as the Board did), `AlertBell`, `ArrivalRowTile`, `AlertStrip`, `ServiceAlertCard`, `followProvider`, `homeSheetProvider`, `settingsProvider.notifier.setSelectedStop`, `planQueryProvider.notifier.setFrom`.
- Produces:
  - `abstract final class StopSheetContent { static Widget header(String stopId); static Widget body(String stopId); }`;
  - keys `StopSheetContent.starKey`, `refreshKey`, `planFromKey`, `goFromKey` (`ValueKey('stop-star')` and so on).
- Behaviour, matching today's Board:
  - **Header:** a `STOP 1150` pill, the name, a live state line, and a refresh button (`BBIcons.refresh`, label `Refresh departures`) that does `ref.invalidate(stopArrivalsProvider(stopId))`. The sheet can't pull to refresh because the drag moves the sheet, so the button replaces pull-to-refresh. Record that in the commit message.
  - **Live state line:** `Live` when any row `isLive`, `Showing schedule` otherwise, and `Checking live data…` while the first load runs. It's in a live region, except during the first load.
  - **Three actions:**
    - ★ (`Your stop` / `Set as my stop`);
    - **Plan from here** (`setFrom(StopPlace)` then `context.push('/search')`);
    - **Go from here** (`setFrom(StopPlace)`, mode `leaveNow`, then `context.push('/search')`). In P1, Go from here and Plan from here do the same thing, because Go mode is P3. Label it `Plan a trip from here` and drop the separate Go button until P3. The spec's §3.2 "Go from here" lands in P3.
  - **Body:**
    - the "Alert set" strip while an alert exists;
    - the stop's relevant alerts (same rule as the Board's `_relevantAlerts`: routes and trips of the rows, plus the stop; first card plus "N more relevant alerts" pushing `/alerts`);
    - then every arrival row with `AlertBell`, where a live row follows its bus (`homeSheet.home()`, then `followProvider.follow(vehicle)`);
    - the loading, error and empty states from the Board, with the same strings.

- [ ] **Step 1: Move the Board tests**

```bash
git mv test/ui/arrival_board_screen_test.dart test/ui/stop_sheet_test.dart
```

In `stop_sheet_test.dart`, change the pump helper so that instead of building `ArrivalBoardScreen(stopId: …)` it pumps the real app at `/board/<id>`. That's `pumpPlannerApp(initial: '/board/1150')`, or the file's own `MaterialApp.router(buildAppRouter(initialLocation: '/board/1150'))` with its existing overrides. Then pull the sheet to full with `await tester.drag(find.bySemanticsLabel('Map sheet'), const Offset(0, -600)); await tester.pumpAndSettle();`.

Replace assertions about pull-to-refresh (`find.byType(BBRefresh)`, `tester.fling(...)` refresh) with a tap on `find.byKey(StopSheetContent.refreshKey)`. Keep every other assertion about strings, rows, the bell, alerts and the live line unchanged. They're the spec for this task.

Add:

```dart
testWidgets('★ makes it your stop', (tester) async {
  // pump at /board/1150 with no stop selected
  await tester.tap(find.byKey(StopSheetContent.starKey));
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  expect(c.read(settingsProvider).selectedStopId, '1150');
  expect(find.bySemanticsLabel('Your stop'), findsOneWidget);
});

testWidgets('every new list reaches the arrival alerts, like the Board did', (tester) async {
  // pump at /board/1150 with an arrival alert set on stop 1150 (use the file's existing alert-set helper)
  // advance the poll: tester.pump(Duration(seconds: refreshIntervalSeconds))
  // assert the alert's expectedAt moved to the new row's time, as the existing Board alert test does
});
```

Replace the comments with the literal setup and assertions from the existing Board alert test in `test/ui/arrival_alerts_ui_test.dart` (`grep -n "onBoardArrivals\|expectedAt" test/ui/arrival_alerts_ui_test.dart`).

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/ui/stop_sheet_test.dart`
Expected: FAIL (`StopSheetContent` doesn't exist).

- [ ] **Step 3: Implement `stop_sheet.dart`**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/realtime/service_alert_models.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/trip_planner/place.dart';
import '../../state/arrival_alert_providers.dart';
import '../../state/follow_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../alerts/service_alert_card.dart';
import '../arrival_alerts/alert_bell.dart';
import '../arrival_alerts/alert_strip.dart';
import '../board/arrival_row_tile.dart';
import '../kit/kit.dart';

/// A stop's sheet: everything today's Board shows (spec 2026-10-12 §3.2).
abstract final class StopSheetContent {
  static const starKey = ValueKey('stop-star');
  static const refreshKey = ValueKey('stop-refresh');
  static const planFromKey = ValueKey('stop-plan-from');
  static Widget header(String stopId) => _StopHeader(stopId: stopId);
  static Widget body(String stopId) => _StopBody(stopId: stopId);
}

class _StopHeader extends ConsumerWidget {
  const _StopHeader({required this.stopId});
  final String stopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final stop = ref.watch(stopInfoProvider(stopId));
    final name = stop?.stopName ?? 'Stop $stopId';
    final arrivals = ref.watch(stopArrivalsProvider(stopId));
    final rows = arrivals.value;
    final checking = rows == null && !arrivals.hasError;
    final live = rows != null && rows.any((r) => r.isLive);
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
            BBIconButton(
              key: StopSheetContent.refreshKey,
              icon: BBIcons.refresh,
              semanticLabel: 'Refresh departures',
              onPressed: () => ref.invalidate(stopArrivalsProvider(stopId)),
            ),
          ]),
          Semantics(
            header: true,
            child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: bb.text.headline),
          ),
          const SizedBox(height: BBSpace.xs),
          Row(children: [
            BBGlyph(BBGlyphKind.liveDot, size: 12, color: live ? bb.colors.live : bb.colors.muted),
            const SizedBox(width: BBSpace.s),
            Flexible(
              child: Semantics(
                liveRegion: !checking,
                child: Text(
                  checking ? 'Checking live data…' : live ? 'Live' : 'Showing schedule',
                  style: bb.text.caption,
                ),
              ),
            ),
          ]),
          const SizedBox(height: BBSpace.s),
          BBButton(
            key: StopSheetContent.planFromKey,
            label: 'Plan a trip from here',
            icon: BBIcons.plan,
            kind: BBButtonKind.quiet,
            expand: true,
            wrap: true,
            onPressed: () {
              ref.read(planQueryProvider.notifier).setFrom(StopPlace(stopId: stopId, name: name));
              context.push('/search');
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

  List<ServiceAlert> _relevant(ServiceUpdates? updates, List<ArrivalRow> rows) {
    if (updates == null) return const [];
    final routes = rows.map((a) => a.routeShortName).toSet();
    final trips = rows.map((a) => a.tripId).toSet();
    return updates
        .activeAlertsAt(DateTime.now())
        .where((a) => a.appliesTo(routeIds: routes, stopId: stopId, tripIds: trips))
        .toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    // Every new list feeds the arrival alerts, as the Board did.
    ref.listen<AsyncValue<List<ArrivalRow>>>(stopArrivalsProvider(stopId), (_, next) {
      final rows = next.value;
      if (rows != null) ref.read(arrivalAlertProvider.notifier).onBoardArrivals(stopId, rows);
    });
    final stop = ref.watch(stopInfoProvider(stopId));
    final name = stop?.stopName ?? 'Stop $stopId';
    final arrivals = ref.watch(stopArrivalsProvider(stopId));
    final rows = arrivals.value;
    final alerts = _relevant(ref.watch(serviceUpdatesProvider).value, rows ?? const []);
    final strip = ref.watch(arrivalAlertProvider).value == null ? null : const AlertStrip();

    VoidCallback? follow(ArrivalRow a) {
      final vehicle = a.followableVehicle;
      if (vehicle == null) return null;
      return () {
        ref.read(homeSheetProvider.notifier).home();
        ref.read(followProvider.notifier).follow(vehicle);
      };
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (strip != null) ...[strip, const SizedBox(height: BBSpace.s)],
          if (alerts.isNotEmpty) ...[
            ServiceAlertCard(
              alert: alerts.first,
              stopNames: stop == null ? const {} : {stopId: stop.stopName},
              compact: true,
              onTap: () => context.push('/alerts'),
            ),
            if (alerts.length > 1)
              BBButton(
                label: '${alerts.length - 1} more relevant ${alerts.length == 2 ? "alert" : "alerts"}',
                kind: BBButtonKind.quiet,
                onPressed: () => context.push('/alerts'),
              ),
            const SizedBox(height: BBSpace.s),
          ],
          if (rows == null && arrivals.hasError)
            const BBEmptyState(icon: BBIcons.error, tone: BBEmptyTone.error, title: "Couldn't load departures")
          else if (rows == null)
            const BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: 5, label: 'Loading departures...')
          else if (rows.isEmpty)
            const BBEmptyState(
              icon: BBIcons.schedule,
              title: 'No upcoming departures',
              message: 'There are no scheduled departures\nfrom this stop right now.',
            )
          else
            for (final a in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: BBSpace.s),
                child: ArrivalRowTile(
                  arrival: a,
                  onTap: follow(a),
                  action: AlertBell(arrival: a, stopId: stopId, stopName: name),
                ),
              ),
        ],
      ),
    );
  }
}
```

Fix the import paths for `AlertStrip`, `AlertBell` and `ArrivalRowTile` to where they actually live (`grep -rn "class AlertStrip\|class AlertBell\|class ArrivalRowTile" lib`). `ArrivalRow.isLive` is the field name the Board's rows use for a live row; check `lib/domain/arrival/arrival_models.dart` and use the actual name. The Board's error copy was `_error` ('Schedule data not loaded'); the provider has no such text, so "Couldn't load departures" is new, and it's the only new string.

In `sheet_content.dart`, `StopSheet(:final stopId)` maps to `StopSheetContent.header(stopId)` and `StopSheetContent.body(stopId)`. `StopCardHeader` and `StopCardBody` are no longer used by the sheet: delete `StopCardBody` and keep `StopCardHeader` only if `grep -rn StopCardHeader lib` shows another user. Otherwise delete it too, keeping `ArrivalsPreview` and `ArrivalsList` in `stop_card.dart`.

Delete the Board:

```bash
git rm lib/ui/board/arrival_board_screen.dart
```

`lib/ui/board/arrival_row_tile.dart` stays.

- [ ] **Step 4: Run the tests**

Run: `flutter analyze && flutter test`
Expected: everything passes. `arrival_alerts_ui_test.dart` and `screen_golden_test.dart` cases that pumped the Board now go through `/board/<id>` with the sheet pulled to full. Update them in this step without changing what they assert.

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "feat(home): a stop's sheet is its Board; refresh is a button since the sheet owns the drag

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: "Where to?" search

**Files:**
- Create: `lib/ui/search/search_screen.dart`, `lib/domain/location/locate_me.dart`
- Modify: `lib/routing/router.dart` (`/search`), `lib/ui/trip_planner/place_picker_sheet.dart` (use `locateMe`; delete `matchStops` from here and move it into `search_screen.dart` as a public function, with its `_compareIds`), plus every importer of `matchStops`
- Test: `test/ui/search_screen_test.dart`

**Interfaces:**
- Consumes: `matchStops` (moved), `savedPlacesProvider` and `recentPlacesProvider` (T3), `planQueryProvider`, `homeSheetProvider`, `mapPickProvider` (created here), `stopInfoProvider`.
- Produces:
  - `Future<Place?> locateMe()`: returns `PinPlace(label: myLocationLabel)` from one fix within `locateTimeLimit`, or null when location is off, denied or slow. Same permission handling as the place picker's `_useMyLocation`.
  - `enum MapPick { from, to }`, and `final mapPickProvider = NotifierProvider<MapPickNotifier, MapPick?>(…)` with `start(MapPick)` and `clear()`, in `lib/state/map_pick_provider.dart`.
  - Route `/search` with optional query `end=from` (choosing the start; default is the destination) and `save=1` (saving a place instead of planning).
  - `SearchScreen`, with `SearchScreen.fieldKey = ValueKey('search-field')`.
- Behaviour (spec §3.3):
  - **The text field** is autofocused, with hint `Search for a stop or a place` (P2 adds places and addresses).
  - **Empty query:**
    - rows `Choose on map` and, for `end=from` only, `My location`;
    - then `Saved places`, then `Recent` (the last 10).
  - **With a query:**
    - stops from `matchStops`;
    - saved places whose name contains the query (any case);
    - a 4-digit number that is a stop puts that stop first. `matchStops` already sorts by id, so a prefix match on id comes first.
  - **Picking a place** for the destination:
    1. `recentPlaces.push(place)`;
    2. `planQuery.setDestination(place)`;
    3. if `planQuery.from` is null, try `locateMe()` and `setFrom` the result when it's not null;
    4. `homeSheet.open(OptionsSheet())`;
    5. `context.pop()`.
  - **Picking a stop** for the destination asks with a `BBDialog`:
    - `Go here` → plan to it, as above;
    - `See its buses` → `homeSheet.open(StopSheet(id))` and `pop`.
  - **For `end=from`:** `setFrom(place)` and `pop`. When options are already open, they replan by themselves.
  - **For `save=1`:** picking a place asks for a name (prefilled with `place.label`) and an icon (Home / Work / School / Star segmented) in a `BBDialog` with a `BBTextField`, then `savedPlaces.put(SavedPlace(id: <millis>, …))` and `pop`.
  - **"Choose on map":** `mapPick.start(end)` and `pop`. On home, the next map tap finishes it (Task 8).

- [ ] **Step 1: Write the failing tests**

Create `test/ui/search_screen_test.dart` with `pumpPlannerApp(initial: '/search')` (and `'/search?end=from'`, `'/search?save=1'`):

```dart
testWidgets('a stop number lists that stop first; Go here opens options to it', (tester) async {
  await pumpPlannerApp(tester, net: TestNetwork.standard(), now: now, initial: '/');
  await tester.tap(find.byKey(HomeSheetContent.whereToKey));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(SearchScreen.fieldKey), '1150');
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('MUN Centre').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Go here'));
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  expect(c.read(homeSheetProvider), isA<OptionsSheet>());
  expect(c.read(planQueryProvider).to, StopPlace(stopId: '1150', name: 'MUN Centre'));
  expect(c.read(recentPlacesProvider).value!.first, StopPlace(stopId: '1150', name: 'MUN Centre'));
});

testWidgets('See its buses opens the stop sheet', (tester) async { /* same, tap 'See its buses', expect StopSheet('1150') */ });

testWidgets('no location: the destination is set and the start stays empty', (tester) async {
  // default pumpPlannerApp geolocator is LocationOffGeolocator
  // …pick 1150 → Go here…
  expect(c.read(planQueryProvider).from, isNull);
});

testWidgets('with location: the start becomes My location', (tester) async {
  // pumpPlannerApp(geolocator: FixedGeolocator(47.57, -52.73))
  // …pick 1150 → Go here…
  expect(c.read(planQueryProvider).from, isA<PinPlace>().having((p) => p.label, 'label', myLocationLabel));
});

testWidgets('empty query shows Choose on map, saved places and recent; end=from adds My location', (tester) async { … });

testWidgets('save=1 saves a named place as Home', (tester) async {
  // pick 1150, type "Home" in the dialog, choose Home, Save
  expect(c.read(savedPlacesProvider).value!.single.icon, SavedPlaceIcon.home);
});

testWidgets('Choose on map arms the map pick and returns home', (tester) async {
  await tester.tap(find.text('Choose on map'));
  await tester.pumpAndSettle();
  expect(c.read(mapPickProvider), MapPick.to);
  expect(find.byType(HomeScreen), findsOneWidget);
});
```

Write each `…` out in full by copying the first test's lines and changing only the commented parts. Leave no `…` in the file.

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/ui/search_screen_test.dart`
Expected: FAIL (`/search` isn't a route).

- [ ] **Step 3: Implement**

`lib/domain/location/locate_me.dart`:

```dart
import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../trip_planner/place.dart';

/// How long a location fix may take before giving up.
const locateTimeLimit = Duration(seconds: 10);

/// One fix of the phone's position as a "My location" pin, or null when location is off, refused or too slow.
Future<PinPlace?> locateMe() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: locateTimeLimit),
    );
    return PinPlace(lat: p.latitude, lon: p.longitude, label: myLocationLabel);
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
}
```

In `place_picker_sheet.dart`, delete `const locateTimeLimit` and import it from `locate_me.dart`. The picker keeps its own row states (failed or off), so leave `_useMyLocation` as is apart from the import.

`lib/state/map_pick_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which end of the trip the next tap on the map chooses (spec 2026-10-12 §3.3), or null.
enum MapPick { from, to }

class MapPickNotifier extends Notifier<MapPick?> {
  @override
  MapPick? build() => null;
  void start(MapPick end) => state = end;
  void clear() => state = null;
}

final mapPickProvider = NotifierProvider<MapPickNotifier, MapPick?>(MapPickNotifier.new);
```

`lib/ui/search/search_screen.dart`: a `ConsumerStatefulWidget` with a `TextEditingController` and a `BBScaffold` with:
- a `BBTopBar(title: …, onBack: context.pop)`, titled `Choose a start` for `end=from`, `Save a place` for `save=1` and `Where to?` otherwise;
- a `BBTextField(key: SearchScreen.fieldKey, autofocus: true, leadingIcon: BBIcons.search, hint: 'Search for a stop or a place', onChanged: setState)`;
- a `ListView` of rows built with the same `_PickRow` shape as `place_picker_sheet.dart`. Move `_PickRow` into the kit as `BBPickRow` if both files need it: put it in `lib/ui/kit/bb_pick_row.dart` and export it from `kit.dart`.

Rows per the behaviour list above. Paste `matchStops` and `_compareIds` from `place_picker_sheet.dart` into this file unchanged, make `matchStops` public, and import it from here in `place_picker_sheet.dart`. The pick handler:

```dart
Future<void> _pick(Place place) async {
  final end = widget.end;
  final router = GoRouter.of(context);
  if (widget.save) return _saveFlow(place);
  final q = ref.read(planQueryProvider.notifier);
  if (end == MapPick.from) {
    q.setFrom(place);
    router.pop();
    return;
  }
  if (place is StopPlace) {
    final goHere = await BBDialog.show<bool>(
      context,
      title: place.label,
      actions: const [
        BBDialogAction(label: 'See its buses', value: false),
        BBDialogAction(label: 'Go here', value: true, primary: true),
      ],
    );
    if (goHere == null || !mounted) return;
    if (!goHere) {
      ref.read(homeSheetProvider.notifier).open(StopSheet(place.stopId));
      router.pop();
      return;
    }
  }
  await ref.read(recentPlacesProvider.notifier).push(place);
  q.setDestination(place);
  if (ref.read(planQueryProvider).from == null) {
    final here = await locateMe();
    if (here != null) q.setFrom(here);
  }
  ref.read(homeSheetProvider.notifier).open(const OptionsSheet());
  if (mounted) router.pop();
}
```

`_saveFlow(place)` shows a `BBDialog` whose content is a `BBTextField` (prefilled with `place.label`, max 40 characters as in `savedTripNameMax`) and a `BBSegmented<SavedPlaceIcon>` with Home / Work / School / Star. Check whether `BBDialog.show` takes a content widget (`grep -n "static Future<T?> show" -A12 lib/ui/kit/bb_dialog.dart`). If it doesn't, use `showGeneralDialog` with a card, as `saved_trips_section.dart`'s `_editTrip` does for renaming, and copy that function's structure. On Save, it does `savedPlaces.put(SavedPlace(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name.trim().isEmpty ? place.label : name.trim(), icon: icon, place: place))`, then `router.pop()`.

Add to the router:

```dart
GoRoute(
  path: '/search',
  builder: (context, state) => SearchScreen(
    end: state.uri.queryParameters['end'] == 'from' ? MapPick.from : MapPick.to,
    save: state.uri.queryParameters['save'] == '1',
  ),
),
```

- [ ] **Step 4: Run the tests**

Run: `flutter analyze && flutter test test/ui/search_screen_test.dart test/ui/plan_screen_test.dart test/ui/home_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "feat(home): Where to? search for stops, saved places and recent destinations

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Trip options and a journey's steps in the sheet; picking on the map

**Files:**
- Create: `lib/ui/home/options_sheet.dart`, `lib/ui/home/journey_sheet.dart`
- Modify: `lib/ui/home/sheet_content.dart` (`OptionsSheet` and `JourneySheet` cases), `lib/ui/home/home_screen.dart` (pick from `mapPickProvider`, drop the `pick` parameter; journey drawing), `lib/ui/trip_planner/map_plan_sheet.dart` (long-press opens options or search, not `/plan`)
- Delete: `lib/ui/trip_planner/plan_screen.dart`, `lib/ui/trip_planner/journey_detail_screen.dart`. Move their tests: `test/ui/plan_screen_test.dart` → `test/ui/options_sheet_test.dart` (`git mv`, adapt) and `test/ui/journey_detail_test.dart` → keep the file name, adapt to the sheet. `test/routing/plan_route_test.dart` now checks the `/plan` and `/plan/journey` redirects to home.

**Interfaces:**
- Consumes: `planQueryProvider`, `planResultsProvider`, `planDefaultTimeProvider`, `plannerClockProvider`, `JourneyCard`, `SavedTripsSection`'s save rules (`savedTripsProvider.notifier.add`), `journeyOnMapProvider`, `homeSheetProvider`, `mapPickProvider`, `mapPlaceAt`.
- Produces:
  - `abstract final class OptionsSheetContent { static Widget header(); static List<Widget> slivers(); static const fromRowKey = ValueKey('plan-from'); static const toRowKey = ValueKey('plan-to'); static const timeButtonKey = ValueKey('plan-time'); static const dateButtonKey = ValueKey('plan-date'); }`. The keys keep the old `PlanScreen` key values, so the moved tests' finders keep working after `PlanScreen.` → `OptionsSheetContent.`.
  - `abstract final class JourneySheetContent { static Widget header(Journey j); static Widget body(Journey j); }`
- Behaviour (spec §3.4):
  - **Options header:**
    - a back button (`homeSheet.back()`, label `Back`);
    - `To <place.label>` as the title;
    - the **From** row: tapping it pushes `/search?end=from`, and "Choose a start" shows when it's empty;
    - the swap button;
    - the Leave now / Leave by / Arrive by segmented control, plus the time and date buttons.

    All of this is moved verbatim from `PlanScreen.build`: the `BBCard` content without its `To` row (the title shows the destination; tapping the title pushes `/search` to change it).
  - **Options body:** today's `_results` slivers unchanged, except that a card tap calls `journeyOnMap.show(j)` and then `homeSheet.open(JourneySheet(j))`. The first `PlanFound` journey is drawn on the map as soon as results arrive (`ref.listen(planResultsProvider, …)` → `journeyOnMap.show(journeys.first)` when nothing is selected yet).
  - **Journey header:**
    - a back button (`homeSheet.back()`);
    - `Your trip`;
    - `Leave HH:MM · arrive HH:MM`.
  - **Journey body:** today's `JourneyDetailScreen` content (broken warning, timeline card, first-ride actions with Follow and the bell, Save trip) without the `BBScaffold`, the top bar and "Show on map" (it's already on the map). Follow does `homeSheet.home()` and then `follow(vehicle)`, instead of `context.go('/map')`.
  - **Leaving the trip:** back from options to home clears `journeyOnMapProvider`. Back from a journey to options shows the first journey again.
  - **Map pick:** while `mapPickProvider` is not null, home shows today's pick banner. Its text comes from the provider, and Cancel calls `mapPick.clear()`. The next map tap sets that end (`mapPlaceAt`), clears the pick and opens `OptionsSheet` (for `to`) or keeps the current sheet (for `from`).
  - **Long-press menu:**
    - "Plan from here" → `setFrom(place)`, then `context.push('/search')`;
    - "Plan to here" → `setDestination(place)`, `locateMe()` for a null start, then `open(OptionsSheet())`.

- [ ] **Step 1: Move and adapt the planner tests**

```bash
git mv test/ui/plan_screen_test.dart test/ui/options_sheet_test.dart
```

In `options_sheet_test.dart`, keep every assertion about results, modes, times, dates, the "too far" and "no journey" copy, saved trips and live refreshes. Change how the form is reached. Instead of `pumpPlannerApp(initial: '/plan')` and tapping the From and To rows to open the place picker, set the draft directly, then open options:

```dart
final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
c.read(planQueryProvider.notifier).setTrip(from, to);
c.read(homeSheetProvider.notifier).open(const OptionsSheet());
await tester.pumpAndSettle();
await tester.drag(find.bySemanticsLabel('Map sheet'), const Offset(0, -600));
await tester.pumpAndSettle();
```

Tests that exercised the place picker for the From row keep using it: the From row still opens `/search?end=from`, so drive the search screen as `search_screen_test.dart` does. Replace `PlanScreen.fromRowKey` with `OptionsSheetContent.fromRowKey`, and the same for the other keys. Delete assertions about the To row's picker; the To end changes through the title (one new test: tapping the title opens `/search`).

Adapt `test/ui/journey_detail_test.dart` the same way: open `JourneySheet(j)` through the provider and keep the assertions about the steps, the broken warning, Follow, the bell and Save trip. Its "Show on map" test becomes "the journey is drawn when its sheet opens" (`journeyOnMapProvider` is that journey).

Add:

```dart
testWidgets('back from a journey returns to options, and back again clears the map and goes home', (tester) async {
  // open options with a found journey (same setup as the first results test above), tap the first JourneyCard
  final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  expect(c.read(homeSheetProvider), isA<JourneySheet>());
  await tester.tap(find.bySemanticsLabel('Back').first);
  await tester.pumpAndSettle();
  expect(c.read(homeSheetProvider), isA<OptionsSheet>());
  await tester.tap(find.bySemanticsLabel('Back').first);
  await tester.pumpAndSettle();
  expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
  expect(c.read(journeyOnMapProvider), isNull);
});

testWidgets('choosing the destination on the map', (tester) async {
  final map = StubMap();
  await pumpPlannerApp(tester, net: TestNetwork.standard(), now: now, initial: '/', mapView: map.build);
  final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  c.read(mapPickProvider.notifier).start(MapPick.to);
  await tester.pumpAndSettle();
  expect(find.text('Tap the map to choose your destination'), findsOneWidget);
  map.tap(47.5735, -52.7334); // next to stop 1150 in the test network; use a coordinate of a stop it has
  await tester.pumpAndSettle();
  expect(c.read(mapPickProvider), isNull);
  expect(c.read(homeSheetProvider), isA<OptionsSheet>());
  expect(c.read(planQueryProvider).to, isA<StopPlace>());
});
```

Replace the first test's comment with the literal setup from the moved "shows results" test.

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/ui/options_sheet_test.dart test/ui/journey_detail_test.dart`
Expected: FAIL (`OptionsSheetContent` and `JourneySheetContent` don't exist).

- [ ] **Step 3: Implement the two sheets by moving code**

`lib/ui/home/options_sheet.dart`:
- Move `_PlanScreenState`'s fields and methods (`_formChanged`, `_pick`, `_pickTime`, `_pickDate`, `_results`) and the `_EndRow` and `_FieldButton` classes from `plan_screen.dart` into a `ConsumerStatefulWidget` named `_OptionsBody`, whose `build` returns a `Column` of the form card's **When** part plus the result cards:
  - `_results` currently returns slivers; make it return plain widgets: `box(x)` → `x`, and `SliverList.separated` → a `Column` with `SizedBox(height: BBSpace.s)` between `JourneyCard`s;
  - the `JourneyCard.onTap` body becomes `{ ref.read(journeyOnMapProvider.notifier).show(journeys[i]); ref.read(homeSheetProvider.notifier).open(JourneySheet(journeys[i])); }`;
  - `_pick(forFrom: true)` becomes `context.push('/search?end=from')`.
- `header()` is a `Row`:
  - `BBIconButton(icon: BBIcons.back, semanticLabel: 'Back', onPressed: …)`, which does `journeyOnMap.clear()` and then `homeSheet.back()`;
  - an `Expanded(BBPressable(semanticLabel: 'Destination, <label>. Change', onTap: () => context.push('/search'), child: Text('To <label>', style: bb.text.headline)))`;
  - below the row, the `From` `_EndRow` (key `OptionsSheetContent.fromRowKey`) and the swap button. These are the same widgets `PlanScreen` used.
- `slivers()` returns `[SliverToBoxAdapter(child: _OptionsBody())]`.
- Inside `_OptionsBody.build`, draw the first journey when results come in:
  ```dart
  ref.listen<AsyncValue<PlanOutcome?>>(planResultsProvider, (_, next) {
    final found = next.value;
    if (found is PlanFound && found.journeys.isNotEmpty && ref.read(homeSheetProvider) is OptionsSheet) {
      ref.read(journeyOnMapProvider.notifier).show(found.journeys.first);
    }
  });
  ```
  Below the results, add a ★ **Save trip** button for the draft's ends. Move the save logic from `JourneyDetailScreen._save` (lines ~115–130: `savedTripsProvider.notifier.add(SavedTrip(id: …, name: …, from: from, to: to))` and its toast) into a top-level function `Future<void> saveTrip(BuildContext context, WidgetRef ref, Place from, Place to)` in `options_sheet.dart`. Both sheets call it.

`lib/ui/home/journey_sheet.dart`:
- Move `JourneyDetailScreen`, its state class and the private widgets (`_BrokenWarning`, `_TimelineRow`, `_WalkRow`, `_RideRow`, `_FirstRideActions`, `_stopName`, `_stopLabel`, `brokenByLiveTimes`) unchanged.
- Rename the screen `_JourneyBody`, and change its `build` to return the `Column` that was inside the `ListView`, without the `BBTopBar`, the "Show on map" button and the bottom `SizedBox`.
- In `_FirstRideActions._follow`, replace `context.go('/map')` with `ref.read(homeSheetProvider.notifier).home();`. Keep the `follow` call before it.
- `header(j)` is a `Row`:
  - `BBIconButton(icon: BBIcons.back, semanticLabel: 'Back', onPressed: …)`, which calls `homeSheet.back()`;
  - `Column(Text('Your trip', style: bb.text.headline), Text('Leave … · arrive …', style: bb.text.caption))`.

  The subtitle needs the live-overlaid times. Compute them the same way `_JourneyBody` does (`overlayLive(widget.journey, feed, now)` when the feed succeeded), in a small `ConsumerWidget` `_JourneyHeader`.

In `sheet_content.dart`:
- `OptionsSheet()` maps to `OptionsSheetContent.header()` for the header and `OptionsSheetContent.slivers()` for the body. `selectionBody` returns a single widget today; change the function to return `List<Widget> slivers` and update `home_screen.dart`'s `slivers: [SliverToBoxAdapter(child: selectionBody(...))]` to `slivers: selectionSlivers(...)`. The other cases wrap their widget in a `SliverToBoxAdapter`.
- `JourneySheet(:final journey)` maps to `JourneySheetContent.header(journey)` and `[SliverToBoxAdapter(child: JourneySheetContent.body(journey))]`.

In `home_screen.dart`:
- remove the `pick` constructor parameter and `_pickFrom`;
- `final pick = ref.watch(mapPickProvider);`;
- the banner shows when `pick != null`, with `_pickBanner(pick == MapPick.from)` and `cancel` = `ref.read(mapPickProvider.notifier).clear()`;
- in `_onTap`, `final pick = ref.read(mapPickProvider); if (pick != null) return _finishPick(pick == MapPick.from, tap);`;
- `_finishPick` sets the end and calls `ref.read(mapPickProvider.notifier).clear()`. For the destination it also calls `homeSheet.open(OptionsSheet())`, and if the start is null, `unawaited(locateMe().then((p) { if (p != null && mounted) q.setFrom(p); }))`;
- remove `context.go('/plan')` there.

The router's `HomeScreen(pick: …)` call becomes `const HomeScreen()`.

In `map_plan_sheet.dart`, the end of `showMapPlanSheet` becomes:

```dart
final q = ref.read(planQueryProvider.notifier);
if (fromHere) {
  q.setFrom(place);
  await GoRouter.of(context).push('/search');
} else {
  q.setDestination(place);
  ref.read(homeSheetProvider.notifier).open(const OptionsSheet());
  if (ref.read(planQueryProvider).from == null) {
    final here = await locateMe();
    if (here != null) q.setFrom(here);
  }
}
```

Delete the old screens:

```bash
git rm lib/ui/trip_planner/plan_screen.dart lib/ui/trip_planner/journey_detail_screen.dart
```

`test/routing/plan_route_test.dart`: replace its body with two tests. `/plan` and `/plan/journey` (with and without `extra`) both land on `HomeScreen` with `HomeSheetHome`.

- [ ] **Step 4: Run all tests**

Run: `flutter analyze && flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "feat(home): trip options and journey steps in the sheet, picking on the map without leaving home

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Tablets: the sheet becomes a left panel

**Files:**
- Modify: `lib/ui/home/home_screen.dart`
- Test: `test/ui/home_tablet_test.dart`

**Interfaces:**
- Consumes: the same `selectionHeader` and `selectionSlivers` (T2, T8).
- Produces: `const homeSidePanelBreakpoint = 700.0` and `const homeSidePanelWidth = 400.0` in `home_screen.dart`. At widths ≥ 700 the content is a fixed left panel (`Positioned(left: BBSpace.s, top: media.padding.top + BBSpace.s, bottom: media.padding.bottom + BBSpace.s, width: 400)`) with `bb.floating(radius: BBRadius.sheet)`, holding a `CustomScrollView(slivers: [SliverToBoxAdapter(child: header), ...slivers])`. There's no `BBSheet` and no detents, and the map's controls and fit padding shift right by 400 + `BBSpace.s`.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('at 1024×768 the sheet is a left panel and the map controls sit to its right', (tester) async {
  tester.view.physicalSize = const Size(1024, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpPlannerApp(tester, net: TestNetwork.standard(), now: now, initial: '/');
  expect(find.byType(BBSheet), findsNothing);
  final panel = tester.getRect(find.byKey(const ValueKey('home-side-panel')));
  expect(panel.left, lessThan(20));
  expect(panel.width, homeSidePanelWidth);
  expect(find.byKey(HomeSheetContent.whereToKey), findsOneWidget);
  expect(tester.getRect(find.bySemanticsLabel('Settings')).left, greaterThan(panel.right));
});

testWidgets('at 390 wide it is the pull-up sheet', (tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpPlannerApp(tester, net: TestNetwork.standard(), now: now, initial: '/');
  expect(find.byType(BBSheet), findsOneWidget);
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/ui/home_tablet_test.dart`. Expected: FAIL (a `BBSheet` is found).

- [ ] **Step 3: Implement**

In the `LayoutBuilder` builder:
- `final wide = constraints.maxWidth >= homeSidePanelBreakpoint;`;
- `final panelInset = wide ? homeSidePanelWidth + BBSpace.s : 0.0;`;
- for the top controls' `Positioned`, set `left: BBSpace.s + panelInset`;
- `_fitPadding`'s left becomes `_fitMargin + panelInset`, and its bottom is `_fitMargin` when wide;
- the credit's `left` becomes `_creditLeft + panelInset`, and its `bottom` is `media.padding.bottom + BBSpace.s` when wide;
- replace the `Positioned.fill(child: BBSheet(...))` with `wide ? Positioned(key: const ValueKey('home-side-panel'), …panel…) : Positioned.fill(child: BBSheet(...))`.

The panel's header and slivers are the same expressions the sheet uses. The header-measure and peek logic only runs when not wide: keep `_scheduleHeaderMeasure()` and only use `peek` in the narrow branch.

- [ ] **Step 4: Run tests**

Run: `flutter analyze && flutter test test/ui/home_tablet_test.dart test/ui/home_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home/home_screen.dart test/ui/home_tablet_test.dart
git commit -m "feat(home): on tablets the sheet is a left panel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: The one-time tip

**Files:**
- Create: `lib/ui/home/home_tip.dart`
- Modify: `lib/ui/home/home_sheet.dart` (the tip sits at the top of the header, above "Where to?")
- Test: add to `test/ui/home_sheet_test.dart`

**Interfaces:**
- Produces:
  ```dart
  final homeTipSeenProvider = AsyncNotifierProvider<HomeTipSeenNotifier, bool>(HomeTipSeenNotifier.new); // dismiss()
  class HomeTip extends ConsumerWidget // renders nothing once seen
  ```
  It's stored in `SharedPreferencesAsync` under `home_tip_seen.v1` (bool). Text, verbatim from the spec: `Everything's on the map now: tap "Where to?" to plan, tap a stop for its buses, and the bell is your alerts.` The dismiss button is labelled `Got it`.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('the tip shows once and stays dismissed', (tester) async {
  await pumpPlannerApp(tester, net: TestNetwork.standard(), now: now, initial: '/');
  expect(find.textContaining("Everything's on the map now"), findsOneWidget);
  await tester.tap(find.text('Got it'));
  await tester.pumpAndSettle();
  expect(find.textContaining("Everything's on the map now"), findsNothing);
  expect(await SharedPreferencesAsync().getBool('home_tip_seen.v1'), isTrue);
});

testWidgets('a seen tip never shows', (tester) async {
  // pumpPlannerApp resets prefs; set the flag through an override instead:
  await pumpPlannerApp(tester, net: TestNetwork.standard(), now: now, initial: '/',
      overrides: [homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen())]);
  expect(find.textContaining("Everything's on the map now"), findsNothing);
});
```

The other `home_sheet_test.dart` tests run with the tip shown. If the tip pushes something below the fold that a test needs, add the same `homeTipSeenProvider` override to that test.

- [ ] **Step 2: Implement**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kit/kit.dart';

const _key = 'home_tip_seen.v1';
const homeTipText =
    'Everything\'s on the map now: tap "Where to?" to plan, tap a stop for its buses, and the bell is your alerts.';

class HomeTipSeenNotifier extends AsyncNotifier<bool> {
  HomeTipSeenNotifier();

  /// Already seen, for tests.
  factory HomeTipSeenNotifier.seen() = _Seen;

  @override
  Future<bool> build() async => await SharedPreferencesAsync().getBool(_key) ?? false;

  Future<void> dismiss() async {
    state = const AsyncData(true);
    await SharedPreferencesAsync().setBool(_key, true);
  }
}

class _Seen extends HomeTipSeenNotifier {
  @override
  Future<bool> build() async => true;
}

final homeTipSeenProvider = AsyncNotifierProvider<HomeTipSeenNotifier, bool>(HomeTipSeenNotifier.new);

/// The one-time "everything moved" tip (spec 2026-10-12 §3.7).
class HomeTip extends ConsumerWidget {
  const HomeTip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(homeTipSeenProvider).value != false) return const SizedBox.shrink();
    final bb = context.bb;
    return Padding(
      padding: const EdgeInsets.only(bottom: BBSpace.s),
      child: DecoratedBox(
        decoration: bb.card(),
        child: Padding(
          padding: const EdgeInsets.all(BBSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(liveRegion: true, child: Text(homeTipText, style: bb.text.body)),
              Align(
                alignment: Alignment.centerRight,
                child: BBButton(
                  label: 'Got it',
                  kind: BBButtonKind.quiet,
                  onPressed: () => ref.read(homeTipSeenProvider.notifier).dismiss(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

In `home_sheet.dart`'s `_Header`, make `const HomeTip()` the first child of the `Column`.

- [ ] **Step 3: Run tests**

Run: `flutter analyze && flutter test test/ui/home_sheet_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/home/home_tip.dart lib/ui/home/home_sheet.dart test/ui/home_sheet_test.dart
git commit -m "feat(home): a one-time tip that everything moved onto the map

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Clean-up, goldens, and the device check

**Files:**
- Modify: `lib/ui/kit/bb_nav_bar.dart` and `lib/ui/kit/kit.dart` (remove `BBNavBar`, `BBNavItem` and `BBNavBarScope` when `grep -rn "BBNavBar\|BBNavItem\|BBNavBarScope" lib` shows nothing outside the kit), `test/kit/nav_bar_test.dart` and `test/kit/kit_golden_test.dart` (drop the nav-bar cases)
- Modify: `test/ui/screen_golden_test.dart` (replace the Board and Plan goldens with home peek, stop sheet and options, in light and dark), `test/ui/screen_overflow_test.dart` (the stop sheet and options at 2× text, 360×640)
- Modify: `store/release-notes/1.5.0-draft.md` (new: one paragraph listing what moved, for the 1.5 notes)

- [ ] **Step 1: Remove the dead kit pieces**

Run `grep -rn "BBNavBar\|BBNavItem\|BBNavBarScope\|reservedHeight" lib test`. Every remaining use outside `lib/ui/kit/bb_nav_bar.dart` and its tests must go: replace the bottom padding with `MediaQuery.paddingOf(context).bottom + BBSpace.l`. Then:

```bash
git rm lib/ui/kit/bb_nav_bar.dart test/kit/nav_bar_test.dart
```

Remove its export from `lib/ui/kit/kit.dart` and its cases from `test/kit/kit_golden_test.dart`. Regenerate kit goldens with `flutter test --update-goldens test/kit/kit_golden_test.dart`, and **look at every changed PNG** before committing.

- [ ] **Step 2: Screen goldens and overflow**

In `screen_golden_test.dart`, delete the Board and Plan golden cases. Add these, light and dark, using the file's existing pump and golden helpers:
- `home_peek`: stop 1150 selected, one saved place, one alert;
- `stop_sheet`: `/board/1150`, sheet at full;
- `options`: the MUN Centre → Avalon Mall draft, sheet at half.

Run `flutter test --update-goldens test/ui/screen_golden_test.dart`, open each new PNG, and check:
- no overflow stripes;
- the sheet header readable;
- the bell badge visible.

In `screen_overflow_test.dart`, add the stop sheet and options at text scale 2.0 on 360×640, light and dark.

- [ ] **Step 3: Full suite**

Run: `flutter analyze && flutter test`
Expected: no issues, all PASS.

- [ ] **Step 4: Device check (Android emulator and iOS simulator)**

Build and run a debug build:
- **Android:** `flutter run -d emulator-5554`, only with the user's OK, because that emulator is the user's. Otherwise use a temporary AVD as in the tablet-screenshot task.
- **iOS:** an iPhone simulator.

Walk through these and note each result in the PR description:
1. **Cold start:** the sheet is at peek, with "Where to?", chips, alerts and your stop's next buses visible with no taps.
2. **First tip:** the tip shows once; "Got it" hides it; a restart doesn't show it again.
3. **Stop sheet:** tap a stop on the map. The stop sheet opens at half, with live rows and the bell. ★ makes it your stop. Back (Android button, or swipe down) returns home.
4. **Follow from a stop:** tap a live row. The bus is followed and the chip shows. Open another stop: its sheet shows, and back returns to the follow card.
5. **Trip from search:** "Where to?" → type `1600` → Go here. Options appear, the first journey is drawn, and tapping a card shows its steps. Follow bus works, and ★ Save trip saves it. Back → options → home, and the drawn trip is gone.
6. **Saved trip:** the saved trip's card on home opens its options.
7. **Long-press menu:** "Plan to here" opens options with "My location" as the start when location is on.
8. **Arrival-alert notification:** set an alert on the stop sheet, background the app, and tap the notification. The app opens on that stop's sheet.
9. **Alerts and Settings:** the bell opens Alerts and back returns; the gear opens Settings.
10. **Accessibility:** with TalkBack (Android) or VoiceOver (iOS), every control above is reachable and announced.
11. **2× text:** at 2× text on a small phone, the peek has no clipping.

- [ ] **Step 5: Release-notes draft**

Create `store/release-notes/1.5.0-draft.md`:

```markdown
# 1.5.0 draft

## What's new (both stores)
- Everything is on one map now: "Where to?" at the top of the sheet, your stop's next buses right under it, no tabs.
- Tap any stop for its live departures, the bell and Follow, right on the map.
- Save places like Home and Work and plan to them in one tap.
- Alerts that affect your stop or your saved trips show on the home screen.
- On tablets, everything sits in a side panel next to the map.
```

- [ ] **Step 6: Commit**

```bash
git add -A lib test store/release-notes/1.5.0-draft.md
git commit -m "chore(home): remove the tab bar from the kit, new screen goldens, 1.5.0 notes draft

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-review notes (author)

- **Spec coverage:**

  | Spec section | Covered by |
  |---|---|
  | §3.1 home | T4 (buttons), T5 (sheet), T10 (tip) |
  | §3.2 stop sheet | T6 |
  | §3.3 search | T7 |
  | §3.4 options and journey | T8 |
  | §3.5 saved places | T3 (store), T5 (chips), T7 (`save=1` flow) |
  | §3.6 old links and what moved | T4 (routes), T5–T8 (the moved screens), T11 (nav bar) |
  | §3.7 tip | T10 |
  | §4.1 navigation | T2, T4 |
  | §4.2 reuse and split | T1, T5–T8 |
  | §4.3 data | T3 |
  | §4.4 edge cases | T5 (no stop), T7 (no location), T9 (tablet) |
  | §4.5 tests | every task, plus T11 goldens and the device check |
  | §5 done | T11 step 3 |

- **Deviations from the spec, recorded:**
  - The stop sheet has no pull-to-refresh, because the sheet owns the drag. A refresh button replaces it (T6).
  - "Go from here" waits for P3, so P1 has "Plan a trip from here" (T6).
  - A saved-place chip's long-press offers Remove only in P1; Rename is re-saving through `save=1` (T5, T7).
  - The follow card shows only over home, and other sheets cover it until back (T2). That gives Review Focus 3.
- **Type consistency:**
  - `HomeSheet` subclasses, `homeSheetProvider`, `OptionsSheet` and `JourneySheet(journey)` are the same names in T2, T4–T8.
  - `setDestination(Place)` is added in T5 and used in T7 and T8.
  - `selectionSlivers` replaces `selectionBody` in T8, and T9 uses the T8 name.
  - `MapPick` and `mapPickProvider` are created in T7 and used in T8.
  - `locateMe` is created in T7 and used in T7 and T8.
