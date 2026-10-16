import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/board/arrival_board_screen.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/shell/top_actions.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';

import '../kit/kit_test_helpers.dart';
import '../helpers/fake_alerts.dart';
import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

final _failing = MockClient((_) async => http.Response('down', 500));
final _emptyKiosk = MockClient((_) async => http.Response('{"arrivals":[]}', 200));

/// Serves one vehicle on the GTFS-Realtime positions endpoint so the live
/// feed counts as available; everything else fails (they are optional).
final _liveFeed = MockClient((request) async {
  if (request.url.path.endsWith('vehiclepositions')) {
    final feed = FeedMessage(
      header: FeedHeader(gtfsRealtimeVersion: '2.0'),
      entity: [
        FeedEntity(
          id: 'vehicle-0859',
          vehicle: VehiclePosition(
            trip: TripDescriptor(tripId: 'trip-20', routeId: '20'),
            position: Position(latitude: 47.53, longitude: -52.75),
            timestamp: Int64(DateTime.now().millisecondsSinceEpoch ~/ 1000),
            vehicle: VehicleDescriptor(id: '0859'),
          ),
        ),
      ],
    );
    return http.Response.bytes(feed.writeToBuffer(), 200);
  }
  return http.Response('down', 500);
});

/// Same feed as [_liveFeed] but for vehicle 2573 on trip-20.
final _liveFeed2573 = MockClient((request) async {
  if (request.url.path.endsWith('vehiclepositions')) {
    final feed = FeedMessage(
      header: FeedHeader(gtfsRealtimeVersion: '2.0'),
      entity: [
        FeedEntity(
          id: 'vehicle-2573',
          vehicle: VehiclePosition(
            trip: TripDescriptor(tripId: 'trip-20', routeId: '20'),
            position: Position(latitude: 47.53, longitude: -52.75),
            timestamp: Int64(DateTime.now().millisecondsSinceEpoch ~/ 1000),
            vehicle: VehicleDescriptor(id: '2573'),
          ),
        ),
      ],
    );
    return http.Response.bytes(feed.writeToBuffer(), 200);
  }
  return http.Response('down', 500);
});

String _clock(int seconds) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(seconds ~/ 3600)}:${two(seconds % 3600 ~/ 60)}:${two(seconds % 60)}';
}

/// A hand-filled repository has no loader to flip the loaded flag.
/// The stop-prediction feed, counting the stops asked for.
class _CountingMobile extends MetrobusMobileApi {
  final asked = <String>[];
  @override
  Future<MetrobusDeparturesResult> fetchDeparturesResult(String stopId, {bool forceRefresh = false}) async {
    asked.add(stopId);
    return MetrobusDeparturesResult.failure();
  }
}

class _LoadedRepository extends GtfsRepository {
  @override
  bool get isLoaded => true;
}

/// MUN Centre with two departures a few minutes out: route 20 on trip-20
/// (the live vehicle's trip) and route 21 on trip-21 (nothing live).
GtfsRepository _repoWithDepartures() {
  final now = DateTime.now();
  final nowSeconds = now.hour * 3600 + now.minute * 60;
  final repo = _LoadedRepository()
    ..stopsById['1150'] = const StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 0, stopLon: 0);
  repo.calendarsById['daily'] = ServiceCalendar(
    serviceId: 'daily',
    monday: true,
    tuesday: true,
    wednesday: true,
    thursday: true,
    friday: true,
    saturday: true,
    sunday: true,
    startDate: DateTime(2000),
    endDate: DateTime(2100),
  );
  for (final (route, trip, headsign, offset) in [
    ('20', 'trip-20', 'Live Terminal', 600),
    ('21', 'trip-21', 'Schedule Terminal', 900),
  ]) {
    repo.routesById[route] = RouteInfo(routeId: route, routeShortName: route, routeLongName: route);
    repo.tripsById[trip] = TripInfo(tripId: trip, routeId: route, serviceId: 'daily', tripHeadsign: headsign, directionId: 0);
    repo.stopTimesByStopId['1150'] = [
      ...?repo.stopTimesByStopId['1150'],
      StopTimeRow(
        tripId: trip,
        arrivalTime: _clock(nowSeconds + offset),
        departureTime: _clock(nowSeconds + offset),
        stopId: '1150',
        stopSequence: 5,
      ),
    ];
  }
  return repo;
}

ServiceAlert _alert(String header) => ServiceAlert(
      sourceIds: {header},
      header: header,
      description: '',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: const [],
      targets: const [ServiceAlertTarget(stopId: '1150')],
    );

/// MUN Centre whose service starts [daysAhead] days from today, so nothing is due today: its first bus leaves at 06:30
/// that day, and a later one at 17:00.
GtfsRepository _repoStartingIn(int daysAhead) {
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day + daysAhead);
  final repo = _LoadedRepository()
    ..stopsById['1150'] = const StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 0, stopLon: 0)
    ..routesById['20'] = const RouteInfo(routeId: '20', routeShortName: '20', routeLongName: '20')
    ..calendarsById['later'] = ServiceCalendar(
      serviceId: 'later',
      monday: true,
      tuesday: true,
      wednesday: true,
      thursday: true,
      friday: true,
      saturday: true,
      sunday: true,
      startDate: start,
      endDate: DateTime(2100),
    );
  for (final (trip, time) in [('am', '06:30:00'), ('pm', '17:00:00')]) {
    repo.tripsById[trip] =
        TripInfo(tripId: trip, routeId: '20', serviceId: 'later', tripHeadsign: 'Downtown', directionId: 0);
    repo.stopTimesByStopId['1150'] = [
      ...?repo.stopTimesByStopId['1150'],
      StopTimeRow(tripId: trip, arrivalTime: time, departureTime: time, stopId: '1150', stopSequence: 1),
    ];
  }
  return repo;
}

GtfsRepository _repo() =>
    GtfsRepository()..stopsById['1150'] = const StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 0, stopLon: 0);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  GtfsRepository? repo,
  Future<GtfsRepository> Function(int load)? schedule,
  List<ServiceAlert> alerts = const [],
  http.Client? timeTrackClient,
  double textScale = 1.0,
  bool preloadRepo = false,
  bool settle = true,
  bool use24h = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  useInMemoryAlertStore();
  final router = GoRouter(initialLocation: '/board/1150', routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('PICKER'), routes: [
      GoRoute(path: 'board/:id', builder: (_, s) => ArrivalBoardScreen(stopId: s.pathParameters['id']!)),
    ]),
    GoRoute(path: '/settings', builder: (_, _) => const Text('SETTINGS')),
    GoRoute(path: '/alerts', builder: (_, _) => const Text('ALERTS')),
    GoRoute(path: '/map', builder: (_, _) => const Text('MAP')),
  ]);
  var loads = 0;
  final container = ProviderContainer(overrides: [
      ...fakeAlertOverrides,
      gtfsRepositoryProvider.overrideWith((ref) async {
        if (schedule != null) return schedule(++loads);
        if (repo == null) throw Exception('not loaded');
        return repo;
      }),
      timetrackApiProvider.overrideWithValue(TimeTrackApi(client: timeTrackClient ?? _failing)),
      metrobusMobileApiProvider.overrideWithValue(MetrobusMobileApi(client: _emptyKiosk)),
      serviceUpdatesProvider.overrideWith((ref) => Stream.value(ServiceUpdates(
            alerts: alerts,
            serviceStatus: null,
            fetchedAt: DateTime(2026, 10, 4),
            feedTimestamp: null,
          ))),
  ]);
  addTearDown(container.dispose);
  // A deep-linked board can mount before the schedule is ready; preloading
  // pins the "first refresh is still in flight" state for the status tests.
  if (preloadRepo) await container.read(gtfsRepositoryProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: BBTheme.light(),
      routerConfig: router,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale), alwaysUse24HourFormat: use24h),
        child: app!,
      ),
    ),
  ));
  if (settle) await tester.pumpAndSettle();
  return container;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('header: stop pill, name, Change, settings, status line', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, repo: _repo());
    expect(find.text('STOP 1150'), findsOneWidget);
    expect(find.text('MUN Centre'), findsOneWidget);
    expect(find.textContaining('Live feed error · showing schedule'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('PICKER'), findsOneWidget);
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('status live region carries only the state, never the timestamp', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, repo: _repo());
    expect(
      find.semantics.byLabel('Live feed error · showing schedule'),
      isSemantics(isLiveRegion: true, label: 'Live feed error · showing schedule'),
    );
    await _unmount(tester);

    await _pump(tester, repo: _repo(), timeTrackClient: _liveFeed);
    expect(find.textContaining(RegExp(r'^ · updated \d\d:\d\d:\d\d$')), findsOneWidget);
    expect(find.semantics.byLabel('Live'), isSemantics(isLiveRegion: true, label: 'Live'));
    // No live-region node may embed the refresh timestamp.
    final liveNodes = find.semantics.byPredicate((n) => n.flagsCollection.isLiveRegion).evaluate();
    expect(liveNodes, isNotEmpty);
    expect(liveNodes.where((n) => n.label.contains('updated')), isEmpty);
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets("the updated time follows the device's 12-hour setting", (tester) async {
    await _pump(tester, repo: _repo(), timeTrackClient: _liveFeed, use24h: false);
    expect(find.textContaining(RegExp(r'^ · updated \d{1,2}:\d\d:\d\d [AP]M$')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('empty board is pull-to-refresh-able', (tester) async {
    await _pump(tester, repo: _repo());
    expect(find.text('No upcoming departures'), findsOneWidget);
    expect(find.text('There are no scheduled departures\nfrom this stop right now.'), findsOneWidget);
    expect(find.byType(BBRefresh), findsOneWidget);
    // Pull-to-refresh must not depend on the host's scroll behaviour.
    expect(tester.widget<ListView>(find.byType(ListView)).physics, isA<AlwaysScrollableScrollPhysics>());
    await _unmount(tester);
  });

  testWidgets('with service over, the empty board names the first bus', (tester) async {
    await _pump(tester, repo: _repoStartingIn(1));
    expect(find.text('No upcoming departures'), findsOneWidget);
    expect(find.text('First bus 06:30'), findsOneWidget);
    expect(find.textContaining('no scheduled departures'), findsNothing);
    await _unmount(tester);
  });

  testWidgets("the first bus follows the device's 12-hour setting", (tester) async {
    await _pump(tester, repo: _repoStartingIn(1), use24h: false);
    expect(find.text('First bus 6:30 AM'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a first bus days away names its weekday, spoken in full', (tester) async {
    final handle = tester.ensureSemantics();
    final day = DateTime.now().add(const Duration(days: 3));
    final short = DateFormat('EEE').format(day), full = DateFormat('EEEE').format(day);
    await _pump(tester, repo: _repoStartingIn(3));
    expect(find.text('First bus $short 06:30'), findsOneWidget);
    expect(find.bySemanticsLabel('No upcoming departures. First bus $full 06:30'), findsOneWidget);
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('with no service in the next 7 days, the empty board keeps its own words', (tester) async {
    await _pump(tester, repo: _repoStartingIn(9));
    expect(find.text('No upcoming departures'), findsOneWidget);
    expect(find.text('There are no scheduled departures\nfrom this stop right now.'), findsOneWidget);
    expect(find.textContaining('First bus'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('schedule not loaded shows the error state', (tester) async {
    await _pump(tester);
    expect(find.text('Schedule data not loaded'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('while the schedule loads at a cold start the board is loading, not an error; then its rows come in',
      (tester) async {
    final handle = tester.ensureSemantics();
    final schedule = Completer<GtfsRepository>();
    await _pump(tester, schedule: (_) => schedule.future, settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Schedule data not loaded'), findsNothing);
    expect(find.byType(BBSkeleton), findsOneWidget);
    expect(find.text('Checking live data…'), findsOneWidget);
    expect(find.textContaining('showing schedule'), findsNothing, reason: 'no provisional state announced');
    schedule.complete(_repoWithDepartures());
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('Schedule data not loaded'), findsNothing);
    expect(find.byType(ArrivalRowTile), findsNWidgets(2));
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('a schedule that fails its first load after a wait shows the error state', (tester) async {
    final schedule = Completer<GtfsRepository>();
    await _pump(tester, schedule: (_) => schedule.future, settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    schedule.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule data not loaded'), findsOneWidget);
    expect(find.byType(BBSkeleton), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a schedule that fails to reload keeps the departures on the old one, refresh after refresh',
      (tester) async {
    // Settings, Refresh schedule, while offline: the second load fails, and the old schedule is kept.
    final first = _repoWithDepartures();
    final container = await _pump(
      tester,
      schedule: (load) async => load > 1 ? throw Exception('offline') : first,
    );
    expect(find.byType(ArrivalRowTile), findsNWidgets(2));
    expect(find.text('MUN Centre'), findsOneWidget);
    container.invalidate(gtfsRepositoryProvider);
    await tester.pump();
    await tester.pump();
    expect(container.read(gtfsRepositoryProvider).hasError, isTrue, reason: 'the reload failed');
    await tester.pump(const Duration(minutes: 1)); // the next refreshes
    await tester.pumpAndSettle();
    expect(find.text('Schedule data not loaded'), findsNothing);
    expect(find.byType(ArrivalRowTile), findsNWidgets(2));
    expect(find.text('MUN Centre'), findsOneWidget, reason: 'the header keeps the stop name, not "Stop 1150"');
    expect(find.text('Stop 1150'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('relevant alerts: compact card + "more" link go to Alerts', (tester) async {
    await _pump(tester, repo: _repo(), alerts: [_alert('Water Street Detour'), _alert('Second')]);
    expect(find.text('Water Street Detour'), findsOneWidget);
    expect(find.text('1 more relevant alert'), findsOneWidget);
    await tester.tap(find.text('1 more relevant alert'));
    await tester.pumpAndSettle();
    expect(find.text('ALERTS'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('leaving the board cancels its refresh timer cleanly', (tester) async {
    await _pump(tester, repo: _repo());
    await _unmount(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header row fits at 320 pt and 2x text', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, repo: _repo(), textScale: 2.0);
    expect(tester.takeException(), isNull);
    expect(find.text('STOP 1150'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('tapping a live row follows that bus and opens the map', (tester) async {
    await _pump(tester, repo: _repoWithDepartures(), timeTrackClient: _liveFeed2573);
    expect(find.text('Live Terminal'), findsOneWidget);
    await tester.tap(find.text('Live Terminal'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.text('MAP')));
    expect(container.read(followProvider), const FollowTarget('2573'));
    expect(find.text('MAP'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('the first arrival keeps its top space under a leading card', (tester) async {
    double firstRowTop() {
      final pad = tester.widget<Padding>(
          find.ancestor(of: find.byType(ArrivalRowTile).first, matching: find.byType(Padding)).first);
      return (pad.padding as EdgeInsets).top;
    }

    await _pump(tester, repo: _repoWithDepartures(), alerts: [_alert('Water Street Detour')]);
    expect(find.text('Water Street Detour'), findsOneWidget);
    expect(firstRowTop(), BBSpace.s);
    expect((tester.widget<Padding>(find.ancestor(of: find.byType(ArrivalRowTile).at(1), matching: find.byType(Padding)).first)
                .padding as EdgeInsets)
            .top,
        0);
    await _unmount(tester);
  });

  testWidgets('the Follow pill does what tapping the row does: follows that bus and opens the map', (tester) async {
    await _pump(tester, repo: _repoWithDepartures(), timeTrackClient: _liveFeed2573);
    expect(find.textContaining('Follow 2573'), findsOneWidget);
    await tester.tap(find.byKey(ArrivalRowTile.followKey));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.text('MAP')));
    expect(container.read(followProvider), const FollowTarget('2573'));
    expect(find.text('MAP'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a scheduled-only row follows nothing and says when it can be followed', (tester) async {
    await _pump(tester, repo: _repoWithDepartures(), timeTrackClient: _liveFeed2573);
    expect(find.text('Schedule Terminal'), findsOneWidget);
    await tester.tap(find.text('Schedule Terminal'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(ArrivalRowTile.notLiveYet), findsOneWidget);
    expect(find.text('MAP'), findsNothing);
    final container = ProviderScope.containerOf(tester.element(find.text('Schedule Terminal')));
    expect(container.read(followProvider), isNull);
    await tester.pump(const Duration(seconds: 4));
    await _unmount(tester);
  });

  testWidgets('first load says "Checking live data…" and stays silent, then announces the result', (tester) async {
    final handle = tester.ensureSemantics();
    final never = MockClient((_) => Completer<http.Response>().future);
    await _pump(tester, repo: _repo(), timeTrackClient: never, preloadRepo: true, settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Checking live data…'), findsOneWidget);
    expect(find.textContaining('Live unavailable'), findsNothing);
    expect(find.textContaining('showing schedule'), findsNothing);
    // The skeleton announces itself with its own live region; the status line itself must be silent.
    expect(
      find.semantics.byPredicate(
        (n) => n.flagsCollection.isLiveRegion && RegExp('live|schedule', caseSensitive: false).hasMatch(n.label),
      ),
      findsNothing,
    );
    expect(find.semantics.byLabel('Checking live data…'), findsOneWidget);
    // The live request times out (10 s): the failure is then announced.
    // The live client tries several feeds in turn, each with its own 10 s timeout.
    // The spinner's ticker used to keep frames coming through that wait; the
    // static skeleton does not, so advance the clock explicitly.
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('Checking live data…'), findsNothing);
    expect(
      find.semantics.byLabel('Live feed error · showing schedule'),
      isSemantics(isLiveRegion: true, label: 'Live feed error · showing schedule'),
    );
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('the Board stops polling behind the other tab, and refreshes once on coming back', (tester) async {
    final mobile = _CountingMobile();
    await pumpPlannerApp(
      tester,
      net: TestNetwork(),
      now: DateTime(testDay.year, testDay.month, testDay.day, 7, 50),
      initial: '/board/A',
      overrides: [metrobusMobileApiProvider.overrideWithValue(mobile)],
    );
    expect(find.byType(ArrivalBoardScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(mobile.asked.length, greaterThan(1), reason: 'polls every 5 s while shown');
    final bar = find.byType(BBNavBar);
    await tester.tap(find.descendant(of: bar, matching: find.text('Map')));
    await tester.pumpAndSettle();
    final hidden = mobile.asked.length;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(mobile.asked.length, hidden, reason: 'no polling behind another tab');
    // Back from the background behind another tab: still no polling.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(seconds: 11));
    expect(mobile.asked.length, hidden, reason: 'a return to the app does not wake the hidden Board');
    await tester.tap(find.descendant(of: bar, matching: find.text('Board')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(mobile.asked.length, hidden + 1, reason: 'one refresh on coming back');
    await tester.pump(const Duration(seconds: 6));
    expect(mobile.asked.length, greaterThan(hidden + 1), reason: 'and polling again');
    await _unmount(tester);
  });

  testWidgets('the Board stops polling behind a page opened over it (the service alerts), and refreshes on return',
      (tester) async {
    final mobile = _CountingMobile();
    await pumpPlannerApp(
      tester,
      net: TestNetwork(),
      now: DateTime(testDay.year, testDay.month, testDay.day, 7, 50),
      initial: '/board/A',
      overrides: [metrobusMobileApiProvider.overrideWithValue(mobile)],
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(find.byKey(TopActions.alertsKey));
    await tester.pumpAndSettle();
    expect(find.byType(AlertsScreen), findsOneWidget);
    final hidden = mobile.asked.length;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(mobile.asked.length, hidden, reason: 'no polling behind the page');
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(mobile.asked.length, greaterThan(hidden), reason: 'a refresh on coming back');
    await _unmount(tester);
  });
}
