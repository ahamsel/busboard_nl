import 'dart:math' as math;

import '../../data/gtfs/gtfs_models.dart';
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
  static const _maxExtrapolationSeconds = 12.0;
  static const _maxDeadReckoningSeconds = 12.0;
  static const _maxExtrapolationSpeedKmh = 80.0;
  static const _minMovingSpeedKmh = 2.0;
  static const _maxVisualBackwardMeters = 120.0;

  /// Counter for consecutive backward movements per bus.
  final Map<String, int> _backwardCount = {};

  /// Last rendered progress per bus key, used to prevent visual snap-backs.
  final Map<String, double> _renderProgressByKey = {};

  /// Trip -> stop_times rows sorted by stop_sequence.
  final Map<String, List<StopTimeRow>> _stopTimesByTripId = {};

  /// Cache of snapped stop progresses keyed by trip|shape.
  final Map<String, List<double>> _tripStopProgressCache = {};

  BusMotionEngine(this._repo) {
    for (final rows in _repo.stopTimesByStopId.values) {
      for (final row in rows) {
        _stopTimesByTripId.putIfAbsent(row.tripId, () => []).add(row);
      }
    }
    for (final rows in _stopTimesByTripId.values) {
      rows.sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    }
  }

  Map<String, BusTrackingState> get states => Map.unmodifiable(_states);

  /// Process a batch of vehicles from the TimeTrack API.
  void processBatch(List<TimeTrackVehicle> vehicles, DateTime fetchTime) {
    final seenKeys = <String>{};

    for (final v in vehicles) {
      final key = _resolveBusKey(v);
      if (key == null || v.busLat == 0.0 || v.busLon == 0.0) continue;

      seenKeys.add(key);

      final headingDeg = _parseHeadingDegrees(v.heading);
      final obs = BusObservation(
        timestamp: fetchTime,
        lat: v.busLat,
        lon: v.busLon,
        heading: headingDeg,
        speed: v.speed,
        gtfsTripId: v.gtfsTripId.isNotEmpty ? v.gtfsTripId : null,
      );

      final existing = _states[key];

      if (existing == null) {
        // New bus
        _states[key] = _createNewState(v, obs, key);
        continue;
      }

      _updateExisting(key, existing, obs, v);
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
      _renderProgressByKey.remove(key);
    }
  }

  BusTrackingState _createNewState(
    TimeTrackVehicle v,
    BusObservation obs,
    String key,
  ) {
    String? shapeId;
    double? progress;
    var smoothedLat = obs.lat;
    var smoothedLon = obs.lon;

    if (obs.gtfsTripId != null) {
      final trip = _repo.tripsById[obs.gtfsTripId];
      shapeId = trip?.shapeId;
    }
    // Fallback: match by route number + headsign when trip ID is unavailable
    shapeId ??= _resolveShapeFallback(v);

    if (shapeId != null) {
      final snap = _trySnap(obs.lat, obs.lon, shapeId);
      if (snap != null &&
          snap.perpendicularDistance <= _offRouteThresholdMeters) {
        progress = snap.distanceAlongRoute;
        smoothedLat = snap.snappedLat;
        smoothedLon = snap.snappedLon;
      }
    }

    final obsWithProgress = obs.copyWith(progressAlongRoute: progress);

    return BusTrackingState(
      routeRun: v.routeRun.isNotEmpty ? v.routeRun : key,
      vehicleId: v.vehicle.isNotEmpty ? v.vehicle : key,
      routeNumber: v.routeNumber,
      headsign: v.gtfsTripHeadsign,
      currentTripId: obs.gtfsTripId,
      shapeId: shapeId,
      observations: [obsWithProgress],
      smoothedLat: smoothedLat,
      smoothedLon: smoothedLon,
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
    var displayLat = obs.lat;
    var displayLon = obs.lon;
    var displayHeading = obs.heading;

    // Outlier rejection: check implied speed
    final lastGood = state.observations.lastWhere(
      (o) => !o.rejected,
      orElse: () => state.observations.last,
    );
    final dtSeconds =
        obs.timestamp.difference(lastGood.timestamp).inMilliseconds / 1000.0;

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
    // Fallback: match by route number + headsign when no shape resolved
    shapeId ??= _resolveShapeFallback(v);

    if (shapeId != null) {
      final snap = _trySnap(obs.lat, obs.lon, shapeId);
      if (snap != null) {
        if (snap.perpendicularDistance > _offRouteThresholdMeters) {
          status = BusStatus.offRoute;
          // Use raw GPS, don't update progress
        } else {
          displayLat = snap.snappedLat;
          displayLon = snap.snappedLon;

          // Check backward movement
          final snappedProgress = snap.distanceAlongRoute;
          if (progress != null && snappedProgress < progress) {
            final backward = progress - snappedProgress;
            if (backward < _backwardSmallThreshold) {
              // Small backward — clamp to previous progress.
            } else if (backward > _backwardLargeThreshold) {
              _backwardCount[key] = (_backwardCount[key] ?? 0) + 1;
              if ((_backwardCount[key] ?? 0) >= 3) {
                // Allow — real detour
                progress = snappedProgress;
                _backwardCount[key] = 0;
              } else {
                status = BusStatus.backtracking;
              }
            } else {
              // Medium backward — clamp
              _backwardCount[key] = (_backwardCount[key] ?? 0) + 1;
            }
          } else {
            progress = snappedProgress;
            _backwardCount[key] = 0;
          }

          final shapeHeading = _headingAlongShape(shapeId, progress);
          if (shapeHeading != null) {
            displayHeading = shapeHeading;
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

    final obsWithProgress = obs.copyWith(progressAlongRoute: progress);
    final newObs = _addObservation(state.observations, obsWithProgress);

    _states[key] = state.copyWith(
      currentTripId: obs.gtfsTripId,
      shapeId: shapeId,
      observations: newObs,
      smoothedLat: displayLat,
      smoothedLon: displayLon,
      smoothedHeading: displayHeading,
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
      final key = entry.key;
      final state = entry.value;
      final good = state.observations.where((o) => !o.rejected).toList();
      if (good.isEmpty) continue;

      final prev = good.length >= 2 ? good[good.length - 2] : null;
      final last = good.last;

      final shapeInterpolated = _interpolateOnShape(
        key: key,
        state: state,
        prev: prev,
        last: last,
        now: now,
      );
      if (shapeInterpolated != null) {
        result[key] = shapeInterpolated;
        continue;
      }

      // Fallback interpolation when no usable shape progress is available.
      if (good.length < 2) {
        result[key] = (
          state.smoothedLat,
          state.smoothedLon,
          state.smoothedHeading,
        );
        continue;
      }

      final prevObs = prev;
      if (prevObs == null) {
        result[key] = (last.lat, last.lon, last.heading);
        continue;
      }

      final segmentMs = last.timestamp
          .difference(prevObs.timestamp)
          .inMilliseconds;
      if (segmentMs <= 0) {
        result[key] = (last.lat, last.lon, last.heading);
        continue;
      }

      final elapsed = now.difference(prevObs.timestamp).inMilliseconds;
      var t = elapsed / segmentMs;

      // Allow slight extrapolation beyond last point
      if (t > 1.0) {
        final extraMs = now.difference(last.timestamp).inMilliseconds;
        if (extraMs > _maxExtrapolationSeconds * 1000) {
          t = 1.0;
        } else {
          final segDistM = NearestStopService.haversineDistance(
            prevObs.lat,
            prevObs.lon,
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

      t = t.clamp(0.0, 1.5);

      final lat = prevObs.lat + (last.lat - prevObs.lat) * t;
      final lon = prevObs.lon + (last.lon - prevObs.lon) * t;
      final heading = _lerpAngle(
        prevObs.heading,
        last.heading,
        t.clamp(0.0, 1.0),
      );

      result[key] = (lat, lon, heading);
    }

    return result;
  }

  (double, double, double)? _interpolateOnShape({
    required String key,
    required BusTrackingState state,
    required BusObservation? prev,
    required BusObservation last,
    required DateTime now,
  }) {
    final shapeId = state.shapeId;
    if (shapeId == null) {
      _renderProgressByKey.remove(key);
      return null;
    }

    final lastProgress = last.progressAlongRoute ?? state.progressAlongRoute;
    if (lastProgress == null) {
      _renderProgressByKey.remove(key);
      return null;
    }

    var nextProgress = lastProgress;

    if (prev != null && prev.progressAlongRoute != null) {
      final prevProgress = prev.progressAlongRoute!;
      final segmentMs = last.timestamp
          .difference(prev.timestamp)
          .inMilliseconds;
      if (segmentMs > 0) {
        final elapsedMs = now.difference(prev.timestamp).inMilliseconds;
        final t = elapsedMs / segmentMs;
        final delta = lastProgress - prevProgress;

        if (t <= 1.0) {
          nextProgress = prevProgress + delta * t.clamp(0.0, 1.0);
        } else {
          final extraSeconds =
              now.difference(last.timestamp).inMilliseconds / 1000.0;
          if (state.status != BusStatus.active &&
              state.status != BusStatus.backtracking) {
            nextProgress = lastProgress;
          } else if (extraSeconds <= _maxExtrapolationSeconds) {
            final segDistM = (lastProgress - prevProgress).abs();
            final segSpeedKmh = segmentMs > 0
                ? (segDistM / (segmentMs / 1000.0)) * 3.6
                : 0.0;
            var speedKmh = last.speed >= _minMovingSpeedKmh
                ? last.speed
                : segSpeedKmh;

            final distanceToStop = _distanceToNextStopMeters(
              tripId: state.currentTripId,
              shapeId: shapeId,
              progress: lastProgress,
            );
            speedKmh = _applyStopHeuristic(
              speedKmh: speedKmh,
              status: state.status,
              distanceToNextStopM: distanceToStop,
            );

            if (speedKmh >= _minMovingSpeedKmh &&
                speedKmh <= _maxExtrapolationSpeedKmh) {
              final direction = delta < -1.0 ? -1.0 : 1.0;
              final extraM =
                  (speedKmh / 3.6) *
                  extraSeconds.clamp(0.0, _maxDeadReckoningSeconds);
              nextProgress = lastProgress + extraM * direction;
            } else {
              nextProgress = lastProgress;
            }
          } else {
            nextProgress = lastProgress;
          }
        }
      }
    } else {
      // Single observation: small forward dead-reckoning while active.
      final extraSeconds =
          now.difference(last.timestamp).inMilliseconds / 1000.0;
      if (state.status == BusStatus.active &&
          last.speed >= _minMovingSpeedKmh &&
          extraSeconds > 0) {
        final distanceToStop = _distanceToNextStopMeters(
          tripId: state.currentTripId,
          shapeId: shapeId,
          progress: lastProgress,
        );
        final speedKmh = _applyStopHeuristic(
          speedKmh: last.speed,
          status: state.status,
          distanceToNextStopM: distanceToStop,
        );
        final extraM =
            (speedKmh / 3.6) *
            extraSeconds.clamp(0.0, _maxDeadReckoningSeconds);
        nextProgress = lastProgress + extraM;
      }
    }

    final clampedProgress = _clampVisualBackward(
      key: key,
      progress: nextProgress,
      state: state,
    );

    final point = _pointOnShape(shapeId, clampedProgress);
    if (point == null) {
      _renderProgressByKey.remove(key);
      return null;
    }

    final heading =
        _headingAlongShape(shapeId, clampedProgress) ?? state.smoothedHeading;
    _renderProgressByKey[key] = clampedProgress;

    return (point.$1, point.$2, heading);
  }

  double _clampVisualBackward({
    required String key,
    required double progress,
    required BusTrackingState state,
  }) {
    final previous = _renderProgressByKey[key];
    if (previous == null) return progress;

    if (progress >= previous) return progress;

    if (state.status == BusStatus.backtracking) {
      return math.max(progress, previous - _maxVisualBackwardMeters);
    }

    // For active/on-time movement, do not visually move backward.
    return previous;
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

  (double, double)? _pointOnShape(String shapeId, double progressMeters) {
    final points = _repo.shapesById[shapeId];
    final dists = _repo.shapeCumulativeDistances[shapeId];
    if (points == null || dists == null || points.isEmpty || dists.isEmpty) {
      return null;
    }

    final total = dists.last;
    final target = progressMeters.clamp(0.0, total);

    if (target <= 0.0) return (points.first.lat, points.first.lon);
    if (target >= total) return (points.last.lat, points.last.lon);

    var idx = _lowerBound(dists, target);
    if (idx <= 0) idx = 1;
    if (idx >= points.length) idx = points.length - 1;

    final d0 = dists[idx - 1];
    final d1 = dists[idx];
    final segLen = d1 - d0;
    final t = segLen <= 1e-6 ? 0.0 : ((target - d0) / segLen).clamp(0.0, 1.0);

    final p0 = points[idx - 1];
    final p1 = points[idx];
    final lat = p0.lat + (p1.lat - p0.lat) * t;
    final lon = p0.lon + (p1.lon - p0.lon) * t;
    return (lat, lon);
  }

  double? _headingAlongShape(String shapeId, double progressMeters) {
    final dists = _repo.shapeCumulativeDistances[shapeId];
    if (dists == null || dists.length < 2) return null;

    final a = _pointOnShape(shapeId, progressMeters);
    final b = _pointOnShape(shapeId, progressMeters + 15.0);
    if (a == null || b == null) return null;

    return _bearingDegrees(a.$1, a.$2, b.$1, b.$2);
  }

  int _lowerBound(List<double> values, double target) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (values[mid] < target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  double? _distanceToNextStopMeters({
    required String? tripId,
    required String shapeId,
    required double progress,
  }) {
    if (tripId == null) return null;

    final stopProgresses = _tripStopProgresses(
      tripId: tripId,
      shapeId: shapeId,
    );
    for (final stopProgress in stopProgresses) {
      if (stopProgress >= progress) {
        return stopProgress - progress;
      }
    }
    return null;
  }

  List<double> _tripStopProgresses({
    required String tripId,
    required String shapeId,
  }) {
    final cacheKey = '$tripId|$shapeId';
    final cached = _tripStopProgressCache[cacheKey];
    if (cached != null) return cached;

    final rows = _stopTimesByTripId[tripId];
    if (rows == null || rows.isEmpty) return const [];

    final progresses = <double>[];
    for (final row in rows) {
      final stop = _repo.stopsById[row.stopId];
      if (stop == null) continue;
      final snap = _trySnap(stop.stopLat, stop.stopLon, shapeId);
      if (snap == null) continue;
      progresses.add(snap.distanceAlongRoute);
    }
    progresses.sort();

    final unique = <double>[];
    for (final value in progresses) {
      if (unique.isEmpty || (value - unique.last).abs() > 5.0) {
        unique.add(value);
      }
    }

    _tripStopProgressCache[cacheKey] = unique;
    return unique;
  }

  double _applyStopHeuristic({
    required double speedKmh,
    required BusStatus status,
    required double? distanceToNextStopM,
  }) {
    if (status == BusStatus.stopped || status == BusStatus.stale) return 0.0;
    if (distanceToNextStopM == null) return speedKmh;

    if (distanceToNextStopM <= 25.0) return 0.0;
    if (distanceToNextStopM >= 180.0) return speedKmh;

    final factor = ((distanceToNextStopM - 25.0) / 155.0).clamp(0.0, 1.0);
    final approachCapKmh = 4.0 + 18.0 * factor;
    return math.min(speedKmh, approachCapKmh);
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

  static double _bearingDegrees(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final phi1 = lat1 * (math.pi / 180.0);
    final phi2 = lat2 * (math.pi / 180.0);
    final dLon = (lon2 - lon1) * (math.pi / 180.0);

    final y = math.sin(dLon) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
    final bearing = math.atan2(y, x) * (180.0 / math.pi);
    return (bearing + 360.0) % 360.0;
  }

  String? _resolveBusKey(TimeTrackVehicle v) {
    if (v.routeRun.isNotEmpty) return v.routeRun;
    if (v.vehicle.isNotEmpty) return 'vehicle:${v.vehicle}';
    if (v.gtfsTripId.isNotEmpty) return 'trip:${v.gtfsTripId}';
    return null;
  }

  /// Fallback shape resolution when gtfsTripId is unavailable.
  /// Matches by route number, then narrows by headsign and service ID.
  String? _resolveShapeFallback(TimeTrackVehicle v) {
    final routeKey = v.routeNumber.toString();
    final candidates = _repo.tripsByRouteShortName[routeKey];
    if (candidates == null || candidates.isEmpty) return null;

    var filtered = candidates;

    // Narrow by headsign if available
    if (v.gtfsTripHeadsign.isNotEmpty) {
      final byHeadsign = candidates
          .where(
            (e) =>
                e.headsign.toLowerCase() == v.gtfsTripHeadsign.toLowerCase(),
          )
          .toList();
      if (byHeadsign.isNotEmpty) filtered = byHeadsign;
    }

    // Narrow by service ID if available
    if (v.gtfsServiceId.isNotEmpty) {
      final byService =
          filtered.where((e) => e.serviceId == v.gtfsServiceId).toList();
      if (byService.isNotEmpty) filtered = byService;
    }

    return filtered.first.shapeId;
  }

  double _parseHeadingDegrees(String rawHeading) {
    final normalized = rawHeading.trim().toUpperCase();
    final parsed = double.tryParse(normalized);
    if (parsed != null) return parsed % 360;

    const compass = <String, double>{
      'N': 0,
      'NNE': 22.5,
      'NE': 45,
      'ENE': 67.5,
      'E': 90,
      'ESE': 112.5,
      'SE': 135,
      'SSE': 157.5,
      'S': 180,
      'SSW': 202.5,
      'SW': 225,
      'WSW': 247.5,
      'W': 270,
      'WNW': 292.5,
      'NW': 315,
      'NNW': 337.5,
    };
    return compass[normalized] ?? 0.0;
  }
}
