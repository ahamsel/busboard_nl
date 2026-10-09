import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/out_and_back.dart';

void main() {
  late RouteGeometry geometry;
  final total = cumulativeFor(outAndBackPoints()).last;

  setUp(() => geometry = RouteGeometry(outAndBackRepo()));

  test('resolves a trip to its shape', () {
    expect(geometry.shapeIdForTrip(outAndBackTripId), outAndBackShapeId);
    expect(geometry.shapeIdForTrip('nope'), isNull);
    expect(geometry.shapeIdForTrip(null), isNull);
    expect(geometry.hasShape(outAndBackShapeId), isTrue);
    expect(geometry.hasShape('nope'), isFalse);
  });

  test('poseAt walks the shape and faces the direction of travel', () {
    final start = geometry.poseAt(outAndBackShapeId, 0)!;
    expect(start.lat, closeTo(outboundLat, 1e-6));
    expect(start.heading, closeTo(90, 1)); // outbound heads east
    final back = geometry.poseAt(outAndBackShapeId, total - 300)!;
    expect(back.lat, closeTo(returnLat, 1e-6));
    expect(back.heading, closeTo(270, 1)); // return heads west
    final clampedHigh = geometry.poseAt(outAndBackShapeId, total + 500)!;
    final end = geometry.poseAt(outAndBackShapeId, total)!;
    expect(clampedHigh.lon, end.lon);
  });

  test('stops are placed in sequence order, each on its own pass', () {
    final p = geometry.stopProgresses(outAndBackTripId, outAndBackShapeId);
    expect(p, hasLength(4));
    expect(p[0], closeTo(200, 15));
    expect(p[1], closeTo(500, 15));
    expect(p[2], closeTo(800, 15));
    expect(p[3], closeTo(total - 300, 15)); // return leg, not 300
  });

  test('a stop is found by its scheduled departure time', () {
    expect(geometry.stopProgressAtTime(outAndBackTripId, outAndBackShapeId, 12 * 3600 + 60), closeTo(500, 15));
    expect(geometry.stopProgressAtTime(outAndBackTripId, outAndBackShapeId, 9 * 3600), isNull);
  });

  test('scheduled progress interpolates between stops and is null far outside the trip', () {
    // Halfway between s1 (12:00:00, 200 m) and s2 (12:01:00, 500 m).
    expect(geometry.scheduledProgress(outAndBackTripId, outAndBackShapeId, 12 * 3600 + 30), closeTo(350, 15));
    expect(geometry.scheduledProgress(outAndBackTripId, outAndBackShapeId, 11 * 3600), isNull);
  });

  test('scheduled progress handles trips past midnight', () {
    final repo = outAndBackRepo();
    // Re-time the trip to 24:00:00 .. 24:05:00 (00:00 .. 00:05 next day).
    for (final rows in repo.stopTimesByStopId.values) {
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final hh = int.parse(r.departureTime.substring(0, 2)) + 12;
        final time = '$hh${r.departureTime.substring(2)}';
        rows[i] = StopTimeRow(tripId: r.tripId, arrivalTime: time, departureTime: time, stopId: r.stopId, stopSequence: r.stopSequence);
      }
    }
    final g = RouteGeometry(repo);
    // 00:00:30 is 30 s into the trip that starts at "24:00:00".
    expect(g.scheduledProgress(outAndBackTripId, outAndBackShapeId, 30), closeTo(350, 15));
  });

  test('the initial hint uses the named next stop, else the timetable shifted by the delay', () {
    expect(geometry.initialHint(fix(meters: 400, seconds: 43250, departureTimeAtClosestStop: 43260), outAndBackTripId, outAndBackShapeId), closeTo(500, 15));
    // No stop named; 12:00:30 on time → 350 m.
    expect(geometry.initialHint(fix(meters: 400, seconds: 43230), outAndBackTripId, outAndBackShapeId), closeTo(350, 15));
    // One minute behind: the timetable is read one minute earlier (12:00:00 → 200 m).
    expect(geometry.initialHint(fix(meters: 300, seconds: 43260, schedDifferenceMins: -1), outAndBackTripId, outAndBackShapeId), closeTo(200, 15));
    expect(geometry.initialHint(fix(meters: 400, seconds: 43250), null, outAndBackShapeId), isNull);
  });

  test('snap with an expectation falls back to the global snap outside its window', () {
    final s = geometry.snap(outboundLat, lonAt(900), outAndBackShapeId, expectedAlong: 400, minAlong: 200, maxAlong: 600)!;
    expect(s.distanceAlongRoute, closeTo(900, 10));
    expect(geometry.snap(nearReturnCurb, lonAt(400), outAndBackShapeId, expectedAlong: 380)!.distanceAlongRoute, closeTo(400, 5));
  });

  test('a fallback shape is found by route number and headsign', () {
    final repo = outAndBackRepo();
    repo.tripsByRouteShortName['10'] = const [
      TripShapeEntry(tripId: 'x', shapeId: 'other', headsign: 'Elsewhere', directionId: 1, serviceId: 'svc'),
      TripShapeEntry(tripId: outAndBackTripId, shapeId: outAndBackShapeId, headsign: 'Loop', directionId: 0, serviceId: 'svc'),
    ];
    final g = RouteGeometry(repo);
    final v = fix(meters: 100, seconds: 43200, tripId: '');
    expect(g.fallbackShapeId(v), 'other'); // no headsign given: first entry
  });

  group('fix round 1', () {
    void retime(GtfsRepository repo, String Function(String time) f) {
      for (final rows in repo.stopTimesByStopId.values) {
        for (var i = 0; i < rows.length; i++) {
          final r = rows[i];
          final time = f(r.departureTime);
          rows[i] = StopTimeRow(tripId: r.tripId, arrivalTime: time, departureTime: time, stopId: r.stopId, stopSequence: r.stopSequence);
        }
      }
    }

    test('one bad stop does not corrupt the stops after it', () {
      final repo = outAndBackRepo();
      // s2..s4 become sequences 3..5; a stop at the west end (where the
      // shape starts and ends) takes sequence 2.
      for (final rows in repo.stopTimesByStopId.values) {
        for (var i = 0; i < rows.length; i++) {
          final r = rows[i];
          if (r.stopSequence >= 2) {
            rows[i] = StopTimeRow(tripId: r.tripId, arrivalTime: r.arrivalTime, departureTime: r.departureTime, stopId: r.stopId, stopSequence: r.stopSequence + 1);
          }
        }
      }
      repo.stopsById['bad'] = StopInfo(stopId: 'bad', stopName: 'bad', stopLat: 47.560045, stopLon: lonAt(0));
      repo.stopTimesByStopId['bad'] = [
        const StopTimeRow(tripId: outAndBackTripId, arrivalTime: '12:00:30', departureTime: '12:00:30', stopId: 'bad', stopSequence: 2),
      ];
      final g = RouteGeometry(repo);
      final p = g.stopProgresses(outAndBackTripId, outAndBackShapeId);
      expect(p, hasLength(5));
      expect(p[0], closeTo(200, 15));
      expect(p[1] == null || p[1]! < 100, isTrue, reason: 'bad stop was ${p[1]}');
      expect(p[2], closeTo(500, 15));
      expect(p[3], closeTo(800, 15));
      expect(p[4], closeTo(total - 300, 15));
      final nonNull = p.whereType<double>().toList();
      for (var i = 1; i < nonNull.length; i++) {
        expect(nonNull[i], greaterThanOrEqualTo(nonNull[i - 1]));
      }
    });

    test('a stop far from the shape is null, never snapped', () {
      final repo = outAndBackRepo();
      repo.stopsById['s2'] = StopInfo(stopId: 's2', stopName: 's2', stopLat: 47.57, stopLon: lonAt(500));
      final p = RouteGeometry(repo).stopProgresses(outAndBackTripId, outAndBackShapeId);
      expect(p[1], isNull);
      expect(p[2], closeTo(800, 15));
    });

    test('poseAt keeps its heading on a duplicated final shape point', () {
      final repo = outAndBackRepo();
      final points = outAndBackPoints();
      final last = points.last;
      points.add(ShapePoint(shapeId: outAndBackShapeId, lat: last.lat, lon: last.lon, sequence: last.sequence + 1));
      repo.shapesById[outAndBackShapeId] = points;
      repo.shapeCumulativeDistances[outAndBackShapeId] = cumulativeFor(points);
      final g = RouteGeometry(repo);
      final end = g.poseAt(outAndBackShapeId, cumulativeFor(points).last)!;
      expect(end.heading, closeTo(270, 1));
      expect(end.lat, closeTo(returnLat, 1e-6));
    });

    test('a stop is found by the closest departure time, not the first within 30 s', () {
      final repo = outAndBackRepo();
      retime(repo, (t) => t == '12:02:00' ? '12:00:20' : t == '12:01:00' ? '12:00:00' : t);
      final g = RouteGeometry(repo);
      expect(g.stopProgressAtTime(outAndBackTripId, outAndBackShapeId, 12 * 3600 + 20), closeTo(800, 15));
    });

    test('a stop is found by departure time for trips past midnight', () {
      final repo = outAndBackRepo();
      retime(repo, (t) => '${int.parse(t.substring(0, 2)) + 12}${t.substring(2)}');
      final g = RouteGeometry(repo);
      expect(g.stopProgressAtTime(outAndBackTripId, outAndBackShapeId, 60), closeTo(500, 15));
    });
  });

  group('tripStops', () {
    test('lists the trip stops in order with their progress and departure', () {
      final g = RouteGeometry(outAndBackRepo());
      final stops = g.tripStops(outAndBackTripId, outAndBackShapeId);
      expect([for (final s in stops) s.stopId], ['s1', 's2', 's3', 's4']);
      expect(stops.first.progress, closeTo(200, 15));
      expect(stops.first.departureSeconds, 12 * 3600);
      expect(stops.last.progress, greaterThan(stops[2].progress!), reason: 's4 is on the return leg');
      expect(stops.first.name, isNotEmpty);
    });

    test('an unknown trip has no stops', () {
      expect(RouteGeometry(outAndBackRepo()).tripStops('nope', outAndBackShapeId), isEmpty);
    });
  });

  group('splitShape', () {
    test('splits the line at a progress; the split point is shared', () {
      final g = RouteGeometry(outAndBackRepo());
      final split = g.splitShape(outAndBackShapeId, 500)!;
      final pose = g.poseAt(outAndBackShapeId, 500)!;
      expect(split.driven.last[0], closeTo(pose.lon, 1e-9));
      expect(split.driven.last[1], closeTo(pose.lat, 1e-9));
      expect(split.ahead.first, split.driven.last);
      final points = outAndBackRepo().shapesById[outAndBackShapeId]!;
      expect(split.driven.first, [points.first.lon, points.first.lat]);
      expect(split.ahead.last, [points.last.lon, points.last.lat]);
    });

    test('ends of the line still give two points on each side', () {
      final g = RouteGeometry(outAndBackRepo());
      for (final p in [-50.0, 0.0, 1e9]) {
        final split = g.splitShape(outAndBackShapeId, p)!;
        expect(split.driven.length, greaterThanOrEqualTo(2), reason: 'p=$p');
        expect(split.ahead.length, greaterThanOrEqualTo(2), reason: 'p=$p');
      }
      expect(g.splitShape('nope', 10), isNull);
    });
  });

  group('shapeBetween', () {
    test('cuts the line between two progresses, ends on the shape', () {
      final g = RouteGeometry(outAndBackRepo());
      final cut = g.shapeBetween(outAndBackShapeId, 200, 700)!;
      final start = g.poseAt(outAndBackShapeId, 200)!;
      final end = g.poseAt(outAndBackShapeId, 700)!;
      expect(cut.first[0], closeTo(start.lon, 1e-9));
      expect(cut.first[1], closeTo(start.lat, 1e-9));
      expect(cut.last[0], closeTo(end.lon, 1e-9));
      expect(cut.last[1], closeTo(end.lat, 1e-9));
      expect(cut.length, greaterThanOrEqualTo(2));
    });

    test('nothing for an unknown shape or an empty span', () {
      final g = RouteGeometry(outAndBackRepo());
      expect(g.shapeBetween('nope', 0, 10), isNull);
      expect(g.shapeBetween(outAndBackShapeId, 500, 500), isNull);
      expect(g.shapeBetween(outAndBackShapeId, 700, 200), isNull);
    });
  });
}
