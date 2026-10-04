import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/map/bus_motion_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// GTFS-Realtime vehicles get their routeRun from Metrobus Fleet View when it
// answers ("Rt 10-1", the block) and from the route ID when it does not
// ("Rt 10"). When Fleet View answers on some polls but not others, the same
// bus on the same trip alternates between the two labels. That must not be
// treated as the bus changing route.

const _shapeId = 'straight';
const _tripId = 'trip-10';
const _lat = 47.5600;
const _west = -52.7600;

double _lonAt(double meters) =>
    _west + meters / (111320 * math.cos(_lat * math.pi / 180));

GtfsRepository _straightRepo() {
  final repo = GtfsRepository();
  repo.routesById['10'] = const RouteInfo(
    routeId: '10',
    routeShortName: '10',
    routeLongName: 'Route 10',
  );
  repo.routesById['6'] = const RouteInfo(
    routeId: '6',
    routeShortName: '6',
    routeLongName: 'Route 6',
  );
  for (final (tripId, routeId) in [(_tripId, '10'), ('trip-6', '6')]) {
    repo.tripsById[tripId] = TripInfo(
      tripId: tripId,
      routeId: routeId,
      serviceId: 'svc',
      tripHeadsign: 'East',
      directionId: 0,
      shapeId: _shapeId,
    );
  }
  final points = [
    for (var i = 0; i <= 20; i++)
      ShapePoint(
        shapeId: _shapeId,
        lat: _lat,
        lon: _lonAt(i * 100.0),
        sequence: i + 1,
      ),
  ];
  repo.shapesById[_shapeId] = points;
  final cumulative = <double>[0];
  for (var i = 1; i < points.length; i++) {
    cumulative.add(
      cumulative.last +
          NearestStopService.haversineDistance(
            points[i - 1].lat,
            points[i - 1].lon,
            points[i].lat,
            points[i].lon,
          ),
    );
  }
  repo.shapeCumulativeDistances[_shapeId] = cumulative;
  return repo;
}

TimeTrackVehicle _fix({
  required String routeRun,
  required double meters,
  required int seconds,
  int routeNumber = 10,
  String tripId = _tripId,
}) {
  return TimeTrackVehicle(
    routeRun: routeRun,
    currentRoute: routeRun.replaceFirst('Rt ', ''),
    routeNumber: routeNumber,
    vehicle: '2573',
    timeStamp: '',
    deviation: '',
    currentLocation: '',
    busLat: _lat,
    busLon: _lonAt(meters),
    heading: '90',
    speed: 29,
    positionTime: '',
    positionTimeSeconds: seconds,
    gtfsTripHeadsign: '',
    gtfsServiceId: '',
    gtfsStopSequenceStatus: 'ON TIME',
    gtfsStopSequenceMinsFromStop: 0,
    gtfsStopSequenceDeviation: '',
    gtfsStopSequenceClosestStop: '',
    gtfsStopSequenceSchedDifferenceMins: 0,
    gtfsTripId: tripId,
    shortStatus: 'OT',
    departureTimeAtClosestStop: 0,
  );
}

void main() {
  test('a flapping routeRun on the same route keeps the bus history', () {
    final engine = BusMotionEngine(_straightRepo());
    final start = DateTime(2026, 10, 4, 12, 0);
    for (var poll = 0; poll < 6; poll++) {
      engine.processBatch([
        _fix(
          routeRun: poll.isEven ? 'Rt 10-1' : 'Rt 10',
          meters: 200.0 + poll * 80,
          seconds: 43200 + poll * 10,
        ),
      ], start.add(Duration(seconds: poll * 10)));
    }
    final state = engine.states['2573']!;
    expect(state.observations, hasLength(6));
    expect(state.progressAlongRoute, closeTo(600, 15));
  });

  test('the drawn bus never moves backward while its routeRun flaps', () {
    final engine = BusMotionEngine(_straightRepo());
    final start = DateTime(2026, 10, 4, 12, 0);
    double? lastDrawn;
    for (var poll = 0; poll < 9; poll++) {
      final pollTime = start.add(Duration(seconds: poll * 10));
      engine.processBatch([
        _fix(
          routeRun: poll % 3 == 0 ? 'Rt 10' : 'Rt 10-1',
          meters: 200.0 + poll * 80,
          seconds: 43200 + poll * 10,
        ),
      ], pollTime);
      for (var ms = 0; ms < 10000; ms += 120) {
        final drawn = engine.interpolate(
          pollTime.add(Duration(milliseconds: ms)),
        )['2573']!;
        final east =
            (drawn.$2 - _west) * 111320 * math.cos(_lat * math.pi / 180);
        if (lastDrawn != null) {
          expect(
            east,
            greaterThanOrEqualTo(lastDrawn - 2),
            reason: 'poll $poll +${ms}ms: drawn at ${east.round()} m',
          );
        }
        lastDrawn = east;
      }
    }
  });

  test('a real route change still starts the bus fresh', () {
    final engine = BusMotionEngine(_straightRepo());
    final start = DateTime(2026, 10, 4, 12, 0);
    engine.processBatch([
      _fix(routeRun: 'Rt 10-1', meters: 200, seconds: 43200),
    ], start);
    engine.processBatch([
      _fix(routeRun: 'Rt 10-1', meters: 280, seconds: 43210),
    ], start.add(const Duration(seconds: 10)));
    engine.processBatch([
      _fix(
        routeRun: 'Rt 6-1',
        routeNumber: 6,
        tripId: 'trip-6',
        meters: 290,
        seconds: 43220,
      ),
    ], start.add(const Duration(seconds: 20)));
    final state = engine.states['2573']!;
    expect(state.routeNumber, 6);
    expect(state.routeRun, 'Rt 6-1');
    expect(state.observations, hasLength(1));
  });

  test('live capture 2026-10-04: no backward jumps when Fleet View answers '
      'intermittently', () async {
    const dir = 'test/fixtures/timetrack/route_run_flap_2026-10-04';
    final repo = GtfsRepository();
    await repo.loadFromDirectory('$dir/gtfs');
    final engine = BusMotionEngine(repo);
    final json =
        jsonDecode(File('$dir/capture.json').readAsStringSync())
            as Map<String, dynamic>;
    final frames = [
      for (final f in (json['frames'] as List).cast<Map<String, dynamic>>())
        if (f['status_code'] == 200) f,
    ];
    expect(frames.length, greaterThan(200));

    var checkedBuses = <String>{};
    final backward = <String>[];
    for (var i = 0; i < frames.length; i++) {
      final pollTime = DateTime.parse(frames[i]['fetch_time'] as String);
      // Fleet View answers on two polls out of three.
      final fleetViewAnswered = i % 3 != 0;
      final vehicles = [
        for (final v
            in (frames[i]['vehicles'] as List).cast<Map<String, dynamic>>())
          TimeTrackVehicle.fromJson({
            ...v,
            if (fleetViewAnswered) 'routeRun': 'Rt ${v['routeNumber']}-1',
          }),
      ];
      final drawnBefore = Map.of(engine.debugRenderedProgressByKey);
      final tripBefore = {
        for (final e in engine.states.entries) e.key: e.value.currentTripId,
      };
      engine.processBatch(vehicles, pollTime);
      engine.interpolate(pollTime.add(const Duration(milliseconds: 120)));
      for (final e in engine.debugRenderedProgressByKey.entries) {
        final before = drawnBefore[e.key];
        if (before == null ||
            tripBefore[e.key] != engine.states[e.key]?.currentTripId) {
          continue;
        }
        checkedBuses.add(e.key);
        if (before - e.value > 30) {
          backward.add(
            'bus ${e.key} poll $i: ${before.round()} -> ${e.value.round()} m',
          );
        }
      }
    }
    expect(checkedBuses, containsAll(['2443', '2444', '2573', '1311']));
    expect(backward, isEmpty, reason: backward.take(5).join('\n'));
  });
}
