import 'bus_track.dart';
import 'route_geometry.dart';

/// Where to draw one bus this frame.
class RenderedBus {
  const RenderedBus({
    required this.vehicleId,
    required this.lat,
    required this.lon,
    required this.heading,
    this.progress,
    this.shapeId,
    this.tripId,
  });

  final String vehicleId;
  final double lat;
  final double lon;
  final double heading;
  final double? progress;
  final String? shapeId;
  final String? tripId;
}

/// Draws each bus about one GPS update behind live, gliding along its route
/// between two real fixes (spec §3.4): render time = now − D, interpolated by
/// distance along the shape, never backward on the same trip; geographic
/// interpolation across a trip change or off route; at most
/// [maxExtrapolation] past the newest fix, then hold.
class DelayedTrackRenderer {
  DelayedTrackRenderer(this._geometry);

  final RouteGeometry _geometry;

  /// The furthest progress drawn per bus, on the trip it was drawn on.
  final Map<String, ({String? tripId, double progress})> _highWater = {};

  static const Duration minDelay = Duration(seconds: 8);
  static const Duration maxDelay = Duration(seconds: 20);
  static const Duration defaultDelay = Duration(seconds: 12);
  static const Duration maxExtrapolation = Duration(seconds: 5);
  static const Duration _delayMargin = Duration(seconds: 2);
  static const int _delaySamples = 8;

  /// Median interval between the track's last fixes, plus 2 s, clamped to
  /// [minDelay]..[maxDelay]; [defaultDelay] with fewer than two fixes.
  Duration delayFor(BusTrack track) {
    final fixes = track.fixes;
    if (fixes.length < 2) return defaultDelay;
    final intervals = <int>[];
    for (var i = fixes.length - 1; i > 0 && intervals.length < _delaySamples; i--) {
      intervals.add(fixes[i].gpsTime.difference(fixes[i - 1].gpsTime).inMilliseconds);
    }
    intervals.sort();
    final mid = intervals.length ~/ 2;
    final median = intervals.length.isOdd ? intervals[mid] : (intervals[mid - 1] + intervals[mid]) ~/ 2;
    final ms = (median + _delayMargin.inMilliseconds).clamp(minDelay.inMilliseconds, maxDelay.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  Map<String, RenderedBus> renderAll(Iterable<BusTrack> tracks, DateTime now) =>
      {for (final t in tracks) t.vehicleId: render(t, now)};

  void forget(String vehicleId) => _highWater.remove(vehicleId);

  RenderedBus render(BusTrack track, DateTime now) {
    final fixes = track.fixes;
    final at = now.subtract(delayFor(track));
    RenderedBus bus;
    if (!at.isAfter(fixes.first.gpsTime)) {
      bus = _atFix(track.vehicleId, fixes.first);
    } else if (!at.isBefore(fixes.last.gpsTime)) {
      bus = _beyondLast(track, at);
    } else {
      var i = fixes.length - 2;
      while (i > 0 && fixes[i].gpsTime.isAfter(at)) {
        i--;
      }
      final a = fixes[i];
      final b = fixes[i + 1];
      final span = b.gpsTime.difference(a.gpsTime).inMicroseconds;
      final f = span <= 0 ? 1.0 : at.difference(a.gpsTime).inMicroseconds / span;
      bus = _between(track.vehicleId, a, b, f.clamp(0.0, 1.0));
    }
    return _neverBackward(bus);
  }

  RenderedBus _atFix(String id, TrackFix f) {
    if (f.progress != null && f.shapeId != null) {
      return _onShape(id, f.shapeId!, f.progress!, f.tripId) ?? _raw(id, f.lat, f.lon, f.heading, f.tripId);
    }
    return _raw(id, f.lat, f.lon, f.heading, f.tripId);
  }

  RenderedBus _between(String id, TrackFix a, TrackFix b, double f) {
    final sameAxis = a.tripId == b.tripId && a.shapeId != null && a.shapeId == b.shapeId && a.progress != null && b.progress != null;
    if (sameAxis) {
      final p = a.progress! + (b.progress! - a.progress!) * f;
      final onShape = _onShape(id, a.shapeId!, p, b.tripId);
      if (onShape != null) return onShape;
    }
    final aLat = a.snappedLat ?? a.lat;
    final aLon = a.snappedLon ?? a.lon;
    final bLat = b.snappedLat ?? b.lat;
    final bLon = b.snappedLon ?? b.lon;
    final heading = (aLat == bLat && aLon == bLon) ? b.heading : bearingDegrees(aLat, aLon, bLat, bLon);
    return _raw(id, aLat + (bLat - aLat) * f, aLon + (bLon - aLon) * f, heading, f < 0.5 ? a.tripId : b.tripId);
  }

  RenderedBus _beyondLast(BusTrack track, DateTime at) {
    final fixes = track.fixes;
    final last = fixes.last;
    if (fixes.length >= 2 && last.progress != null && last.shapeId != null) {
      final prev = fixes[fixes.length - 2];
      if (prev.tripId == last.tripId && prev.shapeId == last.shapeId && prev.progress != null) {
        final segSeconds = last.gpsTime.difference(prev.gpsTime).inMilliseconds / 1000.0;
        final speed = segSeconds <= 0 ? 0.0 : ((last.progress! - prev.progress!) / segSeconds).clamp(0.0, 30.0);
        final past = at.difference(last.gpsTime);
        final ahead = (past > maxExtrapolation ? maxExtrapolation : past).inMilliseconds / 1000.0;
        final onShape = _onShape(track.vehicleId, last.shapeId!, last.progress! + speed * ahead, last.tripId);
        if (onShape != null) return onShape;
      }
    }
    return _atFix(track.vehicleId, last);
  }

  RenderedBus? _onShape(String id, String shapeId, double progress, String? tripId) {
    final pose = _geometry.poseAt(shapeId, progress);
    if (pose == null) return null;
    return RenderedBus(vehicleId: id, lat: pose.lat, lon: pose.lon, heading: pose.heading, progress: progress, shapeId: shapeId, tripId: tripId);
  }

  RenderedBus _raw(String id, double lat, double lon, double heading, String? tripId) =>
      RenderedBus(vehicleId: id, lat: lat, lon: lon, heading: heading, tripId: tripId);

  RenderedBus _neverBackward(RenderedBus bus) {
    final p = bus.progress;
    if (p == null || bus.shapeId == null) return bus;
    final hw = _highWater[bus.vehicleId];
    if (hw != null && hw.tripId == bus.tripId && p < hw.progress) {
      return _onShape(bus.vehicleId, bus.shapeId!, hw.progress, bus.tripId) ?? bus;
    }
    _highWater[bus.vehicleId] = (tripId: bus.tripId, progress: p);
    return bus;
  }
}
