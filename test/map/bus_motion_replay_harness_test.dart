import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/map/bus_journey_tracer.dart';
import 'package:busboard_nl/domain/map/bus_motion_engine.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bus_journey_renderer.dart';

void main() {
  test(
    'bus motion harness: replayed turns stay road-aligned, smooth, and stable',
    () {
      final repo = _buildSyntheticRepo();
      final engine = BusMotionEngine(repo);
      final random = math.Random(42);
      const routeRun = 'Rt 1-1';
      const vehicleKey = 'harness_bus';
      final traceEnv = Platform.environment['BUS_MOTION_TRACE'] ?? '';
      final tracerEnabled = traceEnv.isNotEmpty;
      final baseTime0 = DateTime(2026, 2, 15, 12, 0, 0);
      final tracer = tracerEnabled
          ? BusJourneyTracer(startTime: baseTime0)
          : null;
      final shapePoints = repo.shapesById['shape_main']!;
      final shapeDists = repo.shapeCumulativeDistances['shape_main']!;
      final routeLengthM = shapeDists.last;

      const totalSeconds = 210.0;
      const renderDt = 0.12; // ~8.3 FPS, matches map update cadence.
      final truthTimeline = _buildTruthTimeline(
        totalSeconds: totalSeconds,
        dtSeconds: renderDt,
        routeLengthM: routeLengthM,
      );

      const pollIntervalSeconds = 5.0;
      final baseTime = DateTime(2026, 2, 15, 12, 0, 0);
      var nextPollTime = 0.0;

      double? prevRenderedProgress;
      var activeBackstepCount = 0;
      var activeBackstepMeters = 0.0;

      double? prevRenderedTime;
      double? prevRenderedProgressForSpeed;
      final offShapeErrorsM = <double>[];
      final speedErrorsKmh = <double>[];
      final speedFidelityRatios = <double>[];
      final correctionP90s = <double>[];
      final innovationP50s = <double>[];

      for (var t = 0.0; t <= totalSeconds; t += renderDt) {
        if (t + 1e-9 >= nextPollTime) {
          final lagSeconds = (28.0 + 9.0 * math.sin(t / 33.0)).clamp(
            12.0,
            55.0,
          );
          final measurementT = (t - lagSeconds).clamp(0.0, totalSeconds);
          final truthAtMeasurement = _sampleTruth(truthTimeline, measurementT);

          final progressNoiseM = _gaussianNoise(random, stdDev: 14.0);
          final measuredProgress =
              (truthAtMeasurement.progressM + progressNoiseM).clamp(
                0.0,
                routeLengthM,
              );
          final measuredPoint = _pointOnShape(
            points: shapePoints,
            cumulativeDistances: shapeDists,
            progressMeters: measuredProgress,
          );

          final reportedSpeed = math.max(
            0.0,
            truthAtMeasurement.speedKmh + _gaussianNoise(random, stdDev: 6.0),
          );

          final fetchTime = baseTime.add(
            Duration(milliseconds: (t * 1000).round()),
          );
          final measurementTime = baseTime.add(
            Duration(milliseconds: (measurementT * 1000).round()),
          );

          final vehicle = _buildVehicle(
            routeRun: routeRun,
            lat: measuredPoint.$1,
            lon: measuredPoint.$2,
            speedKmh: reportedSpeed,
            fetchTime: fetchTime,
            measurementTime: measurementTime,
          );

          tracer?.beforeBatch(engine);
          engine.processBatch([vehicle], fetchTime);
          tracer?.afterBatch(engine, fetchTime);
          final d = engine.diagnostics;
          if (d.correctionP90Meters != null) {
            correctionP90s.add(d.correctionP90Meters!);
          }
          if (d.innovationP50Meters != null) {
            innovationP50s.add(d.innovationP50Meters!);
          }

          nextPollTime += pollIntervalSeconds;
        }

        final now = baseTime.add(Duration(milliseconds: (t * 1000).round()));
        final allRendered = engine.interpolate(now);
        if (tracer != null) {
          final truth = _sampleTruth(truthTimeline, t);
          final truthPoint = _pointOnShape(
            points: shapePoints,
            cumulativeDistances: shapeDists,
            progressMeters: truth.progressM,
          );
          tracer.recordFrame(
            now: now,
            engine: engine,
            rendered: allRendered,
            groundTruth: {
              vehicleKey: GroundTruth(
                lat: truthPoint.$1,
                lon: truthPoint.$2,
                progressM: truth.progressM,
                speedKmh: truth.speedKmh,
              ),
            },
          );
        }
        final rendered = allRendered[vehicleKey];
        if (rendered == null) continue;

        final snap = _snapProgressWithContinuity(
          lat: rendered.$1,
          lon: rendered.$2,
          points: shapePoints,
          cumulativeDistances: shapeDists,
          previousProgressM: prevRenderedProgress,
        );
        if (snap == null) continue;
        offShapeErrorsM.add(snap.perpendicularDistanceMeters);
        final renderedProgress =
            engine.debugRenderedProgressByKey[vehicleKey] ?? snap.progressM;

        final state = engine.states[vehicleKey];
        if (state?.status == BusStatus.active && prevRenderedProgress != null) {
          final previousProgress = prevRenderedProgress;
          if (renderedProgress + 1e-3 < previousProgress) {
            activeBackstepCount++;
            activeBackstepMeters += (previousProgress - renderedProgress);
          }
        }
        prevRenderedProgress = renderedProgress;

        if (prevRenderedTime != null && prevRenderedProgressForSpeed != null) {
          final previousTime = prevRenderedTime;
          final previousProgressForSpeed = prevRenderedProgressForSpeed;
          final dt = t - previousTime;
          if (dt > 0.0) {
            final displaySpeedKmh =
                ((renderedProgress - previousProgressForSpeed).abs() / dt) *
                3.6;
            final truth = _sampleTruth(truthTimeline, t);
            speedErrorsKmh.add((displaySpeedKmh - truth.speedKmh).abs());
            if (truth.speedKmh >= 2.0) {
              final ratio = displaySpeedKmh / truth.speedKmh;
              if (ratio.isFinite && ratio >= 0.0) {
                speedFidelityRatios.add(ratio.clamp(0.0, 8.0));
              }
            }
          }
        }
        prevRenderedTime = t;
        prevRenderedProgressForSpeed = renderedProgress;
      }

      final offShapeP90 = _percentile(offShapeErrorsM, 0.90);
      final speedErrP50 = _percentile(speedErrorsKmh, 0.50);
      final speedFidelityP50 = _percentile(speedFidelityRatios, 0.50);
      final speedFidelityP90 = _percentile(speedFidelityRatios, 0.90);
      final correctionP90Median = _percentile(correctionP90s, 0.50);
      final innovationP50Median = _percentile(innovationP50s, 0.50);

      // Human-readable summary for CI logs and future agent debugging.
      // ignore: avoid_print
      print(
        '[Harness] offShapeP90=${offShapeP90.toStringAsFixed(2)}m '
        'speedErrP50=${speedErrP50.toStringAsFixed(2)}km/h '
        'speedFidelity(p50/p90)='
        '${speedFidelityP50.toStringAsFixed(2)}/${speedFidelityP90.toStringAsFixed(2)} '
        'activeBacksteps=$activeBackstepCount '
        'activeBackstepMeters=${activeBackstepMeters.toStringAsFixed(2)} '
        'corrP90Median=${correctionP90Median.toStringAsFixed(2)}m '
        'innovP50Median=${innovationP50Median.toStringAsFixed(2)}m',
      );
      if (tracer != null) {
        BusJourneyRenderer.printReport(
          tracer,
          onlyAnomalous: false,
          verbose: traceEnv == 'verbose',
        );
      }
      _maybeWriteMetrics(
        harness: 'synthetic',
        metrics: {
          'off_shape_p90_m': offShapeP90,
          'speed_error_p50_kmh': speedErrP50,
          'speed_fidelity_ratio_p50': speedFidelityP50,
          'speed_fidelity_ratio_p90': speedFidelityP90,
          'active_backsteps': activeBackstepCount,
          'active_backstep_meters': activeBackstepMeters,
          'correction_p90_median_m': correctionP90Median,
          'innovation_p50_median_m': innovationP50Median,
          'samples_off_shape': offShapeErrorsM.length,
          'samples_speed': speedErrorsKmh.length,
          'samples_speed_fidelity': speedFidelityRatios.length,
        },
      );

      // Conservative guardrails to catch regressions without false positives.
      final totalSamples = offShapeErrorsM.length;
      final backstepRate = totalSamples == 0
          ? 0.0
          : activeBackstepCount / totalSamples;

      expect(offShapeP90, lessThan(6.0));
      // Backsteps can occur during large corrections (e.g. warm-up
      // over-projection) and are handled by blend smoothing. Allow a
      // small rate consistent with the real-world replay harness.
      expect(backstepRate, lessThan(0.02));
      expect(speedErrP50, lessThan(25.0));
      expect(speedFidelityP50, greaterThan(0.3));
      expect(correctionP90Median, lessThan(250.0));
      expect(innovationP50Median, lessThan(120.0));
    },
  );
}

class _TruthSample {
  final double t;
  final double progressM;
  final double speedKmh;

  const _TruthSample({
    required this.t,
    required this.progressM,
    required this.speedKmh,
  });
}

class _SnapProgress {
  final double progressM;
  final double perpendicularDistanceMeters;

  const _SnapProgress({
    required this.progressM,
    required this.perpendicularDistanceMeters,
  });
}

List<_TruthSample> _buildTruthTimeline({
  required double totalSeconds,
  required double dtSeconds,
  required double routeLengthM,
}) {
  final samples = <_TruthSample>[];
  var progress = 0.0;
  var t = 0.0;
  while (t <= totalSeconds + 1e-9) {
    final speed = _speedProfileKmh(t);
    if (samples.isNotEmpty) {
      progress += (speed / 3.6) * dtSeconds;
      if (progress > routeLengthM) {
        progress = routeLengthM;
      }
    }
    samples.add(_TruthSample(t: t, progressM: progress, speedKmh: speed));
    t += dtSeconds;
  }
  return samples;
}

double _speedProfileKmh(double t) {
  // Slow at corners, faster on straights to stress turn handling.
  if (t < 25) return 42;
  if (t < 42) return 20;
  if (t < 80) return 38;
  if (t < 98) return 18;
  if (t < 145) return 40;
  if (t < 162) return 16;
  return 34;
}

_TruthSample _sampleTruth(List<_TruthSample> timeline, double t) {
  if (timeline.isEmpty) {
    return const _TruthSample(t: 0, progressM: 0, speedKmh: 0);
  }
  if (t <= timeline.first.t) return timeline.first;
  if (t >= timeline.last.t) return timeline.last;

  var i = 1;
  while (i < timeline.length && timeline[i].t < t) {
    i++;
  }
  final a = timeline[i - 1];
  final b = timeline[i];
  final span = (b.t - a.t);
  if (span <= 1e-9) return b;
  final r = ((t - a.t) / span).clamp(0.0, 1.0);
  return _TruthSample(
    t: t,
    progressM: a.progressM + (b.progressM - a.progressM) * r,
    speedKmh: a.speedKmh + (b.speedKmh - a.speedKmh) * r,
  );
}

GtfsRepository _buildSyntheticRepo() {
  final repo = GtfsRepository();

  const shapeId = 'shape_main';
  const routeId = 'route_1';
  const tripId = 'trip_1';
  const serviceId = 'svc_1';

  final shape = <ShapePoint>[
    const ShapePoint(
      shapeId: shapeId,
      lat: 47.5600,
      lon: -52.7400,
      sequence: 1,
    ),
    const ShapePoint(
      shapeId: shapeId,
      lat: 47.5600,
      lon: -52.7310,
      sequence: 2,
    ),
    const ShapePoint(
      shapeId: shapeId,
      lat: 47.5675,
      lon: -52.7310,
      sequence: 3,
    ),
    const ShapePoint(
      shapeId: shapeId,
      lat: 47.5675,
      lon: -52.7210,
      sequence: 4,
    ),
    const ShapePoint(
      shapeId: shapeId,
      lat: 47.5730,
      lon: -52.7210,
      sequence: 5,
    ),
  ];
  final cumulative = _buildCumulativeDistances(shape);

  repo.shapesById[shapeId] = shape;
  repo.shapeCumulativeDistances[shapeId] = cumulative;
  repo.routesById[routeId] = const RouteInfo(
    routeId: routeId,
    routeShortName: '1',
    routeLongName: 'Harness Route',
  );
  repo.tripsById[tripId] = const TripInfo(
    tripId: tripId,
    routeId: routeId,
    serviceId: serviceId,
    tripHeadsign: 'Harness Headsign',
    directionId: 0,
    shapeId: shapeId,
  );
  repo.tripsByRouteShortName['1'] = const [
    TripShapeEntry(
      tripId: tripId,
      shapeId: shapeId,
      headsign: 'Harness Headsign',
      directionId: 0,
      serviceId: serviceId,
    ),
  ];

  final stopPoints = <(String, double, double)>[
    ('stop_1', 47.5600, -52.7380),
    ('stop_2', 47.5600, -52.7330),
    ('stop_3', 47.5642, -52.7310),
    ('stop_4', 47.5675, -52.7270),
    ('stop_5', 47.5710, -52.7210),
  ];
  for (var i = 0; i < stopPoints.length; i++) {
    final stop = stopPoints[i];
    repo.stopsById[stop.$1] = StopInfo(
      stopId: stop.$1,
      stopName: 'Harness Stop ${i + 1}',
      stopLat: stop.$2,
      stopLon: stop.$3,
    );
    repo.stopTimesByStopId
        .putIfAbsent(stop.$1, () => [])
        .add(
          StopTimeRow(
            tripId: tripId,
            arrivalTime: '12:00:00',
            departureTime: '12:00:00',
            stopId: stop.$1,
            stopSequence: i + 1,
          ),
        );
  }

  return repo;
}

TimeTrackVehicle _buildVehicle({
  required String routeRun,
  required double lat,
  required double lon,
  required double speedKmh,
  required DateTime fetchTime,
  required DateTime measurementTime,
}) {
  final measurementSeconds =
      measurementTime.hour * 3600 +
      measurementTime.minute * 60 +
      measurementTime.second;

  return TimeTrackVehicle(
    routeRun: routeRun,
    currentRoute: '01-1',
    routeNumber: 1,
    vehicle: 'harness_bus',
    timeStamp: _hhmm(fetchTime),
    deviation: 'ON TIME',
    currentLocation: 'Harness',
    busLat: lat,
    busLon: lon,
    heading: 'E',
    speed: speedKmh,
    positionTime: _hhmm(measurementTime),
    positionTimeSeconds: measurementSeconds,
    gtfsTripHeadsign: 'Harness Headsign',
    gtfsServiceId: 'svc_1',
    gtfsStopSequenceStatus: 'ON TIME',
    gtfsStopSequenceMinsFromStop: 0,
    gtfsStopSequenceDeviation: 'ON TIME',
    gtfsStopSequenceClosestStop: 'Harness Stop',
    gtfsStopSequenceSchedDifferenceMins: 0,
    gtfsTripId: 'trip_1',
    shortStatus: 'OT',
    departureTimeAtClosestStop: measurementSeconds,
  );
}

String _hhmm(DateTime dt) {
  final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final minute = dt.minute.toString().padLeft(2, '0');
  final suffix = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

List<double> _buildCumulativeDistances(List<ShapePoint> points) {
  if (points.isEmpty) return const [];
  final out = <double>[0.0];
  for (var i = 1; i < points.length; i++) {
    final prev = points[i - 1];
    final cur = points[i];
    out.add(
      out.last +
          NearestStopService.haversineDistance(
            prev.lat,
            prev.lon,
            cur.lat,
            cur.lon,
          ),
    );
  }
  return out;
}

(double, double) _pointOnShape({
  required List<ShapePoint> points,
  required List<double> cumulativeDistances,
  required double progressMeters,
}) {
  if (points.isEmpty || cumulativeDistances.isEmpty) return (0.0, 0.0);
  final clamped = progressMeters.clamp(0.0, cumulativeDistances.last);
  if (clamped <= 0.0) return (points.first.lat, points.first.lon);
  if (clamped >= cumulativeDistances.last) {
    return (points.last.lat, points.last.lon);
  }

  var idx = 1;
  while (idx < cumulativeDistances.length &&
      cumulativeDistances[idx] < clamped) {
    idx++;
  }
  if (idx >= points.length) idx = points.length - 1;

  final d0 = cumulativeDistances[idx - 1];
  final d1 = cumulativeDistances[idx];
  final seg = d1 - d0;
  final t = seg <= 1e-9 ? 0.0 : ((clamped - d0) / seg).clamp(0.0, 1.0);
  final p0 = points[idx - 1];
  final p1 = points[idx];
  return (p0.lat + (p1.lat - p0.lat) * t, p0.lon + (p1.lon - p0.lon) * t);
}

double _percentile(List<double> values, double q) {
  if (values.isEmpty) return 0.0;
  final sorted = List<double>.from(values)..sort();
  final idx = ((sorted.length - 1) * q).round().clamp(0, sorted.length - 1);
  return sorted[idx];
}

double _gaussianNoise(math.Random random, {required double stdDev}) {
  // Box-Muller transform.
  final u1 = (random.nextDouble()).clamp(1e-12, 1.0);
  final u2 = random.nextDouble();
  final z0 = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
  return z0 * stdDev;
}

_SnapProgress? _snapProgressWithContinuity({
  required double lat,
  required double lon,
  required List<ShapePoint> points,
  required List<double> cumulativeDistances,
  required double? previousProgressM,
}) {
  if (points.length < 2 || cumulativeDistances.length < 2) return null;

  double bestScore = double.infinity;
  double bestProgress = 0.0;
  double bestPerpDistance = double.infinity;

  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    final proj = _projectToSegment(
      px: lat,
      py: lon,
      ax: a.lat,
      ay: a.lon,
      bx: b.lat,
      by: b.lon,
    );
    final projLat = proj.$1;
    final projLon = proj.$2;
    final t = proj.$3;
    final perp = NearestStopService.haversineDistance(
      lat,
      lon,
      projLat,
      projLon,
    );
    final segLen = cumulativeDistances[i + 1] - cumulativeDistances[i];
    final progress = cumulativeDistances[i] + segLen * t;

    final continuityPenalty = previousProgressM == null
        ? 0.0
        : (progress - previousProgressM).abs() * 0.02;
    final score = perp + continuityPenalty;

    if (score < bestScore) {
      bestScore = score;
      bestProgress = progress;
      bestPerpDistance = perp;
    }
  }

  return _SnapProgress(
    progressM: bestProgress,
    perpendicularDistanceMeters: bestPerpDistance,
  );
}

(double, double, double) _projectToSegment({
  required double px,
  required double py,
  required double ax,
  required double ay,
  required double bx,
  required double by,
}) {
  final dx = bx - ax;
  final dy = by - ay;
  final lenSq = dx * dx + dy * dy;
  if (lenSq <= 1e-12) return (ax, ay, 0.0);
  var t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
  t = t.clamp(0.0, 1.0);
  return (ax + t * dx, ay + t * dy, t);
}

void _maybeWriteMetrics({
  required String harness,
  required Map<String, dynamic> metrics,
}) {
  final outPath = Platform.environment['BUS_MOTION_METRICS_OUT'];
  if (outPath == null || outPath.trim().isEmpty) return;

  final file = File(outPath.trim());
  file.parent.createSync(recursive: true);

  final payload = <String, dynamic>{
    'harness': harness,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    ...metrics,
  };

  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
  // ignore: avoid_print
  print('[Harness] wrote metrics JSON to ${file.path}');
}
