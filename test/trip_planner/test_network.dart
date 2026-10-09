import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';

/// A tiny Metrobus-like network, built straight into a repository (as test/ui/arrival_board_screen_test.dart does).
///
///   Route 1:  A — B — C        trips leave A every 10 min from 08:00 (6 trips), 5 min between stops
///   Route 2:        C — D — E  trips leave C every 15 min from 08:05 (4 trips), 4 min between stops
///   Route 3:  F — E            one trip, F 08:40 → E 08:50
///   Route 9:  X — Y — Z        one late trip, X 23:50 → Y 24:20 → Z 24:50 (past midnight)
/// Stop G is about 300 m from C (a 6-minute walk); H is far from everything. Service runs every day of 2026.
class TestNetwork {
  final GtfsRepository repo = _BuiltRepository();
  static const serviceId = 'WK';

  TestNetwork() {
    _stop('A', 47.5600, -52.7500);
    _stop('B', 47.5650, -52.7500);
    _stop('C', 47.5700, -52.7500);
    _stop('D', 47.5750, -52.7500);
    _stop('E', 47.5800, -52.7500);
    _stop('F', 47.5900, -52.7600);
    _stop('G', 47.5700, -52.7460);
    _stop('H', 47.5400, -52.7000);
    _stop('X', 47.5000, -52.8000);
    _stop('Y', 47.5050, -52.8000);
    _stop('Z', 47.5100, -52.8000);
    for (final r in ['1', '2', '3', '9']) {
      repo.routesById[r] = RouteInfo(routeId: r, routeShortName: r, routeLongName: 'Route $r');
    }
    for (var i = 0; i < 6; i++) {
      addTrip('1-$i', '1', ['A', 'B', 'C'], 8 * 3600 + i * 600, 300);
    }
    for (var i = 0; i < 4; i++) {
      addTrip('2-$i', '2', ['C', 'D', 'E'], 8 * 3600 + 300 + i * 900, 240);
    }
    addTrip('3-0', '3', ['F', 'E'], 8 * 3600 + 2400, 600);
    addTrip('9-0', '9', ['X', 'Y', 'Z'], 23 * 3600 + 50 * 60, 1800);
    repo.calendarsById[serviceId] = ServiceCalendar(
      serviceId: serviceId,
      monday: true,
      tuesday: true,
      wednesday: true,
      thursday: true,
      friday: true,
      saturday: true,
      sunday: true,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
    );
  }

  void _stop(String id, double lat, double lon) =>
      repo.stopsById[id] = StopInfo(stopId: id, stopName: 'Stop $id', stopLat: lat, stopLon: lon);

  /// A trip leaving its first stop at [start] seconds after midnight, [hop] seconds between stops.
  void addTrip(String tripId, String routeId, List<String> stops, int start, int hop) {
    repo.tripsById[tripId] = TripInfo(
      tripId: tripId,
      routeId: routeId,
      serviceId: serviceId,
      tripHeadsign: stops.last,
      directionId: 0,
    );
    for (var i = 0; i < stops.length; i++) {
      final t = _hms(start + i * hop);
      repo.stopTimesByStopId.putIfAbsent(stops[i], () => []).add(
            StopTimeRow(tripId: tripId, arrivalTime: t, departureTime: t, stopId: stops[i], stopSequence: i + 1),
          );
    }
  }

  static String _hms(int s) => [s ~/ 3600, s % 3600 ~/ 60, s % 60].map((v) => v.toString().padLeft(2, '0')).join(':');
}

/// Built in memory rather than loaded from a feed, but as ready as a loaded one (the Board's arrivals check).
class _BuiltRepository extends GtfsRepository {
  @override
  bool get isLoaded => true;
}

/// A Wednesday the test calendar covers.
final testDay = DateTime(2026, 10, 7);
