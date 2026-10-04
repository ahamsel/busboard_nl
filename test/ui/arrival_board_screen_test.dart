import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/board/arrival_board_screen.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kit/kit_test_helpers.dart';

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

Future<void> _pump(
  WidgetTester tester, {
  GtfsRepository? repo,
  List<ServiceAlert> alerts = const [],
  http.Client? timeTrackClient,
  double textScale = 1.0,
  bool preloadRepo = false,
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final router = GoRouter(initialLocation: '/board/1150', routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('PICKER'), routes: [
      GoRoute(path: 'board/:id', builder: (_, s) => ArrivalBoardScreen(stopId: s.pathParameters['id']!)),
    ]),
    GoRoute(path: '/settings', builder: (_, _) => const Text('SETTINGS')),
    GoRoute(path: '/alerts', builder: (_, _) => const Text('ALERTS')),
  ]);
  final container = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async {
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
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
    ),
  ));
  if (settle) await tester.pumpAndSettle();
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

  testWidgets('empty board is pull-to-refresh-able', (tester) async {
    await _pump(tester, repo: _repo());
    expect(find.text('No upcoming departures'), findsOneWidget);
    expect(find.text('There are no scheduled departures\nfrom this stop right now.'), findsOneWidget);
    expect(find.byType(BBRefresh), findsOneWidget);
    // Pull-to-refresh must not depend on the host's scroll behaviour.
    expect(tester.widget<ListView>(find.byType(ListView)).physics, isA<AlwaysScrollableScrollPhysics>());
    await _unmount(tester);
  });

  testWidgets('schedule not loaded shows the error state', (tester) async {
    await _pump(tester);
    expect(find.text('Schedule data not loaded'), findsOneWidget);
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

  testWidgets('first load says "Checking live data…" and stays silent, then announces the result', (tester) async {
    final handle = tester.ensureSemantics();
    final never = MockClient((_) => Completer<http.Response>().future);
    await _pump(tester, repo: _repo(), timeTrackClient: never, preloadRepo: true, settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Checking live data…'), findsOneWidget);
    expect(find.textContaining('Live unavailable'), findsNothing);
    expect(find.textContaining('showing schedule'), findsNothing);
    // BBLoading announces its own spinner; the status line itself must be silent.
    expect(
      find.semantics.byPredicate(
        (n) => n.flagsCollection.isLiveRegion && RegExp('live|schedule', caseSensitive: false).hasMatch(n.label),
      ),
      findsNothing,
    );
    expect(find.semantics.byLabel('Checking live data…'), findsOneWidget);
    // The live request times out (10 s): the failure is then announced.
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Checking live data…'), findsNothing);
    expect(
      find.semantics.byLabel('Live feed error · showing schedule'),
      isSemantics(isLiveRegion: true, label: 'Live feed error · showing schedule'),
    );
    handle.dispose();
    await _unmount(tester);
  });
}
