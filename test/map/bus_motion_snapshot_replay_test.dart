import 'dart:convert';
import 'dart:io';

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
    'bus motion replay harness: captured TimeTrack snapshots stay stable and smooth',
    () {
      final fixturePath =
          Platform.environment['BUS_MOTION_CAPTURE_PATH'] ??
          'test/fixtures/timetrack/capture.json';
      final fixtureFile = File(fixturePath);
      if (!fixtureFile.existsSync()) {
        // ignore: avoid_print
        print(
          '[Replay] skipped: fixture not found at $fixturePath '
          '(capture with: dart run tool/capture_timetrack_snapshots.dart)',
        );
        _maybeWriteMetrics(
          harness: 'snapshot',
          metrics: {
            'status': 'skipped',
            'reason': 'fixture_not_found',
            'fixture': fixturePath,
          },
        );
        return;
      }

      final replayFrames = _loadReplayFrames(fixtureFile);
      if (replayFrames.length < 2) {
        // ignore: avoid_print
        print('[Replay] skipped: fixture has <2 frames at ${fixtureFile.path}');
        _maybeWriteMetrics(
          harness: 'snapshot',
          metrics: {
            'status': 'skipped',
            'reason': 'insufficient_frames',
            'fixture': fixtureFile.path,
            'frames': replayFrames.length,
          },
        );
        return;
      }

      final maxFrames = int.tryParse(
        Platform.environment['BUS_MOTION_MAX_FRAMES'] ?? '',
      );
      final frames = (maxFrames != null && maxFrames > 1)
          ? replayFrames.take(maxFrames).toList()
          : replayFrames;

      final repo = _buildRepoFromFrames(frames);
      final engine = BusMotionEngine(repo);
      final metrics = _ReplayMetrics();
      final traceEnv = Platform.environment['BUS_MOTION_TRACE'] ?? '';
      final tracerEnabled = traceEnv.isNotEmpty;
      final tracer = tracerEnabled
          ? BusJourneyTracer(startTime: frames.first.fetchTime)
          : null;

      final renderStep = const Duration(milliseconds: 120);
      var cursor = frames.first.fetchTime;

      for (final frame in frames) {
        final pollTime = frame.fetchTime;
        if (pollTime.isAfter(cursor)) {
          while (cursor.isBefore(pollTime)) {
            final next = cursor.add(renderStep);
            cursor = next.isAfter(pollTime) ? pollTime : next;
            _collectRenderMetrics(
              now: cursor,
              engine: engine,
              repo: repo,
              metrics: metrics,
              tracer: tracer,
            );
          }
        } else {
          cursor = pollTime;
        }

        tracer?.beforeBatch(engine);
        engine.processBatch(frame.vehicles, pollTime);
        tracer?.afterBatch(engine, pollTime);
        metrics.totalPolls++;
        if (frame.statusCode != 200) {
          metrics.non200Polls++;
        }
        metrics.totalVehiclesInFrames += frame.vehicles.length;
        metrics.totalProcessedVehicles += engine.diagnostics.processedVehicles;
        metrics.totalAcceptedUpdates += engine.diagnostics.acceptedUpdates;
        metrics.totalDuplicateUpdates +=
            engine.diagnostics.duplicateOrOutOfOrderUpdates;
        metrics.totalRejectedOutliers += engine.diagnostics.rejectedOutliers;
        if (engine.diagnostics.correctionP90Meters != null) {
          metrics.correctionP90Samples.add(
            engine.diagnostics.correctionP90Meters!,
          );
        }
        if (engine.diagnostics.innovationP50Meters != null) {
          metrics.innovationP50Samples.add(
            engine.diagnostics.innovationP50Meters!,
          );
        }
      }

      for (var i = 0; i < 50; i++) {
        cursor = cursor.add(renderStep);
        _collectRenderMetrics(
          now: cursor,
          engine: engine,
          repo: repo,
          metrics: metrics,
          tracer: tracer,
        );
      }

      if (tracer != null) {
        BusJourneyRenderer.printReport(
          tracer,
          onlyAnomalous: traceEnv != 'verbose',
          verbose: traceEnv == 'verbose',
        );
      }

      final offShapeP90 = _percentile(metrics.offShapeErrorsM, 0.90);
      final speedErrP50 = _percentile(metrics.speedErrorsKmh, 0.50);
      final speedFidelityP50 = _percentile(metrics.speedFidelityRatios, 0.50);
      final speedFidelityP90 = _percentile(metrics.speedFidelityRatios, 0.90);
      final correctionP90Median = _percentile(
        metrics.correctionP90Samples,
        0.50,
      );
      final innovationP50Median = _percentile(
        metrics.innovationP50Samples,
        0.50,
      );
      final backstepRate = metrics.renderedProgressSamples == 0
          ? 0.0
          : metrics.activeBackstepCount / metrics.renderedProgressSamples;

      // ignore: avoid_print
      print(
        '[Replay] fixture=${fixtureFile.path} frames=${frames.length} '
        'polls=${metrics.totalPolls} vehicles=${metrics.totalVehiclesInFrames} '
        'non200=${metrics.non200Polls} '
        'processed=${metrics.totalProcessedVehicles} '
        'accepted=${metrics.totalAcceptedUpdates} dup=${metrics.totalDuplicateUpdates} '
        'rejected=${metrics.totalRejectedOutliers} '
        'snapped=${metrics.snappedSamples} rendered=${metrics.renderedProgressSamples} '
        'offShapeP90=${offShapeP90.toStringAsFixed(2)}m '
        'speedErrP50=${speedErrP50.toStringAsFixed(2)}km/h '
        'speedFidelity(p50/p90)='
        '${speedFidelityP50.toStringAsFixed(2)}/${speedFidelityP90.toStringAsFixed(2)} '
        'activeBacksteps=${metrics.activeBackstepCount} '
        'activeBackstepMeters=${metrics.activeBackstepMeters.toStringAsFixed(2)} '
        'backstepRate=${backstepRate.toStringAsFixed(4)} '
        'corrP90Median=${correctionP90Median.toStringAsFixed(2)}m '
        'innovP50Median=${innovationP50Median.toStringAsFixed(2)}m',
      );
      _maybeWriteMetrics(
        harness: 'snapshot',
        metrics: {
          'status': 'ok',
          'fixture': fixtureFile.path,
          'frames': frames.length,
          'polls': metrics.totalPolls,
          'non_200_polls': metrics.non200Polls,
          'vehicles': metrics.totalVehiclesInFrames,
          'processed': metrics.totalProcessedVehicles,
          'accepted': metrics.totalAcceptedUpdates,
          'duplicates': metrics.totalDuplicateUpdates,
          'rejected': metrics.totalRejectedOutliers,
          'snapped_samples': metrics.snappedSamples,
          'rendered_samples': metrics.renderedProgressSamples,
          'off_shape_p90_m': offShapeP90,
          'speed_error_p50_kmh': speedErrP50,
          'speed_fidelity_ratio_p50': speedFidelityP50,
          'speed_fidelity_ratio_p90': speedFidelityP90,
          'active_backsteps': metrics.activeBackstepCount,
          'active_backstep_meters': metrics.activeBackstepMeters,
          'backstep_rate': backstepRate,
          'correction_p90_median_m': correctionP90Median,
          'innovation_p50_median_m': innovationP50Median,
          'samples_speed_fidelity': metrics.speedFidelityRatios.length,
        },
      );

      expect(metrics.totalPolls, greaterThanOrEqualTo(2));
      expect(metrics.totalVehiclesInFrames, greaterThan(0));
      expect(metrics.totalProcessedVehicles, greaterThan(0));
      expect(metrics.totalAcceptedUpdates, greaterThan(0));

      if (metrics.renderedProgressSamples >= 40) {
        expect(backstepRate, lessThan(0.02));
      }
      if (metrics.snappedSamples >= 40) {
        expect(offShapeP90, lessThan(60.0));
      }
      if (metrics.speedErrorsKmh.length >= 25) {
        expect(speedErrP50, lessThan(55.0));
      }
      if (metrics.correctionP90Samples.length >= 6) {
        expect(correctionP90Median, lessThan(900.0));
      }
      if (metrics.innovationP50Samples.length >= 6) {
        expect(innovationP50Median, lessThan(350.0));
      }
    },
  );
}

class _ReplayFrame {
  final DateTime fetchTime;
  final int statusCode;
  final List<TimeTrackVehicle> vehicles;

  const _ReplayFrame({
    required this.fetchTime,
    required this.statusCode,
    required this.vehicles,
  });
}

class _TracePoint {
  final DateTime time;
  final double lat;
  final double lon;
  final int routeNumber;
  final String headsign;
  final String serviceId;
  final String tripId;

  const _TracePoint({
    required this.time,
    required this.lat,
    required this.lon,
    required this.routeNumber,
    required this.headsign,
    required this.serviceId,
    required this.tripId,
  });
}

class _RenderProgressSample {
  final DateTime time;
  final double progressM;

  const _RenderProgressSample({required this.time, required this.progressM});
}

class _ReplayMetrics {
  int totalPolls = 0;
  int non200Polls = 0;
  int totalVehiclesInFrames = 0;
  int totalProcessedVehicles = 0;
  int totalAcceptedUpdates = 0;
  int totalDuplicateUpdates = 0;
  int totalRejectedOutliers = 0;
  int snappedSamples = 0;
  int renderedProgressSamples = 0;
  int activeBackstepCount = 0;
  double activeBackstepMeters = 0.0;
  final List<double> offShapeErrorsM = [];
  final List<double> speedErrorsKmh = [];
  final List<double> speedFidelityRatios = [];
  final List<double> correctionP90Samples = [];
  final List<double> innovationP50Samples = [];
  final Map<String, double> previousProgressByKey = {};
  final Map<String, _RenderProgressSample> previousRenderByKey = {};
}

List<_ReplayFrame> _loadReplayFrames(File fixtureFile) {
  final decoded = jsonDecode(fixtureFile.readAsStringSync());
  if (decoded is! Map<String, dynamic>) return const [];
  final rawFrames = decoded['frames'];
  if (rawFrames is! List) return const [];

  final frames = <_ReplayFrame>[];
  for (final raw in rawFrames) {
    if (raw is! Map) continue;
    final map = Map<String, dynamic>.from(raw);
    final fetchTime = DateTime.tryParse(map['fetch_time']?.toString() ?? '');
    if (fetchTime == null) continue;

    final vehiclesRaw = map['vehicles'];
    if (vehiclesRaw is! List) continue;
    final vehicles = vehiclesRaw
        .whereType<Map>()
        .map((e) => TimeTrackVehicle.fromJson(Map<String, dynamic>.from(e)))
        .where((v) => _isValidCoord(v.busLat, v.busLon))
        .toList();

    frames.add(
      _ReplayFrame(
        fetchTime: fetchTime.toUtc(),
        statusCode: _safeInt(map['status_code']),
        vehicles: vehicles,
      ),
    );
  }

  frames.sort((a, b) => a.fetchTime.compareTo(b.fetchTime));
  return frames;
}

GtfsRepository _buildRepoFromFrames(List<_ReplayFrame> frames) {
  final repo = GtfsRepository();
  final pointsByTrace = <String, List<_TracePoint>>{};
  final pointsByTripId = <String, List<_TracePoint>>{};
  final allPoints = <_TracePoint>[];

  for (final frame in frames) {
    for (final vehicle in frame.vehicles) {
      if (!_isValidCoord(vehicle.busLat, vehicle.busLon)) continue;
      final point = _TracePoint(
        time: frame.fetchTime,
        lat: vehicle.busLat,
        lon: vehicle.busLon,
        routeNumber: vehicle.routeNumber,
        headsign: vehicle.gtfsTripHeadsign.trim(),
        serviceId: vehicle.gtfsServiceId.trim(),
        tripId: vehicle.gtfsTripId.trim(),
      );
      allPoints.add(point);

      final traceKey = _traceKey(vehicle);
      if (traceKey != null) {
        pointsByTrace.putIfAbsent(traceKey, () => []).add(point);
      }
      if (point.tripId.isNotEmpty) {
        pointsByTripId.putIfAbsent(point.tripId, () => []).add(point);
      }
    }
  }

  var shapeIndex = 0;
  var syntheticTripIndex = 0;
  final assignedShapeByTripId = <String, String>{};

  for (final trace in pointsByTrace.values) {
    if (trace.length < 2) continue;
    trace.sort((a, b) => a.time.compareTo(b.time));
    final segments = _segmentTrace(trace);
    for (final segment in segments) {
      final shapePoints = _toShapePath(segment);
      if (shapePoints.length < 2) continue;
      final routeNumber = _mostFrequentInt(
        segment.map((p) => p.routeNumber).where((n) => n > 0),
      );
      final routeShortName = (routeNumber != null && routeNumber > 0)
          ? routeNumber.toString()
          : 'replay';
      final routeId = 'replay_route_$routeShortName';
      repo.routesById.putIfAbsent(
        routeId,
        () => RouteInfo(
          routeId: routeId,
          routeShortName: routeShortName,
          routeLongName: 'Replay Route $routeShortName',
        ),
      );

      final shapeId = 'replay_shape_${shapeIndex++}';
      repo.shapesById[shapeId] = [
        for (var i = 0; i < shapePoints.length; i++)
          ShapePoint(
            shapeId: shapeId,
            lat: shapePoints[i].$1,
            lon: shapePoints[i].$2,
            sequence: i + 1,
          ),
      ];
      repo.shapeCumulativeDistances[shapeId] = _buildCumulativeDistances(
        repo.shapesById[shapeId]!,
      );

      final headsign =
          _mostFrequentString(
            segment.map((p) => p.headsign).where((s) => s.isNotEmpty),
          ) ??
          'Replay';
      final serviceId =
          _mostFrequentString(
            segment.map((p) => p.serviceId).where((s) => s.isNotEmpty),
          ) ??
          'replay_service';
      final preferredTripId = _mostFrequentString(
        segment.map((p) => p.tripId).where((s) => s.isNotEmpty),
      );

      final tripId = _uniqueTripId(
        preferred: preferredTripId,
        fallbackPrefix: 'replay_trip',
        currentIndex: syntheticTripIndex++,
        existing: repo.tripsById,
      );
      repo.tripsById[tripId] = TripInfo(
        tripId: tripId,
        routeId: routeId,
        serviceId: serviceId,
        tripHeadsign: headsign,
        directionId: 0,
        shapeId: shapeId,
      );
      repo.tripsByRouteShortName
          .putIfAbsent(routeShortName, () => [])
          .add(
            TripShapeEntry(
              tripId: tripId,
              shapeId: shapeId,
              headsign: headsign,
              directionId: 0,
              serviceId: serviceId,
            ),
          );
      if (preferredTripId != null && preferredTripId.isNotEmpty) {
        assignedShapeByTripId[preferredTripId] = shapeId;
      }
    }
  }

  if (repo.shapesById.isEmpty) {
    _seedFallbackRepo(repo: repo, points: allPoints);
  }

  for (final entry in pointsByTripId.entries) {
    final tripId = entry.key;
    if (repo.tripsById.containsKey(tripId)) continue;
    final points = entry.value;
    final routeNumber = _mostFrequentInt(
      points.map((p) => p.routeNumber).where((n) => n > 0),
    );
    final routeShortName = (routeNumber != null && routeNumber > 0)
        ? routeNumber.toString()
        : 'replay';
    final headsign =
        _mostFrequentString(
          points.map((p) => p.headsign).where((s) => s.isNotEmpty),
        ) ??
        'Replay';
    final serviceId =
        _mostFrequentString(
          points.map((p) => p.serviceId).where((s) => s.isNotEmpty),
        ) ??
        'replay_service';
    final shapeId =
        assignedShapeByTripId[tripId] ??
        _bestShapeForRoute(
          repo: repo,
          routeShortName: routeShortName,
          headsign: headsign,
          serviceId: serviceId,
        );
    if (shapeId == null) continue;

    final routeId = 'replay_route_$routeShortName';
    repo.routesById.putIfAbsent(
      routeId,
      () => RouteInfo(
        routeId: routeId,
        routeShortName: routeShortName,
        routeLongName: 'Replay Route $routeShortName',
      ),
    );
    repo.tripsById[tripId] = TripInfo(
      tripId: tripId,
      routeId: routeId,
      serviceId: serviceId,
      tripHeadsign: headsign,
      directionId: 0,
      shapeId: shapeId,
    );
    repo.tripsByRouteShortName
        .putIfAbsent(routeShortName, () => [])
        .add(
          TripShapeEntry(
            tripId: tripId,
            shapeId: shapeId,
            headsign: headsign,
            directionId: 0,
            serviceId: serviceId,
          ),
        );
  }

  return repo;
}

void _seedFallbackRepo({
  required GtfsRepository repo,
  required List<_TracePoint> points,
}) {
  if (points.isEmpty) return;
  points.sort((a, b) => a.time.compareTo(b.time));
  final path = _toShapePath(points);
  if (path.length < 2) return;

  const shapeId = 'replay_shape_fallback';
  const routeId = 'replay_route_fallback';
  const tripId = 'replay_trip_fallback';
  repo.shapesById[shapeId] = [
    for (var i = 0; i < path.length; i++)
      ShapePoint(
        shapeId: shapeId,
        lat: path[i].$1,
        lon: path[i].$2,
        sequence: i + 1,
      ),
  ];
  repo.shapeCumulativeDistances[shapeId] = _buildCumulativeDistances(
    repo.shapesById[shapeId]!,
  );
  repo.routesById[routeId] = const RouteInfo(
    routeId: routeId,
    routeShortName: 'replay',
    routeLongName: 'Replay Route',
  );
  repo.tripsById[tripId] = const TripInfo(
    tripId: tripId,
    routeId: routeId,
    serviceId: 'replay_service',
    tripHeadsign: 'Replay',
    directionId: 0,
    shapeId: shapeId,
  );
  repo.tripsByRouteShortName['replay'] = const [
    TripShapeEntry(
      tripId: tripId,
      shapeId: shapeId,
      headsign: 'Replay',
      directionId: 0,
      serviceId: 'replay_service',
    ),
  ];
}

List<List<_TracePoint>> _segmentTrace(List<_TracePoint> points) {
  if (points.length < 2) return const [];
  final segments = <List<_TracePoint>>[];
  var current = <_TracePoint>[points.first];

  for (var i = 1; i < points.length; i++) {
    final prev = points[i - 1];
    final cur = points[i];
    final dt = cur.time.difference(prev.time).inSeconds.abs();
    final gapM = NearestStopService.haversineDistance(
      prev.lat,
      prev.lon,
      cur.lat,
      cur.lon,
    );
    final routeChanged =
        prev.routeNumber > 0 &&
        cur.routeNumber > 0 &&
        prev.routeNumber != cur.routeNumber;
    final tripChanged =
        prev.tripId.isNotEmpty &&
        cur.tripId.isNotEmpty &&
        prev.tripId != cur.tripId;

    if (dt > 900 || gapM > 1500.0 || routeChanged || tripChanged) {
      if (_segmentIsUsable(current)) {
        segments.add(current);
      }
      current = <_TracePoint>[cur];
      continue;
    }
    current.add(cur);
  }

  if (_segmentIsUsable(current)) {
    segments.add(current);
  }
  return segments;
}

bool _segmentIsUsable(List<_TracePoint> segment) {
  if (segment.length < 4) return false;
  var totalDistance = 0.0;
  for (var i = 1; i < segment.length; i++) {
    totalDistance += NearestStopService.haversineDistance(
      segment[i - 1].lat,
      segment[i - 1].lon,
      segment[i].lat,
      segment[i].lon,
    );
  }
  return totalDistance >= 180.0;
}

List<(double, double)> _toShapePath(List<_TracePoint> segment) {
  if (segment.isEmpty) return const [];
  final simplified = <(double, double)>[(segment.first.lat, segment.first.lon)];
  for (var i = 1; i < segment.length; i++) {
    final last = simplified.last;
    final next = (segment[i].lat, segment[i].lon);
    final gap = NearestStopService.haversineDistance(
      last.$1,
      last.$2,
      next.$1,
      next.$2,
    );
    if (gap >= 20.0) {
      simplified.add(next);
    }
  }
  final finalPoint = (segment.last.lat, segment.last.lon);
  if (simplified.last != finalPoint) {
    simplified.add(finalPoint);
  }
  return simplified;
}

void _collectRenderMetrics({
  required DateTime now,
  required BusMotionEngine engine,
  required GtfsRepository repo,
  required _ReplayMetrics metrics,
  BusJourneyTracer? tracer,
}) {
  final rendered = engine.interpolate(now);
  tracer?.recordFrame(now: now, engine: engine, rendered: rendered);
  final renderedKeys = rendered.keys.toSet();

  for (final entry in rendered.entries) {
    final key = entry.key;
    final state = engine.states[key];
    if (state == null) continue;

    final renderedLat = entry.value.$1;
    final renderedLon = entry.value.$2;
    final shapeId = state.shapeId;
    final shapePoints = shapeId == null ? null : repo.shapesById[shapeId];
    final shapeDists = shapeId == null
        ? null
        : repo.shapeCumulativeDistances[shapeId];

    double? renderedProgress = engine.debugRenderedProgressByKey[key];
    if (shapePoints != null &&
        shapeDists != null &&
        shapePoints.length >= 2 &&
        shapeDists.length >= 2) {
      final snapped = _snapProgressWithContinuity(
        lat: renderedLat,
        lon: renderedLon,
        points: shapePoints,
        cumulativeDistances: shapeDists,
        previousProgressM: metrics.previousProgressByKey[key],
      );
      if (snapped != null) {
        metrics.snappedSamples++;
        metrics.offShapeErrorsM.add(snapped.perpendicularDistanceMeters);
        renderedProgress ??= snapped.progressM;
      }
    }

    if (renderedProgress == null) {
      metrics.previousProgressByKey.remove(key);
      metrics.previousRenderByKey.remove(key);
      continue;
    }
    metrics.renderedProgressSamples++;

    final previousProgress = metrics.previousProgressByKey[key];
    if (previousProgress != null &&
        state.status == BusStatus.active &&
        !_hasRecentTripTransition(state) &&
        renderedProgress + 1e-3 < previousProgress) {
      metrics.activeBackstepCount++;
      metrics.activeBackstepMeters += (previousProgress - renderedProgress);
    }
    metrics.previousProgressByKey[key] = renderedProgress;

    final previousRender = metrics.previousRenderByKey[key];
    if (previousRender != null) {
      final dt = now.difference(previousRender.time).inMilliseconds / 1000.0;
      if (dt > 0.0) {
        final displaySpeedKmh =
            ((renderedProgress - previousRender.progressM).abs() / dt) * 3.6;
        final lastGood = state.observations.lastWhere(
          (o) => !o.rejected,
          orElse: () => state.observations.last,
        );
        final measurementAgeSeconds =
            now.difference(lastGood.measurementTime).inMilliseconds / 1000.0;
        if (measurementAgeSeconds >= 0 && measurementAgeSeconds <= 25.0) {
          metrics.speedErrorsKmh.add(
            (displaySpeedKmh - lastGood.speed.abs()).abs(),
          );
          final apiSpeedKmh = lastGood.speed.abs();
          if (apiSpeedKmh >= 2.0) {
            final ratio = displaySpeedKmh / apiSpeedKmh;
            if (ratio.isFinite && ratio >= 0.0) {
              metrics.speedFidelityRatios.add(ratio.clamp(0.0, 8.0));
            }
          }
        }
      }
    }
    metrics.previousRenderByKey[key] = _RenderProgressSample(
      time: now,
      progressM: renderedProgress,
    );
  }

  metrics.previousProgressByKey.removeWhere(
    (key, _) => !renderedKeys.contains(key),
  );
  metrics.previousRenderByKey.removeWhere(
    (key, _) => !renderedKeys.contains(key),
  );
}

String? _traceKey(TimeTrackVehicle vehicle) {
  if (vehicle.routeRun.trim().isNotEmpty) {
    return 'routerun:${vehicle.routeRun.trim()}';
  }
  if (vehicle.vehicle.trim().isNotEmpty) {
    return 'vehicle:${vehicle.vehicle.trim()}';
  }
  if (vehicle.gtfsTripId.trim().isNotEmpty) {
    return 'trip:${vehicle.gtfsTripId.trim()}';
  }
  return null;
}

String? _bestShapeForRoute({
  required GtfsRepository repo,
  required String routeShortName,
  required String headsign,
  required String serviceId,
}) {
  final candidates = repo.tripsByRouteShortName[routeShortName];
  if (candidates == null || candidates.isEmpty) return null;

  final byHeadsign = headsign.isEmpty
      ? const <TripShapeEntry>[]
      : candidates
            .where((c) => c.headsign.toLowerCase() == headsign.toLowerCase())
            .toList();
  if (byHeadsign.isNotEmpty) {
    final byService = serviceId.isEmpty
        ? const <TripShapeEntry>[]
        : byHeadsign.where((c) => c.serviceId == serviceId).toList();
    if (byService.isNotEmpty) return byService.first.shapeId;
    return byHeadsign.first.shapeId;
  }

  if (serviceId.isNotEmpty) {
    final byService = candidates
        .where((c) => c.serviceId == serviceId)
        .toList();
    if (byService.isNotEmpty) return byService.first.shapeId;
  }

  return candidates.first.shapeId;
}

bool _hasRecentTripTransition(BusTrackingState state) {
  final good = state.observations.where((o) => !o.rejected).toList();
  if (good.length < 2) return false;
  final last = good[good.length - 1].gtfsTripId;
  final prev = good[good.length - 2].gtfsTripId;
  return last != prev && (last != null || prev != null);
}

String _uniqueTripId({
  required String? preferred,
  required String fallbackPrefix,
  required int currentIndex,
  required Map<String, TripInfo> existing,
}) {
  final base = (preferred != null && preferred.isNotEmpty)
      ? preferred
      : '$fallbackPrefix$currentIndex';
  if (!existing.containsKey(base)) return base;
  var suffix = 1;
  while (existing.containsKey('${base}_$suffix')) {
    suffix++;
  }
  return '${base}_$suffix';
}

int _safeInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _mostFrequentInt(Iterable<int> values) {
  final counts = <int, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  int? bestValue;
  var bestCount = -1;
  for (final entry in counts.entries) {
    if (entry.value > bestCount) {
      bestValue = entry.key;
      bestCount = entry.value;
    }
  }
  return bestValue;
}

String? _mostFrequentString(Iterable<String> values) {
  final counts = <String, int>{};
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    counts[value] = (counts[value] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  String? bestValue;
  var bestCount = -1;
  for (final entry in counts.entries) {
    if (entry.value > bestCount) {
      bestValue = entry.key;
      bestCount = entry.value;
    }
  }
  return bestValue;
}

bool _isValidCoord(double lat, double lon) {
  if (!lat.isFinite || !lon.isFinite) return false;
  if (lat.abs() < 1e-9 && lon.abs() < 1e-9) return false;
  return lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0;
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

double _percentile(List<double> values, double q) {
  if (values.isEmpty) return 0.0;
  final sorted = List<double>.from(values)..sort();
  final idx = ((sorted.length - 1) * q).round().clamp(0, sorted.length - 1);
  return sorted[idx];
}

class _SnapProgress {
  final double progressM;
  final double perpendicularDistanceMeters;

  const _SnapProgress({
    required this.progressM,
    required this.perpendicularDistanceMeters,
  });
}

_SnapProgress? _snapProgressWithContinuity({
  required double lat,
  required double lon,
  required List<ShapePoint> points,
  required List<double> cumulativeDistances,
  required double? previousProgressM,
}) {
  if (points.length < 2 || cumulativeDistances.length < 2) return null;

  var bestScore = double.infinity;
  var bestProgress = 0.0;
  var bestPerpDistance = double.infinity;

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
    final perp = NearestStopService.haversineDistance(
      lat,
      lon,
      proj.$1,
      proj.$2,
    );
    final segLen = cumulativeDistances[i + 1] - cumulativeDistances[i];
    final progress = cumulativeDistances[i] + segLen * proj.$3;
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
  print('[Replay] wrote metrics JSON to ${file.path}');
}
