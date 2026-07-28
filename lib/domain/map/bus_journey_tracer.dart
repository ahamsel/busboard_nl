import 'dart:math' as math;

import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/map/bus_journey_anomaly.dart';
import 'package:busboard_nl/domain/map/bus_motion_engine.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';

/// Ground truth for a single bus at a single point in time.
class GroundTruth {
  final double lat;
  final double lon;
  final double? progressM;
  final double? speedKmh;

  const GroundTruth({
    required this.lat,
    required this.lon,
    this.progressM,
    this.speedKmh,
  });
}

enum TraceEventType {
  blendStarted,
  blendEnded,
  tripChanged,
  vehicleSwapped,
  backstepOccurred,
  backstepClamped,
  statusChanged,
  pollReceived,
}

class TraceEvent {
  final TraceEventType type;
  final String description;

  const TraceEvent(this.type, this.description);

  @override
  String toString() => '${type.name}: $description';
}

/// A single frame of recorded data for one bus.
class FrameRecord {
  final DateTime timestamp;
  final double elapsedSeconds;
  final String busKey;

  // Rendered position (what the user sees)
  final double renderedLat;
  final double renderedLon;
  final double renderedHeading;
  final double? renderedProgressM;

  // Ground truth (synthetic harness only)
  final double? truthLat;
  final double? truthLon;
  final double? truthProgressM;
  final double? truthSpeedKmh;

  // Speeds
  final double? displaySpeedKmh;
  final double? apiReportedSpeedKmh;

  // Engine state
  final BusStatus? status;
  final bool blendActive;
  final double? blendFraction;
  final double? stateProgressM;
  final String? shapeId;
  final String? tripId;
  final String? vehicleId;

  // Events
  final List<TraceEvent> events;

  const FrameRecord({
    required this.timestamp,
    required this.elapsedSeconds,
    required this.busKey,
    required this.renderedLat,
    required this.renderedLon,
    required this.renderedHeading,
    this.renderedProgressM,
    this.truthLat,
    this.truthLon,
    this.truthProgressM,
    this.truthSpeedKmh,
    this.displaySpeedKmh,
    this.apiReportedSpeedKmh,
    this.status,
    this.blendActive = false,
    this.blendFraction,
    this.stateProgressM,
    this.shapeId,
    this.tripId,
    this.vehicleId,
    this.events = const [],
  });
}

/// Per-bus summary statistics.
class BusTraceSummary {
  final String busKey;
  final int frameCount;
  final double durationSeconds;
  final double? routeLengthM;
  final int anomalyCount;
  final Map<AnomalyType, int> anomaliesByType;
  final int backstepCount;
  final double backstepTotalMeters;
  final int blendCount;
  final double? speedFidelityP50;
  final double? speedFidelityP90;
  final double? offShapeP90;
  final double? positionErrorP90;

  const BusTraceSummary({
    required this.busKey,
    required this.frameCount,
    required this.durationSeconds,
    this.routeLengthM,
    required this.anomalyCount,
    required this.anomaliesByType,
    required this.backstepCount,
    required this.backstepTotalMeters,
    required this.blendCount,
    this.speedFidelityP50,
    this.speedFidelityP90,
    this.offShapeP90,
    this.positionErrorP90,
  });
}

/// Internal per-bus tracking state for delta computations.
class _BusTraceState {
  double? previousProgressM;
  double? previousLat;
  double? previousLon;
  DateTime? previousTimestamp;
  BusStatus? previousStatus;
  String? previousTripId;
  String? previousVehicleId;
  String? previousShapeId;
  bool wasBlending = false;
  int blendCount = 0;
  int backstepCount = 0;
  double backstepTotalMeters = 0.0;
  double? freezeProgressM;
  DateTime? freezeStartTime;
  double? freezeApiSpeed;
  final List<double> speedFidelityRatios = [];
  final List<double> positionErrors = [];
}

/// Records per-bus, per-frame data and detects anomalies.
class BusJourneyTracer {
  final AnomalyThresholds thresholds;
  final DateTime _startTime;
  final Map<String, List<FrameRecord>> _frames = {};
  final Map<String, List<Anomaly>> _anomalies = {};
  final Map<String, _BusTraceState> _busStates = {};

  // Pre-batch snapshots for detecting changes.
  Map<String, BusTrackingState> _preBatchStates = {};

  BusJourneyTracer({
    this.thresholds = const AnomalyThresholds(),
    DateTime? startTime,
  }) : _startTime = startTime ?? DateTime.now();

  /// All bus keys that have been traced.
  Iterable<String> get trackedKeys => _frames.keys;

  /// Get all frames for a bus.
  List<FrameRecord> framesFor(String busKey) => _frames[busKey] ?? const [];

  /// Get all anomalies for a bus.
  List<Anomaly> anomaliesFor(String busKey) => _anomalies[busKey] ?? const [];

  /// Get all anomalies across all buses.
  List<Anomaly> get allAnomalies =>
      _anomalies.values.expand((a) => a).toList()
        ..sort((a, b) => a.elapsedSeconds.compareTo(b.elapsedSeconds));

  /// Call before engine.processBatch() to snapshot pre-batch state.
  void beforeBatch(BusMotionEngine engine) {
    _preBatchStates = Map.of(engine.states);
  }

  /// Call after engine.processBatch() to detect batch-level events.
  void afterBatch(BusMotionEngine engine, DateTime fetchTime) {
    final elapsed = _elapsed(fetchTime);
    final newStates = engine.states;

    for (final key in newStates.keys) {
      final pre = _preBatchStates[key];
      final post = newStates[key]!;
      final bs = _busStateFor(key);

      // Detect vehicle swap.
      if (pre != null && post.vehicleId != pre.vehicleId) {
        _addEvent(
          key,
          elapsed,
          TraceEvent(
            TraceEventType.vehicleSwapped,
            '${pre.vehicleId} -> ${post.vehicleId}',
          ),
        );
      }

      // Detect trip change.
      if (pre != null &&
          post.currentTripId != null &&
          post.currentTripId != pre.currentTripId) {
        _addEvent(
          key,
          elapsed,
          TraceEvent(
            TraceEventType.tripChanged,
            '${pre.currentTripId} -> ${post.currentTripId}',
          ),
        );
      }

      // Detect status change.
      if (pre != null && post.status != pre.status) {
        _addEvent(
          key,
          elapsed,
          TraceEvent(
            TraceEventType.statusChanged,
            '${pre.status.name} -> ${post.status.name}',
          ),
        );
      }

      // Record poll.
      _addEvent(
        key,
        elapsed,
        TraceEvent(
          TraceEventType.pollReceived,
          'obs=${post.observations.length}',
        ),
      );

      bs.previousTripId = post.currentTripId;
      bs.previousVehicleId = post.vehicleId;
    }

    _preBatchStates = {};
  }

  /// Call after engine.interpolate() each render tick.
  void recordFrame({
    required DateTime now,
    required BusMotionEngine engine,
    required Map<String, (double, double, double)> rendered,
    Map<String, GroundTruth>? groundTruth,
  }) {
    final elapsed = _elapsed(now);
    final renderedProgress = engine.debugRenderedProgressByKey;

    for (final entry in rendered.entries) {
      final key = entry.key;
      final (lat, lon, heading) = entry.value;
      final state = engine.states[key];
      if (state == null) continue;

      final bs = _busStateFor(key);
      final events = <TraceEvent>[];
      final progressM = renderedProgress[key];
      final truth = groundTruth?[key];
      final blending = engine.isBlending(key);
      final blendFrac = engine.blendFraction(key, now);

      // Blend transitions.
      final blendJustStarted = blending && !bs.wasBlending;
      final blendJustEnded = !blending && bs.wasBlending;
      if (blendJustStarted) {
        events.add(TraceEvent(TraceEventType.blendStarted, 'blend begin'));
        bs.blendCount++;
      } else if (blendJustEnded) {
        events.add(TraceEvent(TraceEventType.blendEnded, 'blend end'));
      }
      bs.wasBlending = blending;

      // Compute display speed from progress delta.
      // Skip when a blend just started — the progress jump between the
      // pre-blend prediction and the blend target is not real movement.
      double? displaySpeedKmh;
      if (!blendJustStarted &&
          progressM != null &&
          bs.previousProgressM != null &&
          bs.previousTimestamp != null) {
        final dt =
            now.difference(bs.previousTimestamp!).inMilliseconds / 1000.0;
        if (dt > 0.01) {
          final deltaM = progressM - bs.previousProgressM!;
          displaySpeedKmh = (deltaM / dt) * 3.6;
          if (displaySpeedKmh < 0) displaySpeedKmh = 0;
        }
      }

      // API reported speed.
      final apiSpeed = state.observations
          .where((o) => !o.rejected)
          .lastOrNull
          ?.speed;

      // Speed fidelity tracking.
      if (displaySpeedKmh != null && apiSpeed != null && apiSpeed > 2.0) {
        bs.speedFidelityRatios.add(displaySpeedKmh / apiSpeed);
      }

      // Position error vs ground truth.
      if (truth != null) {
        final err = NearestStopService.haversineDistance(
          lat,
          lon,
          truth.lat,
          truth.lon,
        );
        bs.positionErrors.add(err);
      }

      // --- Anomaly detection ---

      // Backward jump.
      if (progressM != null &&
          bs.previousProgressM != null &&
          bs.previousShapeId == state.shapeId) {
        final delta = progressM - bs.previousProgressM!;
        if (delta < -thresholds.backwardJumpMeters) {
          final mag = delta.abs();
          bs.backstepCount++;
          bs.backstepTotalMeters += mag;
          events.add(
            TraceEvent(
              TraceEventType.backstepOccurred,
              '${delta.toStringAsFixed(1)}m at progress=${progressM.toStringAsFixed(1)}m',
            ),
          );
          _addAnomaly(
            key,
            Anomaly(
              type: AnomalyType.backwardJump,
              elapsedSeconds: elapsed,
              busKey: key,
              description:
                  'Progress decreased by ${mag.toStringAsFixed(1)}m to ${progressM.toStringAsFixed(1)}m',
              magnitudeMeters: mag,
            ),
          );
        }
      }

      // Teleport.
      if (bs.previousLat != null && bs.previousLon != null) {
        final dist = NearestStopService.haversineDistance(
          bs.previousLat!,
          bs.previousLon!,
          lat,
          lon,
        );
        if (dist > thresholds.teleportMeters) {
          _addAnomaly(
            key,
            Anomaly(
              type: AnomalyType.teleport,
              elapsedSeconds: elapsed,
              busKey: key,
              description:
                  'Position jumped ${dist.toStringAsFixed(1)}m in one frame',
              magnitudeMeters: dist,
            ),
          );
        }
      }

      // Freeze detection.
      if (progressM != null && apiSpeed != null && apiSpeed > 2.0) {
        if (bs.freezeProgressM != null &&
            (progressM - bs.freezeProgressM!).abs() < 0.5) {
          // Still frozen.
          final frozenFor =
              now.difference(bs.freezeStartTime!).inMilliseconds / 1000.0;
          if (frozenFor > thresholds.freezeSeconds) {
            _addAnomaly(
              key,
              Anomaly(
                type: AnomalyType.freeze,
                elapsedSeconds: elapsed,
                busKey: key,
                description:
                    'Frozen for ${frozenFor.toStringAsFixed(1)}s at progress=${progressM.toStringAsFixed(1)}m (api_speed=${apiSpeed.toStringAsFixed(0)}km/h)',
                magnitudeMeters: frozenFor,
              ),
            );
            // Reset to avoid spamming.
            bs.freezeStartTime = now;
          }
        } else {
          // Moving — reset freeze tracking.
          bs.freezeProgressM = progressM;
          bs.freezeStartTime = now;
        }
      } else {
        bs.freezeProgressM = progressM;
        bs.freezeStartTime = now;
      }

      // Speed spike.
      if (displaySpeedKmh != null &&
          displaySpeedKmh > thresholds.speedSpikeKmh) {
        _addAnomaly(
          key,
          Anomaly(
            type: AnomalyType.speedSpike,
            elapsedSeconds: elapsed,
            busKey: key,
            description:
                'Displayed speed ${displaySpeedKmh.toStringAsFixed(1)}km/h',
            magnitudeMeters: displaySpeedKmh,
          ),
        );
      }

      // Collect pending events from afterBatch.
      final pendingEvents = _pendingEvents.remove(key);
      if (pendingEvents != null) {
        events.insertAll(0, pendingEvents);
      }

      final record = FrameRecord(
        timestamp: now,
        elapsedSeconds: elapsed,
        busKey: key,
        renderedLat: lat,
        renderedLon: lon,
        renderedHeading: heading,
        renderedProgressM: progressM,
        truthLat: truth?.lat,
        truthLon: truth?.lon,
        truthProgressM: truth?.progressM,
        truthSpeedKmh: truth?.speedKmh,
        displaySpeedKmh: displaySpeedKmh,
        apiReportedSpeedKmh: apiSpeed,
        status: state.status,
        blendActive: blending,
        blendFraction: blendFrac,
        stateProgressM: state.progressAlongRoute,
        shapeId: state.shapeId,
        tripId: state.currentTripId,
        vehicleId: state.vehicleId,
        events: events,
      );

      _frames.putIfAbsent(key, () => []).add(record);

      // Update tracking state.
      bs.previousProgressM = progressM;
      bs.previousShapeId = state.shapeId;
      bs.previousLat = lat;
      bs.previousLon = lon;
      bs.previousTimestamp = now;
      bs.previousStatus = state.status;
    }
  }

  /// Compute summary for a single bus.
  BusTraceSummary summaryFor(String busKey) {
    final frames = _frames[busKey] ?? [];
    final anomalies = _anomalies[busKey] ?? [];
    final bs = _busStates[busKey] ?? _BusTraceState();

    final duration = frames.isEmpty
        ? 0.0
        : frames.last.elapsedSeconds - frames.first.elapsedSeconds;

    double? maxProgress;
    for (final f in frames) {
      if (f.renderedProgressM != null) {
        maxProgress = math.max(maxProgress ?? 0.0, f.renderedProgressM!);
      }
    }

    final anomalyMap = <AnomalyType, int>{};
    for (final a in anomalies) {
      anomalyMap[a.type] = (anomalyMap[a.type] ?? 0) + 1;
    }

    return BusTraceSummary(
      busKey: busKey,
      frameCount: frames.length,
      durationSeconds: duration,
      routeLengthM: maxProgress,
      anomalyCount: anomalies.length,
      anomaliesByType: anomalyMap,
      backstepCount: bs.backstepCount,
      backstepTotalMeters: bs.backstepTotalMeters,
      blendCount: bs.blendCount,
      speedFidelityP50: _percentile(bs.speedFidelityRatios, 0.5),
      speedFidelityP90: _percentile(bs.speedFidelityRatios, 0.9),
      positionErrorP90: _percentile(bs.positionErrors, 0.9),
    );
  }

  // --- Private helpers ---

  double _elapsed(DateTime now) =>
      now.difference(_startTime).inMilliseconds / 1000.0;

  _BusTraceState _busStateFor(String key) =>
      _busStates.putIfAbsent(key, _BusTraceState.new);

  final Map<String, List<TraceEvent>> _pendingEvents = {};

  void _addEvent(String key, double elapsed, TraceEvent event) {
    _pendingEvents.putIfAbsent(key, () => []).add(event);
  }

  void _addAnomaly(String key, Anomaly anomaly) {
    _anomalies.putIfAbsent(key, () => []).add(anomaly);
  }

  static double? _percentile(List<double> values, double p) {
    if (values.isEmpty) return null;
    final sorted = List.of(values)..sort();
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx];
  }
}
