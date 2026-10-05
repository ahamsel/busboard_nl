import 'dart:math' as math;

import 'package:flutter/widgets.dart' show EdgeInsets, Size;
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../domain/location/nearest_stop_service.dart';

sealed class CameraMove {
  const CameraMove();
}

class FitMove extends CameraMove {
  const FitMove(this.bus, this.stop);
  final LatLng bus;
  final LatLng stop;
}

class CenterMove extends CameraMove {
  const CenterMove(this.target, this.zoom);
  final LatLng target;
  final double zoom;
}

/// Where the follow camera goes (spec §3.5): the bus and your stop in view,
/// closing in as the bus arrives; at most one move a second.
class FollowCamera {
  static const interval = Duration(seconds: 1);
  static const double closeMeters = 250;
  static const double nearZoom = 16.5;
  static const double soloZoom = 15.5;

  /// Metres per logical point at zoom 0 on the equator. MapLibre Native's
  /// world is 512 points wide at zoom 0 (512-point tiles), so this is half
  /// the 156543.03 of 256-pixel web tiles.
  static const double _metresPerPointAtZoom0 = 40075016.686 / 512;

  DateTime? _last;

  /// The next move may happen at once (the rider asked to be taken back).
  void reset() => _last = null;

  /// [padding] is the part of the view kept clear (chips, peeking sheet), as
  /// for a [FitMove]: a centre move puts its point in the middle of what is
  /// left, not of the whole view.
  CameraMove? next({required LatLng bus, LatLng? stop, required DateTime now, EdgeInsets padding = EdgeInsets.zero}) {
    final last = _last;
    if (last != null && now.difference(last) < interval) return null;
    _last = now;
    if (stop == null) return CenterMove(_inWindow(bus, soloZoom, padding), soloZoom);
    final d = NearestStopService.haversineDistance(bus.latitude, bus.longitude, stop.latitude, stop.longitude);
    if (d < closeMeters) {
      final mid = LatLng((bus.latitude + stop.latitude) / 2, (bus.longitude + stop.longitude) / 2);
      return CenterMove(_inWindow(mid, nearZoom, padding), nearZoom);
    }
    return FitMove(bus, stop);
  }

  /// The camera (centre and zoom, north-up) that shows [a] and [b] inside the
  /// part of a [view] left clear by [padding], filling it along the tighter
  /// side, never closer than [maxZoom]. Web Mercator on MapLibre's 512-point
  /// world. Computed here rather than with the platform's bounds fit, because
  /// MapLibre iOS centres the bounds as if the padding were symmetric: with a
  /// tall card below and chips above, the far point was drawn under the card.
  static ({LatLng target, double zoom}) fitCamera(
    LatLng a,
    LatLng b, {
    required EdgeInsets padding,
    required Size view,
    double maxZoom = 18,
  }) {
    final w = math.max(1.0, view.width - padding.horizontal);
    final h = math.max(1.0, view.height - padding.vertical);
    final ax = _mercX(a.longitude), ay = _mercY(a.latitude);
    final bx = _mercX(b.longitude), by = _mercY(b.latitude);
    final dx = (ax - bx).abs(), dy = (ay - by).abs();
    final worldFit = math.min(dx == 0 ? double.infinity : w / dx, dy == 0 ? double.infinity : h / dy);
    final zoom = worldFit.isInfinite ? maxZoom : math.min(maxZoom, math.log(worldFit / _worldPoints) / math.ln2);
    final world = _worldPoints * math.pow(2, zoom);
    // The middle of the two points goes to the middle of the window, which
    // sits off the view's centre by half the padding difference.
    final cx = (ax + bx) / 2 - (padding.left - padding.right) / 2 / world;
    final cy = (ay + by) / 2 - (padding.top - padding.bottom) / 2 / world;
    return (target: LatLng(_latOf(cy), cx * 360 - 180), zoom: zoom);
  }

  /// MapLibre Native's world width at zoom 0, in points.
  static const double _worldPoints = 512;

  static double _mercX(double lon) => (lon + 180) / 360;

  static double _mercY(double lat) {
    final r = lat * math.pi / 180;
    return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
  }

  static double _latOf(double y) {
    final n = math.pi * (1 - 2 * y);
    return math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
  }

  /// The camera centre that shows [point] in the middle of the padded window
  /// at [zoom] on a north-up map: more padding below moves the centre south,
  /// so the point is drawn higher.
  static LatLng _inWindow(LatLng point, double zoom, EdgeInsets padding) {
    final down = (padding.bottom - padding.top) / 2; // points
    final right = (padding.right - padding.left) / 2;
    if (down == 0 && right == 0) return point;
    final cosLat = math.cos(point.latitude * math.pi / 180);
    final metresPerPoint = _metresPerPointAtZoom0 * cosLat / math.pow(2, zoom);
    const metresPerDegree = 111320.0;
    return LatLng(
      point.latitude - down * metresPerPoint / metresPerDegree,
      point.longitude + right * metresPerPoint / (metresPerDegree * cosLat),
    );
  }
}
