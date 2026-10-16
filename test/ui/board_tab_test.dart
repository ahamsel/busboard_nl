import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
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
import '../helpers/planner_app.dart';
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

  testWidgets('a stop that is not in the schedule (a removed stop left in the recents) has no chip', (tester) async {
    await _pumpBoard(tester, recent: ['GONE', 'B']);
    expect(_chipOrder(tester),
        ['board-chip-yours-A', 'board-chip-recent-B', 'board-chip-near-me', 'board-chip-find-stop']);
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

  group('the whole app, with the real departures', () {
    testWidgets('at a cold start, while the schedule loads, the Board is loading, not "No upcoming departures" (I1)',
        (tester) async {
      await pumpPlannerApp(
        tester,
        net: TestNetwork(),
        now: DateTime(2026, 10, 7, 13, 0),
        tab: HomeTab.board,
        repoFuture: Completer<GtfsRepository>().future,
        settle: false,
        overrides: [settingsProvider.overrideWith(() => _Settings('C'))],
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('STOP C'), findsOneWidget, reason: 'your stop shows at once');
      expect(find.text('No upcoming departures'), findsNothing);
      expect(find.text('Showing schedule'), findsNothing, reason: 'nor is that announced');
      expect(find.text('Checking live data…'), findsOneWidget);
      expect(find.descendant(of: find.byType(BoardTab), matching: find.byType(BBSkeleton)), findsOneWidget);
    });
  });
}
