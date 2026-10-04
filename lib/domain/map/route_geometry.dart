import 'dart:math' as math;

import '../../data/gtfs/gtfs_models.dart';
import '../../data/gtfs/gtfs_repository.dart';
import '../../data/gtfs/gtfs_time.dart';
import '../../data/realtime/timetrack_models.dart';
import 'shape_matcher.dart';

/// A point on a shape and the direction of travel there (degrees, 0 = north).
typedef ShapePose = ({double lat, double lon, double heading});

/// Initial bearing from point 1 to point 2, in degrees clockwise from north.
double bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final y = math.sin(dLon) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Read-only route geometry for the motion engine, over [GtfsRepository]:
/// snapping to shapes, poses along them, stops in trip order and where the
/// timetable says a bus should be. Caches per trip and shape.
class RouteGeometry {
  RouteGeometry(this._repo);

  final GtfsRepository _repo;
  late final Map<String, List<StopTimeRow>> _stopTimesByTripId = _indexStopTimes();
  final Map<String, List<double?>> _stopProgressCache = {};

  Map<String, List<StopTimeRow>> _indexStopTimes() {
    final byTrip = <String, List<StopTimeRow>>{};
    for (final rows in _repo.stopTimesByStopId.values) {
      for (final row in rows) {
        byTrip.putIfAbsent(row.tripId, () => []).add(row);
      }
    }
    for (final rows in byTrip.values) {
      rows.sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    }
    return byTrip;
  }

  /// A fix this far from the shape is off route (detour, depot, bad GPS).
  static const double offRouteMeters = 150;

  String? shapeIdForTrip(String? tripId) => tripId == null ? null : _repo.tripsById[tripId]?.shapeId;

  /// When the trip is unknown: a shape of the same route number, narrowed by
  /// headsign, then by service.
  String? fallbackShapeId(TimeTrackVehicle v) {
    final candidates = _repo.tripsByRouteShortName[v.routeNumber.toString()];
    if (candidates == null || candidates.isEmpty) return null;
    var filtered = candidates;
    if (v.gtfsTripHeadsign.isNotEmpty) {
      final byHeadsign = filtered.where((e) => e.headsign.toLowerCase() == v.gtfsTripHeadsign.toLowerCase()).toList();
      if (byHeadsign.isNotEmpty) filtered = byHeadsign;
    }
    if (v.gtfsServiceId.isNotEmpty) {
      final byService = filtered.where((e) => e.serviceId == v.gtfsServiceId).toList();
      if (byService.isNotEmpty) filtered = byService;
    }
    return filtered.first.shapeId;
  }

  bool hasShape(String shapeId) =>
      (_repo.shapesById[shapeId]?.length ?? 0) >= 2 && _repo.shapeCumulativeDistances[shapeId] != null;

  /// Snaps to [shapeId]. Without [expectedAlong] this is the global nearest
  /// point. With it, the pass nearest the expectation wins; when a
  /// [minAlong]/[maxAlong] window holds nothing within [offRouteMeters], the
  /// window is dropped (real detours, long gaps).
  SnapResult? snap(double lat, double lon, String shapeId, {double? expectedAlong, double? minAlong, double? maxAlong}) {
    final points = _repo.shapesById[shapeId];
    final dists = _repo.shapeCumulativeDistances[shapeId];
    if (points == null || dists == null) return null;
    if (expectedAlong == null) {
      return ShapeMatcher.snapToShape(lat: lat, lon: lon, points: points, cumulativeDistances: dists);
    }
    final near = ShapeMatcher.snapNear(
      lat: lat, lon: lon, points: points, cumulativeDistances: dists,
      expectedAlong: expectedAlong, minAlong: minAlong, maxAlong: maxAlong,
    );
    if (near != null && near.perpendicularDistance <= offRouteMeters) return near;
    if (minAlong == null && maxAlong == null) return near;
    return ShapeMatcher.snapNear(lat: lat, lon: lon, points: points, cumulativeDistances: dists, expectedAlong: expectedAlong);
  }

  /// Position and heading [progress] metres along [shapeId], clamped to the
  /// shape's ends.
  ShapePose? poseAt(String shapeId, double progress) {
    final points = _repo.shapesById[shapeId];
    final dists = _repo.shapeCumulativeDistances[shapeId];
    if (points == null || dists == null || points.length < 2) return null;
    final p = progress.clamp(0.0, dists.last);
    var lo = 0;
    var hi = dists.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (dists[mid] <= p) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = points[lo];
    final b = points[hi];
    final seg = dists[hi] - dists[lo];
    final t = seg <= 0 ? 0.0 : (p - dists[lo]) / seg;
    // A zero-length segment (a duplicated point) has no direction: use the
    // nearest earlier segment that has one, else the nearest later one.
    var h = lo;
    while (h > 0 && dists[h + 1] - dists[h] <= 0) {
      h--;
    }
    if (dists[h + 1] - dists[h] <= 0) {
      h = lo;
      while (h < dists.length - 2 && dists[h + 1] - dists[h] <= 0) {
        h++;
      }
    }
    return (
      lat: a.lat + (b.lat - a.lat) * t,
      lon: a.lon + (b.lon - a.lon) * t,
      heading: bearingDegrees(points[h].lat, points[h].lon, points[h + 1].lat, points[h + 1].lon),
    );
  }

  /// Progress of each of [tripId]'s stop_times rows (stop_sequence order) on
  /// [shapeId], or null where a stop is unknown. Each stop is placed at or
  /// after the previous one, so a stop on a road the route uses twice lands
  /// on its own pass rather than the nearest one.
  List<double?> stopProgresses(String tripId, String shapeId) {
    final key = '$tripId|$shapeId';
    final cached = _stopProgressCache[key];
    if (cached != null) return cached;
    final rows = _stopTimesByTripId[tripId] ?? const <StopTimeRow>[];
    final points = _repo.shapesById[shapeId];
    final dists = _repo.shapeCumulativeDistances[shapeId];
    final result = <double?>[];
    double? previous;
    int? previousSeconds;
    for (final row in rows) {
      final stop = _repo.stopsById[row.stopId];
      final seconds = _secondsOf(row.departureTime);
      SnapResult? s;
      if (stop != null && points != null && dists != null) {
        if (previous == null) {
          s = ShapeMatcher.snapNear(
            lat: stop.stopLat, lon: stop.stopLon, points: points, cumulativeDistances: dists, expectedAlong: 0.0,
          );
        } else {
          // Forward only, and no further than the timetable allows: a stop
          // that can't be placed in that window is skipped, never snapped
          // somewhere else, so it can't drag the stops after it.
          final dt = seconds == null || previousSeconds == null ? 0 : math.max(0, seconds - previousSeconds);
          s = ShapeMatcher.snapNear(
            lat: stop.stopLat, lon: stop.stopLon, points: points, cumulativeDistances: dists,
            expectedAlong: previous, minAlong: previous - 5.0, maxAlong: previous + 300.0 + 30.0 * dt,
          );
        }
      }
      if (s != null && s.perpendicularDistance <= offRouteMeters) {
        result.add(s.distanceAlongRoute);
        previous = s.distanceAlongRoute;
        if (seconds != null) previousSeconds = seconds;
      } else {
        result.add(null);
      }
    }
    return _stopProgressCache[key] = List.unmodifiable(result);
  }

  /// Progress of the stop [tripId] departs closest to [departureSeconds]
  /// (within ±30 s; also matches trips past midnight).
  double? stopProgressAtTime(String tripId, String shapeId, int departureSeconds) {
    final rows = _stopTimesByTripId[tripId];
    if (rows == null) return null;
    final progresses = stopProgresses(tripId, shapeId);
    double? best;
    var bestGap = 31;
    for (var i = 0; i < rows.length; i++) {
      final seconds = _secondsOf(rows[i].departureTime);
      final progress = progresses[i];
      if (seconds == null || progress == null) continue;
      final gap = math.min(
        (seconds - departureSeconds).abs(),
        (seconds - (departureSeconds + Duration.secondsPerDay)).abs(),
      );
      if (gap < bestGap) {
        bestGap = gap;
        best = progress;
      }
    }
    return best;
  }

  /// Progress the timetable implies for [tripId] at [secondsOfDay], by linear
  /// interpolation between consecutive stops; null more than 20 minutes
  /// outside the trip. Trips past midnight (times above 24:00:00) are matched
  /// against [secondsOfDay] + 1 day.
  double? scheduledProgress(String tripId, String shapeId, int secondsOfDay) {
    final rows = _stopTimesByTripId[tripId];
    if (rows == null || rows.isEmpty) return null;
    final progresses = stopProgresses(tripId, shapeId);
    final times = <int>[];
    final along = <double>[];
    for (var i = 0; i < rows.length; i++) {
      final seconds = _secondsOf(rows[i].departureTime);
      final p = progresses[i];
      if (seconds == null || p == null) continue;
      times.add(seconds);
      along.add(p);
    }
    if (times.isEmpty) return null;
    const slack = 20 * 60;
    for (final now in [secondsOfDay, secondsOfDay + Duration.secondsPerDay]) {
      if (now < times.first - slack || now > times.last + slack) continue;
      if (now <= times.first) return along.first;
      if (now >= times.last) return along.last;
      for (var i = 0; i < times.length - 1; i++) {
        if (now >= times[i] && now <= times[i + 1]) {
          final span = times[i + 1] - times[i];
          final f = span == 0 ? 0.0 : (now - times[i]) / span;
          return along[i] + (along[i + 1] - along[i]) * f;
        }
      }
    }
    return null;
  }

  /// Where along [shapeId] a bus just starting to be tracked on [tripId]
  /// should be: the stop the feed says it is approaching, otherwise where
  /// the timetable, shifted by the reported delay, puts it at the fix time.
  double? initialHint(TimeTrackVehicle v, String? tripId, String shapeId) {
    if (tripId == null || tripId.isEmpty) return null;
    if (v.departureTimeAtClosestStop > 0) {
      final stop = stopProgressAtTime(tripId, shapeId, v.departureTimeAtClosestStop);
      if (stop != null) return stop;
    }
    if (v.positionTimeSeconds <= 0) return null;
    // Positive schedule difference = ahead: the bus is where the timetable
    // puts it that many minutes later.
    return scheduledProgress(tripId, shapeId, v.positionTimeSeconds + v.gtfsStopSequenceSchedDifferenceMins * 60);
  }

  int? _secondsOf(String gtfsTime) {
    try {
      return GtfsTime.parse(gtfsTime).totalSeconds;
    } catch (_) {
      return null;
    }
  }
}
