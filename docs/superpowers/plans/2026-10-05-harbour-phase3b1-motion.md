# Harbour Phase 3b-1 — Motion Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `BusMotionEngine` (1,800 lines of live extrapolation) with a small pure-Dart pipeline. Map buses are drawn about one GPS update behind live and glide along their route between two real fixes, so they never freeze, lurch or go backward. The existing map screen switches to it unchanged otherwise.

**Architecture:** Three pure-Dart units in `lib/domain/map/`, with no Flutter imports and time passed in:
1. `RouteGeometry`: shape snapping with an expected position (`ShapeMatcher.snapNear`), points along a shape, stop positions in trip order, and the timetable position.
2. `BusTrackStore`: one track of GPS fixes per physical vehicle, with identity and reset rules.
3. `DelayedTrackRenderer`: draws each track at `now − D` by interpolating along the shape between fixes, never backward on the same trip.

Riverpod providers wire them to the existing poll loop. The map screen and bus sheet read `BusTrackingState` snapshots as before.

**Tech Stack:** Flutter 3.47.6 / Dart 3.13, Riverpod 3, flutter_test. GTFS data comes via `GtfsRepository`; live vehicles via `TimeTrackApi` (`TimeTrackVehicle`).

**Spec:** [docs/superpowers/specs/2026-10-04-harbour-phase3-design.md](../specs/2026-10-04-harbour-phase3-design.md) §3.4 (motion) and §1 (success criteria). Phase 3b is split into 3b-1 (this plan: motion, behind the current map) and 3b-2 (style, layers, cards, follow mode), per spec §5's ordering. Handoff notes: [Phase 3a ledger](../notes/2026-10-04-harbour-phase3a-ledger.md).

## Global Constraints

**Motion rules (spec §3.4)**
- `lib/domain/map/` stays pure Dart. Import `dart:*`, `package:collection`, and the app's `data/` and `domain/` libraries only. Never import `package:flutter/*`.
- Identity: one track per physical **vehicle ID**. A route-number change starts a new track. A trip change continues the same track. Duplicate or out-of-order GPS timestamps are ignored.
- Snapping is progress-hinted:
  - known bus: previous progress + speed × time;
  - new bus or trip change: the trip's next stop, else the timetable position shifted by the reported delay.
  - Stops are placed along the shape in sequence order.
- Render time = `now − D`. D = second-largest recent (next fetch − GPS time) lag + 1 s, clamped to 8–30 s; one fix: age + 15 s; slewed ≤ 0.1 s/s. *(Amended in Task 5 — was median interval + 2 s, 8–20 s.)* Drawn motion is limited to ≤ 30 m/s.
- Never draw a bus backward along the same trip. When GPS runs backward, the bus holds.
- Trip change: geographic interpolation across the terminal.
- Off-route (perpendicular distance over 150 m): straight-line interpolation of the raw GPS.
- Next fix late: extrapolate at the last segment's speed for at most 5 s, then hold.
- Stale: no new fix for over 90 s. Drop the track after 5 min without a new fix.

**Unchanged in this plan**
- Arrival countdowns on the Board are not touched. They come from predictions, not from this engine.
- The map UI is not redesigned here; that's 3b-2. `map_screen.dart` and `bus_bottom_sheet.dart` change only where they read the engine.

**Testing**
- Use `isSemantics` for semantics assertions.
- Call `tester.ensureSemantics()` and finish with `handle.dispose()` at the end of the test body.
- Pure-Dart tests use `test()`, not `testWidgets()`.

**Before every commit**
- `flutter analyze lib test` prints "No issues found!".
- The full `flutter test` passes.

**Commits**
- Stage only the files your task lists.
- Never stage `analysis_options.yaml` or `tool/capture_raw_gtfsrt.dart`.
- End every commit with your own model's Co-Authored-By trailer.

**Behaviour changes this plan introduces** (reviewers: intended)
1. Buses on the map are drawn about 8–30 s (typically ~25 s, since fixes arrive ~10 s old every ~16 s) behind real time, and glide between fixes instead of freezing and catching up. *(Amended in Task 5 — was ~12 s.)*
2. `BusStatus` loses `stopped` and `backtracking`. A bus is `active`, `offRoute` or `stale`.
3. The bus sheet's speed comes from the latest fix (`BusTrackingState.speedKmh`) instead of `observations.last`.
4. For GTFS-Realtime vehicles, `gtfsStopSequenceMinsFromStop` is 0. It used to be filled with the absolute delay, which only the deleted engine read.

## Review Focus

1. **Out-and-back route** where a fix sits nearer the opposite pass: the bus must stay on its own pass. (Task 3: "a bus on the outbound leg stays on its pass when GPS sits nearer the return leg".)
2. **GPS running backward within a trip** (detour or GPS drift): the drawn bus must hold, not slide back. (Task 4: "GPS that runs backward holds the bus instead of sliding it back".)
3. **The feed repeating one GPS timestamp for a minute or more** at a terminal or layover: no motion, not marked stale before 90 s, and no extrapolation runaway. (Task 4: "a repeated GPS timestamp holds the bus after at most 5 s of extrapolation".)
4. **A brand-new bus whose very first fix is on the shared stretch of an out-and-back:** the stop or timetable hint picks the right pass. (Task 3: "the first fix uses the next stop, else the timetable, to pick the pass".)
5. **Midnight-crossing trips** (times above 24:00:00) and GPS clock times near midnight: no 24-hour jump in D or in interpolation. (Task 2: "scheduled progress handles trips past midnight"; Task 3: "a fix just after midnight follows one just before it".)

---

### Task 1: `ShapeMatcher.snapNear`, plus shared out-and-back test fixtures

**Files:**
- Modify: `lib/domain/map/shape_matcher.dart` (add `snapNear` and two constants)
- Create: `test/map/support/out_and_back.dart` (shared synthetic route for Tasks 1–4)
- Create: `test/map/shape_matcher_test.dart`

**Interfaces:**
- Produces:
  - `static SnapResult? ShapeMatcher.snapNear({required double lat, required double lon, required List<ShapePoint> points, required List<double> cumulativeDistances, required double expectedAlong, double? minAlong, double? maxAlong})`
  - `static const double ShapeMatcher.ambiguityToleranceMeters = 25.0`
- Produces, in `test/map/support/out_and_back.dart`:
  - `const outAndBackShapeId = 'out-and-back'`
  - `const outAndBackTripId = 'trip-out-and-back'`
  - `const outboundLat = 47.5600`, `const returnLat = 47.56007`
  - `const nearReturnCurb = 47.560052`, `const nearOutboundCurb = 47.560012`
  - `double lonAt(double meters)`
  - `List<ShapePoint> outAndBackPoints()`
  - `List<double> cumulativeFor(List<ShapePoint> points)`
  - `GtfsRepository outAndBackRepo()`
  - `TimeTrackVehicle fix({required double meters, required int seconds, double lat = nearReturnCurb, String vehicle = '2573', int routeNumber = 10, String routeRun = 'Rt 10', String tripId = outAndBackTripId, int departureTimeAtClosestStop = 0, int schedDifferenceMins = 0, double speed = 29})`

- [ ] **Step 1: Create the shared fixtures**

Create `test/map/support/out_and_back.dart`:

```dart
import 'dart:math' as math;

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';

// An out-and-back shape: ~1 km east along one curb, then ~1 km back west
// along the other curb 8 m north. Both legs share one road, so a GPS fix on
// the outbound leg can be nearer the return leg (the real failure on Metrobus
// routes 10, 14, 21 and others).
const outAndBackShapeId = 'out-and-back';
const outAndBackTripId = 'trip-out-and-back';
const outboundLat = 47.5600;
const returnLat = 47.56007; // ~8 m north
const _west = -52.7600;
const _east = -52.7465; // ~1 km east at this latitude

/// Between the curbs, 2.4 m from the return leg and 5.8 m from the outbound.
const nearReturnCurb = 47.560052;

/// 1.3 m from the outbound leg.
const nearOutboundCurb = 47.560012;

/// Longitude [meters] east of the shape's west end.
double lonAt(double meters) =>
    _west + meters / (111320 * math.cos(outboundLat * math.pi / 180));

List<ShapePoint> outAndBackPoints() {
  final points = <ShapePoint>[];
  var seq = 1;
  for (var i = 0; i <= 10; i++) {
    points.add(ShapePoint(
      shapeId: outAndBackShapeId,
      lat: outboundLat,
      lon: _west + (_east - _west) * i / 10,
      sequence: seq++,
    ));
  }
  for (var i = 10; i >= 0; i--) {
    points.add(ShapePoint(
      shapeId: outAndBackShapeId,
      lat: returnLat,
      lon: _west + (_east - _west) * i / 10,
      sequence: seq++,
    ));
  }
  return points;
}

List<double> cumulativeFor(List<ShapePoint> points) {
  final result = <double>[0];
  for (var i = 1; i < points.length; i++) {
    result.add(result.last +
        NearestStopService.haversineDistance(
          points[i - 1].lat,
          points[i - 1].lon,
          points[i].lat,
          points[i].lon,
        ));
  }
  return result;
}

/// Route 10 on the out-and-back shape. Stops sit between the curbs, nearer
/// the return leg, so a global snap would put outbound stops on the way back:
/// s1 200 m (12:00), s2 500 m (12:01), s3 800 m (12:02) outbound, s4 300 m
/// from the west end on the return leg (12:05).
GtfsRepository outAndBackRepo() {
  final repo = GtfsRepository();
  repo.routesById['r10'] = const RouteInfo(
    routeId: 'r10',
    routeShortName: '10',
    routeLongName: 'Out and back',
  );
  repo.tripsById[outAndBackTripId] = const TripInfo(
    tripId: outAndBackTripId,
    routeId: 'r10',
    serviceId: 'svc',
    tripHeadsign: 'Loop',
    directionId: 0,
    shapeId: outAndBackShapeId,
  );
  final points = outAndBackPoints();
  repo.shapesById[outAndBackShapeId] = points;
  repo.shapeCumulativeDistances[outAndBackShapeId] = cumulativeFor(points);
  final stops = [
    ('s1', 200.0, '12:00:00'),
    ('s2', 500.0, '12:01:00'),
    ('s3', 800.0, '12:02:00'),
    ('s4', 300.0, '12:05:00'),
  ];
  for (var i = 0; i < stops.length; i++) {
    final (id, meters, time) = stops[i];
    repo.stopsById[id] = StopInfo(stopId: id, stopName: id, stopLat: 47.560045, stopLon: lonAt(meters));
    repo.stopTimesByStopId.putIfAbsent(id, () => []).add(StopTimeRow(
          tripId: outAndBackTripId,
          arrivalTime: time,
          departureTime: time,
          stopId: id,
          stopSequence: i + 1,
        ));
  }
  return repo;
}

TimeTrackVehicle fix({
  required double meters,
  required int seconds,
  double lat = nearReturnCurb,
  String vehicle = '2573',
  int routeNumber = 10,
  String routeRun = 'Rt 10',
  String tripId = outAndBackTripId,
  int departureTimeAtClosestStop = 0,
  int schedDifferenceMins = 0,
  double speed = 29,
}) {
  return TimeTrackVehicle(
    routeRun: routeRun,
    currentRoute: routeRun.replaceFirst('Rt ', ''),
    routeNumber: routeNumber,
    vehicle: vehicle,
    timeStamp: '',
    deviation: '',
    currentLocation: '',
    busLat: lat,
    busLon: lonAt(meters),
    heading: '90',
    speed: speed,
    positionTime: '',
    positionTimeSeconds: seconds,
    gtfsTripHeadsign: '',
    gtfsServiceId: '',
    gtfsStopSequenceStatus: 'ON TIME',
    gtfsStopSequenceMinsFromStop: 0,
    gtfsStopSequenceDeviation: '',
    gtfsStopSequenceClosestStop: '',
    gtfsStopSequenceSchedDifferenceMins: schedDifferenceMins,
    gtfsTripId: tripId,
    shortStatus: 'OT',
    departureTimeAtClosestStop: departureTimeAtClosestStop,
  );
}
```

- [ ] **Step 2: Write the failing tests**

Create `test/map/shape_matcher_test.dart`:

```dart
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
```

- [ ] **Step 3: Run the tests and watch them fail**

Run: `flutter test test/map/shape_matcher_test.dart`
Expected: compile error, "The method 'snapNear' isn't defined for the type 'ShapeMatcher'".

- [ ] **Step 4: Add `snapNear`**

In `lib/domain/map/shape_matcher.dart`, add these members to `ShapeMatcher`, above `_projectToSegment`:

```dart
  /// Perpendicular slack within which two passes count as equally close.
  static const ambiguityToleranceMeters = 25.0;

  /// Perpendicular meters charged per meter of distance from the expected
  /// progress when choosing among equally close passes.
  static const _expectationWeight = 0.05;

  /// Snap a GPS point to a shape, preferring the pass nearest [expectedAlong].
  ///
  /// Routes often use one road twice (out and back, loops), so the globally
  /// nearest point can belong to a pass kilometres away along the shape.
  /// Candidates within [ambiguityToleranceMeters] of the best perpendicular
  /// distance are equally plausible; among those the one closest to
  /// [expectedAlong] wins. A clearly nearer pass still wins outright.
  ///
  /// [minAlong]/[maxAlong] optionally restrict candidates to a window of
  /// distance along the route; the result then reports the perpendicular
  /// distance within that window so callers can detect "not near where
  /// expected" and fall back to [snapToShape].
  static SnapResult? snapNear({
    required double lat,
    required double lon,
    required List<ShapePoint> points,
    required List<double> cumulativeDistances,
    required double expectedAlong,
    double? minAlong,
    double? maxAlong,
  }) {
    if (points.length < 2) return null;
    final lo = minAlong ?? double.negativeInfinity;
    final hi = maxAlong ?? double.infinity;

    final candidates = <SnapResult>[];
    var bestPerp = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final startAlong = cumulativeDistances[i];
      final endAlong = cumulativeDistances[i + 1];
      if (endAlong < lo || startAlong > hi) continue;

      final a = points[i];
      final b = points[i + 1];
      var (projLat, projLon, t) = _projectToSegment(lat, lon, a.lat, a.lon, b.lat, b.lon);
      final segLen = endAlong - startAlong;
      var along = startAlong + segLen * t;
      if (along < lo || along > hi) {
        along = along.clamp(lo, hi);
        t = segLen > 0 ? (along - startAlong) / segLen : 0.0;
        projLat = a.lat + (b.lat - a.lat) * t;
        projLon = a.lon + (b.lon - a.lon) * t;
      }
      final perp = NearestStopService.haversineDistance(lat, lon, projLat, projLon);
      if (perp < bestPerp) bestPerp = perp;
      candidates.add(SnapResult(
        snappedLat: projLat,
        snappedLon: projLon,
        distanceAlongRoute: along,
        perpendicularDistance: perp,
      ));
    }
    if (candidates.isEmpty) return null;

    SnapResult? best;
    var bestScore = double.infinity;
    for (final c in candidates) {
      if (c.perpendicularDistance > bestPerp + ambiguityToleranceMeters) continue;
      final score = c.perpendicularDistance + _expectationWeight * (c.distanceAlongRoute - expectedAlong).abs();
      if (score < bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }
```

- [ ] **Step 5: Run the tests and watch them pass; then analyze and run the full suite**

Run, in order:
- `flutter test test/map/shape_matcher_test.dart`, which should PASS (6 tests).
- `flutter analyze lib test && flutter test`, which should be green.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/map/shape_matcher.dart test/map/shape_matcher_test.dart test/map/support/out_and_back.dart
git commit -m "feat(map): progress-hinted shape snapping (ShapeMatcher.snapNear)"
```

---

### Task 2: `RouteGeometry`

**Files:**
- Create: `lib/domain/map/route_geometry.dart`
- Create: `test/map/route_geometry_test.dart`

**Interfaces:**
- Consumes: `ShapeMatcher.snapToShape`, `ShapeMatcher.snapNear` (Task 1); `GtfsRepository` (`shapesById`, `shapeCumulativeDistances`, `tripsById`, `stopsById`, `stopTimesByStopId`, `tripsByRouteShortName`); `GtfsTime.parse(String).totalSeconds`; `TimeTrackVehicle`.
- Produces:
  - `typedef ShapePose = ({double lat, double lon, double heading})`
  - `class RouteGeometry`:
    - `RouteGeometry(GtfsRepository repo)`
    - `static const double offRouteMeters = 150`
    - `String? shapeIdForTrip(String? tripId)`
    - `String? fallbackShapeId(TimeTrackVehicle v)`
    - `bool hasShape(String shapeId)`
    - `SnapResult? snap(double lat, double lon, String shapeId, {double? expectedAlong, double? minAlong, double? maxAlong})`
    - `ShapePose? poseAt(String shapeId, double progress)`
    - `List<double?> stopProgresses(String tripId, String shapeId)`
    - `double? stopProgressAtTime(String tripId, String shapeId, int departureSeconds)`
    - `double? scheduledProgress(String tripId, String shapeId, int secondsOfDay)`
    - `double? initialHint(TimeTrackVehicle v, String? tripId, String shapeId)`
  - `double bearingDegrees(double lat1, double lon1, double lat2, double lon2)` (top-level)

- [ ] **Step 1: Write the failing tests**

Create `test/map/route_geometry_test.dart`:

```dart
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
```

If `TripShapeEntry`'s constructor has no `const`, drop the `const` keywords in the last test. If `StopTimeRow` lacks a constructor field used above, mirror the fields in `lib/data/gtfs/gtfs_models.dart`.

- [ ] **Step 2: Run the tests and watch them fail**

Run: `flutter test test/map/route_geometry_test.dart`
Expected: compile error, "Target of URI doesn't exist: 'package:busboard_nl/domain/map/route_geometry.dart'".

- [ ] **Step 3: Create `lib/domain/map/route_geometry.dart`**

```dart
import 'dart:math' as math;

import '../../data/gtfs/gtfs_models.dart';
import '../../data/gtfs/gtfs_repository.dart';
import '../../data/gtfs/gtfs_time.dart';
import '../../data/realtime/timetrack_models.dart';
import 'shape_matcher.dart';

/// A point on a shape and the direction of travel there (degrees, 0 = north).
typedef ShapePose = ({double lat, double lon, double heading});

/// Initial bearing from point 1 to point 2, in degrees clockwise from north.
double bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final y = math.sin(dLon) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Read-only route geometry for the motion engine, over [GtfsRepository]:
/// snapping to shapes, poses along them, stops in trip order and where the
/// timetable says a bus should be. Caches per trip and shape.
class RouteGeometry {
  RouteGeometry(this._repo) {
    for (final rows in _repo.stopTimesByStopId.values) {
      for (final row in rows) {
        _stopTimesByTripId.putIfAbsent(row.tripId, () => []).add(row);
      }
    }
    for (final rows in _stopTimesByTripId.values) {
      rows.sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    }
  }

  final GtfsRepository _repo;
  final Map<String, List<StopTimeRow>> _stopTimesByTripId = {};
  final Map<String, List<double?>> _stopProgressCache = {};

  /// A fix this far from the shape is off route (detour, depot, bad GPS).
  static const double offRouteMeters = 150;

  String? shapeIdForTrip(String? tripId) => tripId == null ? null : _repo.tripsById[tripId]?.shapeId;

  /// When the trip is unknown: a shape of the same route number, narrowed by
  /// headsign, then by service.
  String? fallbackShapeId(TimeTrackVehicle v) {
    final candidates = _repo.tripsByRouteShortName[v.routeNumber.toString()];
    if (candidates == null || candidates.isEmpty) return null;
    var filtered = candidates;
    if (v.gtfsTripHeadsign.isNotEmpty) {
      final byHeadsign = filtered.where((e) => e.headsign.toLowerCase() == v.gtfsTripHeadsign.toLowerCase()).toList();
      if (byHeadsign.isNotEmpty) filtered = byHeadsign;
    }
    if (v.gtfsServiceId.isNotEmpty) {
      final byService = filtered.where((e) => e.serviceId == v.gtfsServiceId).toList();
      if (byService.isNotEmpty) filtered = byService;
    }
    return filtered.first.shapeId;
  }

  bool hasShape(String shapeId) =>
      (_repo.shapesById[shapeId]?.length ?? 0) >= 2 && _repo.shapeCumulativeDistances[shapeId] != null;

  /// Snaps to [shapeId]. Without [expectedAlong] this is the global nearest
  /// point. With it, the pass nearest the expectation wins; when a
  /// [minAlong]/[maxAlong] window holds nothing within [offRouteMeters], the
  /// window is dropped (real detours, long gaps).
  SnapResult? snap(double lat, double lon, String shapeId, {double? expectedAlong, double? minAlong, double? maxAlong}) {
    final points = _repo.shapesById[shapeId];
    final dists = _repo.shapeCumulativeDistances[shapeId];
    if (points == null || dists == null) return null;
    if (expectedAlong == null) {
      return ShapeMatcher.snapToShape(lat: lat, lon: lon, points: points, cumulativeDistances: dists);
    }
    final near = ShapeMatcher.snapNear(
      lat: lat, lon: lon, points: points, cumulativeDistances: dists,
      expectedAlong: expectedAlong, minAlong: minAlong, maxAlong: maxAlong,
    );
    if (near != null && near.perpendicularDistance <= offRouteMeters) return near;
    if (minAlong == null && maxAlong == null) return near;
    return ShapeMatcher.snapNear(lat: lat, lon: lon, points: points, cumulativeDistances: dists, expectedAlong: expectedAlong);
  }

  /// Position and heading [progress] metres along [shapeId], clamped to the
  /// shape's ends.
  ShapePose? poseAt(String shapeId, double progress) {
    final points = _repo.shapesById[shapeId];
    final dists = _repo.shapeCumulativeDistances[shapeId];
    if (points == null || dists == null || points.length < 2) return null;
    final p = progress.clamp(0.0, dists.last);
    var lo = 0;
    var hi = dists.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (dists[mid] <= p) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = points[lo];
    final b = points[hi];
    final seg = dists[hi] - dists[lo];
    final t = seg <= 0 ? 0.0 : (p - dists[lo]) / seg;
    return (
      lat: a.lat + (b.lat - a.lat) * t,
      lon: a.lon + (b.lon - a.lon) * t,
      heading: bearingDegrees(a.lat, a.lon, b.lat, b.lon),
    );
  }

  /// Progress of each of [tripId]'s stop_times rows (stop_sequence order) on
  /// [shapeId], or null where a stop is unknown. Each stop is placed at or
  /// after the previous one, so a stop on a road the route uses twice lands
  /// on its own pass rather than the nearest one.
  List<double?> stopProgresses(String tripId, String shapeId) {
    final key = '$tripId|$shapeId';
    final cached = _stopProgressCache[key];
    if (cached != null) return cached;
    final rows = _stopTimesByTripId[tripId] ?? const <StopTimeRow>[];
    final result = <double?>[];
    double? previous;
    for (final row in rows) {
      final stop = _repo.stopsById[row.stopId];
      final s = stop == null
          ? null
          : snap(stop.stopLat, stop.stopLon, shapeId,
              expectedAlong: previous ?? 0.0, minAlong: previous == null ? null : previous - 5.0);
      final progress = s?.distanceAlongRoute;
      result.add(progress);
      if (progress != null) previous = progress;
    }
    return _stopProgressCache[key] = List.unmodifiable(result);
  }

  /// Progress of the stop [tripId] departs at [departureSeconds] (±30 s).
  double? stopProgressAtTime(String tripId, String shapeId, int departureSeconds) {
    final rows = _stopTimesByTripId[tripId];
    if (rows == null) return null;
    final progresses = stopProgresses(tripId, shapeId);
    for (var i = 0; i < rows.length; i++) {
      final seconds = _secondsOf(rows[i].departureTime);
      if (seconds != null && (seconds - departureSeconds).abs() <= 30 && progresses[i] != null) {
        return progresses[i];
      }
    }
    return null;
  }

  /// Progress the timetable implies for [tripId] at [secondsOfDay], by linear
  /// interpolation between consecutive stops; null more than 20 minutes
  /// outside the trip. Trips past midnight (times above 24:00:00) are matched
  /// against [secondsOfDay] + 1 day.
  double? scheduledProgress(String tripId, String shapeId, int secondsOfDay) {
    final rows = _stopTimesByTripId[tripId];
    if (rows == null || rows.isEmpty) return null;
    final progresses = stopProgresses(tripId, shapeId);
    final times = <int>[];
    final along = <double>[];
    for (var i = 0; i < rows.length; i++) {
      final seconds = _secondsOf(rows[i].departureTime);
      final p = progresses[i];
      if (seconds == null || p == null) continue;
      times.add(seconds);
      along.add(p);
    }
    if (times.isEmpty) return null;
    const slack = 20 * 60;
    for (final now in [secondsOfDay, secondsOfDay + Duration.secondsPerDay]) {
      if (now < times.first - slack || now > times.last + slack) continue;
      if (now <= times.first) return along.first;
      if (now >= times.last) return along.last;
      for (var i = 0; i < times.length - 1; i++) {
        if (now >= times[i] && now <= times[i + 1]) {
          final span = times[i + 1] - times[i];
          final f = span == 0 ? 0.0 : (now - times[i]) / span;
          return along[i] + (along[i + 1] - along[i]) * f;
        }
      }
    }
    return null;
  }

  /// Where along [shapeId] a bus just starting to be tracked on [tripId]
  /// should be: the stop the feed says it is approaching, otherwise where
  /// the timetable, shifted by the reported delay, puts it at the fix time.
  double? initialHint(TimeTrackVehicle v, String? tripId, String shapeId) {
    if (tripId == null || tripId.isEmpty) return null;
    if (v.departureTimeAtClosestStop > 0) {
      final stop = stopProgressAtTime(tripId, shapeId, v.departureTimeAtClosestStop);
      if (stop != null) return stop;
    }
    if (v.positionTimeSeconds <= 0) return null;
    // Positive schedule difference = ahead: the bus is where the timetable
    // puts it that many minutes later.
    return scheduledProgress(tripId, shapeId, v.positionTimeSeconds + v.gtfsStopSequenceSchedDifferenceMins * 60);
  }

  int? _secondsOf(String gtfsTime) {
    try {
      return GtfsTime.parse(gtfsTime).totalSeconds;
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 4: Run the tests and watch them pass; then analyze and run the full suite**

Run, in order:
- `flutter test test/map/route_geometry_test.dart`, which should PASS.
- `flutter analyze lib test && flutter test`, which should be green.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/map/route_geometry.dart test/map/route_geometry_test.dart
git commit -m "feat(map): RouteGeometry — poses, ordered stops, timetable hints"
```

---

### Task 3: `BusTrack` and `BusTrackStore`

**Files:**
- Create: `lib/domain/map/bus_track.dart` (`TrackFix`, `BusTrack`)
- Create: `lib/domain/map/bus_track_store.dart`
- Create: `test/map/bus_track_store_test.dart`

**Interfaces:**
- Consumes: `RouteGeometry` (Task 2): `shapeIdForTrip`, `fallbackShapeId`, `hasShape`, `snap`, `initialHint`, and `RouteGeometry.offRouteMeters`.
- Produces, in `bus_track.dart`:
  - `class TrackFix { DateTime gpsTime; DateTime fetchTime; double lat; double lon; double heading; double speedKmh; String? tripId; String? shapeId; double? progress; double? snappedLat; double? snappedLon; bool offRoute; }`
  - `class BusTrack`:
    - fields: `String vehicleId`, `int routeNumber`, `String routeRun`, `String headsign`, `List<TrackFix> fixes`, `DateTime lastFixAt`
    - getter `TrackFix get latest`
- Produces, in `bus_track_store.dart`:
  - `class BusTrackStore`:
    - `BusTrackStore(RouteGeometry geometry, {int maxFixes = 24})`
    - `Map<String, BusTrack> get tracks`
    - `void ingest(List<TimeTrackVehicle> vehicles, DateTime fetchTime)`
    - `bool isStale(BusTrack track, DateTime now)`
    - `static const Duration staleAfter = Duration(seconds: 90)`
    - `static const Duration dropAfter = Duration(minutes: 5)`
    - `int get duplicateAssignments` (count from the last ingest)

- [ ] **Step 1: Write the failing tests**

Create `test/map/bus_track_store_test.dart`:

```dart
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/domain/map/bus_track_store.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/out_and_back.dart';

void main() {
  final start = DateTime(2026, 10, 4, 12, 0);
  final total = cumulativeFor(outAndBackPoints()).last;
  late BusTrackStore store;

  setUp(() => store = BusTrackStore(RouteGeometry(outAndBackRepo())));

  void poll(int i, List<dynamic> vehicles) =>
      store.ingest(vehicles.cast(), start.add(Duration(seconds: i * 10)));

  test('one track per physical vehicle, even on the same route run', () {
    poll(0, [
      fix(meters: 100, seconds: 43200, vehicle: '859', routeRun: 'Rt 10-1'),
      fix(meters: 300, seconds: 43200, vehicle: '861', routeRun: 'Rt 10-1'),
    ]);
    expect(store.tracks.keys, containsAll(['859', '861']));
  });

  test('duplicate interlined assignments keep one physical bus', () {
    final noData = fix(meters: 100, seconds: 43200, vehicle: '859', routeNumber: 6, routeRun: 'Rt 6-1', tripId: '');
    final live = fix(meters: 100, seconds: 43200, vehicle: '859', routeRun: 'Rt 10-1');
    store.ingest([
      noData.copyForTest(status: 'NO DATA', shortStatus: 'A3'),
      live,
    ], start);
    expect(store.tracks, hasLength(1));
    expect(store.tracks['859']!.routeNumber, 10);
    expect(store.duplicateAssignments, 1);
  });

  test('a replacement vehicle never inherits another bus\'s track', () {
    poll(0, [fix(meters: 100, seconds: 43200, vehicle: '859')]);
    poll(1, [fix(meters: 300, seconds: 43210, vehicle: '861')]);
    expect(store.tracks['861']!.fixes, hasLength(1));
    expect(store.tracks['859']!.fixes, hasLength(1));
  });

  test('a flapping routeRun on the same route keeps the track', () {
    for (var i = 0; i < 6; i++) {
      poll(i, [fix(meters: 100.0 + i * 80, seconds: 43200 + i * 10, routeRun: i.isEven ? 'Rt 10-1' : 'Rt 10')]);
    }
    expect(store.tracks['2573']!.fixes, hasLength(6));
  });

  test('a route-number change starts a new track', () {
    poll(0, [fix(meters: 100, seconds: 43200)]);
    poll(1, [fix(meters: 180, seconds: 43210)]);
    poll(2, [fix(meters: 190, seconds: 43220, routeNumber: 6, routeRun: 'Rt 6-1', tripId: '')]);
    final t = store.tracks['2573']!;
    expect(t.routeNumber, 6);
    expect(t.fixes, hasLength(1));
  });

  test('a trip change continues the same track', () {
    final repo = outAndBackRepo();
    repo.tripsById['next-trip'] = repo.tripsById[outAndBackTripId]!.copyForTest(tripId: 'next-trip');
    store = BusTrackStore(RouteGeometry(repo));
    poll(0, [fix(meters: 900, seconds: 43200)]);
    poll(1, [fix(meters: 980, seconds: 43210, tripId: 'next-trip')]);
    final t = store.tracks['2573']!;
    expect(t.fixes, hasLength(2));
    expect(t.fixes.last.tripId, 'next-trip');
  });

  test('duplicate and out-of-order GPS timestamps are ignored', () {
    poll(0, [fix(meters: 100, seconds: 43200)]);
    poll(1, [fix(meters: 100, seconds: 43200)]); // same GPS time
    poll(2, [fix(meters: 50, seconds: 43190)]); // older GPS time
    expect(store.tracks['2573']!.fixes, hasLength(1));
  });

  test('a fix just after midnight follows one just before it', () {
    final late = DateTime(2026, 10, 4, 23, 59, 55);
    store.ingest([fix(meters: 100, seconds: 86395)], late);
    store.ingest([fix(meters: 140, seconds: 5)], late.add(const Duration(seconds: 10)));
    final fixes = store.tracks['2573']!.fixes;
    expect(fixes, hasLength(2));
    expect(fixes[1].gpsTime.difference(fixes[0].gpsTime), const Duration(seconds: 10));
  });

  test('a bus on the outbound leg stays on its pass when GPS sits nearer the return leg', () {
    for (var i = 0; i < 9; i++) {
      poll(i, [fix(meters: 100.0 + i * 80, seconds: 43200 + i * 10, lat: i.isEven ? nearReturnCurb : nearOutboundCurb)]);
      final p = store.tracks['2573']!.latest.progress!;
      expect(p, closeTo(100.0 + i * 80, 40), reason: 'poll $i progress $p');
    }
  });

  test('the first fix uses the next stop, else the timetable, to pick the pass', () {
    poll(0, [fix(meters: 400, seconds: 43250, departureTimeAtClosestStop: 43260)]);
    expect(store.tracks['2573']!.latest.progress, closeTo(400, 40));
    final other = BusTrackStore(RouteGeometry(outAndBackRepo()));
    other.ingest([fix(meters: 400, seconds: 43240, vehicle: '9')], start);
    expect(other.tracks['9']!.latest.progress, closeTo(400, 40));
    expect(other.tracks['9']!.latest.progress, lessThan(total / 2));
  });

  test('a fix far from the route is off route and carries no progress', () {
    poll(0, [fix(meters: 400, seconds: 43200, lat: 47.5700)]); // ~1 km north
    final f = store.tracks['2573']!.latest;
    expect(f.offRoute, isTrue);
    expect(f.progress, isNull);
  });

  test('stale after 90 s without a new fix; dropped after 5 minutes', () {
    poll(0, [fix(meters: 100, seconds: 43200)]);
    final t = store.tracks['2573']!;
    expect(store.isStale(t, start.add(const Duration(seconds: 89))), isFalse);
    expect(store.isStale(t, start.add(const Duration(seconds: 91))), isTrue);
    store.ingest([], start.add(const Duration(minutes: 4)));
    expect(store.tracks, contains('2573'));
    store.ingest([], start.add(const Duration(minutes: 5, seconds: 1)));
    expect(store.tracks, isNot(contains('2573')));
  });

  test('a vehicle without coordinates is skipped', () {
    store.ingest([fix(meters: 100, seconds: 43200).copyForTest(lat: 0, lon: 0)], start);
    expect(store.tracks, isEmpty);
  });

  test('an unknown trip still tracks a bus without a shape', () {
    store = BusTrackStore(RouteGeometry(GtfsRepository()));
    poll(0, [fix(meters: 100, seconds: 43200)]);
    final f = store.tracks['2573']!.latest;
    expect(f.shapeId, isNull);
    expect(f.progress, isNull);
    expect(f.offRoute, isFalse);
  });
}
```

Add these test-only helpers at the bottom of `test/map/support/out_and_back.dart`. They are extensions that copy model objects with changes. Add them only if `TimeTrackVehicle`/`TripInfo` have no `copyWith`:

```dart
extension TimeTrackVehicleTestCopy on TimeTrackVehicle {
  TimeTrackVehicle copyForTest({String? status, String? shortStatus, double? lat, double? lon}) => TimeTrackVehicle(
        routeRun: routeRun, currentRoute: currentRoute, routeNumber: routeNumber, vehicle: vehicle,
        timeStamp: timeStamp, deviation: deviation, currentLocation: currentLocation,
        busLat: lat ?? busLat, busLon: lon ?? busLon, heading: heading, speed: speed,
        positionTime: positionTime, positionTimeSeconds: positionTimeSeconds,
        gtfsTripHeadsign: gtfsTripHeadsign, gtfsServiceId: gtfsServiceId,
        gtfsStopSequenceStatus: status ?? gtfsStopSequenceStatus,
        gtfsStopSequenceMinsFromStop: gtfsStopSequenceMinsFromStop,
        gtfsStopSequenceDeviation: gtfsStopSequenceDeviation,
        gtfsStopSequenceClosestStop: gtfsStopSequenceClosestStop,
        gtfsStopSequenceSchedDifferenceMins: gtfsStopSequenceSchedDifferenceMins,
        gtfsTripId: gtfsTripId, shortStatus: shortStatus ?? this.shortStatus,
        departureTimeAtClosestStop: departureTimeAtClosestStop,
      );
}

extension TripInfoTestCopy on TripInfo {
  TripInfo copyForTest({required String tripId}) => TripInfo(
        tripId: tripId, routeId: routeId, serviceId: serviceId, tripHeadsign: tripHeadsign,
        directionId: directionId, shapeId: shapeId);
}
```

(Add `import 'package:busboard_nl/data/gtfs/gtfs_models.dart';` there if it's missing. It's already imported.) Stage `test/map/support/out_and_back.dart` in this task's commit.

- [ ] **Step 2: Run the tests and watch them fail**

Run: `flutter test test/map/bus_track_store_test.dart`
Expected: compile error, "Target of URI doesn't exist: 'package:busboard_nl/domain/map/bus_track_store.dart'".

- [ ] **Step 3: Create `lib/domain/map/bus_track.dart`**

```dart
/// One GPS fix of a tracked bus, with its place on the trip's shape.
class TrackFix {
  const TrackFix({
    required this.gpsTime,
    required this.fetchTime,
    required this.lat,
    required this.lon,
    required this.heading,
    required this.speedKmh,
    this.tripId,
    this.shapeId,
    this.progress,
    this.snappedLat,
    this.snappedLon,
    this.offRoute = false,
  });

  /// When the bus measured this position (from the feed's position time).
  final DateTime gpsTime;

  /// When we received it.
  final DateTime fetchTime;
  final double lat;
  final double lon;
  final double heading;
  final double speedKmh;
  final String? tripId;
  final String? shapeId;

  /// Metres along [shapeId]; null when off route or without a shape.
  final double? progress;
  final double? snappedLat;
  final double? snappedLon;

  /// More than RouteGeometry.offRouteMeters from the shape.
  final bool offRoute;
}

/// The recent fixes of one physical bus (keyed by vehicle ID).
class BusTrack {
  BusTrack({
    required this.vehicleId,
    required this.routeNumber,
    required this.routeRun,
    required this.headsign,
    required this.fixes,
    required this.lastFixAt,
  });

  final String vehicleId;
  int routeNumber;
  String routeRun;
  String headsign;

  /// Oldest first; never empty.
  final List<TrackFix> fixes;

  /// Fetch time of the newest fix with a new GPS time.
  DateTime lastFixAt;

  TrackFix get latest => fixes.last;
}
```

- [ ] **Step 4: Create `lib/domain/map/bus_track_store.dart`**

```dart
import 'dart:math' as math;

import '../../data/realtime/timetrack_models.dart';
import 'bus_track.dart';
import 'route_geometry.dart';
import 'shape_matcher.dart';

/// Keeps one [BusTrack] per physical vehicle from successive feed polls.
///
/// Identity and reset rules (spec §3.4): a route-number change starts a new
/// track; a trip change continues the same track; duplicate or out-of-order
/// GPS times are ignored. Each fix is snapped near where the bus should be
/// (previous progress + speed × time), or for a new bus or trip near the
/// stop it is approaching or its timetable position.
class BusTrackStore {
  BusTrackStore(this._geometry, {this.maxFixes = 24});

  final RouteGeometry _geometry;
  final int maxFixes;
  final Map<String, BusTrack> _tracks = {};
  int _duplicateAssignments = 0;

  static const Duration staleAfter = Duration(seconds: 90);
  static const Duration dropAfter = Duration(minutes: 5);

  /// How far behind its last progress a fix may snap, and the fixed lead and
  /// speed allowance ahead of it.
  static const double _windowBackMeters = 250;
  static const double _windowAheadMeters = 400;
  static const double _windowMaxSpeedMps = 30;

  Map<String, BusTrack> get tracks => Map.unmodifiable(_tracks);
  int get duplicateAssignments => _duplicateAssignments;

  bool isStale(BusTrack track, DateTime now) => now.difference(track.lastFixAt) > staleAfter;

  void ingest(List<TimeTrackVehicle> vehicles, DateTime fetchTime) {
    final canonical = _selectCanonical(vehicles);
    for (final entry in canonical.entries) {
      final v = entry.value;
      if (v.busLat == 0.0 || v.busLon == 0.0) continue;
      _ingestOne(entry.key, v, fetchTime);
    }
    _tracks.removeWhere((_, t) => fetchTime.difference(t.lastFixAt) > dropAfter);
  }

  void _ingestOne(String key, TimeTrackVehicle v, DateTime fetchTime) {
    final gpsTime = _gpsTime(v.positionTimeSeconds, fetchTime);
    final tripId = v.gtfsTripId.isEmpty ? null : v.gtfsTripId;
    final shapeId = _shapeFor(v, tripId);

    var track = _tracks[key];
    if (track != null && _routeChanged(v, track)) track = null;
    if (track != null && !gpsTime.isAfter(track.latest.gpsTime)) return;

    final previous = track?.latest;
    final continuing = previous != null &&
        previous.progress != null &&
        previous.shapeId == shapeId &&
        previous.tripId == tripId;

    double? progress;
    double? snappedLat;
    double? snappedLon;
    var offRoute = false;
    if (shapeId != null) {
      final snap = continuing
          ? _snapContinuing(v, shapeId, previous, gpsTime)
          : _geometry.snap(v.busLat, v.busLon, shapeId, expectedAlong: _geometry.initialHint(v, tripId, shapeId));
      if (snap != null) {
        if (snap.perpendicularDistance > RouteGeometry.offRouteMeters) {
          offRoute = true;
        } else {
          progress = snap.distanceAlongRoute;
          snappedLat = snap.snappedLat;
          snappedLon = snap.snappedLon;
        }
      }
    }

    final fix = TrackFix(
      gpsTime: gpsTime,
      fetchTime: fetchTime,
      lat: v.busLat,
      lon: v.busLon,
      heading: _parseHeading(v.heading),
      speedKmh: v.speed,
      tripId: tripId,
      shapeId: shapeId,
      progress: progress,
      snappedLat: snappedLat,
      snappedLon: snappedLon,
      offRoute: offRoute,
    );

    if (track == null) {
      _tracks[key] = BusTrack(
        vehicleId: key,
        routeNumber: v.routeNumber,
        routeRun: v.routeRun,
        headsign: v.gtfsTripHeadsign,
        fixes: [fix],
        lastFixAt: fetchTime,
      );
      return;
    }
    track.fixes.add(fix);
    if (track.fixes.length > maxFixes) track.fixes.removeAt(0);
    track
      ..routeRun = v.routeRun.isNotEmpty ? v.routeRun : track.routeRun
      ..headsign = v.gtfsTripHeadsign.isNotEmpty ? v.gtfsTripHeadsign : track.headsign
      ..lastFixAt = fetchTime;
  }

  SnapResult? _snapContinuing(TimeTrackVehicle v, String shapeId, TrackFix previous, DateTime gpsTime) {
    final dt = gpsTime.difference(previous.gpsTime).inMilliseconds / 1000.0;
    final prior = previous.progress!;
    return _geometry.snap(
      v.busLat,
      v.busLon,
      shapeId,
      expectedAlong: prior + (v.speed / 3.6).clamp(0.0, 25.0) * dt,
      minAlong: prior - _windowBackMeters,
      maxAlong: prior + _windowAheadMeters + _windowMaxSpeedMps * dt,
    );
  }

  String? _shapeFor(TimeTrackVehicle v, String? tripId) {
    final byTrip = _geometry.shapeIdForTrip(tripId);
    final shapeId = byTrip ?? _geometry.fallbackShapeId(v);
    if (shapeId == null || !_geometry.hasShape(shapeId)) return null;
    return shapeId;
  }

  /// Route number decides when both sides know it. The routeRun label is not
  /// stable for one route (Fleet View's block vs the route ID fallback).
  bool _routeChanged(TimeTrackVehicle v, BusTrack track) {
    if (v.routeNumber > 0 && track.routeNumber > 0) return v.routeNumber != track.routeNumber;
    return v.routeRun.isNotEmpty && v.routeRun != track.routeRun;
  }

  String? _keyOf(TimeTrackVehicle v) {
    if (v.vehicle.isNotEmpty) return v.vehicle;
    if (v.routeRun.isNotEmpty) return v.routeRun;
    if (v.gtfsTripId.isNotEmpty) return 'trip:${v.gtfsTripId}';
    return null;
  }

  /// The feed can publish two route assignments for one physical vehicle
  /// during interlining. Keep one deterministic, best-supported record.
  Map<String, TimeTrackVehicle> _selectCanonical(List<TimeTrackVehicle> vehicles) {
    _duplicateAssignments = 0;
    final selected = <String, TimeTrackVehicle>{};
    for (final vehicle in vehicles) {
      final key = _keyOf(vehicle);
      if (key == null) continue;
      final current = selected[key];
      if (current != null) _duplicateAssignments++;
      if (current == null || _prefer(vehicle, current, _tracks[key])) selected[key] = vehicle;
    }
    return selected;
  }

  bool _prefer(TimeTrackVehicle candidate, TimeTrackVehicle current, BusTrack? existing) {
    final cPos = candidate.busLat != 0.0 && candidate.busLon != 0.0;
    final kPos = current.busLat != 0.0 && current.busLon != 0.0;
    if (cPos != kPos) return cPos;
    final cStatus = _statusRank(candidate);
    final kStatus = _statusRank(current);
    if (cStatus != kStatus) return cStatus > kStatus;
    final cTrip = _tripRank(candidate);
    final kTrip = _tripRank(current);
    if (cTrip != kTrip) return cTrip > kTrip;
    final cDist = _scheduleDistance(candidate);
    final kDist = _scheduleDistance(current);
    if (cDist != kDist) return cDist < kDist;
    if (existing != null) {
      final cCont = candidate.routeNumber == existing.routeNumber;
      final kCont = current.routeNumber == existing.routeNumber;
      if (cCont != kCont) return cCont;
    }
    return false;
  }

  int _statusRank(TimeTrackVehicle v) {
    final short = v.shortStatus.trim().toUpperCase();
    final long = v.gtfsStopSequenceStatus.trim().toUpperCase();
    if (long == 'NO DATA') return 0;
    if (short == 'OT' || short.startsWith('A') || short.startsWith('B') ||
        long.contains('ON TIME') || long.contains('AHEAD') || long.contains('BEHIND')) {
      return 2;
    }
    return long.isNotEmpty ? 1 : 0;
  }

  int _tripRank(TimeTrackVehicle v) {
    if (v.gtfsTripId.isEmpty) return 0;
    return _geometry.shapeIdForTrip(v.gtfsTripId) != null ? 2 : 1;
  }

  int _scheduleDistance(TimeTrackVehicle v) {
    if (v.positionTimeSeconds <= 0 || v.departureTimeAtClosestStop <= 0) return 1 << 30;
    final raw = (v.positionTimeSeconds - v.departureTimeAtClosestStop).abs() % Duration.secondsPerDay;
    return math.min(raw, Duration.secondsPerDay - raw);
  }

  /// The feed's seconds-since-midnight, placed on the day nearest [fetchTime].
  DateTime _gpsTime(int secondsOfDay, DateTime fetchTime) {
    if (secondsOfDay <= 0 || secondsOfDay >= Duration.secondsPerDay) return fetchTime;
    var t = DateTime(fetchTime.year, fetchTime.month, fetchTime.day).add(Duration(seconds: secondsOfDay));
    final diff = fetchTime.difference(t).inSeconds;
    if (diff > 43200) t = t.add(const Duration(days: 1));
    if (diff < -43200) t = t.subtract(const Duration(days: 1));
    return t;
  }

  double _parseHeading(String raw) {
    final normalized = raw.trim().toUpperCase();
    final parsed = double.tryParse(normalized);
    if (parsed != null) return parsed % 360;
    const compass = <String, double>{
      'N': 0, 'NNE': 22.5, 'NE': 45, 'ENE': 67.5, 'E': 90, 'ESE': 112.5, 'SE': 135, 'SSE': 157.5,
      'S': 180, 'SSW': 202.5, 'SW': 225, 'WSW': 247.5, 'W': 270, 'WNW': 292.5, 'NW': 315, 'NNW': 337.5,
    };
    return compass[normalized] ?? 0.0;
  }
}
```

- [ ] **Step 5: Run the tests and watch them pass; then analyze and run the full suite**

Run, in order:
- `flutter test test/map/bus_track_store_test.dart`, which should PASS.
- `flutter analyze lib test && flutter test`, which should be green.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/map/bus_track.dart lib/domain/map/bus_track_store.dart test/map/bus_track_store_test.dart test/map/support/out_and_back.dart
git commit -m "feat(map): BusTrackStore — one track per vehicle, hinted snapping"
```

---

### Task 4: `DelayedTrackRenderer`

**Files:**
- Create: `lib/domain/map/delayed_track_renderer.dart`
- Create: `test/map/delayed_track_renderer_test.dart`

**Interfaces:**
- Consumes:
  - `BusTrack`, `TrackFix` (Task 3)
  - `RouteGeometry.poseAt` and `bearingDegrees` (Task 2)
- Produces:
  - `class RenderedBus`, with fields:
    - `String vehicleId`
    - `double lat`, `double lon`, `double heading`
    - `double? progress`
    - `String? shapeId`, `String? tripId`
  - `class DelayedTrackRenderer`, with members:
    - `DelayedTrackRenderer(RouteGeometry geometry)`
    - `static const Duration minDelay = Duration(seconds: 8)`
    - `static const Duration maxDelay = Duration(seconds: 20)`
    - `static const Duration defaultDelay = Duration(seconds: 12)`
    - `static const Duration maxExtrapolation = Duration(seconds: 5)`
    - `Duration delayFor(BusTrack track)`
    - `RenderedBus render(BusTrack track, DateTime now)`
    - `Map<String, RenderedBus> renderAll(Iterable<BusTrack> tracks, DateTime now)`
    - `void forget(String vehicleId)`

- [ ] **Step 1: Write the failing tests**

Create `test/map/delayed_track_renderer_test.dart`:

```dart
import 'package:busboard_nl/domain/map/bus_track.dart';
import 'package:busboard_nl/domain/map/delayed_track_renderer.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/out_and_back.dart';

final _t0 = DateTime(2026, 10, 4, 12, 0);
final _geometry = RouteGeometry(outAndBackRepo());

TrackFix _fix(int s, double progress, {String trip = outAndBackTripId, bool offRoute = false, double? lat, double? lon}) {
  final pose = _geometry.poseAt(outAndBackShapeId, progress)!;
  return TrackFix(
    gpsTime: _t0.add(Duration(seconds: s)),
    fetchTime: _t0.add(Duration(seconds: s + 2)),
    lat: lat ?? pose.lat,
    lon: lon ?? pose.lon,
    heading: pose.heading,
    speedKmh: 30,
    tripId: trip,
    shapeId: offRoute ? null : outAndBackShapeId,
    progress: offRoute ? null : progress,
    snappedLat: offRoute ? null : pose.lat,
    snappedLon: offRoute ? null : pose.lon,
    offRoute: offRoute,
  );
}

BusTrack _track(List<TrackFix> fixes) => BusTrack(
      vehicleId: '2573', routeNumber: 10, routeRun: 'Rt 10', headsign: 'Loop',
      fixes: fixes, lastFixAt: fixes.last.fetchTime);

void main() {
  test('delay is the median fix interval plus 2 s, clamped to 8..20 s', () {
    final r = DelayedTrackRenderer(_geometry);
    expect(r.delayFor(_track([_fix(0, 100)])), DelayedTrackRenderer.defaultDelay);
    expect(r.delayFor(_track([_fix(0, 100), _fix(10, 180), _fix(20, 260), _fix(40, 420)])), const Duration(seconds: 12));
    expect(r.delayFor(_track([_fix(0, 100), _fix(2, 110), _fix(4, 120)])), DelayedTrackRenderer.minDelay);
    expect(r.delayFor(_track([_fix(0, 100), _fix(60, 400), _fix(120, 700)])), DelayedTrackRenderer.maxDelay);
  });

  test('draws the bus between two fixes, along the shape, at now − D', () {
    final r = DelayedTrackRenderer(_geometry);
    final track = _track([_fix(0, 100), _fix(10, 180), _fix(20, 260)]);
    // D = 12 s; at now = 27 s the render time is 15 s: halfway 180 → 260.
    final bus = r.render(track, _t0.add(const Duration(seconds: 27)));
    expect(bus.progress, closeTo(220, 0.5));
    expect(bus.shapeId, outAndBackShapeId);
    final pose = _geometry.poseAt(outAndBackShapeId, 220)!;
    expect(bus.lat, closeTo(pose.lat, 1e-9));
    expect(bus.lon, closeTo(pose.lon, 1e-9));
  });

  test('moves every frame while the fixes show movement', () {
    final r = DelayedTrackRenderer(_geometry);
    final track = _track([_fix(0, 100), _fix(10, 180), _fix(20, 260), _fix(30, 340)]);
    double? last;
    for (var ms = 22000; ms < 40000; ms += 120) {
      final p = r.render(track, _t0.add(Duration(milliseconds: ms))).progress!;
      if (last != null) expect(p, greaterThan(last), reason: 'frame at $ms ms');
      last = p;
    }
  });

  test('GPS that runs backward holds the bus instead of sliding it back', () {
    final r = DelayedTrackRenderer(_geometry);
    final track = _track([_fix(0, 300), _fix(10, 400), _fix(20, 330), _fix(30, 450)]);
    double highWater = 0;
    // D = 12 s; render times run 0 s .. 30 s (the last fix), so no
    // extrapolation is involved.
    for (var ms = 12000; ms <= 42000; ms += 120) {
      final p = r.render(track, _t0.add(Duration(milliseconds: ms))).progress!;
      expect(p, greaterThanOrEqualTo(highWater - 1e-6), reason: 'frame at $ms ms');
      if (p > highWater) highWater = p;
    }
    expect(highWater, closeTo(450, 0.5));
  });

  test('a repeated GPS timestamp holds the bus after at most 5 s of extrapolation', () {
    final r = DelayedTrackRenderer(_geometry);
    final track = _track([_fix(0, 100), _fix(10, 180)]);
    // D = 12 s. Render time passes the last fix (10 s) at now = 22 s.
    final at27 = r.render(track, _t0.add(const Duration(seconds: 27))).progress!; // 5 s past
    final at60 = r.render(track, _t0.add(const Duration(seconds: 60))).progress!;
    expect(at27, closeTo(180 + 8 * 5, 1)); // last segment speed 8 m/s
    expect(at60, at27);
  });

  test('a trip change crosses the terminal in plain geography', () {
    final r = DelayedTrackRenderer(_geometry);
    final a = _fix(0, 1000);
    final b = _fix(10, 1100, trip: 'next-trip');
    final bus = r.render(_track([a, b]), _t0.add(const Duration(seconds: 17))); // render time 5 s
    expect(bus.lat, closeTo((a.lat + b.lat) / 2, 1e-9));
    expect(bus.lon, closeTo((a.lon + b.lon) / 2, 1e-9));
  });

  test('a new trip resets the never-backward rule', () {
    final r = DelayedTrackRenderer(_geometry);
    final track = _track([_fix(0, 1500), _fix(10, 1600), _fix(20, 50, trip: 'next-trip'), _fix(30, 130, trip: 'next-trip')]);
    // Render time 8 s: 1580 m on the first trip sets that trip's high-water mark.
    expect(r.render(track, _t0.add(const Duration(seconds: 20))).progress, closeTo(1580, 1));
    final bus = r.render(track, _t0.add(const Duration(seconds: 37)));
    expect(bus.tripId, 'next-trip');
    expect(bus.progress, closeTo(90, 1));
  });

  test('off-route fixes are interpolated in a straight line', () {
    final r = DelayedTrackRenderer(_geometry);
    final a = _fix(0, 0, offRoute: true, lat: 47.570, lon: -52.750);
    final b = _fix(10, 0, offRoute: true, lat: 47.571, lon: -52.749);
    final bus = r.render(_track([a, b]), _t0.add(const Duration(seconds: 17)));
    expect(bus.lat, closeTo(47.5705, 1e-9));
    expect(bus.lon, closeTo(-52.7495, 1e-9));
    expect(bus.progress, isNull);
  });

  test('before the first fix the bus sits at that fix', () {
    final r = DelayedTrackRenderer(_geometry);
    final bus = r.render(_track([_fix(0, 100)]), _t0.add(const Duration(seconds: 3)));
    expect(bus.progress, closeTo(100, 1e-6));
  });

  test('renderAll draws every track and forget clears one bus', () {
    final r = DelayedTrackRenderer(_geometry);
    final one = _track([_fix(0, 100), _fix(10, 180)]);
    final all = r.renderAll([one], _t0.add(const Duration(seconds: 20)));
    expect(all.keys, ['2573']);
    r.forget('2573');
    expect(r.render(one, _t0.add(const Duration(seconds: 13))).progress, lessThan(all['2573']!.progress!));
  });
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `flutter test test/map/delayed_track_renderer_test.dart`
Expected: compile error, "Target of URI doesn't exist: … delayed_track_renderer.dart".

- [ ] **Step 3: Create `lib/domain/map/delayed_track_renderer.dart`**

```dart
import 'bus_track.dart';
import 'route_geometry.dart';

/// Where to draw one bus this frame.
class RenderedBus {
  const RenderedBus({
    required this.vehicleId,
    required this.lat,
    required this.lon,
    required this.heading,
    this.progress,
    this.shapeId,
    this.tripId,
  });

  final String vehicleId;
  final double lat;
  final double lon;
  final double heading;
  final double? progress;
  final String? shapeId;
  final String? tripId;
}

/// Draws each bus about one GPS update behind live, gliding along its route
/// between two real fixes (spec §3.4): render time = now − D, interpolated by
/// distance along the shape, never backward on the same trip; geographic
/// interpolation across a trip change or off route; at most
/// [maxExtrapolation] past the newest fix, then hold.
class DelayedTrackRenderer {
  DelayedTrackRenderer(this._geometry);

  final RouteGeometry _geometry;

  /// The furthest progress drawn per bus, on the trip it was drawn on.
  final Map<String, ({String? tripId, double progress})> _highWater = {};

  static const Duration minDelay = Duration(seconds: 8);
  static const Duration maxDelay = Duration(seconds: 20);
  static const Duration defaultDelay = Duration(seconds: 12);
  static const Duration maxExtrapolation = Duration(seconds: 5);
  static const Duration _delayMargin = Duration(seconds: 2);
  static const int _delaySamples = 8;

  /// Median interval between the track's last fixes, plus 2 s, clamped to
  /// [minDelay]..[maxDelay]; [defaultDelay] with fewer than two fixes.
  Duration delayFor(BusTrack track) {
    final fixes = track.fixes;
    if (fixes.length < 2) return defaultDelay;
    final intervals = <int>[];
    for (var i = fixes.length - 1; i > 0 && intervals.length < _delaySamples; i--) {
      intervals.add(fixes[i].gpsTime.difference(fixes[i - 1].gpsTime).inMilliseconds);
    }
    intervals.sort();
    final mid = intervals.length ~/ 2;
    final median = intervals.length.isOdd ? intervals[mid] : (intervals[mid - 1] + intervals[mid]) ~/ 2;
    final ms = (median + _delayMargin.inMilliseconds).clamp(minDelay.inMilliseconds, maxDelay.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  Map<String, RenderedBus> renderAll(Iterable<BusTrack> tracks, DateTime now) =>
      {for (final t in tracks) t.vehicleId: render(t, now)};

  void forget(String vehicleId) => _highWater.remove(vehicleId);

  RenderedBus render(BusTrack track, DateTime now) {
    final fixes = track.fixes;
    final at = now.subtract(delayFor(track));
    RenderedBus bus;
    if (!at.isAfter(fixes.first.gpsTime)) {
      bus = _atFix(track.vehicleId, fixes.first);
    } else if (!at.isBefore(fixes.last.gpsTime)) {
      bus = _beyondLast(track, at);
    } else {
      var i = fixes.length - 2;
      while (i > 0 && fixes[i].gpsTime.isAfter(at)) {
        i--;
      }
      final a = fixes[i];
      final b = fixes[i + 1];
      final span = b.gpsTime.difference(a.gpsTime).inMicroseconds;
      final f = span <= 0 ? 1.0 : at.difference(a.gpsTime).inMicroseconds / span;
      bus = _between(track.vehicleId, a, b, f.clamp(0.0, 1.0));
    }
    return _neverBackward(bus);
  }

  RenderedBus _atFix(String id, TrackFix f) {
    if (f.progress != null && f.shapeId != null) {
      return _onShape(id, f.shapeId!, f.progress!, f.tripId) ?? _raw(id, f.lat, f.lon, f.heading, f.tripId);
    }
    return _raw(id, f.lat, f.lon, f.heading, f.tripId);
  }

  RenderedBus _between(String id, TrackFix a, TrackFix b, double f) {
    final sameAxis = a.tripId == b.tripId && a.shapeId != null && a.shapeId == b.shapeId && a.progress != null && b.progress != null;
    if (sameAxis) {
      final p = a.progress! + (b.progress! - a.progress!) * f;
      final onShape = _onShape(id, a.shapeId!, p, b.tripId);
      if (onShape != null) return onShape;
    }
    final aLat = a.snappedLat ?? a.lat;
    final aLon = a.snappedLon ?? a.lon;
    final bLat = b.snappedLat ?? b.lat;
    final bLon = b.snappedLon ?? b.lon;
    final heading = (aLat == bLat && aLon == bLon) ? b.heading : bearingDegrees(aLat, aLon, bLat, bLon);
    return _raw(id, aLat + (bLat - aLat) * f, aLon + (bLon - aLon) * f, heading, f < 0.5 ? a.tripId : b.tripId);
  }

  RenderedBus _beyondLast(BusTrack track, DateTime at) {
    final fixes = track.fixes;
    final last = fixes.last;
    if (fixes.length >= 2 && last.progress != null && last.shapeId != null) {
      final prev = fixes[fixes.length - 2];
      if (prev.tripId == last.tripId && prev.shapeId == last.shapeId && prev.progress != null) {
        final segSeconds = last.gpsTime.difference(prev.gpsTime).inMilliseconds / 1000.0;
        final speed = segSeconds <= 0 ? 0.0 : ((last.progress! - prev.progress!) / segSeconds).clamp(0.0, 30.0);
        final past = at.difference(last.gpsTime);
        final ahead = (past > maxExtrapolation ? maxExtrapolation : past).inMilliseconds / 1000.0;
        final onShape = _onShape(track.vehicleId, last.shapeId!, last.progress! + speed * ahead, last.tripId);
        if (onShape != null) return onShape;
      }
    }
    return _atFix(track.vehicleId, last);
  }

  RenderedBus? _onShape(String id, String shapeId, double progress, String? tripId) {
    final pose = _geometry.poseAt(shapeId, progress);
    if (pose == null) return null;
    return RenderedBus(vehicleId: id, lat: pose.lat, lon: pose.lon, heading: pose.heading, progress: progress, shapeId: shapeId, tripId: tripId);
  }

  RenderedBus _raw(String id, double lat, double lon, double heading, String? tripId) =>
      RenderedBus(vehicleId: id, lat: lat, lon: lon, heading: heading, tripId: tripId);

  RenderedBus _neverBackward(RenderedBus bus) {
    final p = bus.progress;
    if (p == null || bus.shapeId == null) return bus;
    final hw = _highWater[bus.vehicleId];
    if (hw != null && hw.tripId == bus.tripId && p < hw.progress) {
      return _onShape(bus.vehicleId, bus.shapeId!, hw.progress, bus.tripId) ?? bus;
    }
    _highWater[bus.vehicleId] = (tripId: bus.tripId, progress: p);
    return bus;
  }
}
```

- [ ] **Step 4: Run the tests and watch them pass; then analyze and run the full suite**

Run, in order:
- `flutter test test/map/delayed_track_renderer_test.dart`, which should PASS.
- `flutter analyze lib test && flutter test`, which should be green.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/map/delayed_track_renderer.dart test/map/delayed_track_renderer_test.dart
git commit -m "feat(map): DelayedTrackRenderer — smooth, never-backward delayed drawing"
```

---

### Task 5: Replay tests on recorded live data

**Files:**
- Create: `test/fixtures/timetrack/replay_2026-10-04_22bus/` (a 10-minute, 22-bus slice plus its GTFS subset)
- Create: `tool/build_replay_fixture.py` (makes the slice; documented and reusable for the 2026-10-05 rush-hour capture)
- Create: `test/map/motion_replay_test.dart`

**Interfaces:**
- Consumes: `RouteGeometry`, `BusTrackStore`, `DelayedTrackRenderer` (Tasks 2–4); `GtfsRepository.loadFromDirectory`; `TimeTrackVehicle.fromJson`.
- Produces: one replay test per fixture directory under `test/fixtures/timetrack/` that contains `capture.json` and `gtfs/`. The existing `route_run_flap_2026-10-04/` is picked up automatically. A future rush-hour fixture needs only its folder.

- [ ] **Step 1: Build the 22-bus fixture**

Create `tool/build_replay_fixture.py`:

```python
"""Slice a capture_timetrack_snapshots.dart capture into a replay fixture.

Keeps the first N minutes of frames, every vehicle (or --vehicles), and only
the GTFS rows those vehicles' trips need. Metrobus open data.

  python3 tool/build_replay_fixture.py CAPTURE.json GTFS_DIR OUT_DIR [--minutes 10] [--vehicles 2443,2573]
"""
import argparse, csv, json, os
from datetime import datetime, timedelta

ap = argparse.ArgumentParser()
ap.add_argument('capture'); ap.add_argument('gtfs'); ap.add_argument('out')
ap.add_argument('--minutes', type=float, default=10)
ap.add_argument('--vehicles', default='')
a = ap.parse_args()

d = json.load(open(a.capture))
want = set(filter(None, a.vehicles.split(',')))
t0 = datetime.fromisoformat(d['frames'][0]['fetch_time'].replace('Z', '+00:00'))
end = t0 + timedelta(minutes=a.minutes)
frames, trips = [], set()
for f in d['frames']:
    if datetime.fromisoformat(f['fetch_time'].replace('Z', '+00:00')) > end:
        break
    f['vehicles'] = [v for v in f['vehicles'] if not want or v['vehicle'] in want]
    trips |= {v['gtfsTripId'] for v in f['vehicles'] if v.get('gtfsTripId')}
    frames.append(f)
d['frames'] = frames
d['note'] = f"Metrobus open data. {a.minutes:g} min from {d['frames'][0]['fetch_time']}, vehicles: {a.vehicles or 'all'}."
os.makedirs(f'{a.out}/gtfs', exist_ok=True)
json.dump(d, open(f'{a.out}/capture.json', 'w'), separators=(',', ':'))

def copy(name, keep):
    with open(f'{a.gtfs}/{name}', encoding='utf-8-sig') as f:
        r = csv.DictReader(f); rows = [x for x in r if keep(x)]
        w = csv.DictWriter(open(f'{a.out}/gtfs/{name}', 'w', newline=''), fieldnames=r.fieldnames)
        w.writeheader(); w.writerows(rows)
    return rows

tr = copy('trips.txt', lambda x: x['trip_id'] in trips)
shapes = {t['shape_id'] for t in tr}; routes = {t['route_id'] for t in tr}; svc = {t['service_id'] for t in tr}
st = copy('stop_times.txt', lambda x: x['trip_id'] in trips)
stops = {s['stop_id'] for s in st}
copy('stops.txt', lambda x: x['stop_id'] in stops)
copy('shapes.txt', lambda x: x['shape_id'] in shapes)
copy('routes.txt', lambda x: x['route_id'] in routes)
copy('calendar.txt', lambda x: x['service_id'] in svc)
copy('calendar_dates.txt', lambda x: x['service_id'] in svc)
print(len(frames), 'frames', len(trips), 'trips', len(shapes), 'shapes')
```

Run it:

```bash
python3 tool/build_replay_fixture.py \
  /private/tmp/claude-501/-Users-aham-projects-dev-busboard-nl--claude-worktrees-unified-ui-map-redesign-fc0a89/e8754cf0-60a0-4b9b-9334-c88b99bb1192/scratchpad/cap/snap_sun.json \
  /Users/aham/Library/Developer/CoreSimulator/Devices/0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54/data/Containers/Data/Application/A4B7260A-F283-4590-813C-16F701D8EF83/Documents/gtfs_data \
  test/fixtures/timetrack/replay_2026-10-04_22bus --minutes 10
du -sh test/fixtures/timetrack/replay_2026-10-04_22bus
```

Expected:
- about 120 frames;
- trips for all 22 buses;
- under 3 MB total.

If either source path no longer exists, stop and report NEEDS_CONTEXT. Don't invent a fixture.

- [ ] **Step 2: Write the replay test**

Create `test/map/motion_replay_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/map/bus_track_store.dart';
import 'package:busboard_nl/domain/map/delayed_track_renderer.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays every recorded capture under test/fixtures/timetrack/ through the
/// motion pipeline at the map's 120 ms frame rate and checks spec §1:
/// never backward on a trip, never faster than the fixes imply, and moving
/// whenever the fixes on both sides show movement. Measured inside the
/// renderer (progress along the shape), not by projecting drawn points.
void main() {
  final dirs = Directory('test/fixtures/timetrack')
      .listSync()
      .whereType<Directory>()
      .where((d) => File('${d.path}/capture.json').existsSync() && Directory('${d.path}/gtfs').existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('at least one replay fixture is present', () => expect(dirs, isNotEmpty));

  for (final dir in dirs) {
    test('replay ${dir.path.split('/').last}', () async {
      final repo = GtfsRepository();
      await repo.loadFromDirectory('${dir.path}/gtfs');
      final geometry = RouteGeometry(repo);
      final store = BusTrackStore(geometry);
      final renderer = DelayedTrackRenderer(geometry);
      final json = jsonDecode(File('${dir.path}/capture.json').readAsStringSync()) as Map<String, dynamic>;
      final frames = [
        for (final f in (json['frames'] as List).cast<Map<String, dynamic>>())
          if (f['status_code'] == 200)
            (DateTime.parse(f['fetch_time'] as String),
             [for (final v in (f['vehicles'] as List)) TimeTrackVehicle.fromJson(v as Map<String, dynamic>)]),
      ];
      expect(frames.length, greaterThan(20));

      const step = Duration(milliseconds: 120);
      final last = <String, ({String? trip, double? p, double lat, double lon})>{};
      final backward = <String>[];
      var movingFrames = 0;
      var advancedFrames = 0;
      var maxKmh = 0.0;
      var maxImpliedKmh = 0.0;

      for (var i = 0; i < frames.length; i++) {
        final (poll, vehicles) = frames[i];
        store.ingest(vehicles, poll);
        final end = i + 1 < frames.length ? frames[i + 1].$1 : poll.add(const Duration(seconds: 5));
        for (var t = poll; t.isBefore(end); t = t.add(step)) {
          for (final track in store.tracks.values) {
            final bus = renderer.render(track, t);
            final prev = last[bus.vehicleId];
            last[bus.vehicleId] = (trip: bus.tripId, p: bus.progress, lat: bus.lat, lon: bus.lon);
            if (prev == null) continue;
            final meters = NearestStopService.haversineDistance(prev.lat, prev.lon, bus.lat, bus.lon);
            maxKmh = math.max(maxKmh, meters / 0.12 * 3.6);
            if (prev.trip == bus.tripId && prev.p != null && bus.p != null) {
              if (bus.p! < prev.p! - 0.01) backward.add('${bus.vehicleId} ${prev.p!.round()}→${bus.p!.round()}');
              // "Moving" = the two fixes around this frame are on the same
              // trip and more than 20 m apart along it.
              final fixes = track.fixes;
              final at = t.subtract(renderer.delayFor(track));
              for (var k = 0; k + 1 < fixes.length; k++) {
                final a = fixes[k], b = fixes[k + 1];
                if (!at.isBefore(a.gpsTime) && at.isBefore(b.gpsTime) &&
                    a.tripId == b.tripId && a.progress != null && b.progress != null &&
                    b.progress! - a.progress! > 20) {
                  movingFrames++;
                  if (bus.p! > prev.p!) advancedFrames++;
                  final secs = b.gpsTime.difference(a.gpsTime).inMilliseconds / 1000.0;
                  maxImpliedKmh = math.max(maxImpliedKmh, (b.progress! - a.progress!) / secs * 3.6);
                }
              }
            }
          }
        }
      }

      expect(backward, isEmpty, reason: backward.take(5).join('\n'));
      expect(movingFrames, greaterThan(0));
      expect(advancedFrames / movingFrames, greaterThanOrEqualTo(0.95),
          reason: '$advancedFrames of $movingFrames moving frames advanced');
      // Geographic hops at trip changes and off-route stretches are allowed
      // up to the fastest implied segment speed plus margin.
      expect(maxKmh, lessThan(math.max(maxImpliedKmh, 60) * 1.5 + 20),
          reason: 'max drawn ${maxKmh.round()} km/h, max implied ${maxImpliedKmh.round()} km/h');
    });
  }
}
```

- [ ] **Step 3: Run the replay tests**

Run: `flutter test test/map/motion_replay_test.dart`
Expected: PASS for `replay_2026-10-04_22bus` and `route_run_flap_2026-10-04`.

If an assertion fails:
- Report its reason text.
- Fix the pipeline (Tasks 2–4 code) so the stated behaviour holds; never loosen a threshold.
- If you believe a threshold contradicts spec §1, stop and report NEEDS_CONTEXT with the numbers.

- [ ] **Step 4: Run analyze and the full suite**

Run: `flutter analyze lib test && flutter test`, which should be green.

- [ ] **Step 5: Commit**

```bash
git add tool/build_replay_fixture.py test/fixtures/timetrack/replay_2026-10-04_22bus test/map/motion_replay_test.dart
git commit -m "test(map): replay recorded live data through the new motion pipeline"
```

---

### Task 6: Wire the new pipeline into the app and remove `BusMotionEngine`

**Files:**
- Modify: `lib/domain/map/bus_tracking_state.dart` (drop `observations`/`progressAlongRoute`; add `speedKmh`, `lastGpsTime`, `progress`; `BusStatus` = active / offRoute / stale; add `BusTrackingState.fromTrack`)
- Modify: `lib/state/providers.dart` (replace `busMotionEngineProvider`; rewrite `busTrackingStreamProvider` on the store; remove `_SpeedFidelityTracker`)
- Modify: `lib/ui/map/map_screen.dart` (the two `engine.interpolate` call sites)
- Modify: `lib/ui/map/bus_bottom_sheet.dart` (speed and status badge)
- Modify: `test/bus_bottom_sheet_test.dart` (state helper)
- Create: `test/state/bus_tracking_provider_test.dart`
- Delete: `lib/domain/map/bus_motion_engine.dart`, `bus_journey_tracer.dart`, `bus_journey_anomaly.dart`, `bus_observation.dart`; `test/map/bus_identity_test.dart`, `bus_journey_tracer_test.dart`, `bus_journey_renderer.dart`, `bus_motion_replay_harness_test.dart`, `bus_motion_snapshot_replay_test.dart`, `bus_route_run_flap_test.dart`
- Modify: `test/live_backend_test.dart`, `lib/data/realtime/timetrack_api.dart:192`, `test/fixtures/timetrack/README.md`

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces:
  - `final routeGeometryProvider = Provider<RouteGeometry?>`
  - `final busTrackStoreProvider = Provider<BusTrackStore?>`
  - `final busTrackRendererProvider = Provider<DelayedTrackRenderer?>`
  - `final busTrackingStreamProvider = StreamProvider<Map<String, BusTrackingState>>` (same name and type as today)
  - `BusTrackingState.fromTrack(BusTrack track, {required bool stale})`
  - New `BusTrackingState` fields: `double speedKmh`, `DateTime lastGpsTime`, `double? progress`

- [ ] **Step 1: Write the failing provider test**

Create `test/state/bus_tracking_provider_test.dart`:

```dart
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../map/support/out_and_back.dart';

class _FakeApi extends TimeTrackApi {
  _FakeApi(this.batches);
  final List<List<TimeTrackVehicle>> batches;
  var calls = 0;
  @override
  Future<TimeTrackFetchResult> fetchVehiclesResult() async =>
      TimeTrackFetchResult.success(batches[(calls++).clamp(0, batches.length - 1)], source: LiveDataSource.gtfsRealtime);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the tracking stream publishes one snapshot per bus from the new store', () async {
    final api = _FakeApi([
      [fix(meters: 100, seconds: 43200)],
    ]);
    final container = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => outAndBackRepo()),
      timetrackApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    await container.read(gtfsRepositoryProvider.future);
    final snapshot = await container.read(busTrackingStreamProvider.future);
    final bus = snapshot['2573']!;
    expect(bus.vehicleId, '2573');
    expect(bus.routeNumber, 10);
    expect(bus.currentTripId, outAndBackTripId);
    expect(bus.shapeId, outAndBackShapeId);
    expect(bus.status, BusStatus.active);
    expect(bus.speedKmh, 29);
    expect(container.read(busTrackRendererProvider), isNotNull);
    expect(container.read(busTrackStoreProvider)!.tracks.keys, ['2573']);
  });

  test('without a schedule the stream is empty', () async {
    final container = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
      timetrackApiProvider.overrideWithValue(_FakeApi([[]])),
    ]);
    addTearDown(container.dispose);
    await container.read(gtfsRepositoryProvider.future);
    expect(await container.read(busTrackingStreamProvider.future), isEmpty);
  });
}
```

`gtfsRepositoryProvider` is a `FutureProvider<GtfsRepository>`. `TimeTrackFetchResult.success(vehicles, source:)` already exists (`lib/data/realtime/timetrack_api.dart`).
- If `TimeTrackApi`'s constructor needs arguments, mirror them in `_FakeApi` (e.g. `super(client: ...)`).
- If `timetrackApiProvider` disposes its value, use `overrideWith((ref) => api)` instead.

- [ ] **Step 2: Run the test and watch it fail**

Run: `flutter test test/state/bus_tracking_provider_test.dart`
Expected: compile errors, `busTrackRendererProvider` / `busTrackStoreProvider` / `speedKmh` undefined.

- [ ] **Step 3: Rewrite `lib/domain/map/bus_tracking_state.dart`**

```dart
import 'bus_track.dart';

enum BusStatus { active, offRoute, stale }

/// What the map and bus sheet know about one physical bus right now: its
/// identity, its latest fix and whether it is still reporting. Where to draw
/// it this frame comes from DelayedTrackRenderer.
class BusTrackingState {
  final String routeRun;
  final String vehicleId;
  final int routeNumber;
  final String headsign;
  final String? currentTripId;
  final String? shapeId;
  final double smoothedLat;
  final double smoothedLon;
  final double smoothedHeading;
  final double? progress;
  final double speedKmh;
  final DateTime lastGpsTime;
  final BusStatus status;
  final DateTime lastUpdateTime;

  const BusTrackingState({
    required this.routeRun,
    required this.vehicleId,
    required this.routeNumber,
    required this.headsign,
    this.currentTripId,
    this.shapeId,
    required this.smoothedLat,
    required this.smoothedLon,
    required this.smoothedHeading,
    this.progress,
    required this.speedKmh,
    required this.lastGpsTime,
    required this.status,
    required this.lastUpdateTime,
  });

  factory BusTrackingState.fromTrack(BusTrack track, {required bool stale}) {
    final f = track.latest;
    return BusTrackingState(
      routeRun: track.routeRun,
      vehicleId: track.vehicleId,
      routeNumber: track.routeNumber,
      headsign: track.headsign,
      currentTripId: f.tripId,
      shapeId: f.shapeId,
      smoothedLat: f.snappedLat ?? f.lat,
      smoothedLon: f.snappedLon ?? f.lon,
      smoothedHeading: f.heading,
      progress: f.progress,
      speedKmh: f.speedKmh,
      lastGpsTime: f.gpsTime,
      status: stale ? BusStatus.stale : (f.offRoute ? BusStatus.offRoute : BusStatus.active),
      lastUpdateTime: track.lastFixAt,
    );
  }
}
```

- [ ] **Step 4: Replace the engine providers in `lib/state/providers.dart`**
1. Replace the import `../domain/map/bus_motion_engine.dart` with imports of `../domain/map/bus_track_store.dart`, `../domain/map/delayed_track_renderer.dart` and `../domain/map/route_geometry.dart`.
2. Replace everything from `final busMotionEngineProvider` through the end of `busTrackingStreamProvider` with the code below.
3. Delete `_SpeedFidelityTracker` and `_SpeedFidelitySample` at the bottom of the file.

```dart
// ─── Bus motion (spec §3.4) ───────────────────────────────

final routeGeometryProvider = Provider<RouteGeometry?>((ref) {
  final repo = ref.watch(gtfsRepositoryProvider).asData?.value;
  return repo == null ? null : RouteGeometry(repo);
});

final busTrackStoreProvider = Provider<BusTrackStore?>((ref) {
  final geometry = ref.watch(routeGeometryProvider);
  return geometry == null ? null : BusTrackStore(geometry);
});

final busTrackRendererProvider = Provider<DelayedTrackRenderer?>((ref) {
  final geometry = ref.watch(routeGeometryProvider);
  return geometry == null ? null : DelayedTrackRenderer(geometry);
});

/// Polls the live feed into [busTrackStoreProvider] and publishes one
/// [BusTrackingState] per bus after every poll.
final busTrackingStreamProvider = StreamProvider<Map<String, BusTrackingState>>((ref) async* {
  final store = ref.watch(busTrackStoreProvider);
  if (store == null) {
    yield const {};
    return;
  }
  final api = ref.read(timetrackApiProvider);
  final interval = Duration(seconds: ref.watch(settingsProvider.select((s) => s.refreshIntervalSeconds)));

  Map<String, BusTrackingState> snapshot(DateTime now) => Map.unmodifiable({
        for (final t in store.tracks.values) t.vehicleId: BusTrackingState.fromTrack(t, stale: store.isStale(t, now)),
      });

  Future<void> poll() async {
    final now = DateTime.now();
    final result = await api.fetchVehiclesResult();
    if (result.succeeded) {
      store.ingest(result.vehicles, now);
    } else if (kDebugMode) {
      debugPrint('[Map] Live-data poll failed: ${result.error}');
    }
  }

  await poll();
  yield snapshot(DateTime.now());
  await for (final _ in Stream.periodic(interval)) {
    try {
      await poll();
      yield snapshot(DateTime.now());
    } catch (e) {
      if (kDebugMode) debugPrint('[Map] Live-data poll error: $e');
    }
  }
});
```

- [ ] **Step 5: Switch the map screen to the renderer**

In `lib/ui/map/map_screen.dart`:
- In `_renderBusAnnotations`, replace `final engine = ref.read(busMotionEngineProvider); if (engine == null) return; final interpolated = engine.interpolate(DateTime.now());` with the block below. Then change `final pos = interpolated[entry.key]; final lat = pos?.$1 ?? state.smoothedLat; final lon = pos?.$2 ?? state.smoothedLon;` to `final pos = drawn[entry.key]; final lat = pos?.lat ?? state.smoothedLat; final lon = pos?.lon ?? state.smoothedLon;`.

```dart
    final renderer = ref.read(busTrackRendererProvider);
    final store = ref.read(busTrackStoreProvider);
    if (renderer == null || store == null) return;
    final drawn = renderer.renderAll(store.tracks.values, DateTime.now());
```

- In `_findNearestBus`, make the same replacement: an engine null-check becomes a renderer/store null-check, and `interpolated[entry.key]` becomes `drawn[entry.key]` with `.lat`/`.lon`.
- Remove the now-unused `bus_motion_engine.dart` import if present.

- [ ] **Step 6: Update the bus sheet**

In `lib/ui/map/bus_bottom_sheet.dart`:
- Delete the `lastObservation` lookup (`liveBus.observations.lastWhere(...)`).
- Show speed as `'${liveBus.speedKmh.round()} km/h'`.
- Reduce `_StatusBadge`'s switch to the three statuses:

```dart
      BusStatus.active => ('ACTIVE', const Color(0xFF4FC3F7)),
      BusStatus.offRoute => ('OFF ROUTE', const Color(0xFFEF5350)),
      BusStatus.stale => ('STALE', const Color(0xFF9E9E9E)),
```

- If the sheet showed "last update" from `observations`, use `liveBus.lastGpsTime`.

In `test/bus_bottom_sheet_test.dart`:
- Remove the `bus_observation.dart` import and the `observations:` argument from `_busState`.
- Add `speedKmh: 30, lastGpsTime: now,`.
- Leave every assertion unchanged.

- [ ] **Step 7: Delete the old engine and its tests**

The old engine no longer compiles against the new `BusTrackingState`. Its coverage now lives in `bus_track_store_test`, `delayed_track_renderer_test` and `motion_replay_test`.

```bash
git rm lib/domain/map/bus_motion_engine.dart lib/domain/map/bus_journey_tracer.dart lib/domain/map/bus_journey_anomaly.dart lib/domain/map/bus_observation.dart \
  test/map/bus_identity_test.dart test/map/bus_journey_tracer_test.dart test/map/bus_journey_renderer.dart \
  test/map/bus_motion_replay_harness_test.dart test/map/bus_motion_snapshot_replay_test.dart test/map/bus_route_run_flap_test.dart
```

Keep `test/fixtures/timetrack/route_run_flap_2026-10-04/`, because `motion_replay_test.dart` replays it.

- [ ] **Step 8: Port the live backend test**

In `test/live_backend_test.dart`, replace the engine import with:

```dart
import 'package:busboard_nl/domain/map/bus_track_store.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
```

Then replace `final engine = BusMotionEngine(GtfsRepository()); engine.processBatch(result.vehicles, DateTime.now());` with:

```dart
      final store = BusTrackStore(RouteGeometry(GtfsRepository()));
      store.ingest(result.vehicles, DateTime.now());
```

and `expect(engine.states.length, uniqueVehicles.length);` with `expect(store.tracks.length, uniqueVehicles.length);`. Any other `engine.` use in that file gets the same mapping.

- [ ] **Step 9: Stop the GTFS-RT adapter reporting the delay as minutes-to-stop**

In `lib/data/realtime/timetrack_api.dart`, in the GTFS-Realtime mapping, replace `gtfsStopSequenceMinsFromStop: delayMins?.abs() ?? 0,` with:

```dart
            // GTFS-Realtime has no "minutes to the closest stop"; the delay
            // is reported separately (gtfsStopSequenceSchedDifferenceMins).
            gtfsStopSequenceMinsFromStop: 0,
```

If a test in `test/timetrack_api_test.dart` asserts the old value, update that assertion to 0, and cite behaviour change 4 in your report.

- [ ] **Step 10: Update the fixtures README**

Replace the "Replay command" and "Replay + metrics artifact" sections of `test/fixtures/timetrack/README.md` with:

````markdown
## Replay fixtures

`test/map/motion_replay_test.dart` replays every folder here that holds a
`capture.json` and a `gtfs/` subset through the motion pipeline
(`BusTrackStore` + `DelayedTrackRenderer`) and checks that buses never move
backward on a trip, never move faster than their fixes imply, and keep moving
while their fixes do.

Make a fixture from a fresh capture:

```bash
dart run tool/capture_timetrack_snapshots.dart --interval 5 --duration 900 --out /tmp/capture.json
python3 tool/build_replay_fixture.py /tmp/capture.json <unpacked GTFS dir> test/fixtures/timetrack/replay_<date>_<label> --minutes 10
```
````

- [ ] **Step 11: Run the tests, confirm nothing references the old engine, then analyze and run the full suite**

```bash
flutter test test/state/bus_tracking_provider_test.dart test/bus_bottom_sheet_test.dart
grep -rn "BusMotionEngine\|BusJourneyTracer\|BusObservation\|bus_motion_engine\|bus_journey" lib test tool
flutter analyze lib test && flutter test
```

Expected:
- the two tests pass;
- `grep` prints nothing;
- analyze prints "No issues found!";
- the full suite passes.

- [ ] **Step 12: Commit**

```bash
git add lib/domain/map/bus_tracking_state.dart lib/state/providers.dart lib/ui/map/map_screen.dart lib/ui/map/bus_bottom_sheet.dart \
  test/bus_bottom_sheet_test.dart test/state/bus_tracking_provider_test.dart test/live_backend_test.dart \
  lib/data/realtime/timetrack_api.dart test/fixtures/timetrack/README.md
git commit -m "feat(map): drive the live map from the track store and delayed renderer; remove BusMotionEngine"
```

The `git rm` in Step 7 already staged the deletions. Before committing, check `git status`: `analysis_options.yaml` and `tool/capture_raw_gtfsrt.dart` must not be staged.

---

## After the last task (controller)

- **Simulator check:** run the app on the iOS simulator with live data and watch a bus for at least a minute.
  - It must glide continuously.
  - It must never jump back.
  - It may run ~12 s behind.
- **Android check:** do the same on the Android emulator.
- **Record:** note the result in the ledger.
- **Rush-hour fixture:** when the 2026-10-05 capture exists, build `replay_2026-10-05_rush` with `tool/build_replay_fixture.py`. The replay test picks it up automatically.
- **Next plan:** Plan 3b-2 (style, layers, cards, follow mode) consumes `busTrackStoreProvider`, `busTrackRendererProvider` and `RenderedBus.heading`/`progress`.
