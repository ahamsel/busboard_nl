import 'dart:math';
import '../../data/gtfs/gtfs_models.dart';

/// Result of a nearest stop query.
class NearbyStop {
  final StopInfo stop;

  /// Distance in meters from the query point.
  final double distanceMeters;

  const NearbyStop({required this.stop, required this.distanceMeters});

  /// Display distance as a human-friendly string.
  String get distanceDisplay {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()}m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
  }
}

/// Finds the nearest bus stops using haversine distance.
class NearestStopService {
  static const _earthRadiusMeters = 6371000.0;
  static const _defaultMaxDistance = 800.0; // meters
  static const _defaultMaxResults = 10;

  /// Find the nearest stops to [latitude], [longitude].
  ///
  /// Returns up to [maxResults] stops within [maxDistance] meters,
  /// sorted by distance.
  List<NearbyStop> findNearestStops({
    required double latitude,
    required double longitude,
    required Iterable<StopInfo> allStops,
    double maxDistance = _defaultMaxDistance,
    int maxResults = _defaultMaxResults,
  }) {
    final nearby = <NearbyStop>[];

    for (final stop in allStops) {
      final distance = haversineDistance(
        latitude,
        longitude,
        stop.stopLat,
        stop.stopLon,
      );

      if (distance <= maxDistance) {
        nearby.add(NearbyStop(stop: stop, distanceMeters: distance));
      }
    }

    // Sort by distance
    nearby.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    // Return up to maxResults
    return nearby.take(maxResults).toList();
  }

  /// Calculate the haversine distance between two points in meters.
  static double haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return _earthRadiusMeters * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180.0;
}
