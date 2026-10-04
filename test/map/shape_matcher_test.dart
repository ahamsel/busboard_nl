import 'package:busboard_nl/domain/map/shape_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/out_and_back.dart';

void main() {
  final points = outAndBackPoints();
  final cumulative = cumulativeFor(points);
  final total = cumulative.last;
  final fixLon = lonAt(400);

  test('the global snap is ambiguous on a shared road', () {
    final global = ShapeMatcher.snapToShape(
      lat: nearReturnCurb, lon: fixLon, points: points, cumulativeDistances: cumulative)!;
    expect(global.distanceAlongRoute, closeTo(total - 400, 15));
  });

  test('prefers the pass nearest the expected progress', () {
    final near = ShapeMatcher.snapNear(
      lat: nearReturnCurb, lon: fixLon, points: points, cumulativeDistances: cumulative, expectedAlong: 380)!;
    expect(near.distanceAlongRoute, closeTo(400, 5));
    expect(near.perpendicularDistance, lessThan(10));
  });

  test('follows the bus onto the return leg when that is expected', () {
    final near = ShapeMatcher.snapNear(
      lat: nearOutboundCurb, lon: fixLon, points: points, cumulativeDistances: cumulative, expectedAlong: total - 420)!;
    expect(near.distanceAlongRoute, closeTo(total - 400, 5));
  });

  test('a fix far from the expected place still snaps where it is', () {
    final near = ShapeMatcher.snapNear(
      lat: outboundLat, lon: lonAt(950), points: points, cumulativeDistances: cumulative, expectedAlong: 100)!;
    expect(near.distanceAlongRoute, closeTo(950, 10));
    expect(near.perpendicularDistance, lessThan(5));
  });

  test('a window limits candidates and reports how far off the bus is', () {
    final near = ShapeMatcher.snapNear(
      lat: outboundLat,
      lon: lonAt(900),
      points: points,
      cumulativeDistances: cumulative,
      expectedAlong: 400,
      minAlong: 200,
      maxAlong: 600,
    )!;
    expect(near.distanceAlongRoute, closeTo(600, 5));
    expect(near.perpendicularDistance, greaterThan(250));
  });

  test('fewer than two points cannot be snapped to', () {
    expect(
      ShapeMatcher.snapNear(lat: 0, lon: 0, points: [points.first], cumulativeDistances: [0], expectedAlong: 0),
      isNull,
    );
  });
}
