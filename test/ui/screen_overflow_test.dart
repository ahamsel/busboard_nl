import 'dart:async';
import 'dart:io';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/board/arrival_board_screen.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:busboard_nl/ui/stop_picker/stop_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kit/kit_test_helpers.dart';

/// Large-text guard: every Phase 2 screen is scrolled to its end at 2x text on
/// the two smallest supported phones, and any layout exception fails the test.
const _sizes = [Size(320, 568), Size(360, 640)];

const _longStopName = 'Elizabeth Avenue at Allandale Road Westbound';
const _stop = StopInfo(stopId: '1150', stopName: _longStopName, stopLat: 47.57, stopLon: -52.73);
const _routes = ['1', '2', '3', '6', '9', '10', '10A', '11', '12'];

GtfsRepository _repo() {
  final repo = GtfsRepository()..stopsById['1150'] = _stop;
  final times = <StopTimeRow>[];
  for (var i = 0; i < _routes.length; i++) {
    repo.routesById['r$i'] = RouteInfo(routeId: 'r$i', routeShortName: _routes[i], routeLongName: '');
    repo.tripsById['t$i'] = TripInfo(tripId: 't$i', routeId: 'r$i', serviceId: 's', tripHeadsign: '', directionId: 0);
    times.add(StopTimeRow(
        tripId: 't$i', arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1));
  }
  repo.stopTimesByStopId['1150'] = times;
  return repo;
}

ServiceAlert _alert(String header, {String description = ''}) => ServiceAlert(
      sourceIds: {header},
      header: header,
      description: description,
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: [
        ServiceAlertPeriod(
          start: DateTime.now().subtract(const Duration(days: 1)),
          end: DateTime.now().add(const Duration(days: 20)),
        ),
      ],
      targets: const [
        ServiceAlertTarget(routeId: '10'),
        ServiceAlertTarget(routeId: '10A'),
        ServiceAlertTarget(routeId: '29'),
        ServiceAlertTarget(stopId: '1150'),
        ServiceAlertTarget(stopId: '9999'),
      ],
    );

ServiceUpdates _updates(List<ServiceAlert> alerts) => ServiceUpdates(
      alerts: alerts,
      serviceStatus: const MetrobusServiceStatus(
          serviceOperating: true, serviceId: '1', day: 'Weekday', message: 'Weekday service operating'),
      fetchedAt: DateTime(2026, 10, 4),
      feedTimestamp: null,
    );

final _failing = MockClient((_) async => http.Response('down', 500));
final _emptyKiosk = MockClient((_) async => http.Response('{"arrivals":[]}', 200));

class _Screen {
  const _Screen(this.name, this.build);
  final String name;
  final Widget Function(WidgetTester tester) build;
}

Widget _app(Widget screen, List<Override> overrides) {
  final container = ProviderContainer(retry: (_, _) => null, overrides: overrides);
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: BBTheme.light(), builder: _scaled, routerConfig: _router(screen)),
  );
}

Widget _scaled(BuildContext context, Widget? app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
      child: app!,
    );

GoRouter _router(Widget screen) => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/alerts', builder: (_, _) => const SizedBox()),
    ]);

final _screens = <_Screen>[
  _Screen('picker (last stop + nearby with 9 routes)', (t) {
    SharedPreferences.setMockInitialValues({'selectedStopId': '1150'});
    return _app(const StopPickerScreen(), [
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
      nearestStopsProvider.overrideWith((ref) async => const [
            NearbyStop(stop: _stop, distanceMeters: 80),
            NearbyStop(stop: _stop, distanceMeters: 640),
          ]),
    ]);
  }),
  _Screen('picker (schedule failed to load)', (t) {
    SharedPreferences.setMockInitialValues({});
    return _app(const StopPickerScreen(), [
      gtfsRepositoryProvider.overrideWith((ref) async =>
          throw const SocketException('Failed host lookup: busboard.example.com (OS Error: nodename nor servname provided, errno = 8)')),
    ]);
  }),
  _Screen('board (alert + failing live feed)', (t) {
    SharedPreferences.setMockInitialValues({});
    return _app(const ArrivalBoardScreen(stopId: '1150'), [
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
      timetrackApiProvider.overrideWithValue(TimeTrackApi(client: _failing)),
      metrobusMobileApiProvider.overrideWithValue(MetrobusMobileApi(client: _emptyKiosk)),
      serviceUpdatesProvider.overrideWith((ref) => Stream.value(_updates([
            _alert('Water Street detour', description: 'Routes 10 and 10A use Harbour Drive.'),
            _alert('Second alert'),
          ]))),
    ]);
  }),
  _Screen('alerts (data)', (t) {
    SharedPreferences.setMockInitialValues({});
    return _app(const AlertsScreen(), [
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
      serviceUpdatesProvider.overrideWith((ref) => Stream.value(_updates([
            for (var i = 0; i < 4; i++)
              _alert('Water Street detour number $i',
                  description: 'Routes 10, 10A and 29 use Harbour Drive between Duckworth Street and Prescott Street.'),
          ]))),
    ]);
  }),
  _Screen('alerts (error)', (t) {
    SharedPreferences.setMockInitialValues({});
    return _app(const AlertsScreen(), [
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
      serviceUpdatesProvider.overrideWith((ref) => Stream<ServiceUpdates>.error(const SocketException(
          'Failed host lookup: busboard.example.com (OS Error: nodename nor servname provided, or not known, errno = 8), address = busboard.example.com, port = 443'))),
    ]);
  }),
  _Screen('settings', (t) {
    SharedPreferences.setMockInitialValues({});
    return _app(const SettingsScreen(), [
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
    ]);
  }),
];

/// Drags the first scrollable up repeatedly (past its end), failing on any
/// exception recorded by the framework (RenderFlex overflow, etc.).
Future<void> _scrollThrough(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 14; i++) {
    await tester.drag(scrollable, const Offset(0, -300), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull, reason: 'after drag ${i + 1}');
  }
}

void main() {
  setUpAll(loadAppFonts);

  for (final size in _sizes) {
    for (final screen in _screens) {
      testWidgets('${screen.name} at ${size.width.toInt()}x${size.height.toInt()}, 2.0x text', (tester) async {
        tester.view.physicalSize = Size(size.width * 3, size.height * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(screen.build(tester));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'initial layout');
        await _scrollThrough(tester);

        // Unmount and let the board's refresh timer / request timeouts drain.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 11));
      });
    }
  }
}
