import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../domain/location/nearest_stop_service.dart';
import 'map_layers.dart';

/// Tap radius in metres: ~200 m at zoom 13, halving per zoom level (smoothly) to ~6 m at 18.
double tapRadiusMeters(double zoom) => 200.0 / math.pow(2, zoom.clamp(13, 18) - 13);

double _dist(LatLng a, double lat, double lon) =>
    NearestStopService.haversineDistance(a.latitude, a.longitude, lat, lon);

/// The vehicle ID of the drawn bus closest to [tap] within [radius] metres.
String? nearestBus(LatLng tap, double radius, List<BusMarker> drawn) {
  String? best;
  var bestDist = radius;
  for (final m in drawn) {
    final d = _dist(tap, m.lat, m.lon);
    if (d < bestDist) {
      best = m.vehicleId;
      bestDist = d;
    }
  }
  return best;
}

StopInfo? nearestStop(LatLng tap, double radius, Iterable<StopInfo> stops) {
  StopInfo? best;
  var bestDist = radius;
  for (final s in stops) {
    final d = _dist(tap, s.stopLat, s.stopLon);
    if (d < bestDist) {
      best = s;
      bestDist = d;
    }
  }
  return best;
}
