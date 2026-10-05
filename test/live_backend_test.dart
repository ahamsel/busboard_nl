import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/service_alerts_api.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/domain/map/bus_track_store.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const runLive = bool.fromEnvironment('RUN_LIVE_METROBUS_TESTS');

  test(
    'current Metrobus backend returns standard live vehicle data',
    () async {
      final api = TimeTrackApi();
      addTearDown(api.dispose);

      final result = await api.fetchVehiclesResult();
      final uniqueVehicles = result.vehicles
          .map((vehicle) => vehicle.vehicle)
          .where((vehicle) => vehicle.isNotEmpty)
          .toSet();
      final store = BusTrackStore(RouteGeometry(GtfsRepository()));
      store.ingest(result.vehicles, DateTime.now());

      // ignore: avoid_print
      print(
        '[LiveBackend] source=${result.source?.label} '
        'rows=${result.vehicles.length} '
        'physicalVehicles=${uniqueVehicles.length}',
      );
      expect(result.succeeded, isTrue);
      expect(result.source, LiveDataSource.gtfsRealtime);
      expect(result.vehicles, isNotEmpty);
      expect(uniqueVehicles, isNotEmpty);
      expect(store.tracks.length, uniqueVehicles.length);
      expect(
        result.vehicles.where(
          (vehicle) =>
              vehicle.busLat != 0 &&
              vehicle.busLon != 0 &&
              vehicle.gtfsTripId.isNotEmpty,
        ),
        isNotEmpty,
      );
    },
    skip: runLive ? false : 'Set RUN_LIVE_METROBUS_TESTS=1',
  );

  test(
    'current Metrobus backend returns service alerts and network status',
    () async {
      final api = ServiceAlertsApi();
      addTearDown(api.dispose);

      final updates = await api.fetchUpdates();

      // ignore: avoid_print
      print(
        '[LiveAlerts] alerts=${updates.alerts.length} '
        'active=${updates.activeAlertsAt(DateTime.now()).length} '
        'status=${updates.serviceStatus?.message}',
      );
      expect(updates.feedTimestamp, isNotNull);
      expect(updates.serviceStatus, isNotNull);
    },
    skip: runLive ? false : 'Set RUN_LIVE_METROBUS_TESTS=1',
  );

  test(
    'current Metrobus kiosk returns structured stop predictions',
    () async {
      final api = MetrobusMobileApi();
      addTearDown(api.dispose);

      final result = await api.fetchDeparturesResult('2735');
      final realtimeCount = result.departures
          .where((departure) => departure.isRealtime)
          .length;

      // ignore: avoid_print
      print(
        '[LiveStop] source=${result.source?.name} '
        'departures=${result.departures.length} '
        'realtime=$realtimeCount',
      );
      expect(result.succeeded, isTrue);
      expect(result.source, MetrobusDepartureSource.timeTrackJson);
      for (final departure in result.departures) {
        expect(departure.routeShortName, isNotEmpty);
        expect(departure.tripId, isNotEmpty);
        expect(departure.scheduledGtfsTime, isNotNull);
      }
    },
    skip: runLive ? false : 'Set RUN_LIVE_METROBUS_TESTS=1',
  );
}
