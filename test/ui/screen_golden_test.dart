import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:busboard_nl/ui/stop_picker/plan_trip_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kit/kit_test_helpers.dart';

final _rows = [
  ArrivalRow(routeShortName: '29', headsign: 'Signal Hill Rd', scheduledTime: GtfsTime.parse('09:52:00'),
      predictedTime: GtfsTime.parse('09:51:00'), minutesAway: 4, isLive: true, liveStatus: LiveStatus.ahead,
      tripId: 'a', vehicleNumber: '2134', routeRun: '29-1', currentLocation: 'MUN Centre'),
  ArrivalRow(routeShortName: '23', headsign: 'Stavanger Drive', scheduledTime: GtfsTime.parse('09:52:00'),
      predictedTime: GtfsTime.parse('09:54:00'), minutesAway: 6, isLive: true, liveStatus: LiveStatus.behind,
      tripId: 'b', vehicleNumber: '1207'),
  ArrivalRow(routeShortName: '10', headsign: 'AVALON MALL - MUN CENTRE - DOWNTOWN', scheduledTime: GtfsTime.parse('09:55:00'),
      predictedTime: GtfsTime.parse('09:55:00'), minutesAway: 9, isLive: true, isEnhanced: true, tripId: 'c'),
  ArrivalRow(routeShortName: '16', headsign: 'Avalon Mall', scheduledTime: GtfsTime.parse('09:48:00'),
      minutesAway: 0, tripId: 'd'),
];

Widget _app(Widget home, Brightness b) => ProviderScope(
      overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
        appVersionProvider.overrideWith((ref) async => '1.5.0'),
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

SavedTrip _saved(String id, String from, String to) => SavedTrip(
      id: id,
      name: '$from → $to',
      from: StopPlace(stopId: id, name: from),
      to: StopPlace(stopId: '$id-to', name: to),
    );

final _savedTrips = [
  _saved('home', 'Home', 'MUN Centre'),
  _saved('mun', 'MUN Centre', 'Avalon Mall'),
  _saved('work', 'Work', 'Home'),
  _saved('dt', 'Downtown', 'Home'),
];

/// A journey on the planner's test day whose first bus leaves at [h]:[m].
Journey _leaving(int h, int m, {bool live = false}) => Journey(serviceDate: DateTime(2026, 10, 8), legs: [
      RideLeg(routeId: '10', tripId: 't$h$m', boardStopId: 'a', alightStopId: 'b', departs: h * 3600 + m * 60,
          arrives: h * 3600 + m * 60 + 900, stopCount: 6, live: live),
    ]);

class _FixedTrips extends SavedTripsNotifier {
  @override
  Future<List<SavedTrip>> build() async => _savedTrips;
}

void main() {
  setUpAll(loadAppFonts);

  for (final b in Brightness.values) {
    testWidgets('arrival rows ${b.name}', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 520 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(kitHost(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [for (final r in _rows) Padding(padding: const EdgeInsets.only(bottom: 8), child: ArrivalRowTile(arrival: r, onTap: r.followableVehicle == null ? null : () {}))]),
        ),
        brightness: b,
      ));
      await expectLater(find.byType(Column).first, matchesGoldenFile('goldens/arrival_rows_${b.name}.png'));
    });

    testWidgets('plan a trip card ${b.name}', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 360 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          savedTripsProvider.overrideWith(_FixedTrips.new),
          savedTripNextProvider('home').overrideWith((ref) async => [_leaving(8, 12)]),
          savedTripNextProvider('mun').overrideWith((ref) async => [_leaving(8, 20, live: true)]),
          savedTripNextProvider('work').overrideWith((ref) async => const <Journey>[]),
        ],
        child: kitHost(
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [PlanTripCard()]),
          ),
          brightness: b,
          use24h: false,
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(find.byType(Padding).first, matchesGoldenFile('goldens/plan_trip_card_${b.name}.png'));
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
  }
}
