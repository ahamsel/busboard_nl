import 'dart:math' as math;

/// The farthest a rider walks to their first stop or from their last (spec §3.2).
const maxAccessMeters = 800.0;

/// The farthest a rider walks between two stops to change buses.
const maxTransferMeters = 400.0;

/// Straight-line distance × this, for the streets in between.
const walkDetourFactor = 1.3;

/// 4.5 km/h.
const walkSpeedMetersPerSecond = 4.5 / 3.6;

/// Changing buses at the same stop takes at least this long.
const minTransferSeconds = 60;

double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Walking time for a straight-line distance, in seconds, rounded up to the whole minute.
int walkSeconds(double straightMeters) {
  if (straightMeters <= 0) return 0;
  final seconds = straightMeters * walkDetourFactor / walkSpeedMetersPerSecond;
  return (seconds / 60).ceil() * 60;
}
