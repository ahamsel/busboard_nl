import 'dart:math' as math;

import '../../data/gtfs/gtfs_models.dart';
import '../../data/gtfs/gtfs_repository.dart';
import '../../data/realtime/timetrack_models.dart';
import '../location/nearest_stop_service.dart';
import 'bus_observation.dart';
import 'bus_tracking_state.dart';
import 'shape_matcher.dart';

/// Per-batch diagnostics to quantify interpolation quality.
class BusMotionDiagnostics {
  final DateTime timestamp;
  final int processedVehicles;
  final int acceptedUpdates;
  final int duplicateOrOutOfOrderUpdates;
  final int rejectedOutliers;
  final double? correctionP50Meters;
  final double? correctionP90Meters;
  final double? correctionMeanMeters;
  final double? innovationP50Meters;
  final double? innovationP90Meters;
  final double? innovationMeanMeters;
  final bool autoAdjustEnabled;
  final double kalmanAccelStdMps2;
  final double kalmanMeasurementStdM;
  final int blendDurationMs;

  const BusMotionDiagnostics({
    required this.timestamp,
    required this.processedVehicles,
    required this.acceptedUpdates,
    required this.duplicateOrOutOfOrderUpdates,
    required this.rejectedOutliers,
    this.correctionP50Meters,
    this.correctionP90Meters,
    this.correctionMeanMeters,
    this.innovationP50Meters,
    this.innovationP90Meters,
    this.innovationMeanMeters,
    required this.autoAdjustEnabled,
    required this.kalmanAccelStdMps2,
    required this.kalmanMeasurementStdM,
    required this.blendDurationMs,
  });

  BusMotionDiagnostics.empty()
    : timestamp = DateTime.fromMillisecondsSinceEpoch(0),
      processedVehicles = 0,
      acceptedUpdates = 0,
      duplicateOrOutOfOrderUpdates = 0,
      rejectedOutliers = 0,
      correctionP50Meters = null,
      correctionP90Meters = null,
      correctionMeanMeters = null,
      innovationP50Meters = null,
      innovationP90Meters = null,
      innovationMeanMeters = null,
      autoAdjustEnabled = true,
      kalmanAccelStdMps2 = 1.5,
      kalmanMeasurementStdM = 20.0,
      blendDurationMs = 600;
}

class _UpdateResult {
  final bool accepted;
  final bool duplicateOrOutOfOrder;
  final bool rejectedOutlier;
  final double? correctionMeters;
  final double? filterInnovationMeters;

  const _UpdateResult._({
    required this.accepted,
    required this.duplicateOrOutOfOrder,
    required this.rejectedOutlier,
    this.correctionMeters,
    this.filterInnovationMeters,
  });

  const _UpdateResult.accepted({
    double? correctionMeters,
    double? filterInnovationMeters,
  }) : this._(
         accepted: true,
         duplicateOrOutOfOrder: false,
         rejectedOutlier: false,
         correctionMeters: correctionMeters,
         filterInnovationMeters: filterInnovationMeters,
       );

  const _UpdateResult.duplicate()
    : this._(
        accepted: false,
        duplicateOrOutOfOrder: true,
        rejectedOutlier: false,
      );

  const _UpdateResult.rejected()
    : this._(
        accepted: false,
        duplicateOrOutOfOrder: false,
        rejectedOutlier: true,
      );
}

class _ProgressProjection {
  final double progressMeters;
  final double velocityMps;
  final double ageSeconds;

  const _ProgressProjection({
    required this.progressMeters,
    required this.velocityMps,
    required this.ageSeconds,
  });
}

class _BlendOrigin {
  final double lat;
  final double lon;
  final double heading;
  final DateTime startTime;
  final String? shapeId;
  final double? progressAlongRoute;

  const _BlendOrigin({
    required this.lat,
    required this.lon,
    required this.heading,
    required this.startTime,
    this.shapeId,
    this.progressAlongRoute,
  });
}

class _RouteProgressKalman {
  final String shapeId;
  DateTime _time;
  double _positionM;
  double _velocityMps;
  double _p00;
  double _p01;
  double _p10;
  double _p11;

  _RouteProgressKalman({
    required this.shapeId,
    required DateTime measurementTime,
    required double positionMeters,
    required double velocityMps,
  }) : _time = measurementTime,
       _positionM = positionMeters,
       _velocityMps = velocityMps,
       _p00 = 400.0,
       _p01 = 0.0,
       _p10 = 0.0,
       _p11 = 64.0;

  DateTime get measurementTime => _time;

  double ingest({
    required DateTime measurementTime,
    required double measuredProgressM,
    required double measuredSpeedMps,
    required double accelStdMps2,
    required double measurementStdM,
  }) {
    final dt = measurementTime.difference(_time).inMilliseconds / 1000.0;
    if (dt > 0.0) {
      _predict(dt: dt, accelStdMps2: accelStdMps2);
      _time = measurementTime;
    }

    final r = measurementStdM * measurementStdM;
    final innovation = measuredProgressM - _positionM;
    final s = _p00 + r;
    if (s <= 1e-6) return innovation.abs();

    final k0 = _p00 / s;
    final k1 = _p10 / s;

    _positionM += k0 * innovation;
    _velocityMps += k1 * innovation;

    final p00 = (1.0 - k0) * _p00;
    final p01 = (1.0 - k0) * _p01;
    final p10 = _p10 - k1 * _p00;
    final p11 = _p11 - k1 * _p01;

    _p00 = p00;
    _p01 = p01;
    _p10 = p10;
    _p11 = p11;

    if (measuredSpeedMps.isFinite) {
      _velocityMps = _velocityMps * 0.85 + measuredSpeedMps * 0.15;
    }
    return innovation.abs();
  }

  _ProgressProjection project({
    required DateTime now,
    required double maxProjectionSeconds,
  }) {
    var dt = now.difference(_time).inMilliseconds / 1000.0;
    if (dt < 0.0) dt = 0.0;
    final clampedDt = dt.clamp(0.0, maxProjectionSeconds);

    final projectedPosition = _positionM + _velocityMps * clampedDt;
    return _ProgressProjection(
      progressMeters: projectedPosition,
      velocityMps: _velocityMps,
      ageSeconds: clampedDt,
    );
  }

  void _predict({required double dt, required double accelStdMps2}) {
    if (dt <= 0.0) return;
    final sigma2 = accelStdMps2 * accelStdMps2;

    final q00 = 0.25 * dt * dt * dt * dt * sigma2;
    final q01 = 0.5 * dt * dt * dt * sigma2;
    final q11 = dt * dt * sigma2;

    final newPosition = _positionM + _velocityMps * dt;
    final newVelocity = _velocityMps;

    final fp00 = _p00 + dt * (_p10 + _p01) + dt * dt * _p11;
    final fp01 = _p01 + dt * _p11;
    final fp10 = _p10 + dt * _p11;
    final fp11 = _p11;

    _positionM = newPosition;
    _velocityMps = newVelocity;
    _p00 = fp00 + q00;
    _p01 = fp01 + q01;
    _p10 = fp10 + q01;
    _p11 = fp11 + q11;
  }
}

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
  static const _maxExtrapolationSeconds = 35.0;
  static const _maxDeadReckoningSeconds = 35.0;
  static const _maxExtrapolationSpeedKmh = 80.0;
  static const _minMovingSpeedKmh = 2.0;

  /// Seconds of extrapolation at full speed before decay begins.
  static const _decayOnsetSeconds = 10.0;

  /// Minimum fraction of speed retained during decay (65%).
  static const _decayFloor = 0.65;

  /// Keep full trust in reported speed while source data is fresh.
  static const _freshMeasurementAgeSeconds = 20.0;

  /// Beyond this age, prediction trust drops to [_staleSpeedFloor].
  static const _staleMeasurementAgeSeconds = 120.0;

  /// Never trust stale measurements for more than this speed fraction.
  static const _staleSpeedFloor = 0.2;
  static const _kalmanAccelStdMps2 = 1.5;
  static const _kalmanMeasurementStdM = 20.0;
  static const _kalmanMinMeasurementStdM = 8.0;
  static const _kalmanMaxMeasurementStdM = 65.0;
  static const _kalmanSnapDistanceWeight = 0.35;
  static const _kalmanMaxProjectionSeconds = 180.0;
  static const _kalmanMinAccelStdMps2 = 0.6;
  static const _kalmanMaxAccelStdMps2 = 3.5;
  static const _autoAdjustMinSamples = 6;
  static const _targetInnovationP50Meters = 25.0;
  static const _targetCorrectionP90Meters = 45.0;
  static const _autoAdjustEwmaAlpha = 0.2;
  static const _blendDurationMinMs = 420;
  static const _blendDurationMaxMs = 1100;
  static const _maxVisualBackwardMeters = 120.0;
  static const _maxOffRouteVisualBackwardMeters = 60.0;

  /// Counter for consecutive backward movements per bus.
  final Map<String, int> _backwardCount = {};

  /// Last rendered progress per bus key, used to prevent visual snap-backs.
  final Map<String, double> _renderProgressByKey = {};

  /// Blend origin per bus. When shape progress is available, blend in progress
  /// space so correction follows the road geometry through turns.
  final Map<String, _BlendOrigin> _blendOrigins = {};
  static const _blendDurationMs = 600;

  /// Route-progress Kalman filter per bus key.
  final Map<String, _RouteProgressKalman> _progressFilters = {};

  BusMotionDiagnostics _lastDiagnostics = BusMotionDiagnostics.empty();
  final bool _autoAdjustEnabled = true;
  double _kalmanAccelStdMps2Current = _kalmanAccelStdMps2;
  double _kalmanMeasurementStdMCurrent = _kalmanMeasurementStdM;
  int _blendDurationMsCurrent = _blendDurationMs;
  double? _innovationP50Ewma;
  double? _correctionP90Ewma;

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
  BusMotionDiagnostics get diagnostics => _lastDiagnostics;
  Map<String, double> get debugRenderedProgressByKey =>
      Map.unmodifiable(_renderProgressByKey);

  /// Process a batch of vehicles from the TimeTrack API.
  void processBatch(List<TimeTrackVehicle> vehicles, DateTime fetchTime) {
    final seenKeys = <String>{};
    final correctionSamples = <double>[];
    final innovationSamples = <double>[];
    var processedVehicles = 0;
    var acceptedUpdates = 0;
    var duplicateUpdates = 0;
    var rejectedOutliers = 0;

    for (final v in vehicles) {
      final key = _resolveBusKey(v);
      if (key == null || v.busLat == 0.0 || v.busLon == 0.0) continue;
      processedVehicles++;

      seenKeys.add(key);

      final headingDeg = _parseHeadingDegrees(v.heading);
      final measurementTime = _measurementTimeFromSeconds(
        v.positionTimeSeconds,
        fetchTime,
      );
      final obs = BusObservation(
        timestamp: fetchTime,
        measurementTime: measurementTime,
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
        acceptedUpdates++;
        continue;
      }

      final result = _updateExisting(key, existing, obs, v);
      if (result.accepted) acceptedUpdates++;
      if (result.duplicateOrOutOfOrder) duplicateUpdates++;
      if (result.rejectedOutlier) rejectedOutliers++;
      if (result.correctionMeters != null) {
        correctionSamples.add(result.correctionMeters!);
      }
      if (result.filterInnovationMeters != null) {
        innovationSamples.add(result.filterInnovationMeters!);
      }
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
      _blendOrigins.remove(key);
      _progressFilters.remove(key);
    }

    final correctionStats = _summarizeSamples(correctionSamples);
    final innovationStats = _summarizeSamples(innovationSamples);
    _autoAdjustParameters(
      correctionSampleCount: correctionSamples.length,
      correctionP90Meters: correctionStats.$2,
      innovationSampleCount: innovationSamples.length,
      innovationP50Meters: innovationStats.$1,
    );
    _lastDiagnostics = BusMotionDiagnostics(
      timestamp: fetchTime,
      processedVehicles: processedVehicles,
      acceptedUpdates: acceptedUpdates,
      duplicateOrOutOfOrderUpdates: duplicateUpdates,
      rejectedOutliers: rejectedOutliers,
      correctionP50Meters: correctionStats.$1,
      correctionP90Meters: correctionStats.$2,
      correctionMeanMeters: correctionStats.$3,
      innovationP50Meters: innovationStats.$1,
      innovationP90Meters: innovationStats.$2,
      innovationMeanMeters: innovationStats.$3,
      autoAdjustEnabled: _autoAdjustEnabled,
      kalmanAccelStdMps2: _kalmanAccelStdMps2Current,
      kalmanMeasurementStdM: _kalmanMeasurementStdMCurrent,
      blendDurationMs: _blendDurationMsCurrent,
    );
  }

  BusTrackingState _createNewState(
    TimeTrackVehicle v,
    BusObservation obs,
    String key,
  ) {
    String? shapeId;
    double? progress;
    double? snapDistanceMeters;
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
        snapDistanceMeters = snap.perpendicularDistance;
        smoothedLat = snap.snappedLat;
        smoothedLon = snap.snappedLon;
      }
    }

    final obsWithProgress = obs.copyWith(progressAlongRoute: progress);
    if (shapeId != null && progress != null) {
      _ingestProgressMeasurement(
        key: key,
        shapeId: shapeId,
        measuredProgressM: progress,
        measurementTime: obs.measurementTime,
        measuredSpeedKmh: obs.speed,
        snapDistanceMeters: snapDistanceMeters,
      );
    }

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

  _UpdateResult _updateExisting(
    String key,
    BusTrackingState state,
    BusObservation obs,
    TimeTrackVehicle v,
  ) {
    var displayLat = obs.lat;
    var displayLon = obs.lon;
    var displayHeading = obs.heading;
    double? snapDistanceMeters;
    double? filterInnovationMeters;

    // Outlier rejection and duplicate suppression.
    final lastGood = state.observations.lastWhere(
      (o) => !o.rejected,
      orElse: () => state.observations.last,
    );
    final measurementDeltaSeconds = _measurementDeltaSeconds(lastGood, obs);

    // Duplicate or out-of-order source data. Keep the last known pose but
    // refresh liveness so the bus doesn't go stale while feed catches up.
    if (measurementDeltaSeconds <= 0.0) {
      _states[key] = state.copyWith(lastUpdateTime: obs.timestamp);
      return const _UpdateResult.duplicate();
    }

    final motionDeltaSeconds = _motionDeltaSeconds(lastGood, obs);
    if (motionDeltaSeconds > 0.5) {
      final dist = NearestStopService.haversineDistance(
        lastGood.lat,
        lastGood.lon,
        obs.lat,
        obs.lon,
      );
      final impliedSpeedKmh = (dist / motionDeltaSeconds) * 3.6;
      if (impliedSpeedKmh > _maxSpeedKmh) {
        // Reject this observation
        final rejected = obs.copyWith(rejected: true);
        final newObs = _addObservation(state.observations, rejected);
        _states[key] = state.copyWith(
          observations: newObs,
          lastUpdateTime: obs.timestamp,
        );
        return const _UpdateResult.rejected();
      }
    }

    // Capture where this bus is currently rendered before we change state,
    // so we can blend smoothly from the predicted position to the new one.
    final now = DateTime.now();
    final currentVisual = _interpolateSingle(key, state, now);
    if (currentVisual != null) {
      final currentShapeId = state.shapeId;
      final currentProgress = currentShapeId == null
          ? null
          : (_renderProgressByKey[key] ??
                state.progressAlongRoute ??
                _projectProgressFilter(
                  key: key,
                  shapeId: currentShapeId,
                  now: now,
                )?.progressMeters);

      _blendOrigins[key] = _BlendOrigin(
        lat: currentVisual.$1,
        lon: currentVisual.$2,
        heading: currentVisual.$3,
        startTime: now,
        shapeId: currentShapeId,
        progressAlongRoute: currentProgress,
      );
    }

    // Shape matching
    String? shapeId = state.shapeId;
    double? progress = state.progressAlongRoute;
    var status = BusStatus.active;

    final tripChanged =
        obs.gtfsTripId != null && obs.gtfsTripId != state.currentTripId;
    if (tripChanged) {
      // Trip changed — re-resolve shape
      final trip = _repo.tripsById[obs.gtfsTripId];
      shapeId = trip?.shapeId;
    }
    // Fallback: match by route number + headsign when no shape resolved
    shapeId ??= _resolveShapeFallback(v);

    if (tripChanged) {
      // Reset visual continuity constraints across trip boundaries so we do
      // not inherit old progress clamping/blending into a new trip.
      _renderProgressByKey.remove(key);
      _blendOrigins.remove(key);
      _backwardCount.remove(key);
    }

    if (shapeId != null) {
      final snap = _trySnap(obs.lat, obs.lon, shapeId);
      if (snap != null) {
        if (snap.perpendicularDistance > _offRouteThresholdMeters) {
          status = BusStatus.offRoute;
          // Use raw GPS, don't update progress
        } else {
          displayLat = snap.snappedLat;
          displayLon = snap.snappedLon;
          snapDistanceMeters = snap.perpendicularDistance;

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
    if (measurementDeltaSeconds > _stoppedDuration.inSeconds) {
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

    if (shapeId != null &&
        progress != null &&
        status != BusStatus.offRoute &&
        status != BusStatus.stale) {
      filterInnovationMeters = _ingestProgressMeasurement(
        key: key,
        shapeId: shapeId,
        measuredProgressM: progress,
        measurementTime: obs.measurementTime,
        measuredSpeedKmh: obs.speed,
        snapDistanceMeters: snapDistanceMeters,
      );
    }

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

    final correctionMeters = currentVisual == null
        ? null
        : NearestStopService.haversineDistance(
            currentVisual.$1,
            currentVisual.$2,
            displayLat,
            displayLon,
          );
    return _UpdateResult.accepted(
      correctionMeters: correctionMeters,
      filterInnovationMeters: filterInnovationMeters,
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

      final raw = _interpolateSingle(key, state, now);
      if (raw == null) continue;

      var (lat, lon, heading) = raw;

      // Apply blend smoothing: when new data just arrived, ease from the
      // old predicted position to the new interpolation target.
      final blend = _blendOrigins[key];
      if (blend != null) {
        final blendAge = now.difference(blend.startTime).inMilliseconds;
        if (blendAge < _blendDurationMsCurrent) {
          // Ease-out cubic for natural deceleration feel
          final t = blendAge / _blendDurationMsCurrent;
          final eased = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);

          final targetShapeId = state.shapeId;
          final targetProgress = _renderProgressByKey[key];
          final canBlendOnShape =
              blend.shapeId != null &&
              blend.progressAlongRoute != null &&
              targetShapeId != null &&
              targetProgress != null &&
              blend.shapeId == targetShapeId;

          if (canBlendOnShape) {
            final blendedProgress =
                blend.progressAlongRoute! +
                (targetProgress - blend.progressAlongRoute!) * eased;
            final shapedPoint = _pointOnShape(targetShapeId, blendedProgress);
            if (shapedPoint != null) {
              lat = shapedPoint.$1;
              lon = shapedPoint.$2;
              heading =
                  _headingAlongShape(targetShapeId, blendedProgress) ??
                  _lerpAngle(blend.heading, heading, eased);
            }
          } else if (blend.shapeId != null &&
              targetShapeId != null &&
              blend.shapeId != targetShapeId) {
            // Trip/shape changed — do not blend across unrelated paths.
          } else {
            lat = blend.lat + (lat - blend.lat) * eased;
            lon = blend.lon + (lon - blend.lon) * eased;
            heading = _lerpAngle(blend.heading, heading, eased);
          }
        } else {
          _blendOrigins.remove(key);
        }
      }

      result[key] = (lat, lon, heading);
    }

    return result;
  }

  /// Compute the interpolated position for a single bus without blend.
  /// Used both by the render loop and to capture blend origins.
  (double, double, double)? _interpolateSingle(
    String key,
    BusTrackingState state,
    DateTime now,
  ) {
    final good = state.observations.where((o) => !o.rejected).toList();
    if (good.isEmpty) return null;

    final prev = good.length >= 2 ? good[good.length - 2] : null;
    final last = good.last;

    final shapeInterpolated = _interpolateOnShape(
      key: key,
      state: state,
      prev: prev,
      last: last,
      now: now,
    );
    if (shapeInterpolated != null) return shapeInterpolated;

    // Fallback interpolation when no usable shape progress is available.
    if (good.length < 2) {
      return (state.smoothedLat, state.smoothedLon, state.smoothedHeading);
    }

    final prevObs = prev;
    if (prevObs == null) return (last.lat, last.lon, last.heading);

    final segmentMs = last.timestamp
        .difference(prevObs.timestamp)
        .inMilliseconds;
    if (segmentMs <= 0) return (last.lat, last.lon, last.heading);
    final segmentMotionSeconds = _motionDeltaSeconds(prevObs, last);
    final usableMotionSeconds = segmentMotionSeconds > 0
        ? segmentMotionSeconds
        : (segmentMs / 1000.0);

    final elapsed = now.difference(prevObs.timestamp).inMilliseconds;
    var t = elapsed / segmentMs;

    // Extrapolation beyond last GPS point (no shape available).
    if (t > 1.0) {
      final extraSeconds =
          now.difference(last.timestamp).inMilliseconds / 1000.0;
      if (extraSeconds > _maxExtrapolationSeconds) {
        t = 1.0;
      } else {
        final segDistM = NearestStopService.haversineDistance(
          prevObs.lat,
          prevObs.lon,
          last.lat,
          last.lon,
        );
        final segSpeedKmh = usableMotionSeconds > 0
            ? (segDistM / usableMotionSeconds) * 3.6
            : 0.0;
        if (segSpeedKmh > _maxExtrapolationSpeedKmh ||
            segSpeedKmh < _minMovingSpeedKmh) {
          t = 1.0;
        } else if (segDistM <= 1e-3) {
          t = 1.0;
        } else {
          // Compute t with speed decay applied
          var decayedSpeed = _applyExtrapolationDecay(
            segSpeedKmh,
            extraSeconds,
          );
          final measurementAgeSeconds =
              now.difference(last.measurementTime).inMilliseconds / 1000.0;
          decayedSpeed = _applyMeasurementAgeConfidence(
            decayedSpeed,
            measurementAgeSeconds,
          );
          final extraM = (decayedSpeed / 3.6) * extraSeconds;
          t = 1.0 + (extraM / segDistM);
        }
      }
    }

    t = t.clamp(0.0, 1.0 + (_maxExtrapolationSeconds / (segmentMs / 1000.0)));

    final lat = prevObs.lat + (last.lat - prevObs.lat) * t;
    final lon = prevObs.lon + (last.lon - prevObs.lon) * t;
    final heading = _lerpAngle(
      prevObs.heading,
      last.heading,
      t.clamp(0.0, 1.0),
    );

    return (lat, lon, heading);
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
    final projected = _projectProgressFilter(
      key: key,
      shapeId: shapeId,
      now: now,
    );
    final canProjectFromFilter =
        projected != null &&
        (state.status == BusStatus.active ||
            state.status == BusStatus.backtracking) &&
        projected.ageSeconds <= _maxExtrapolationSeconds;

    if (canProjectFromFilter) {
      var speedKmh = projected.velocityMps.abs() * 3.6;
      speedKmh = _applyMeasurementAgeConfidence(speedKmh, projected.ageSeconds);

      final predictedDelta = projected.progressMeters - lastProgress;
      final direction = predictedDelta < -1.0 ? -1.0 : 1.0;
      var deltaM = predictedDelta.abs();

      final maxBySpeed =
          (speedKmh / 3.6) *
          projected.ageSeconds.clamp(0.0, _maxDeadReckoningSeconds);
      deltaM = math.min(deltaM, maxBySpeed);
      var tentativeProgress = lastProgress + deltaM * direction;

      final distanceToStop = _distanceToNextStopMeters(
        tripId: state.currentTripId,
        shapeId: shapeId,
        progress: tentativeProgress,
      );
      speedKmh = _applyStopHeuristic(
        speedKmh: speedKmh,
        status: state.status,
        distanceToNextStopM: distanceToStop,
      );

      final maxAfterStop =
          (speedKmh / 3.6) *
          projected.ageSeconds.clamp(0.0, _maxDeadReckoningSeconds);
      deltaM = math.min(deltaM, maxAfterStop);
      tentativeProgress = lastProgress + deltaM * direction;
      nextProgress = tentativeProgress;
    } else if (prev != null && prev.progressAlongRoute != null) {
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
          // Extrapolation beyond the last GPS point.
          final extraSeconds =
              now.difference(last.timestamp).inMilliseconds / 1000.0;
          if (state.status != BusStatus.active &&
              state.status != BusStatus.backtracking) {
            nextProgress = lastProgress;
          } else if (extraSeconds <= _maxExtrapolationSeconds) {
            // Prefer segment average speed — it reflects real-world
            // conditions (stops, traffic) better than instantaneous speed.
            final segDistM = (lastProgress - prevProgress).abs();
            final segmentMotionSeconds = _motionDeltaSeconds(prev, last);
            final segAvgKmh = segmentMotionSeconds > 0
                ? (segDistM / segmentMotionSeconds) * 3.6
                : 0.0;
            // Use segment average if meaningful, else fall back to
            // instantaneous. Both must clear the minimum threshold.
            var speedKmh = segAvgKmh >= _minMovingSpeedKmh
                ? segAvgKmh
                : (last.speed >= _minMovingSpeedKmh ? last.speed : 0.0);

            // Apply speed decay: full speed for the first N seconds,
            // then linearly decay to _decayFloor over the remaining window.
            speedKmh = _applyExtrapolationDecay(speedKmh, extraSeconds);
            final measurementAgeSeconds =
                now.difference(last.measurementTime).inMilliseconds / 1000.0;
            speedKmh = _applyMeasurementAgeConfidence(
              speedKmh,
              measurementAgeSeconds,
            );

            // Slow near upcoming stops using extrapolated progress,
            // not just the last GPS point.
            final currentExtraM =
                (speedKmh / 3.6) *
                extraSeconds.clamp(0.0, _maxDeadReckoningSeconds);
            final direction = delta < -1.0 ? -1.0 : 1.0;
            final tentativeProgress = lastProgress + currentExtraM * direction;
            final distanceToStop = _distanceToNextStopMeters(
              tripId: state.currentTripId,
              shapeId: shapeId,
              progress: tentativeProgress,
            );
            speedKmh = _applyStopHeuristic(
              speedKmh: speedKmh,
              status: state.status,
              distanceToNextStopM: distanceToStop,
            );

            if (speedKmh >= _minMovingSpeedKmh &&
                speedKmh <= _maxExtrapolationSpeedKmh) {
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
      // Single observation: dead-reckon forward using reported speed.
      final extraSeconds =
          now.difference(last.timestamp).inMilliseconds / 1000.0;
      if (state.status == BusStatus.active &&
          last.speed >= _minMovingSpeedKmh &&
          extraSeconds > 0 &&
          extraSeconds <= _maxExtrapolationSeconds) {
        var speedKmh = _applyExtrapolationDecay(last.speed, extraSeconds);
        final measurementAgeSeconds =
            now.difference(last.measurementTime).inMilliseconds / 1000.0;
        speedKmh = _applyMeasurementAgeConfidence(
          speedKmh,
          measurementAgeSeconds,
        );
        final tentativeProgress =
            lastProgress + (speedKmh / 3.6) * extraSeconds;
        final distanceToStop = _distanceToNextStopMeters(
          tripId: state.currentTripId,
          shapeId: shapeId,
          progress: tentativeProgress,
        );
        speedKmh = _applyStopHeuristic(
          speedKmh: speedKmh,
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

    if (_hasRecentTripTransition(state)) return progress;

    // Keep normal active movement monotonic to avoid "typewriter" jitter.
    if (state.status == BusStatus.active || state.status == BusStatus.stopped) {
      return previous;
    }

    // Allow limited backward correction only when status says we are likely
    // backtracking/off-route.
    if (state.status == BusStatus.backtracking) {
      return math.max(progress, previous - _maxVisualBackwardMeters);
    }
    if (state.status == BusStatus.offRoute) {
      return math.max(progress, previous - _maxOffRouteVisualBackwardMeters);
    }
    return previous;
  }

  bool _hasRecentTripTransition(BusTrackingState state) {
    final good = state.observations.where((o) => !o.rejected).toList();
    if (good.length < 2) return false;
    final last = good[good.length - 1].gtfsTripId;
    final prev = good[good.length - 2].gtfsTripId;
    return last != prev && (last != null || prev != null);
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

  /// Gentle slow-down near stops. Most stops are skipped (nobody waiting),
  /// so we never fully stop — just ease off slightly. The blend smoothing
  /// handles correction when real data arrives.
  double _applyStopHeuristic({
    required double speedKmh,
    required BusStatus status,
    required double? distanceToNextStopM,
  }) {
    if (status == BusStatus.stopped || status == BusStatus.stale) return 0.0;
    if (distanceToNextStopM == null) return speedKmh;

    // Only apply a gentle slowdown within 80m of a stop.
    // Never go below 60% of current speed — just a hint, not a brake.
    if (distanceToNextStopM >= 80.0) return speedKmh;
    final factor = (distanceToNextStopM / 80.0).clamp(0.0, 1.0);
    // At 0m: 60% speed. At 80m: 100% speed.
    final scale = 0.6 + 0.4 * factor;
    return speedKmh * scale;
  }

  /// Gradually reduce speed during extrapolation to avoid overshooting.
  /// Full speed for the first [_decayOnsetSeconds], then linearly decays
  /// to [_decayFloor] fraction by [_maxExtrapolationSeconds].
  double _applyExtrapolationDecay(double speedKmh, double extraSeconds) {
    if (extraSeconds <= _decayOnsetSeconds) return speedKmh;
    final decayWindow = _maxExtrapolationSeconds - _decayOnsetSeconds;
    if (decayWindow <= 0) return speedKmh;
    final t = ((extraSeconds - _decayOnsetSeconds) / decayWindow).clamp(
      0.0,
      1.0,
    );
    final factor = 1.0 - (1.0 - _decayFloor) * t;
    return speedKmh * factor;
  }

  double? _ingestProgressMeasurement({
    required String key,
    required String shapeId,
    required double measuredProgressM,
    required DateTime measurementTime,
    required double measuredSpeedKmh,
    required double? snapDistanceMeters,
  }) {
    final measuredSpeedMps = (measuredSpeedKmh / 3.6).clamp(-35.0, 35.0);
    final dynamicMeasurementStd =
        (_kalmanMeasurementStdMCurrent +
                (snapDistanceMeters ?? 0.0) * _kalmanSnapDistanceWeight)
            .clamp(_kalmanMinMeasurementStdM, _kalmanMaxMeasurementStdM);
    final existing = _progressFilters[key];

    if (existing == null || existing.shapeId != shapeId) {
      _progressFilters[key] = _RouteProgressKalman(
        shapeId: shapeId,
        measurementTime: measurementTime,
        positionMeters: measuredProgressM,
        velocityMps: measuredSpeedMps,
      );
      return null;
    }

    return existing.ingest(
      measurementTime: measurementTime,
      measuredProgressM: measuredProgressM,
      measuredSpeedMps: measuredSpeedMps,
      accelStdMps2: _kalmanAccelStdMps2Current,
      measurementStdM: dynamicMeasurementStd,
    );
  }

  _ProgressProjection? _projectProgressFilter({
    required String key,
    required String shapeId,
    required DateTime now,
  }) {
    final filter = _progressFilters[key];
    if (filter == null || filter.shapeId != shapeId) return null;
    return filter.project(
      now: now,
      maxProjectionSeconds: _kalmanMaxProjectionSeconds,
    );
  }

  (double?, double?, double?) _summarizeSamples(List<double> samples) {
    if (samples.isEmpty) return (null, null, null);
    final sorted = List<double>.from(samples)..sort();
    final p50 = sorted[((sorted.length - 1) * 0.50).round()];
    final p90 = sorted[((sorted.length - 1) * 0.90).round()];
    final mean = sorted.reduce((a, b) => a + b) / sorted.length;
    return (p50, p90, mean);
  }

  void _autoAdjustParameters({
    required int correctionSampleCount,
    required double? correctionP90Meters,
    required int innovationSampleCount,
    required double? innovationP50Meters,
  }) {
    if (!_autoAdjustEnabled) return;

    if (innovationSampleCount >= _autoAdjustMinSamples &&
        innovationP50Meters != null) {
      _innovationP50Ewma = _updateEwma(
        current: _innovationP50Ewma,
        sample: innovationP50Meters,
        alpha: _autoAdjustEwmaAlpha,
      );
      final innovationError =
          ((_innovationP50Ewma! - _targetInnovationP50Meters) /
                  _targetInnovationP50Meters)
              .clamp(-1.0, 1.0);

      final accelScale = (1.0 + innovationError * 0.06).clamp(0.94, 1.06);
      final measurementScale = (1.0 - innovationError * 0.04).clamp(0.96, 1.04);

      _kalmanAccelStdMps2Current = (_kalmanAccelStdMps2Current * accelScale)
          .clamp(_kalmanMinAccelStdMps2, _kalmanMaxAccelStdMps2);
      _kalmanMeasurementStdMCurrent =
          (_kalmanMeasurementStdMCurrent * measurementScale).clamp(
            _kalmanMinMeasurementStdM,
            _kalmanMaxMeasurementStdM,
          );
    }

    if (correctionSampleCount >= _autoAdjustMinSamples &&
        correctionP90Meters != null) {
      _correctionP90Ewma = _updateEwma(
        current: _correctionP90Ewma,
        sample: correctionP90Meters,
        alpha: _autoAdjustEwmaAlpha,
      );
      final correctionError =
          ((_correctionP90Ewma! - _targetCorrectionP90Meters) /
                  _targetCorrectionP90Meters)
              .clamp(-1.0, 1.0);
      final blendDeltaMs = (correctionError * 24.0).round();
      _blendDurationMsCurrent = (_blendDurationMsCurrent + blendDeltaMs).clamp(
        _blendDurationMinMs,
        _blendDurationMaxMs,
      );
    }
  }

  double _updateEwma({
    required double? current,
    required double sample,
    required double alpha,
  }) {
    if (current == null) return sample;
    return current + (sample - current) * alpha;
  }

  DateTime _measurementTimeFromSeconds(int positionTimeSeconds, DateTime now) {
    if (positionTimeSeconds <= 0 || positionTimeSeconds >= 86400) {
      return now;
    }

    var measurement = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(seconds: positionTimeSeconds));

    final diffSeconds = now.difference(measurement).inSeconds;
    if (diffSeconds > 43200) {
      measurement = measurement.add(const Duration(days: 1));
    } else if (diffSeconds < -43200) {
      measurement = measurement.subtract(const Duration(days: 1));
    }
    return measurement;
  }

  double _measurementDeltaSeconds(BusObservation older, BusObservation newer) {
    return _secondsBetweenClockTimes(
      older.measurementTime,
      newer.measurementTime,
    );
  }

  double _motionDeltaSeconds(BusObservation older, BusObservation newer) {
    final measurementDelta = _measurementDeltaSeconds(older, newer);
    if (measurementDelta > 0) return measurementDelta;
    return newer.timestamp.difference(older.timestamp).inMilliseconds / 1000.0;
  }

  double _secondsBetweenClockTimes(DateTime earlier, DateTime later) {
    var delta = later.difference(earlier).inMilliseconds / 1000.0;
    if (delta < -43200.0) delta += 86400.0;
    if (delta > 43200.0) delta -= 86400.0;
    return delta;
  }

  double _applyMeasurementAgeConfidence(
    double speedKmh,
    double measurementAgeSeconds,
  ) {
    if (measurementAgeSeconds <= _freshMeasurementAgeSeconds) {
      return speedKmh;
    }
    if (measurementAgeSeconds >= _staleMeasurementAgeSeconds) {
      return speedKmh * _staleSpeedFloor;
    }
    final t =
        ((measurementAgeSeconds - _freshMeasurementAgeSeconds) /
                (_staleMeasurementAgeSeconds - _freshMeasurementAgeSeconds))
            .clamp(0.0, 1.0);
    final factor = 1.0 - (1.0 - _staleSpeedFloor) * t;
    return speedKmh * factor;
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
            (e) => e.headsign.toLowerCase() == v.gtfsTripHeadsign.toLowerCase(),
          )
          .toList();
      if (byHeadsign.isNotEmpty) filtered = byHeadsign;
    }

    // Narrow by service ID if available
    if (v.gtfsServiceId.isNotEmpty) {
      final byService = filtered
          .where((e) => e.serviceId == v.gtfsServiceId)
          .toList();
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
