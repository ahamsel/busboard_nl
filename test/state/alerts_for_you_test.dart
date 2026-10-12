import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/alerts_for_you_provider.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

ServiceAlert _alert(String header, List<ServiceAlertTarget> targets) => ServiceAlert(
      sourceIds: {header},
      header: header,
      description: '',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
      targets: targets,
    );

final _onRoute10 = _alert('Detour on 10', const [ServiceAlertTarget(routeId: '10')]);
final _onStop1150 = _alert('Stop 1150 closed', const [ServiceAlertTarget(stopId: '1150')]);
final _onRoute99 = _alert('Detour on 99', const [ServiceAlertTarget(routeId: '99')]);
final _onRoute24 = _alert('Detour on 24', const [ServiceAlertTarget(routeId: '24')]);

/// Stop 1150 is served by route 10; route 24 serves only stop 2000, which no one has chosen.
GtfsRepository _repo() {
  final repo = GtfsRepository();
  repo.stopsById['1150'] = const StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.57, stopLon: -52.73);
  for (final r in ['10', '24', '99']) {
    repo.routesById['r$r'] = RouteInfo(routeId: 'r$r', routeShortName: r, routeLongName: '');
  }
  repo.tripsById['t10'] = const TripInfo(tripId: 't10', routeId: 'r10', serviceId: 's', tripHeadsign: '', directionId: 0);
  repo.tripsById['t24'] = const TripInfo(tripId: 't24', routeId: 'r24', serviceId: 's', tripHeadsign: '', directionId: 0);
  repo.stopTimesByStopId['1150'] = const [
    StopTimeRow(tripId: 't10', arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1),
  ];
  repo.stopTimesByStopId['2000'] = const [
    StopTimeRow(tripId: 't24', arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '2000', stopSequence: 1),
  ];
  return repo;
}

class _FixedSettings extends SettingsNotifier {
  _FixedSettings(this.stopId);
  final String? stopId;
  @override
  AppSettings build() => AppSettings(selectedStopId: stopId);
}

class _FixedSavedTrips extends SavedTripsNotifier {
  _FixedSavedTrips(this.trips);
  final List<SavedTrip> trips;
  @override
  Future<List<SavedTrip>> build() async => trips;
}

final _trip = SavedTrip(
  id: 'trip-1',
  name: 'To work',
  from: StopPlace(stopId: '2000', name: 'Elsewhere'),
  to: StopPlace(stopId: '1150', name: 'MUN Centre'),
);

Journey _ridingRoute24() => Journey(
      serviceDate: DateTime(2026, 10, 12),
      legs: [
        RideLeg(
          routeId: 'r24',
          tripId: 't24',
          boardStopId: '2000',
          alightStopId: '1150',
          departs: 8 * 3600,
          arrives: 8 * 3600 + 600,
          stopCount: 2,
        ),
      ],
    );

Future<ProviderContainer> _container({
  String? stopId = '1150',
  List<SavedTrip> trips = const [],
  List<Override> extra = const [],
}) async {
  final container = ProviderContainer(overrides: [
    serviceUpdatesProvider.overrideWith((ref) => Stream.value(ServiceUpdates(
          alerts: [_onRoute10, _onStop1150, _onRoute99, _onRoute24],
          serviceStatus: null,
          fetchedAt: DateTime(2026, 10, 12),
          feedTimestamp: null,
        ))),
    gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
    settingsProvider.overrideWith(() => _FixedSettings(stopId)),
    savedTripsProvider.overrideWith(() => _FixedSavedTrips(trips)),
    ...extra,
  ]);
  addTearDown(container.dispose);
  // A provider nobody listens to is paused (Riverpod 3), and a paused stream never delivers.
  container.listen(serviceUpdatesProvider, (_, _) {});
  container.listen(gtfsRepositoryProvider, (_, _) {});
  container.listen(savedTripsProvider, (_, _) {});
  container.listen(alertsForYouProvider, (_, _) {});
  await container.read(serviceUpdatesProvider.future);
  await container.read(gtfsRepositoryProvider.future);
  await container.read(savedTripsProvider.future);
  return container;
}

void main() {
  test('only alerts on your stop, its routes or your saved trips\' routes', () async {
    final container = await _container();
    expect(container.read(alertsForYouProvider).map((a) => a.header), ['Detour on 10', 'Stop 1150 closed']);
  });

  test('a saved trip\'s next bus adds its route', () async {
    final container = await _container(
      trips: [_trip],
      extra: [savedTripNextProvider('trip-1').overrideWith((ref) async => [_ridingRoute24()])],
    );
    container.listen(savedTripNextProvider('trip-1'), (_, _) {});
    await container.read(savedTripNextProvider('trip-1').future);
    expect(container.read(alertsForYouProvider).map((a) => a.header), ['Detour on 10', 'Stop 1150 closed', 'Detour on 24']);
  });

  test('with no stop and no saved trips there is nothing for you', () async {
    final container = await _container(stopId: null);
    expect(container.read(alertsForYouProvider), isEmpty);
  });

  test('nothing until the alerts and the schedule have loaded', () {
    final container = ProviderContainer(overrides: [
      serviceUpdatesProvider.overrideWith((ref) => const Stream.empty()),
      gtfsRepositoryProvider.overrideWith((ref) => Future<GtfsRepository>.delayed(const Duration(days: 1))),
      settingsProvider.overrideWith(() => _FixedSettings('1150')),
      savedTripsProvider.overrideWith(() => _FixedSavedTrips(const [])),
    ]);
    addTearDown(container.dispose);
    container.listen(alertsForYouProvider, (_, _) {});
    expect(container.read(alertsForYouProvider), isEmpty);
  });
}
