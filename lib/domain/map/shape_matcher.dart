import '../../data/gtfs/gtfs_models.dart';
import '../location/nearest_stop_service.dart';

/// Result of snapping a GPS point to a polyline shape.
class SnapResult {
  final double snappedLat;
  final double snappedLon;
  final double distanceAlongRoute;
  final double perpendicularDistance;

  const SnapResult({
    required this.snappedLat,
    required this.snappedLon,
    required this.distanceAlongRoute,
    required this.perpendicularDistance,
  });
}

/// Snaps GPS coordinates to the nearest point on a GTFS shape polyline.
class ShapeMatcher {
  /// Snap a GPS point to the nearest position on a shape polyline.
  ///
  /// [points] must be sorted by sequence. [cumulativeDistances] must have
  /// the same length, with element i being the cumulative haversine distance
  /// from point 0 to point i.
  static SnapResult? snapToShape({
    required double lat,
    required double lon,
    required List<ShapePoint> points,
    required List<double> cumulativeDistances,
  }) {
    if (points.length < 2) return null;

    double bestDist = double.infinity;
    double bestLat = 0;
    double bestLon = 0;
    double bestDistAlong = 0;

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];

      final result = _projectToSegment(lat, lon, a.lat, a.lon, b.lat, b.lon);
      final projLat = result.$1;
      final projLon = result.$2;
      final t = result.$3;

      final dist = NearestStopService.haversineDistance(
        lat,
        lon,
        projLat,
        projLon,
      );

      if (dist < bestDist) {
        bestDist = dist;
        bestLat = projLat;
        bestLon = projLon;

        // Interpolate distance along route
        final segLen =
            cumulativeDistances[i + 1] - cumulativeDistances[i];
        bestDistAlong = cumulativeDistances[i] + segLen * t;
      }
    }

    return SnapResult(
      snappedLat: bestLat,
      snappedLon: bestLon,
      distanceAlongRoute: bestDistAlong,
      perpendicularDistance: bestDist,
    );
  }

  /// Project point (px, py) onto segment (ax, ay)→(bx, by).
  /// Returns (projLat, projLon, t) where t is clamped to [0, 1].
  static (double, double, double) _projectToSegment(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;

    if (lenSq < 1e-12) {
      return (ax, ay, 0.0);
    }

    var t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
    t = t.clamp(0.0, 1.0);

    return (ax + t * dx, ay + t * dy, t);
  }
}
