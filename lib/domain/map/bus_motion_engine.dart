import '../../data/gtfs/gtfs_repository.dart';
import '../../data/realtime/timetrack_models.dart';
import '../location/nearest_stop_service.dart';
import 'bus_observation.dart';
import 'bus_tracking_state.dart';
import 'shape_matcher.dart';

/// Processes raw TimeTrack vehicle batches into smoothed bus tracking states.
///
/// Handles outlier rejection, shape matching, backward clamping,
/// stopped detection, and interpolation for smooth map animation.
class BusMotionEngine {
  final GtfsRepository _repo;
  final Map<String, BusTrackingState> _states = {};
  static const _maxObservations = 10;
  static const _maxSpeedKmh = 140.0;
  static const _offRouteThresholdMeters = 150.0;
  static const _backwardSmallThreshold = 30.0;
  static const _backwardLargeThreshold = 80.0;
  static const _stoppedDistanceMeters = 15.0;
  static const _stoppedDuration = Duration(minutes: 2);
  static const _staleDuration = Duration(minutes: 5);
  static const _maxExtrapolationSeconds = 5.0;
  static const _maxExtrapolationSpeedKmh = 80.0;

  /// Counter for consecutive backward movements per bus.
  final Map<String, int> _backwardCount = {};

  BusMotionEngine(this._repo);

  Map<String, BusTrackingState> get states =>
      Map.unmodifiable(_states);

  /// Process a batch of vehicles from the TimeTrack API.
  void processBatch(List<TimeTrackVehicle> vehicles, DateTime fetchTime) {
    final seenKeys = <String>{};

    for (final v in vehicles) {
      if (v.routeRun.isEmpty || v.busLat == 0.0 || v.busLon == 0.0) continue;

      seenKeys.add(v.routeRun);

      final headingDeg = double.tryParse(v.heading) ?? 0.0;
      final obs = BusObservation(
        timestamp: fetchTime,
        lat: v.busLat,
        lon: v.busLon,
        heading: headingDeg,
        speed: v.speed,
        gtfsTripId: v.gtfsTripId.isNotEmpty ? v.gtfsTripId : null,
      );

      final existing = _states[v.routeRun];

      if (existing == null) {
        // New bus
        _states[v.routeRun] = _createNewState(v, obs);
        continue;
      }

      _updateExisting(v.routeRun, existing, obs, v);
    }

    // Mark unseen buses as stale or prune
    final toRemove = <String>[];
    for (final entry in _states.entries) {
      if (!seenKeys.contains(entry.key)) {
        final age = fetchTime.difference(entry.value.lastUpdateTime);
        if (age > _staleDuration) {
          toRemove.add(entry.key);
        } else {
          _states[entry.key] = entry.value.copyWith(status: BusStatus.stale);
        }
      }
    }
    for (final key in toRemove) {
      _states.remove(key);
      _backwardCount.remove(key);
    }
  }

  BusTrackingState _createNewState(
    TimeTrackVehicle v,
    BusObservation obs,
  ) {
    String? shapeId;
    double? progress;

    if (obs.gtfsTripId != null) {
      final trip = _repo.tripsById[obs.gtfsTripId];
      shapeId = trip?.shapeId;
      if (shapeId != null) {
        final snap = _trySnap(obs.lat, obs.lon, shapeId);
        if (snap != null && snap.perpendicularDistance <= _offRouteThresholdMeters) {
          progress = snap.distanceAlongRoute;
        }
      }
    }

    return BusTrackingState(
      routeRun: v.routeRun,
      vehicleId: v.vehicle,
      routeNumber: v.routeNumber,
      headsign: v.gtfsTripHeadsign,
      currentTripId: obs.gtfsTripId,
      shapeId: shapeId,
      observations: [obs],
      smoothedLat: obs.lat,
      smoothedLon: obs.lon,
      smoothedHeading: obs.heading,
      progressAlongRoute: progress,
      status: BusStatus.active,
      lastUpdateTime: obs.timestamp,
    );
  }

  void _updateExisting(
    String key,
    BusTrackingState state,
    BusObservation obs,
    TimeTrackVehicle v,
  ) {
    // Outlier rejection: check implied speed
    final lastGood = state.observations.lastWhere(
      (o) => !o.rejected,
      orElse: () => state.observations.last,
    );
    final dtSeconds = obs.timestamp.difference(lastGood.timestamp).inMilliseconds / 1000.0;

    if (dtSeconds > 0.5) {
      final dist = NearestStopService.haversineDistance(
        lastGood.lat,
        lastGood.lon,
        obs.lat,
        obs.lon,
      );
      final impliedSpeedKmh = (dist / dtSeconds) * 3.6;
      if (impliedSpeedKmh > _maxSpeedKmh) {
        // Reject this observation
        final rejected = obs.copyWith(rejected: true);
        final newObs = _addObservation(state.observations, rejected);
        _states[key] = state.copyWith(
          observations: newObs,
          lastUpdateTime: obs.timestamp,
        );
        return;
      }
    }

    // Shape matching
    String? shapeId = state.shapeId;
    double? progress = state.progressAlongRoute;
    var status = BusStatus.active;

    if (obs.gtfsTripId != null && obs.gtfsTripId != state.currentTripId) {
      // Trip changed — re-resolve shape
      final trip = _repo.tripsById[obs.gtfsTripId];
      shapeId = trip?.shapeId;
    }

    if (shapeId != null) {
      final snap = _trySnap(obs.lat, obs.lon, shapeId);
      if (snap != null) {
        if (snap.perpendicularDistance > _offRouteThresholdMeters) {
          status = BusStatus.offRoute;
          // Use raw GPS, don't update progress
        } else {
          // Check backward movement
          if (progress != null && snap.distanceAlongRoute < progress) {
            final backward = progress - snap.distanceAlongRoute;
            if (backward < _backwardSmallThreshold) {
              // Small backward — clamp to previous
              // progress stays the same
            } else if (backward > _backwardLargeThreshold) {
              _backwardCount[key] = (_backwardCount[key] ?? 0) + 1;
              if ((_backwardCount[key] ?? 0) >= 3) {
                // Allow — real detour
                progress = snap.distanceAlongRoute;
                _backwardCount[key] = 0;
              } else {
                status = BusStatus.backtracking;
              }
            } else {
              // Medium backward — clamp
              _backwardCount[key] = (_backwardCount[key] ?? 0) + 1;
            }
          } else {
            progress = snap.distanceAlongRoute;
            _backwardCount[key] = 0;
          }
        }
      }
    }

    // Stopped detection
    if (dtSeconds > _stoppedDuration.inSeconds) {
      final dist = NearestStopService.haversineDistance(
        lastGood.lat,
        lastGood.lon,
        obs.lat,
        obs.lon,
      );
      if (dist < _stoppedDistanceMeters) {
        status = BusStatus.stopped;
      }
    }

    final newObs = _addObservation(state.observations, obs);

    _states[key] = state.copyWith(
      currentTripId: obs.gtfsTripId,
      shapeId: shapeId,
      observations: newObs,
      smoothedLat: obs.lat,
      smoothedLon: obs.lon,
      smoothedHeading: obs.heading,
      progressAlongRoute: progress,
      status: status,
      lastUpdateTime: obs.timestamp,
    );
  }

  /// Interpolate bus positions for smooth animation at render time.
  ///
  /// Returns a map of routeRun → (lat, lon, heading).
  Map<String, (double, double, double)> interpolate(DateTime now) {
    final result = <String, (double, double, double)>{};

    for (final entry in _states.entries) {
      final state = entry.value;
      final good = state.observations.where((o) => !o.rejected).toList();
      if (good.isEmpty) continue;

      if (good.length < 2) {
        result[entry.key] = (state.smoothedLat, state.smoothedLon, state.smoothedHeading);
        continue;
      }

      final prev = good[good.length - 2];
      final last = good.last;
      final segmentMs = last.timestamp.difference(prev.timestamp).inMilliseconds;
      if (segmentMs <= 0) {
        result[entry.key] = (last.lat, last.lon, last.heading);
        continue;
      }

      final elapsed = now.difference(prev.timestamp).inMilliseconds;
      var t = elapsed / segmentMs;

      // Allow slight extrapolation beyond last point
      if (t > 1.0) {
        final extraMs = now.difference(last.timestamp).inMilliseconds;
        if (extraMs > _maxExtrapolationSeconds * 1000) {
          t = 1.0;
        } else {
          // Clamp extrapolation speed
          final segDistM = NearestStopService.haversineDistance(
            prev.lat,
            prev.lon,
            last.lat,
            last.lon,
          );
          final segSpeedKmh = segmentMs > 0
              ? (segDistM / (segmentMs / 1000.0)) * 3.6
              : 0.0;
          if (segSpeedKmh > _maxExtrapolationSpeedKmh) {
            t = 1.0;
          }
        }
      }

      t = t.clamp(0.0, 1.5); // cap extrapolation

      final lat = prev.lat + (last.lat - prev.lat) * t;
      final lon = prev.lon + (last.lon - prev.lon) * t;
      final heading = _lerpAngle(prev.heading, last.heading, t.clamp(0.0, 1.0));

      result[entry.key] = (lat, lon, heading);
    }

    return result;
  }

  SnapResult? _trySnap(double lat, double lon, String shapeId) {
    final points = _repo.shapesById[shapeId];
    final dists = _repo.shapeCumulativeDistances[shapeId];
    if (points == null || dists == null) return null;

    return ShapeMatcher.snapToShape(
      lat: lat,
      lon: lon,
      points: points,
      cumulativeDistances: dists,
    );
  }

  List<BusObservation> _addObservation(
    List<BusObservation> existing,
    BusObservation obs,
  ) {
    final list = List<BusObservation>.from(existing)..add(obs);
    if (list.length > _maxObservations) {
      list.removeRange(0, list.length - _maxObservations);
    }
    return list;
  }

  /// Linearly interpolate between two angles (in degrees), taking the shortest path.
  static double _lerpAngle(double a, double b, double t) {
    var diff = (b - a) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (a + diff * t) % 360;
  }
}
