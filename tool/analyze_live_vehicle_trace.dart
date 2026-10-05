import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:busboard_nl/data/realtime/timetrack_models.dart';

void main(List<String> args) {
  final path = args.isEmpty
      ? 'test/fixtures/timetrack/capture.json'
      : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('[Identity] capture not found: $path');
    exitCode = 2;
    return;
  }

  final frames = _loadFrames(file);
  if (frames.length < 2) {
    stderr.writeln('[Identity] at least two valid frames are required');
    exitCode = 2;
    return;
  }

  final metrics = _analyze(frames);
  stdout.writeln(
    '[Identity] file=$path frames=${frames.length} '
    'duration=${metrics.duration.inSeconds}s '
    'successful=${metrics.successfulFrames}/${frames.length} '
    'rows=${metrics.totalRows} distinctVehicles=${metrics.distinctVehicles}',
  );
  stdout.writeln(
    '[Identity] missingVehicleIds=${metrics.missingVehicleIds} '
    'duplicateAssignmentRows=${metrics.duplicateAssignmentRows} '
    'duplicateAssignmentFrames=${metrics.duplicateAssignmentFrames} '
    'tripOwnerTransfers=${metrics.tripOwnerTransfers} '
    'blockOwnerTransfers=${metrics.blockOwnerTransfers}',
  );
  stdout.writeln(
    '[Motion] distinctGpsUpdates=${metrics.distinctGpsUpdates} '
    'rawTeleportsOver140kmh=${metrics.rawTeleports.length} '
    'rawPingPongs=${metrics.rawPingPongs.length} '
    'gpsCadenceP50=${_formatSeconds(metrics.gpsCadenceP50Seconds)} '
    'gpsCadenceP90=${_formatSeconds(metrics.gpsCadenceP90Seconds)}',
  );

  for (final detail in metrics.duplicateDetails.take(12)) {
    stdout.writeln('[Duplicate] $detail');
  }
  for (final detail in metrics.rawTeleports.take(12)) {
    stdout.writeln('[Teleport] $detail');
  }
  for (final detail in metrics.rawPingPongs.take(12)) {
    stdout.writeln('[PingPong] $detail');
  }
  if (metrics.duplicateDetails.length > 12 ||
      metrics.rawTeleports.length > 12 ||
      metrics.rawPingPongs.length > 12) {
    stdout.writeln('[Identity] detail output truncated to 12 per category');
  }

  final rawFeedStable =
      metrics.rawTeleports.isEmpty && metrics.rawPingPongs.isEmpty;
  stdout.writeln(
    '[Verdict] rawIdentity=${metrics.missingVehicleIds == 0 ? "stable" : "incomplete"} '
    'rawMotion=${rawFeedStable ? "stable" : "anomalies-found"}; '
    'build a replay fixture from this capture (tool/build_replay_fixture.py) '
    'and run test/map/motion_replay_test.dart to verify the app-rendered path.',
  );
}

class _Frame {
  final DateTime fetchTime;
  final int statusCode;
  final List<TimeTrackVehicle> vehicles;

  const _Frame({
    required this.fetchTime,
    required this.statusCode,
    required this.vehicles,
  });
}

class _Point {
  final DateTime fetchTime;
  final DateTime? measurementTime;
  final double lat;
  final double lon;
  final String tripId;
  final int routeNumber;

  const _Point({
    required this.fetchTime,
    required this.measurementTime,
    required this.lat,
    required this.lon,
    required this.tripId,
    required this.routeNumber,
  });

  DateTime get effectiveTime => measurementTime ?? fetchTime;
}

class _Metrics {
  final Duration duration;
  final int successfulFrames;
  final int totalRows;
  final int distinctVehicles;
  final int missingVehicleIds;
  final int duplicateAssignmentRows;
  final int duplicateAssignmentFrames;
  final int tripOwnerTransfers;
  final int blockOwnerTransfers;
  final int distinctGpsUpdates;
  final double? gpsCadenceP50Seconds;
  final double? gpsCadenceP90Seconds;
  final List<String> duplicateDetails;
  final List<String> rawTeleports;
  final List<String> rawPingPongs;

  const _Metrics({
    required this.duration,
    required this.successfulFrames,
    required this.totalRows,
    required this.distinctVehicles,
    required this.missingVehicleIds,
    required this.duplicateAssignmentRows,
    required this.duplicateAssignmentFrames,
    required this.tripOwnerTransfers,
    required this.blockOwnerTransfers,
    required this.distinctGpsUpdates,
    required this.gpsCadenceP50Seconds,
    required this.gpsCadenceP90Seconds,
    required this.duplicateDetails,
    required this.rawTeleports,
    required this.rawPingPongs,
  });
}

List<_Frame> _loadFrames(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) return const [];
  final rawFrames = decoded['frames'];
  if (rawFrames is! List) return const [];

  final frames = <_Frame>[];
  for (final raw in rawFrames.whereType<Map>()) {
    final frame = Map<String, dynamic>.from(raw);
    final fetchTime = DateTime.tryParse(frame['fetch_time']?.toString() ?? '');
    final vehicles = frame['vehicles'];
    if (fetchTime == null || vehicles is! List) continue;
    frames.add(
      _Frame(
        fetchTime: fetchTime.toUtc(),
        statusCode: _readInt(frame['status_code']),
        vehicles: vehicles
            .whereType<Map>()
            .map(
              (vehicle) =>
                  TimeTrackVehicle.fromJson(Map<String, dynamic>.from(vehicle)),
            )
            .where(
              (vehicle) =>
                  vehicle.busLat.abs() <= 90 &&
                  vehicle.busLon.abs() <= 180 &&
                  (vehicle.busLat != 0 || vehicle.busLon != 0),
            )
            .toList(),
      ),
    );
  }
  frames.sort((a, b) => a.fetchTime.compareTo(b.fetchTime));
  return frames;
}

_Metrics _analyze(List<_Frame> frames) {
  final allVehicleIds = <String>{};
  final pointsByVehicle = <String, List<_Point>>{};
  final previousTripOwner = <String, String>{};
  final previousBlockOwner = <String, String>{};
  final duplicateDetails = <String>[];
  var successfulFrames = 0;
  var totalRows = 0;
  var missingVehicleIds = 0;
  var duplicateAssignmentRows = 0;
  var duplicateAssignmentFrames = 0;
  var tripOwnerTransfers = 0;
  var blockOwnerTransfers = 0;

  for (final frame in frames) {
    if (frame.statusCode == 200) successfulFrames++;
    totalRows += frame.vehicles.length;
    final assignments = <String, List<TimeTrackVehicle>>{};
    final tripOwnerThisFrame = <String, String>{};
    final blockOwnerThisFrame = <String, String>{};

    for (final vehicle in frame.vehicles) {
      final vehicleId = vehicle.vehicle.trim();
      if (vehicleId.isEmpty) {
        missingVehicleIds++;
        continue;
      }
      allVehicleIds.add(vehicleId);
      assignments.putIfAbsent(vehicleId, () => []).add(vehicle);

      final tripId = vehicle.gtfsTripId.trim();
      if (tripId.isNotEmpty) tripOwnerThisFrame[tripId] = vehicleId;
      final block = vehicle.routeRun.trim();
      if (block.isNotEmpty) blockOwnerThisFrame[block] = vehicleId;

      final point = _Point(
        fetchTime: frame.fetchTime,
        measurementTime:
            DateTime.tryParse(vehicle.positionTime) ??
            DateTime.tryParse(vehicle.timeStamp),
        lat: vehicle.busLat,
        lon: vehicle.busLon,
        tripId: tripId,
        routeNumber: vehicle.routeNumber,
      );
      final trace = pointsByVehicle.putIfAbsent(vehicleId, () => []);
      if (trace.isEmpty || !_sameObservation(trace.last, point)) {
        trace.add(point);
      }
    }

    final duplicates = assignments.entries
        .where((entry) => entry.value.length > 1)
        .toList();
    if (duplicates.isNotEmpty) duplicateAssignmentFrames++;
    for (final duplicate in duplicates) {
      duplicateAssignmentRows += duplicate.value.length - 1;
      final variants = duplicate.value
          .map(
            (vehicle) =>
                'route=${vehicle.routeNumber} block=${vehicle.routeRun} '
                'trip=${vehicle.gtfsTripId}',
          )
          .join(' | ');
      duplicateDetails.add(
        '${frame.fetchTime.toIso8601String()} vehicle=${duplicate.key}: '
        '$variants',
      );
    }

    for (final entry in tripOwnerThisFrame.entries) {
      final previous = previousTripOwner[entry.key];
      if (previous != null && previous != entry.value) tripOwnerTransfers++;
    }
    for (final entry in blockOwnerThisFrame.entries) {
      final previous = previousBlockOwner[entry.key];
      if (previous != null && previous != entry.value) blockOwnerTransfers++;
    }
    previousTripOwner
      ..clear()
      ..addAll(tripOwnerThisFrame);
    previousBlockOwner
      ..clear()
      ..addAll(blockOwnerThisFrame);
  }

  final cadences = <double>[];
  final teleports = <String>[];
  final pingPongs = <String>[];
  var distinctGpsUpdates = 0;

  for (final entry in pointsByVehicle.entries) {
    final points = entry.value;
    distinctGpsUpdates += points.length;
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final dt =
          current.effectiveTime
              .difference(previous.effectiveTime)
              .inMilliseconds /
          1000.0;
      if (dt <= 0) continue;
      cadences.add(dt);
      final distance = _distanceMeters(
        previous.lat,
        previous.lon,
        current.lat,
        current.lon,
      );
      final speedKmh = distance / dt * 3.6;
      if (speedKmh > 140) {
        teleports.add(
          'vehicle=${entry.key} at=${current.fetchTime.toIso8601String()} '
          'distance=${distance.toStringAsFixed(0)}m '
          'dt=${dt.toStringAsFixed(1)}s speed=${speedKmh.toStringAsFixed(0)}km/h '
          'route=${previous.routeNumber}->${current.routeNumber} '
          'trip=${previous.tripId}->${current.tripId}',
        );
      }
    }

    for (var i = 2; i < points.length; i++) {
      final a = points[i - 2];
      final b = points[i - 1];
      final c = points[i];
      final ab = _distanceMeters(a.lat, a.lon, b.lat, b.lon);
      final bc = _distanceMeters(b.lat, b.lon, c.lat, c.lon);
      final ac = _distanceMeters(a.lat, a.lon, c.lat, c.lon);
      final sameTrip =
          a.tripId.isEmpty ||
          b.tripId.isEmpty ||
          c.tripId.isEmpty ||
          (a.tripId == b.tripId && b.tripId == c.tripId);
      if (sameTrip && ab >= 75 && bc >= 75 && ac <= 30) {
        pingPongs.add(
          'vehicle=${entry.key} at=${c.fetchTime.toIso8601String()} '
          'out=${ab.toStringAsFixed(0)}m '
          'back=${bc.toStringAsFixed(0)}m '
          'returnError=${ac.toStringAsFixed(0)}m trip=${c.tripId}',
        );
      }
    }
  }

  return _Metrics(
    duration: frames.last.fetchTime.difference(frames.first.fetchTime),
    successfulFrames: successfulFrames,
    totalRows: totalRows,
    distinctVehicles: allVehicleIds.length,
    missingVehicleIds: missingVehicleIds,
    duplicateAssignmentRows: duplicateAssignmentRows,
    duplicateAssignmentFrames: duplicateAssignmentFrames,
    tripOwnerTransfers: tripOwnerTransfers,
    blockOwnerTransfers: blockOwnerTransfers,
    distinctGpsUpdates: distinctGpsUpdates,
    gpsCadenceP50Seconds: _percentile(cadences, 0.50),
    gpsCadenceP90Seconds: _percentile(cadences, 0.90),
    duplicateDetails: duplicateDetails,
    rawTeleports: teleports,
    rawPingPongs: pingPongs,
  );
}

bool _sameObservation(_Point a, _Point b) {
  if (a.measurementTime != null && b.measurementTime != null) {
    return a.measurementTime == b.measurementTime &&
        a.lat == b.lat &&
        a.lon == b.lon;
  }
  return a.lat == b.lat && a.lon == b.lon;
}

double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusM = 6371000.0;
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dPhi = (lat2 - lat1) * math.pi / 180;
  final dLambda = (lon2 - lon1) * math.pi / 180;
  final a =
      math.sin(dPhi / 2) * math.sin(dPhi / 2) +
      math.cos(phi1) *
          math.cos(phi2) *
          math.sin(dLambda / 2) *
          math.sin(dLambda / 2);
  return earthRadiusM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double? _percentile(List<double> values, double q) {
  if (values.isEmpty) return null;
  final sorted = List<double>.from(values)..sort();
  final index = ((sorted.length - 1) * q).round().clamp(0, sorted.length - 1);
  return sorted[index];
}

String _formatSeconds(double? value) =>
    value == null ? 'n/a' : '${value.toStringAsFixed(1)}s';

int _readInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
