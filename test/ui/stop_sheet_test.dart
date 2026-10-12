import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/platform/alert_runner.dart';
import 'package:busboard_nl/state/arrival_alert_providers.dart';
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/stop_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
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

GtfsRepository _repo() =>
    GtfsRepository()..stopsById['1150'] = const StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 0, stopLon: 0);

/// A phone's alert runner (it does not watch live): it takes a re-timed alert from the stop's sheet.
class _PhoneRunner implements AlertRunner {
  final updated = <ArrivalAlert>[];
  @override
  bool get watchesLive => false;
  @override
  Stream<void> get finished => const Stream.empty();
  @override
  Future<void> start(ArrivalAlert alert) async {}
  @override
  Future<void> update(ArrivalAlert alert) async => updated.add(alert);
  @override
  Future<void> onBackground(ArrivalAlert alert) async {}
  @override
  Future<void> ensureRunning(ArrivalAlert alert) async {}
  @override
  Future<void> stop() async {}
}

class _SlowPollSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(refreshIntervalSeconds: 3600);
}

/// The real app at [initial] (a stop's Board link), with the stop's sheet pulled to full.
Future<void> _pump(
  WidgetTester tester, {
  GtfsRepository? repo,
  List<ServiceAlert> alerts = const [],
  http.Client? timeTrackClient,
  double textScale = 1.0,
  bool settle = true,
  bool pullUp = true,
  String initial = '/board/1150',
  List<Override> overrides = const [],
  AlertRunner? alertRunner,
}) async {
  await pumpPlannerApp(
    tester,
    net: TestNetwork(),
    now: DateTime.now(),
    appRoutes: true,
    initial: initial,
    alerts: alerts,
    repoFuture: Future.value(repo ?? _repo()),
    liveClient: timeTrackClient ?? _failing,
    textScale: textScale,
    settle: settle,
    alertRunner: alertRunner,
    overrides: [
      metrobusMobileApiProvider.overrideWithValue(MetrobusMobileApi(client: _emptyKiosk)),
      ...overrides,
    ],
  );
  if (settle && pullUp) await _pullUp(tester);
}

/// Pulls the sheet to its full height (the header is part of the sheet, so a drag on it moves it).
Future<void> _pullUp(WidgetTester tester) async {
  await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
  await tester.pumpAndSettle();
}

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeScreen)));

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('header: stop pill, name, status line, refresh and the three controls', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, repo: _repo());
    expect(find.text('STOP 1150'), findsOneWidget);
    expect(find.text('MUN Centre'), findsOneWidget);
    expect(find.text('Showing schedule'), findsOneWidget);
    expect(find.bySemanticsLabel('Refresh departures'), findsOneWidget);
    expect(find.bySemanticsLabel('Set as my stop'), findsOneWidget);
    expect(find.bySemanticsLabel('Plan a trip from here'), findsOneWidget);
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('status live region carries only the state', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, repo: _repo());
    expect(
      find.semantics.byLabel('Showing schedule'),
      isSemantics(isLiveRegion: true, label: 'Showing schedule'),
    );
    await _unmount(tester);

    await _pump(tester, repo: _repoWithDepartures(), timeTrackClient: _liveFeed);
    expect(find.semantics.byLabel('Live'), isSemantics(isLiveRegion: true, label: 'Live'));
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('empty board says so', (tester) async {
    await _pump(tester, repo: _repo());
    expect(find.text('No upcoming departures'), findsOneWidget);
    expect(find.text('There are no scheduled departures\nfrom this stop right now.'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets("a list that can't load shows the error state", (tester) async {
    await _pump(tester, overrides: [
      stopArrivalsProvider.overrideWith((ref, stopId) => Future<List<ArrivalRow>>.error(Exception('down'))),
    ]);
    expect(find.text("Couldn't load departures"), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('an unknown stop still gets a sheet: "Stop 9999" and the empty state', (tester) async {
    await _pump(tester, repo: _repo(), initial: '/board/9999');
    expect(_c(tester).read(homeSheetProvider), const StopSheet('9999'));
    expect(find.text('STOP 9999'), findsOneWidget);
    expect(find.text('Stop 9999'), findsOneWidget);
    expect(find.text('No upcoming departures'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('relevant alerts: compact card + "more" link go to Alerts', (tester) async {
    await _pump(tester, repo: _repo(), alerts: [_alert('Water Street Detour'), _alert('Second')]);
    expect(find.text('Water Street Detour'), findsOneWidget);
    expect(find.text('1 more relevant alert'), findsOneWidget);
    await tester.tap(find.text('1 more relevant alert'));
    await tester.pumpAndSettle();
    expect(find.text('Service alerts'), findsWidgets);
    await _unmount(tester);
  });

  testWidgets('leaving the stop cancels its refresh timer cleanly', (tester) async {
    await _pump(tester, repo: _repo());
    await _unmount(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header fits at 320 pt and 2x text', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, repo: _repo(), textScale: 2.0);
    expect(tester.takeException(), isNull);
    expect(find.text('STOP 1150'), findsOneWidget);
    expect(find.text('Plan a trip from here'), findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(find.text('Plan a trip from here')).didExceedMaxLines, isFalse);
    await _unmount(tester);
  });

  testWidgets('tapping a live row follows that bus and goes home to the map', (tester) async {
    await _pump(tester, repo: _repoWithDepartures(), timeTrackClient: _liveFeed2573);
    expect(find.text('Live Terminal'), findsOneWidget);
    await tester.tap(find.text('Live Terminal'));
    await tester.pumpAndSettle();
    final container = _c(tester);
    expect(container.read(followProvider), const FollowTarget('2573'));
    expect(container.read(homeSheetProvider), isA<HomeSheetHome>());
    await _unmount(tester);
  });

  testWidgets('the alert card leads the arrivals', (tester) async {
    await _pump(tester, repo: _repoWithDepartures(), alerts: [_alert('Water Street Detour')]);
    expect(find.text('Water Street Detour'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Water Street Detour')).dy,
        lessThan(tester.getTopLeft(find.byType(ArrivalRowTile).first).dy));
    expect(find.byType(ArrivalRowTile), findsNWidgets(2));
    await _unmount(tester);
  });

  testWidgets('a scheduled-only row is not tappable', (tester) async {
    await _pump(tester, repo: _repoWithDepartures(), timeTrackClient: _liveFeed2573);
    expect(find.text('Schedule Terminal'), findsOneWidget);
    await tester.tap(find.text('Schedule Terminal'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule Terminal'), findsOneWidget);
    expect(_c(tester).read(homeSheetProvider), const StopSheet('1150'));
    expect(_c(tester).read(followProvider), isNull);
    await _unmount(tester);
  });

  ArrivalRow row({required String route, required bool live, String? vehicle}) => ArrivalRow(
        routeShortName: route,
        headsign: 'Downtown',
        scheduledTime: GtfsTime.parse('09:52:00'),
        minutesAway: 4,
        isLive: live,
        tripId: 't-$route',
        vehicleNumber: vehicle,
      );

  testWidgets('scheduled-only and vehicle-less rows are inert', (tester) async {
    await _pump(tester, repo: _repo(), overrides: [
      stopArrivalsProvider.overrideWith((ref, stopId) async => [
            row(route: '5', live: false, vehicle: '2574'),
            row(route: '6', live: true),
            row(route: '7', live: true, vehicle: ''),
          ]),
    ]);
    for (final route in ['5', '6', '7']) {
      await tester.tap(find.bySemanticsLabel(RegExp('^Route $route ')));
      await tester.pumpAndSettle();
    }
    expect(_c(tester).read(followProvider), isNull);
    expect(_c(tester).read(homeSheetProvider), const StopSheet('1150'));
    await _unmount(tester);
  });

  testWidgets('only live rows announce the follow hint', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, repo: _repo(), overrides: [
      stopArrivalsProvider.overrideWith(
          (ref, stopId) async => [row(route: '21', live: true, vehicle: '2573'), row(route: '5', live: false)]),
    ]);
    expect(
      find.semantics.byLabel('Route 21 Downtown, live, 4 minutes'),
      isSemantics(
        label: 'Route 21 Downtown, live, 4 minutes',
        isButton: true,
        hasTapAction: true,
        onTapHint: 'follow bus 2573 on the map',
      ),
    );
    expect(
      find.semantics.byLabel('Route 5 Downtown, scheduled, 4 minutes'),
      isSemantics(label: 'Route 5 Downtown, scheduled, 4 minutes', isButton: false, hasTapAction: false),
    );
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('first load says "Checking live data…" and stays silent, then announces the result', (tester) async {
    final handle = tester.ensureSemantics();
    final never = MockClient((_) => Completer<http.Response>().future);
    // The poll is moved out of the way: a poll shorter than the live request would restart it for ever.
    await _pump(tester, repo: _repo(), timeTrackClient: never, settle: false, overrides: [
      settingsProvider.overrideWith(() => _SlowPollSettings()),
    ]);
    await tester.pump(const Duration(milliseconds: 100));
    // The sheet is at its peek: the header is what shows.
    expect(find.text('Checking live data…'), findsOneWidget);
    expect(find.text('Showing schedule'), findsNothing);
    // The skeleton announces itself with its own live region; the status line itself must be silent.
    expect(
      find.semantics.byPredicate(
        (n) => n.flagsCollection.isLiveRegion && RegExp('live|schedule', caseSensitive: false).hasMatch(n.label),
      ),
      findsNothing,
    );
    expect(find.semantics.byLabel('Checking live data…'), findsOneWidget);
    // The live request times out (10 s): the failure is then announced.
    // The live client tries several feeds in turn, each with its own 10 s timeout, and the static
    // skeleton keeps no frames coming through that wait, so advance the clock explicitly.
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('Checking live data…'), findsNothing);
    expect(
      find.semantics.byLabel('Showing schedule'),
      isSemantics(isLiveRegion: true, label: 'Showing schedule'),
    );
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('refresh asks for the departures again', (tester) async {
    var loads = 0;
    await _pump(tester, repo: _repo(), overrides: [
      stopArrivalsProvider.overrideWith((ref, stopId) async {
        loads++;
        return const <ArrivalRow>[];
      }),
    ]);
    final before = loads;
    await tester.tap(find.byKey(StopSheetContent.refreshKey));
    await tester.pumpAndSettle();
    expect(loads, greaterThan(before));
    await _unmount(tester);
  });

  testWidgets('★ makes it your stop', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, repo: _repo());
    expect(_c(tester).read(settingsProvider).selectedStopId, isNull);
    await tester.tap(find.byKey(StopSheetContent.starKey));
    await tester.pumpAndSettle();
    expect(_c(tester).read(settingsProvider).selectedStopId, '1150');
    expect(find.bySemanticsLabel('Your stop'), findsOneWidget);
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('Plan a trip from here starts the plan from this stop', (tester) async {
    await _pump(tester, repo: _repo());
    final container = _c(tester);
    await tester.tap(find.byKey(StopSheetContent.planFromKey));
    await tester.pump();
    expect(container.read(planQueryProvider).from, StopPlace(stopId: '1150', name: 'MUN Centre'));
    // /search lands with the search screen (the next task); the router just has no page for it yet.
    await _unmount(tester);
  });

  testWidgets('every new list reaches the arrival alerts, like the Board did', (tester) async {
    final runner = _PhoneRunner();
    final now = DateTime.now();
    final nowSeconds = GtfsTime.fromDateTime(now).totalSeconds;
    // The next poll's list has the bus 3 minutes later than the first.
    var delayMinutes = 0;
    ArrivalRow bus() => ArrivalRow(
          routeShortName: '20',
          headsign: 'Live Terminal',
          scheduledTime: GtfsTime.fromSeconds(nowSeconds + 1200),
          predictedTime: GtfsTime.fromSeconds(nowSeconds + 1200 + delayMinutes * 60),
          minutesAway: 20 + delayMinutes,
          isLive: true,
          tripId: 'trip-20',
          vehicleNumber: '0859',
        );
    await _pump(tester, repo: _repo(), alertRunner: runner, overrides: [
      // Polls like the real provider: a new list every refresh interval while it is watched.
      stopArrivalsProvider.overrideWith((ref, stopId) async {
        final timer = Timer(const Duration(seconds: 5), ref.invalidateSelf);
        ref.onDispose(timer.cancel);
        return [bus()];
      }),
    ]);
    final alerts = _c(tester).read(arrivalAlertProvider.notifier);
    await alerts.set(bus(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    await tester.pump();
    final set = _c(tester).read(arrivalAlertProvider).value!;
    expect(runner.updated, isEmpty);

    delayMinutes = 3;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(runner.updated, hasLength(1));
    final moved = _c(tester).read(arrivalAlertProvider).value!;
    expect(moved.expectedAt, set.expectedAt.add(const Duration(minutes: 3)));
    expect(runner.updated.single.expectedAt, moved.expectedAt);
    await _unmount(tester);
  });
}
