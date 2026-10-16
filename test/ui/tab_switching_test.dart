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
import 'package:flutter/widgets.dart' show ValueKey;
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

  testWidgets('a switch to the Map at an action is said to screen readers; one already on the Map is not (M4)',
      (tester) async {
    await _pumpOnBoard(tester);
    tester.takeAnnouncements();
    await tester.tap(find.byType(ArrivalRowTile).first);
    await tester.pumpAndSettle();
    _expectMap(tester);
    expect(tester.takeAnnouncements(), [isAccessibilityAnnouncement('Map tab')]);
    // Asked for again on the Map (the same bus): nothing changes for the rider, so nothing is said.
    _c(tester).read(followProvider.notifier).follow('2573');
    await tester.pumpAndSettle();
    expect(tester.takeAnnouncements(), isEmpty);
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
    // The stop it replaced keeps a chip, as the most recent stop (final review M1).
    expect(find.byKey(const ValueKey('board-chip-recent-C')), findsOneWidget);
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

  group('asking again for what is already set still switches to the Map (fix round 1)', () {
    testWidgets('Where to? on the Board while trip options are already open on the hidden map', (tester) async {
      await _pumpOnBoard(tester);
      final c = _c(tester);
      c.read(homeSheetProvider.notifier).open(const OptionsSheet());
      c.read(homeTabProvider.notifier).select(HomeTab.board);
      await tester.pumpAndSettle();
      expect(find.byType(BoardTab), findsOneWidget, reason: 'back on the Board, the options still open');
      await tester.tap(find.byKey(BoardTab.whereToKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(SearchScreen.fieldKey), '1150');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('MUN Centre').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go here'));
      await tester.pumpAndSettle();
      _expectMap(tester);
      expect(c.read(homeSheetProvider), isA<OptionsSheet>());
    });

    testWidgets('Plan a trip from here on the Board while trip options are already open', (tester) async {
      await _pumpOnBoard(tester);
      final c = _c(tester);
      c.read(homeSheetProvider.notifier).open(const OptionsSheet());
      c.read(homeTabProvider.notifier).select(HomeTab.board);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(StopSheetContent.planFromKey));
      await tester.tap(find.byKey(StopSheetContent.planFromKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(SearchScreen.fieldKey), '1150');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('MUN Centre').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go here'));
      await tester.pumpAndSettle();
      _expectMap(tester);
    });

    testWidgets('Follow on the Board for the bus already followed', (tester) async {
      await _pumpOnBoard(tester);
      final c = _c(tester);
      c.read(followProvider.notifier).follow('2573');
      c.read(homeTabProvider.notifier).select(HomeTab.board);
      await tester.pumpAndSettle();
      expect(find.byType(BoardTab), findsOneWidget);
      await tester.tap(find.byType(ArrivalRowTile).first);
      await tester.pumpAndSettle();
      _expectMap(tester);
      expect(c.read(followProvider)?.vehicleId, '2573');
    });

    testWidgets('Choose on map from the Board while a pick is already pending', (tester) async {
      await _pumpOnBoard(tester);
      final c = _c(tester);
      c.read(mapPickProvider.notifier).start(MapPick.to);
      c.read(homeTabProvider.notifier).select(HomeTab.board);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(BoardTab.whereToKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose on map'));
      await tester.pumpAndSettle();
      _expectMap(tester);
      expect(c.read(mapPickProvider), MapPick.to);
    });
  });

  group('a stop the schedule does not know does not show an empty Board (fix round 1)', () {
    testWidgets('a /board/ link to it leaves the Board on your stop', (tester) async {
      await pumpPlannerApp(tester,
          net: _network(),
          now: _now,
          initial: '/board/9999',
          overrides: [
            settingsProvider.overrideWith(_StopC.new),
            stopArrivalsProvider.overrideWith((ref, id) async => [_row(4)]),
          ]);
      _expectBoardOn(tester, 'C');
      expect(find.text('STOP 9999'), findsNothing);
      expect(_c(tester).read(boardStopProvider), isNull);
    });

    testWidgets('a notification for it, while the Board shows another stop, leaves that stop', (tester) async {
      await _pumpOnBoard(tester, tab: HomeTab.map);
      _c(tester).read(homeTabProvider.notifier).showBoard('B');
      await tester.pumpAndSettle();
      _expectBoardOn(tester, 'B');
      openNotificationRoute('/board/9999', GoRouter.of(routerElement(tester)).go);
      await tester.pumpAndSettle();
      _expectBoardOn(tester, 'B');
      expect(find.text('STOP 9999'), findsNothing);
    });
  });
}
