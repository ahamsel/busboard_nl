import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart' show PlanMode;
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/saved_place_providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/home/options_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/planner_app.dart';
import '../../tool/src/harbour_style.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/test_network.dart';

final _rows = [
  ArrivalRow(routeShortName: '29', headsign: 'Signal Hill Rd', scheduledTime: GtfsTime.parse('09:52:00'),
      predictedTime: GtfsTime.parse('09:51:00'), minutesAway: 4, isLive: true, liveStatus: LiveStatus.ahead,
      tripId: 'a', vehicleNumber: '2134', routeRun: '29-1', currentLocation: 'MUN Centre'),
  ArrivalRow(routeShortName: '23', headsign: 'Stavanger Drive', scheduledTime: GtfsTime.parse('09:52:00'),
      predictedTime: GtfsTime.parse('09:54:00'), minutesAway: 6, isLive: true, liveStatus: LiveStatus.behind,
      tripId: 'b', vehicleNumber: '1207'),
  ArrivalRow(routeShortName: '10', headsign: 'Avalon Mall - MUN Centre - Downtown', scheduledTime: GtfsTime.parse('09:55:00'),
      predictedTime: GtfsTime.parse('09:55:00'), minutesAway: 9, isLive: true, isEnhanced: true, tripId: 'c'),
  ArrivalRow(routeShortName: '16', headsign: 'Avalon Mall', scheduledTime: GtfsTime.parse('09:48:00'),
      minutesAway: 0, tripId: 'd'),
];

Widget _app(Widget home, Brightness b) => ProviderScope(
      overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
        serviceUpdatesProvider.overrideWith((ref) => Stream.value(ServiceUpdates(
              alerts: [
                ServiceAlert(sourceIds: const {'a'}, header: 'Water Street Detour',
                    description: 'Routes 3 and 10 use Harbour Drive between Prescott St and Waldegrave St.',
                    cause: ServiceAlertCause.construction, effect: ServiceAlertEffect.detour,
                    severity: ServiceAlertSeverity.warning,
                    activePeriods: [ServiceAlertPeriod(end: DateTime(2099, 11, 1, 12, 44))],
                    targets: const [ServiceAlertTarget(routeId: '3'), ServiceAlertTarget(routeId: '10')]),
              ],
              serviceStatus: const MetrobusServiceStatus(serviceOperating: true, serviceId: '1', day: 'Weekday',
                  message: 'Weekday service operating'),
              fetchedAt: DateTime(2026, 10, 4, 9, 52, 4),
              feedTimestamp: null,
            ))),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: b == Brightness.dark ? BBTheme.dark() : BBTheme.light(),
        home: home,
      ),
    );

class _StopSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(selectedStopId: '1150');
}

class _OnePlace extends SavedPlacesNotifier {
  @override
  Future<List<SavedPlace>> build() async => [
        SavedPlace(id: 'home', name: 'Home', icon: SavedPlaceIcon.home, place: StopPlace(stopId: 'C', name: 'Avalon Mall')),
      ];
}

/// A small network where stop 1150 is MUN Centre and stop C is Avalon Mall, so the options read as a real trip.
TestNetwork _munToAvalon() {
  final net = TestNetwork();
  net.repo.stopsById['1150'] = const StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.5600, stopLon: -52.7500);
  net.repo.stopsById['C'] = const StopInfo(stopId: 'C', stopName: 'Avalon Mall', stopLat: 47.5700, stopLon: -52.7500);
  for (var i = 0; i < 4; i++) {
    net.addTrip('g-$i', '1', ['1150', 'B', 'C'], 8 * 3600 + 300 + i * 600, 300);
  }
  return net;
}

/// The Harbour map's land colour for [b], so the sheet's separation from the map shows in the goldens.
Color _land(Brightness b) {
  final hex = (b == Brightness.dark ? HarbourPalette.dark : HarbourPalette.light).land;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

/// The real app at [initial] on a 390x844 phone at 3x: stop 1150 is the rider's stop, one saved place, one alert
/// that applies to routes 29 and 23 and to the stop, and four fixed departures (so the picture does not move).
Future<void> _pumpApp(WidgetTester tester, Brightness b, {String initial = '/'}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await pumpPlannerApp(
    tester,
    net: _munToAvalon(),
    now: DateTime(testDay.year, testDay.month, testDay.day, 8, 1),
    initial: initial,
    mapView: StubMap(color: _land(b)).build,
    theme: b == Brightness.dark ? BBTheme.dark() : BBTheme.light(),
    alerts: [
      ServiceAlert(
        sourceIds: const {'a'},
        header: 'Water Street Detour',
        description: 'Routes 29 and 23 use Harbour Drive between Prescott St and Waldegrave St.',
        cause: ServiceAlertCause.construction,
        effect: ServiceAlertEffect.detour,
        severity: ServiceAlertSeverity.warning,
        activePeriods: [ServiceAlertPeriod(end: DateTime(2099, 11, 1, 12, 44))],
        targets: const [ServiceAlertTarget(routeId: '29'), ServiceAlertTarget(stopId: '1150')],
      ),
    ],
    nearby: const [
      NearbyStop(stop: StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.56, stopLon: -52.75), distanceMeters: 80),
    ],
    overrides: [
      settingsProvider.overrideWith(_StopSettings.new),
      savedPlacesProvider.overrideWith(_OnePlace.new),
      stopArrivalsProvider.overrideWith((ref, id) async => _rows),
      metrobusMobileApiProvider.overrideWithValue(MetrobusMobileApi(client: MockClient((_) async => http.Response('{"arrivals":[]}', 200)))),
    ],
  );
}

void main() {
  setUpAll(loadAppFonts);

  for (final b in Brightness.values) {
    testWidgets('home peek ${b.name}', (tester) async {
      await _pumpApp(tester, b);
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/home_peek_${b.name}.png'));
    });

    testWidgets('stop sheet at full ${b.name}', (tester) async {
      await _pumpApp(tester, b, initial: '/board/1150');
      await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/stop_sheet_${b.name}.png'));
    });

    testWidgets('options at half ${b.name}', (tester) async {
      await _pumpApp(tester, b);
      final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      c.read(planQueryProvider.notifier).setTrip(
            StopPlace(stopId: '1150', name: 'MUN Centre'),
            StopPlace(stopId: 'C', name: 'Avalon Mall'),
          );
      c.read(homeSheetProvider.notifier).open(const OptionsSheet());
      await tester.pumpAndSettle();
      // The grabber steps peek -> half.
      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('Map sheet'));
      await tester.pumpAndSettle();
      handle.dispose();
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/options_${b.name}.png'));
    });

    testWidgets('arrival rows ${b.name}', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 520 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(kitHost(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [for (final r in _rows) Padding(padding: const EdgeInsets.only(bottom: 8), child: ArrivalRowTile(arrival: r))]),
        ),
        brightness: b,
      ));
      await expectLater(find.byType(Column).first, matchesGoldenFile('goldens/arrival_rows_${b.name}.png'));
    });

    testWidgets('alerts screen ${b.name}', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const AlertsScreen(), b));
      await tester.pumpAndSettle();
      await expectLater(find.byType(AlertsScreen), matchesGoldenFile('goldens/alerts_${b.name}.png'));
    });

    testWidgets('settings screen ${b.name}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390 * 3, 1100 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const SettingsScreen(), b));
      await tester.pumpAndSettle();
      await expectLater(find.byType(SettingsScreen), matchesGoldenFile('goldens/settings_${b.name}.png'));
    });

    testWidgets('when picker ${b.name}', (tester) async {
      await _pumpApp(tester, b);
      final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      c.read(planQueryProvider.notifier)
        ..setTrip(StopPlace(stopId: '1150', name: 'MUN Centre'), StopPlace(stopId: 'C', name: 'Avalon Mall'))
        ..setMode(PlanMode.leaveBy);
      c.read(homeSheetProvider.notifier).open(const OptionsSheet());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(OptionsSheetContent.whenButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OptionsSheetContent.whenButtonKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/when_picker_${b.name}.png'));
    });
  }

  testWidgets('home at half dark', (tester) async {
    await _pumpApp(tester, Brightness.dark);
    final peek = tester.getRect(find.byKey(BBSheet.cardKey)).top;
    await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, lessThan(peek - 100), reason: 'the sheet is up at half');
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/home_half_dark.png'));
  });
}
