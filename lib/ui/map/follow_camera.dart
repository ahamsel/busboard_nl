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

  DateTime? _last;

  /// The next move may happen at once (the rider asked to be taken back).
  void reset() => _last = null;

  CameraMove? next({required LatLng bus, LatLng? stop, required DateTime now}) {
    final last = _last;
    if (last != null && now.difference(last) < interval) return null;
    _last = now;
    if (stop == null) return CenterMove(bus, soloZoom);
    final d = NearestStopService.haversineDistance(bus.latitude, bus.longitude, stop.latitude, stop.longitude);
    if (d < closeMeters) {
      return CenterMove(LatLng((bus.latitude + stop.latitude) / 2, (bus.longitude + stop.longitude) / 2), nearZoom);
    }
    return FitMove(bus, stop);
  }
}
