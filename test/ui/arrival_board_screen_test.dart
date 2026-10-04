import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/board/arrival_board_screen.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _failing = MockClient((_) async => http.Response('down', 500));

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

Future<void> _pump(WidgetTester tester, {GtfsRepository? repo, List<ServiceAlert> alerts = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final router = GoRouter(initialLocation: '/board/1150', routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('PICKER'), routes: [
      GoRoute(path: 'board/:id', builder: (_, s) => ArrivalBoardScreen(stopId: s.pathParameters['id']!)),
    ]),
    GoRoute(path: '/settings', builder: (_, _) => const Text('SETTINGS')),
    GoRoute(path: '/alerts', builder: (_, _) => const Text('ALERTS')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async {
        if (repo == null) throw Exception('not loaded');
        return repo;
      }),
      timetrackApiProvider.overrideWithValue(TimeTrackApi(client: _failing)),
      metrobusMobileApiProvider.overrideWithValue(MetrobusMobileApi(client: _failing)),
      serviceUpdatesProvider.overrideWith((ref) => Stream.value(ServiceUpdates(
            alerts: alerts,
            serviceStatus: null,
            fetchedAt: DateTime(2026, 10, 4),
            feedTimestamp: null,
          ))),
    ],
    child: MaterialApp.router(theme: BBTheme.light(), routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
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

  testWidgets('empty board is pull-to-refresh-able', (tester) async {
    await _pump(tester, repo: _repo());
    expect(find.text('No upcoming departures'), findsOneWidget);
    expect(find.text('There are no scheduled departures\nfrom this stop right now.'), findsOneWidget);
    expect(find.byType(BBRefresh), findsOneWidget);
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
}
