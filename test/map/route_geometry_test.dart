import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
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
}
