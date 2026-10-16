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
