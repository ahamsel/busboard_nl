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
