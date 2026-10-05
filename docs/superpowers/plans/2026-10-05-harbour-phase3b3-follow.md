# Harbour Phase 3b-3 — Follow mode

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a rider pick one bus, from its bus card or from a live row on the Board, and follow it smoothly through its trip to their stop. Follow mode adds:
- the followed route line;
- an emphasised marker for the followed bus;
- a camera that keeps the bus and the rider's stop in view;
- a follow card with stops remaining, a stop strip and the full stop list;
- clean endings with no switch to another bus.

**Architecture:**
- **Pure Dart:** two new domain pieces. `RouteGeometry.tripStops`/`splitShape` give the followed trip's stops and route line. `FollowTracker` turns each frame's bus state into a `FollowSnapshot`: stops remaining, arrival, staleness and how the follow ends. It never looks at any other vehicle.
- **Target provider:** `followProvider` holds only the followed vehicle ID, so the Board can start a follow from another tab.
- **Map screen:** the screen feeds the tracker from its existing frame loop. A small `FollowCamera` decides the camera moves, a pointer `Listener` pauses following on a pan, and the sheet shows the follow card.

**Tech Stack:** Flutter 3.47.6 / Dart 3.13.5, Riverpod 3, go_router 18, maplibre_gl 0.27.1.

**Spec:** `docs/superpowers/specs/2026-10-04-harbour-phase3-design.md` §3.5 (follow mode), §3.2 (route line, followed and dimmed buses), §1 (success criteria) and §4 (follow-mode tests). This plan builds on Phase 3b-1 (motion) and 3b-2 (the map on the kit). The record of those phases is `docs/superpowers/notes/2026-10-05-harbour-phase3b1-ledger.md` and `docs/superpowers/notes/2026-10-05-harbour-phase3b2-ledger.md`.

## Global Constraints

- **Entry:** tapping a **live** arrival row on the Board switches to the Map tab and follows that row's vehicle. Rows without a live vehicle can't be tapped. Following can also start from **Follow** on a bus card (§3.5).
- **State:** the followed state holds a vehicle ID, never a route or trip (§3.5).
- **Camera:** it keeps the bus and your stop in view, with padding for the sheet and chips, and zooms in as the bus approaches. A pan or zoom gesture pauses following and shows a "Back to bus 2573" `BBChip`. Camera moves respect Reduce Motion: they jump instead of animating (§3.5).
- **Top chip:** "● Following bus 2573" (§3.5).
- **Card at peek:**
  - header: route badge · "to <headsign>" · "Bus 2573 · 1 min late" · minutes to your stop from live predictions (`soon` colour at 5 min or less);
  - "2 stops to MUN Centre";
  - a stop strip (driven / the bus's position / upcoming / your stop);
  - buttons *Stop following* and *See all stops* (§3.5).
- **See all stops** (half or full): a timeline from the bus to the end of its trip, with ETAs (scheduled + current delay) and your stop emphasised. If your stop isn't on this trip, it shows the next ~6 stops (§3.5).
- **Endings:**
  - **Arrival:** the card shows "Arrived at MUN Centre", follows for 10 s more, then ends.
  - **Past your stop, or trip ended:** ends with a `BBToast`.
  - **Feed gap:** the marker turns grey and the card shows "Last seen 1 min ago". After 5 min, following ends with a toast.
  - Following **never switches to a different vehicle** (§3.5).
- **Screen readers:** the card has a live region that announces only changes in stops remaining, at most once per stop. Every control has a label and an action (§3.5).
- **Route line** (follow mode only): the followed trip's shape in the route colour, 6 px, over a 30%-ink casing. The part already driven is drawn at 40% opacity (§3.2).
- **Followed bus:** drawn 1.35× larger. Other buses fade to 35% opacity (§3.2).
- **Code rules:**
  - Screen code under `lib/ui/` (outside the kit) imports only `package:flutter/widgets.dart` and `ui/kit/kit.dart`. The kit guard's allow-list stays empty.
  - `lib/domain/` has no Flutter imports.
  - The app stays free: no keys, no cloud.
- **Accessibility:** cards survive 320 pt and 360 pt widths at text ×2.0 (§4).

## Review Focus

1. **The followed bus drops out of the feed mid-follow.** The marker turns grey and the card reads "Last seen 1 min ago". After 5 min (when the store drops the track), following ends with a toast, and nothing jumps to another bus. Tests: Task 2 "a bus that stops reporting is lost after the store drops it", and Task 6 "a stale followed bus shows Last seen".
2. **Your stop is not on the followed trip.** The card says so, the timeline shows the next 6 stops, nothing waits for an arrival, and following ends when the trip ends. Tests: Task 2 "your stop not on the trip", Task 5 "next six stops when your stop isn't on the trip".
3. **Following from the Board a bus that isn't in the map feed yet** (feed lag or a stale prediction). The card shows "Finding bus 2573…". It ends with a toast after 60 s if the bus never appears. Test: Task 2 "a bus that never appears ends as not found".
4. **A loop route whose trip visits your stop twice.** Stops remaining and arrival use the upcoming visit, not the first one in the timetable. Test: Task 2 "a stop visited twice uses the upcoming visit".
5. **The rider pans, then the follow ends.** The Back chip goes away, and the camera makes no further moves. Test: Task 6 "after following ends, the camera stops and the Back chip goes".

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/domain/map/route_geometry.dart` | + `TripStop`, `tripStops(tripId, shapeId)`, `splitShape(shapeId, progress)` |
| `lib/domain/map/follow_tracker.dart` (new) | `FollowTracker` → `FollowSnapshot` (pure) |
| `lib/state/follow_providers.dart` (new) | `followProvider`, the followed vehicle ID |
| `lib/ui/board/arrival_row_tile.dart`, `arrival_board_screen.dart` | Live rows can be tapped to follow |
| `lib/ui/map/bus_card.dart` | + *Follow* button |
| `lib/ui/map/map_surface.dart` | + `addLineLayer`, `MapCamera.fitBounds` |
| `lib/ui/map/map_layers.dart` | + route line layers; followed and dimmed marker emphasis |
| `lib/ui/map/follow_card.dart` (new) | Follow card header, stop strip and all-stops timeline |
| `lib/ui/map/follow_camera.dart` (new) | Which camera move to make, when (pure) |
| `lib/ui/map/map_screen.dart` | Follow integration: tracker per frame, camera, pause / Back chip, top chip, sheet, endings |
| `test/map/support/fake_map_surface.dart` | + line layers, `fitBounds` |

---

### Task 1: Trip stops and the route line split

**Files:**
- Modify: `lib/domain/map/route_geometry.dart`
- Test: `test/map/route_geometry_test.dart` (add a group)

**Interfaces:**
- Produces:
  - `class TripStop { final String stopId; final String name; final int sequence; final double? progress; final int? departureSeconds; }`
  - `List<TripStop> RouteGeometry.tripStops(String tripId, String shapeId)`: in stop_sequence order, with progress from `stopProgresses` and departure as seconds since midnight (over 86400 past midnight).
  - `({List<List<double>> driven, List<List<double>> ahead})? RouteGeometry.splitShape(String shapeId, double progress)`: `[lon, lat]` pairs. The split point ends `driven` and starts `ahead`, and both always have at least 2 points. Returns null for an unknown shape.

- [ ] **Step 1: Write the failing tests**

Add to `test/map/route_geometry_test.dart`. It already imports `support/out_and_back.dart`, which provides `outAndBackRepo()`, `outAndBackTripId`, `outAndBackShapeId`, `lonAt` and `outboundLat`, and stops s1…s4.

```dart
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
```

Check the actual stop IDs and the first departure in `test/map/support/out_and_back.dart` before relying on `s1…s4` and 12:00:00. If they differ, use the real values.

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/map/route_geometry_test.dart`
Expected: a compile error, because `tripStops` and `splitShape` are not defined.

- [ ] **Step 3: Implement**

In `lib/domain/map/route_geometry.dart`, add `TripStop` above the class and these two methods on `RouteGeometry`. Both reuse the existing private `_stopTimesByTripId` index and `_secondsOf`.

```dart
/// One stop of a trip, in stop_sequence order (follow mode's strip and
/// timeline). [progress] is null where the stop could not be placed on the
/// shape; [departureSeconds] is seconds since midnight (over 86400 past it).
class TripStop {
  const TripStop({
    required this.stopId,
    required this.name,
    required this.sequence,
    required this.progress,
    required this.departureSeconds,
  });

  final String stopId;
  final String name;
  final int sequence;
  final double? progress;
  final int? departureSeconds;
}
```

```dart
  List<TripStop> tripStops(String tripId, String shapeId) {
    final rows = _stopTimesByTripId[tripId] ?? const <StopTimeRow>[];
    final progresses = stopProgresses(tripId, shapeId);
    return [
      for (var i = 0; i < rows.length; i++)
        TripStop(
          stopId: rows[i].stopId,
          name: _repo.stopsById[rows[i].stopId]?.stopName ?? 'Stop ${rows[i].stopId}',
          sequence: rows[i].stopSequence,
          progress: i < progresses.length ? progresses[i] : null,
          departureSeconds: _secondsOf(rows[i].departureTime),
        ),
    ];
  }

  /// [shapeId]'s line split at [progress] (clamped to the shape) into the part
  /// already driven and the part ahead, as [lon, lat] pairs. The split point
  /// ends one and starts the other; each has at least two points.
  ({List<List<double>> driven, List<List<double>> ahead})? splitShape(String shapeId, double progress) {
    final points = _repo.shapesById[shapeId];
    final dists = _repo.shapeCumulativeDistances[shapeId];
    if (points == null || dists == null || points.length < 2 || dists.length != points.length) return null;
    final p = progress.clamp(0.0, dists.last);
    var i = 0;
    while (i < dists.length - 2 && dists[i + 1] < p) {
      i++;
    }
    final span = dists[i + 1] - dists[i];
    final f = span <= 0 ? 0.0 : (p - dists[i]) / span;
    final split = [
      points[i].lon + (points[i + 1].lon - points[i].lon) * f,
      points[i].lat + (points[i + 1].lat - points[i].lat) * f,
    ];
    final driven = [for (var k = 0; k <= i; k++) [points[k].lon, points[k].lat], split];
    final ahead = [split, for (var k = i + 1; k < points.length; k++) [points[k].lon, points[k].lat]];
    return (driven: driven, ahead: ahead);
  }
```

`poseAt` interpolates in the same linear way, so the test's comparison of the split point with `poseAt` holds. If the comparison fails by more than `1e-9`, make the split point come from `poseAt(shapeId, p)` instead.

- [ ] **Step 4: Run, analyze, commit**

Run: `flutter test test/map/route_geometry_test.dart && flutter analyze lib test`
Expected: PASS, no issues.

```bash
git add lib/domain/map/route_geometry.dart test/map/route_geometry_test.dart
git commit -m "feat(map): trip stops and route-line split for follow mode"
```

---

### Task 2: `FollowTracker`

**Files:**
- Create: `lib/domain/map/follow_tracker.dart`
- Test: `test/map/follow_tracker_test.dart`

**Interfaces:**
- Consumes: `TripStop` (Task 1); `BusTrackingState` (`lib/domain/map/bus_tracking_state.dart`), whose fields are:
  - `vehicleId`, `routeNumber`, `routeRun`, `headsign`, `currentTripId`, `shapeId`
  - `lat`, `lon`, `heading`, `progress`, `speedKmh`
  - `lastGpsTime`, `status` (`BusStatus.active` / `offRoute` / `stale`), `lastUpdateTime`, `schedDiffMins`
- Produces:
  - `enum FollowEnd { arrived, passedYourStop, tripEnded, lostContact, notFound }`
  - `class FollowSnapshot { vehicleId, bus, stale, lastSeenAgo, stops, busIndex, yourStopIndex, stopsToYourStop, arrived, ended, tripId }`, with value equality over the fields the card shows.
  - `class FollowTracker`:
    - `FollowTracker({required String vehicleId, required List<TripStop> Function(String tripId, String shapeId) stopsFor})`
    - `FollowSnapshot update({required BusTrackingState? bus, required double? drawnProgress, required String? yourStopId, required DateTime now})`
    - constants `arrivalRadius = 30`, `arrivalLinger = 10 s`, `passedMargin = 150`, `tripEndMargin = 30`, `notFoundAfter = 60 s`, `lostAfter = 5 min`

**Rules** (spec §3.5, with the tie-breaks decided here):
- **Vehicle:** only `vehicleId` is ever followed. The caller passes that vehicle's state or null; the tracker never picks another.
- **Trip:** the first non-null `currentTripId` seen is the followed trip. If a later fix reports a different trip, the trip has ended (`tripEnded`).
- **Progress `p`:** `drawnProgress ?? bus.progress`. While both are null (off route), the last known `p` is kept.
- **`busIndex`:** the last stop with `progress <= p + arrivalRadius`, or −1.
- **`yourStopIndex`:** the first stop with `stopId == yourStopId` whose progress is null or at least `p − passedMargin`. If the stop is on the trip but every visit is further back than that, the bus has passed it (`passedYourStop`). It is null when the stop isn't on the trip.
- **`stopsToYourStop`:** `yourStopIndex − busIndex`, at least 0.
- **Arrival:** when `p >= yourStop.progress − arrivalRadius`, `arrived` is true and stays true. After `arrivalLinger`, the follow ends with `arrived`.
- **Trip end:** when your stop isn't on the trip and `p >= lastPlacedStop.progress − tripEndMargin`, the follow ends with `tripEnded`.
- **Never found:** if no fix has ever been seen and `now − firstUpdate > notFoundAfter`, the follow ends with `notFound`.
- **Lost:**
  - If a bus was seen before and now `bus == null` (the store drops a track after 5 min stale), the follow ends with `lostContact`.
  - It also ends with `lostContact` if `bus.lastGpsTime` is more than `lostAfter` ago.
- **Stale:** `stale` is `bus.status == BusStatus.stale`, and `lastSeenAgo` is `now − bus.lastGpsTime`.
- **Ending is sticky:** after `ended` is set, every later snapshot repeats it.

- [ ] **Step 1: Write the failing tests**

Create `test/map/follow_tracker_test.dart`:

```dart
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/domain/map/follow_tracker.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 5, 12);
DateTime _at(int s) => _t0.add(Duration(seconds: s));

const _stops = [
  TripStop(stopId: 'a', name: 'A', sequence: 1, progress: 0, departureSeconds: 43200),
  TripStop(stopId: 'b', name: 'B', sequence: 2, progress: 400, departureSeconds: 43260),
  TripStop(stopId: 'mun', name: 'MUN Centre', sequence: 3, progress: 800, departureSeconds: 43320),
  TripStop(stopId: 'c', name: 'C', sequence: 4, progress: 1200, departureSeconds: 43380),
];

BusTrackingState _bus({double progress = 100, String trip = 't1', BusStatus status = BusStatus.active, DateTime? gps, String id = '2573'}) =>
    BusTrackingState(
      routeRun: 'Rt 10',
      vehicleId: id,
      routeNumber: 10,
      headsign: 'Downtown',
      currentTripId: trip,
      shapeId: 's',
      lat: 47.56,
      lon: -52.71,
      heading: 90,
      progress: progress,
      speedKmh: 30,
      lastGpsTime: gps ?? _t0,
      status: status,
      lastUpdateTime: gps ?? _t0,
    );

FollowTracker _tracker([List<TripStop> stops = _stops]) => FollowTracker(vehicleId: '2573', stopsFor: (_, _) => stops);

void main() {
  test('counts stops to your stop as the bus advances', () {
    final t = _tracker();
    var s = t.update(bus: _bus(progress: 100), drawnProgress: 100, yourStopId: 'mun', now: _t0);
    expect((s.busIndex, s.yourStopIndex, s.stopsToYourStop), (0, 2, 2));
    s = t.update(bus: _bus(progress: 420), drawnProgress: 420, yourStopId: 'mun', now: _at(30));
    expect(s.stopsToYourStop, 1);
    expect(s.arrived, isFalse);
    expect(s.ended, isNull);
  });

  test('arrival shows for 10 s, then the follow ends', () {
    final t = _tracker();
    t.update(bus: _bus(progress: 700), drawnProgress: 700, yourStopId: 'mun', now: _t0);
    var s = t.update(bus: _bus(progress: 790), drawnProgress: 790, yourStopId: 'mun', now: _at(1));
    expect(s.arrived, isTrue);
    expect(s.ended, isNull);
    s = t.update(bus: _bus(progress: 900), drawnProgress: 900, yourStopId: 'mun', now: _at(10));
    expect(s.ended, isNull, reason: 'still within the 10 s linger');
    s = t.update(bus: _bus(progress: 950), drawnProgress: 950, yourStopId: 'mun', now: _at(11));
    expect(s.ended, FollowEnd.arrived);
  });

  test('a bus already past your stop ends as passed', () {
    final s = _tracker().update(bus: _bus(progress: 1100), drawnProgress: 1100, yourStopId: 'mun', now: _t0);
    expect(s.ended, FollowEnd.passedYourStop);
  });

  test('the bus starting another trip ends the follow; it never switches vehicle', () {
    final t = _tracker();
    t.update(bus: _bus(trip: 't1'), drawnProgress: 100, yourStopId: 'mun', now: _t0);
    final s = t.update(bus: _bus(trip: 't2', progress: 10), drawnProgress: 10, yourStopId: 'mun', now: _at(20));
    expect(s.ended, FollowEnd.tripEnded);
    expect(s.vehicleId, '2573');
  });

  test('a bus that stops reporting is lost after the store drops it', () {
    final t = _tracker();
    t.update(bus: _bus(), drawnProgress: 100, yourStopId: 'mun', now: _t0);
    var s = t.update(bus: _bus(status: BusStatus.stale), drawnProgress: 100, yourStopId: 'mun', now: _at(95));
    expect(s.stale, isTrue);
    expect(s.lastSeenAgo, const Duration(seconds: 95));
    expect(s.ended, isNull);
    s = t.update(bus: null, drawnProgress: null, yourStopId: 'mun', now: _at(301));
    expect(s.ended, FollowEnd.lostContact);
  });

  test('a GPS time older than 5 min is lost even if the track lingers', () {
    final s = _tracker().update(bus: _bus(gps: _t0), drawnProgress: 100, yourStopId: 'mun', now: _at(301));
    expect(s.ended, FollowEnd.lostContact);
  });

  test('a bus that never appears ends as not found after 60 s', () {
    final t = _tracker();
    expect(t.update(bus: null, drawnProgress: null, yourStopId: 'mun', now: _t0).ended, isNull);
    expect(t.update(bus: null, drawnProgress: null, yourStopId: 'mun', now: _at(59)).ended, isNull);
    expect(t.update(bus: null, drawnProgress: null, yourStopId: 'mun', now: _at(61)).ended, FollowEnd.notFound);
  });

  test('your stop not on the trip: no arrival, ends at the trip end', () {
    final t = _tracker();
    var s = t.update(bus: _bus(progress: 900), drawnProgress: 900, yourStopId: 'elsewhere', now: _t0);
    expect((s.yourStopIndex, s.stopsToYourStop, s.arrived, s.ended), (null, null, false, null));
    s = t.update(bus: _bus(progress: 1180), drawnProgress: 1180, yourStopId: 'elsewhere', now: _at(60));
    expect(s.ended, FollowEnd.tripEnded);
  });

  test('a stop visited twice uses the upcoming visit', () {
    const loop = [
      TripStop(stopId: 'mun', name: 'MUN Centre', sequence: 1, progress: 0, departureSeconds: 43200),
      TripStop(stopId: 'b', name: 'B', sequence: 2, progress: 600, departureSeconds: 43300),
      TripStop(stopId: 'mun', name: 'MUN Centre', sequence: 3, progress: 1500, departureSeconds: 43500),
    ];
    final s = _tracker(loop).update(bus: _bus(progress: 700), drawnProgress: 700, yourStopId: 'mun', now: _t0);
    expect(s.yourStopIndex, 2);
    expect(s.stopsToYourStop, 1);
    expect(s.ended, isNull);
  });

  test('off route keeps the last known position; endings are sticky', () {
    final t = _tracker();
    t.update(bus: _bus(progress: 420), drawnProgress: 420, yourStopId: 'mun', now: _t0);
    var s = t.update(bus: _bus(progress: 0).copyWithoutProgress(), drawnProgress: null, yourStopId: 'mun', now: _at(5));
    expect(s.stopsToYourStop, 1);
    s = t.update(bus: _bus(progress: 1100), drawnProgress: 1100, yourStopId: 'mun', now: _at(6));
    s = t.update(bus: _bus(progress: 100), drawnProgress: 100, yourStopId: 'mun', now: _at(7));
    expect(s.ended, isNotNull);
  });
}

extension on BusTrackingState {
  BusTrackingState copyWithoutProgress() => BusTrackingState(
        routeRun: routeRun,
        vehicleId: vehicleId,
        routeNumber: routeNumber,
        headsign: headsign,
        currentTripId: currentTripId,
        shapeId: shapeId,
        lat: lat,
        lon: lon,
        heading: heading,
        speedKmh: speedKmh,
        lastGpsTime: lastGpsTime,
        status: BusStatus.offRoute,
        lastUpdateTime: lastUpdateTime,
      );
}
```

The last test's `1100` jump passes your stop without first being within `arrivalRadius`. By the rules it ends as `passedYourStop`. That is why it asserts only `isNotNull` followed by stickiness.

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/map/follow_tracker_test.dart`
Expected: a compile error, because `follow_tracker.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/domain/map/follow_tracker.dart`:

```dart
import 'bus_tracking_state.dart';
import 'route_geometry.dart';

/// Why a follow ended (spec §3.5).
enum FollowEnd { arrived, passedYourStop, tripEnded, lostContact, notFound }

/// What the follow card shows this frame.
class FollowSnapshot {
  const FollowSnapshot({
    required this.vehicleId,
    required this.bus,
    required this.tripId,
    required this.stale,
    required this.lastSeenAgo,
    required this.stops,
    required this.busIndex,
    required this.yourStopIndex,
    required this.stopsToYourStop,
    required this.arrived,
    required this.ended,
  });

  final String vehicleId;

  /// The followed vehicle's latest state; null while it is not in the feed.
  final BusTrackingState? bus;
  final String? tripId;
  final bool stale;
  final Duration? lastSeenAgo;
  final List<TripStop> stops;

  /// The last stop the bus has reached (-1 before the first).
  final int busIndex;

  /// The upcoming visit to your stop on this trip; null when it isn't on it.
  final int? yourStopIndex;
  final int? stopsToYourStop;
  final bool arrived;
  final FollowEnd? ended;

  /// The card only needs rebuilding when one of these changes.
  @override
  bool operator ==(Object other) =>
      other is FollowSnapshot &&
      other.vehicleId == vehicleId &&
      other.tripId == tripId &&
      (other.bus == null) == (bus == null) &&
      other.bus?.schedDiffMins == bus?.schedDiffMins &&
      other.stale == stale &&
      other.lastSeenAgo?.inMinutes == lastSeenAgo?.inMinutes &&
      other.busIndex == busIndex &&
      other.yourStopIndex == yourStopIndex &&
      other.stopsToYourStop == stopsToYourStop &&
      other.arrived == arrived &&
      other.ended == ended &&
      identical(other.stops, stops);

  @override
  int get hashCode => Object.hash(vehicleId, tripId, bus == null, stale, busIndex, yourStopIndex, stopsToYourStop, arrived, ended);
}

/// Follows exactly one vehicle (spec §3.5): never another, whatever the feed
/// does. Feed it that vehicle's state every frame; it decides stops remaining,
/// arrival (shown for [arrivalLinger], then the end) and the other endings.
class FollowTracker {
  FollowTracker({required this.vehicleId, required this.stopsFor});

  final String vehicleId;
  final List<TripStop> Function(String tripId, String shapeId) stopsFor;

  static const double arrivalRadius = 30;
  static const Duration arrivalLinger = Duration(seconds: 10);
  static const double passedMargin = 150;
  static const double tripEndMargin = 30;
  static const Duration notFoundAfter = Duration(seconds: 60);
  static const Duration lostAfter = Duration(minutes: 5);

  DateTime? _startedAt;
  bool _seen = false;
  String? _tripId;
  String? _shapeId;
  List<TripStop> _stops = const [];
  double? _p;
  DateTime? _arrivedAt;
  FollowEnd? _ended;
  FollowSnapshot? _last;

  FollowSnapshot update({
    required BusTrackingState? bus,
    required double? drawnProgress,
    required String? yourStopId,
    required DateTime now,
  }) {
    _startedAt ??= now;
    if (_ended != null) return _snapshot(bus, now, null, null, ended: _ended);

    if (bus == null) {
      if (_seen) return _end(FollowEnd.lostContact, bus, now);
      if (now.difference(_startedAt!) > notFoundAfter) return _end(FollowEnd.notFound, bus, now);
      return _snapshot(null, now, null, null);
    }
    _seen = true;
    if (now.difference(bus.lastGpsTime) > lostAfter) return _end(FollowEnd.lostContact, bus, now);

    final trip = bus.currentTripId;
    if (trip != null) {
      if (_tripId == null) {
        _tripId = trip;
      } else if (trip != _tripId) {
        return _end(FollowEnd.tripEnded, bus, now);
      }
    }
    final shape = bus.shapeId;
    if (_tripId != null && shape != null && (shape != _shapeId || _stops.isEmpty)) {
      _shapeId = shape;
      _stops = stopsFor(_tripId!, shape);
    }
    _p = drawnProgress ?? bus.progress ?? _p;
    final p = _p;
    if (p == null) return _snapshot(bus, now, null, null);

    var busIndex = -1;
    for (var i = 0; i < _stops.length; i++) {
      final sp = _stops[i].progress;
      if (sp != null && sp <= p + arrivalRadius) busIndex = i;
    }

    int? yourIndex;
    var yourStopOnTrip = false;
    if (yourStopId != null) {
      for (var i = 0; i < _stops.length; i++) {
        if (_stops[i].stopId != yourStopId) continue;
        yourStopOnTrip = true;
        final sp = _stops[i].progress;
        if (sp == null || sp >= p - passedMargin) {
          yourIndex = i;
          break;
        }
      }
    }

    if (yourIndex != null) {
      final yp = _stops[yourIndex].progress;
      if (yp != null && p >= yp - arrivalRadius) _arrivedAt ??= now;
    } else if (yourStopOnTrip && _arrivedAt == null) {
      return _end(FollowEnd.passedYourStop, bus, now);
    }
    if (_arrivedAt != null && now.difference(_arrivedAt!) > arrivalLinger) {
      return _end(FollowEnd.arrived, bus, now);
    }
    if (!yourStopOnTrip) {
      final lastPlaced = _stops.lastWhere((s) => s.progress != null, orElse: () => const TripStop(stopId: '', name: '', sequence: 0, progress: null, departureSeconds: null));
      if (lastPlaced.progress != null && p >= lastPlaced.progress! - tripEndMargin) {
        return _end(FollowEnd.tripEnded, bus, now);
      }
    }
    final toGo = yourIndex == null ? null : (yourIndex - busIndex).clamp(0, _stops.length);
    return _snapshot(bus, now, busIndex, yourIndex, stopsTo: toGo);
  }

  FollowSnapshot _end(FollowEnd why, BusTrackingState? bus, DateTime now) {
    _ended = why;
    return _snapshot(bus, now, _last?.busIndex, _last?.yourStopIndex, ended: why, stopsTo: _last?.stopsToYourStop);
  }

  FollowSnapshot _snapshot(BusTrackingState? bus, DateTime now, int? busIndex, int? yourIndex, {int? stopsTo, FollowEnd? ended}) {
    final s = FollowSnapshot(
      vehicleId: vehicleId,
      bus: bus,
      tripId: _tripId,
      stale: bus?.status == BusStatus.stale,
      lastSeenAgo: bus == null ? null : now.difference(bus.lastGpsTime),
      stops: _stops,
      busIndex: busIndex ?? _last?.busIndex ?? -1,
      yourStopIndex: yourIndex ?? (ended == null ? null : _last?.yourStopIndex),
      stopsToYourStop: stopsTo ?? (ended == null && busIndex == null ? _last?.stopsToYourStop : null),
      arrived: _arrivedAt != null,
      ended: ended,
    );
    return _last = s;
  }
}
```

The "off route keeps the last known position" test needs `busIndex`, `yourStopIndex` and `stopsToYourStop` carried over when `p` is unknown. `_snapshot(bus, now, null, null)` falls back to `_last` for each of these. Check the fallbacks against the test and adjust only the fallbacks: carry the last known values while `p` is null, and use fresh values otherwise.

- [ ] **Step 4: Run, analyze, commit**

Run: `flutter test test/map/follow_tracker_test.dart && flutter analyze lib test`
Expected: PASS, no issues.

```bash
git add lib/domain/map/follow_tracker.dart test/map/follow_tracker_test.dart
git commit -m "feat(map): FollowTracker — one vehicle, stops to your stop, arrival and endings"
```

---

### Task 3: Starting a follow — `followProvider`, Board rows, the bus card's *Follow*

**Files:**
- Create: `lib/state/follow_providers.dart`
- Modify:
  - `lib/ui/board/arrival_row_tile.dart`: add an optional `onTap`.
  - `lib/ui/board/arrival_board_screen.dart`: live rows follow their bus.
  - `lib/ui/map/bus_card.dart`: add the *Follow* button.
- Test:
  - `test/state/follow_providers_test.dart`
  - `test/ui/arrival_row_tile_test.dart` (add)
  - `test/ui/arrival_board_screen_test.dart` (add)
  - `test/ui/map_cards_test.dart` (add)

**Interfaces:**
- Produces:
  - `class FollowTarget { const FollowTarget(this.vehicleId); final String vehicleId; }` with value equality.
  - `final followProvider = NotifierProvider<FollowNotifier, FollowTarget?>`, with `FollowNotifier.follow(String vehicleId)` and `.stop()`.
  - `ArrivalRowTile({required ArrivalRow arrival, VoidCallback? onTap})`.

`followProvider` is app-wide, not map-scoped (spec §3.5 says map-scoped), because the Board must start a follow from another tab. Only the map reads it. Task 7 records this ruling in the spec.

- [ ] **Step 1: Write the failing tests**

Create `test/state/follow_providers_test.dart`:

```dart
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('follow holds one vehicle id; stop clears it', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(followProvider), isNull);
    c.read(followProvider.notifier).follow('2573');
    expect(c.read(followProvider), const FollowTarget('2573'));
    c.read(followProvider.notifier).follow('1311');
    expect(c.read(followProvider), const FollowTarget('1311'), reason: 'a new follow replaces the old one');
    c.read(followProvider.notifier).stop();
    expect(c.read(followProvider), isNull);
  });
}
```

Add to `test/ui/arrival_row_tile_test.dart`, using that file's existing row fixtures and host:
- A live row with a vehicle number, given `onTap`, calls it when tapped. Its semantics node has the button flag and an `onTapHint` of "follow bus <n> on the map".
- A row given `onTap: null` has no tap action.

Add to `test/ui/arrival_board_screen_test.dart`, following that file's existing harness and fakes:
- Tapping a live row whose `vehicleNumber` is `'2573'` sets `followProvider` to `FollowTarget('2573')` and navigates to `/map`. Add a `GoRoute('/map')` that shows `Text('MAP')` to the test router.
- A scheduled-only row (not live, or no vehicle number) is not tappable.

Add to `test/ui/map_cards_test.dart`:
- `BusCardBody` shows a *Follow* button.
- Tapping it sets `followProvider` to the card's vehicle, and clears `mapSelectionProvider`.

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/state/follow_providers_test.dart test/ui/arrival_row_tile_test.dart test/ui/arrival_board_screen_test.dart test/ui/map_cards_test.dart`
Expected: compile and test failures.

- [ ] **Step 3: Implement**

Create `lib/state/follow_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bus being followed (spec §3.5): a vehicle ID, never a route or trip.
class FollowTarget {
  const FollowTarget(this.vehicleId);
  final String vehicleId;

  @override
  bool operator ==(Object other) => other is FollowTarget && other.vehicleId == vehicleId;
  @override
  int get hashCode => vehicleId.hashCode;
}

class FollowNotifier extends Notifier<FollowTarget?> {
  @override
  FollowTarget? build() => null;

  void follow(String vehicleId) => state = FollowTarget(vehicleId);
  void stop() => state = null;
}

/// App-wide so the Board can start a follow; only the map acts on it.
final followProvider = NotifierProvider<FollowNotifier, FollowTarget?>(FollowNotifier.new);
```

**`ArrivalRowTile`.** Add `this.onTap` (a `VoidCallback?`) to the constructor. Pass it to the `BBCard` (`BBCard(onTap: onTap, …)`). On the outer `Semantics`, add `button: onTap != null ? true : null` and `onTapHint: onTap == null ? null : 'follow bus ${a.vehicleNumber} on the map'`. If `excludeSemantics: true` on that node swallows `BBCard`'s tap action for screen readers, add `onTap: onTap` on the same `Semantics` too.

**Board screen.** In `arrival_board_screen.dart`'s `itemBuilder`:

```dart
          child: ArrivalRowTile(
            arrival: _arrivals[index - leading],
            onTap: _followable(_arrivals[index - leading]),
          ),
```

and add to the state class:

```dart
  /// A live row with a known vehicle follows that bus on the map (spec §3.5);
  /// scheduled-only rows are not tappable.
  VoidCallback? _followable(ArrivalRow a) {
    final vehicle = a.vehicleNumber;
    if (!a.isLive || vehicle == null || vehicle.isEmpty) return null;
    return () {
      ref.read(followProvider.notifier).follow(vehicle);
      context.go('/map');
    };
  }
```

Import `../../state/follow_providers.dart`.

**Bus card.** In `bus_card.dart`, in `_BusCardBodyState.build`, add this before the *Technical details* toggle:

```dart
          BBButton(
            label: 'Follow',
            icon: BBIcons.bus,
            expand: true,
            onPressed: () {
              ref.read(mapSelectionProvider.notifier).clear();
              ref.read(followProvider.notifier).follow(widget.vehicleId);
            },
          ),
          const SizedBox(height: BBSpace.m),
```

Import `../../state/follow_providers.dart` and `../../state/map_providers.dart`.

- [ ] **Step 4: Run, analyze, commit**

Run: `flutter test test/state/ test/ui/ && flutter analyze lib test`
Expected: PASS, no issues.

```bash
git add lib/state/follow_providers.dart lib/ui/board/arrival_row_tile.dart lib/ui/board/arrival_board_screen.dart lib/ui/map/bus_card.dart \
  test/state/follow_providers_test.dart test/ui/arrival_row_tile_test.dart test/ui/arrival_board_screen_test.dart test/ui/map_cards_test.dart
git commit -m "feat(map): follow a bus from a live Board row or its bus card"
```

---

### Task 4: Route line and followed-bus emphasis on the map

**Files:**
- Modify: `lib/ui/map/map_surface.dart`, `lib/ui/map/map_layers.dart`, `test/map/support/fake_map_surface.dart`
- Test: `test/map/map_layers_test.dart` (add)

**Interfaces:**
- Produces:
  - **`MapSurface`:**
    - `Future<void> addLineLayer(String sourceId, String layerId, LineLayerProperties properties)`
  - **`MapCamera`:**
    - `Future<void> fitBounds(LatLng a, LatLng b, {required EdgeInsets padding, required bool animate})`
  - **`MapLayers`:**
    - static ids `routeSource = 'bb-route'`, `routeCasingLayer = 'bb-route-casing'`, `routeLineLayer = 'bb-route-line'`
    - `Future<void> updateRoute({required List<List<double>> driven, required List<List<double>> ahead, required Color color})`
    - `Future<void> clearRoute()`
  - **`BusMarker`:**
    - new field `final MarkerEmphasis emphasis`, where `enum MarkerEmphasis { normal, followed, dimmed }`, default `normal`
  - **`busMarkers(...)`:**
    - new named param `String? followedVehicleId`: that bus is `followed`; every other bus is `dimmed` while it is set
  - **Bus feature properties:**
    - `scale`: 1.35 when followed, else 1.0
    - `opacity`: 0.35 when dimmed, else 1.0
    - `sort`: followed 2, live 1, stale 0
  - **Both bus symbol layers:**
    - `iconSize: ['get','scale']`, `iconOpacity: ['get','opacity']`

`icon-size` 1.35 scales the badge's 2 px white outline to 2.7 px, against the spec's 2.6 px. One image per route is kept, with no separate followed bitmaps. Task 7 records this in the spec.

- [ ] **Step 1: Extend the fake**

In `test/map/support/fake_map_surface.dart`, add:

```dart
  final fits = <(LatLng, LatLng, EdgeInsets, bool)>[];

  @override
  Future<void> addLineLayer(String sourceId, String layerId, LineLayerProperties p) async {
    if (layers.containsKey(layerId)) throw StateError('Layer $layerId already exists');
    calls.add('layer $layerId');
    layers[layerId] = p;
    layerMinZoom[layerId] = null;
  }

  @override
  Future<void> fitBounds(LatLng a, LatLng b, {required EdgeInsets padding, required bool animate}) async =>
      fits.add((a, b, padding, animate));
```

Import `package:flutter/widgets.dart` for `EdgeInsets`. Match how the fake's existing add methods throw "already exists". If they throw something other than `StateError`, mirror that.

- [ ] **Step 2: Write the failing tests**

Add to `test/map/map_layers_test.dart`. Its existing `_bus` helper builds a `BusTrackingState`.

```dart
  group('follow mode', () {
    test('the followed bus is emphasised and every other bus dimmed', () {
      final markers = busMarkers(
        tracking: {'a': _bus('a'), 'b': _bus('b')},
        drawn: const {},
        routeFilter: const {},
        headings: HeadingSmoother(),
        now: _now,
        followedVehicleId: 'a',
      );
      expect({for (final m in markers) m.vehicleId: m.emphasis}, {'a': MarkerEmphasis.followed, 'b': MarkerEmphasis.dimmed});
      final none = busMarkers(tracking: {'a': _bus('a')}, drawn: const {}, routeFilter: const {}, headings: HeadingSmoother(), now: _now);
      expect(none.single.emphasis, MarkerEmphasis.normal);
    });

    testWidgets('bus features carry scale, opacity and sort for the emphasis', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        await layers.updateBuses(busMarkers(
          tracking: {'a': _bus('a'), 'b': _bus('b')},
          drawn: const {},
          routeFilter: const {},
          headings: HeadingSmoother(),
          now: _now,
          followedVehicleId: 'a',
        ));
        final props = {for (final f in surface.features(MapLayers.busesSource)) f['properties']['vehicleId']: f['properties']};
        expect((props['a']['scale'], props['a']['opacity'], props['a']['sort']), (1.35, 1.0, 2));
        expect((props['b']['scale'], props['b']['opacity']), (1.0, 0.35));
      });
    });

    testWidgets('the route line sits under every other layer and splits into driven and ahead', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        final order = [for (final c in surface.calls) if (c.startsWith('layer ')) c.substring(6)];
        expect(order.take(2), [MapLayers.routeCasingLayer, MapLayers.routeLineLayer]);
        await layers.updateRoute(
          driven: const [[-52.70, 47.56], [-52.71, 47.56]],
          ahead: const [[-52.71, 47.56], [-52.72, 47.56]],
          color: RouteHue.green.line,
        );
        final f = surface.features(MapLayers.routeSource);
        expect([for (final x in f) x['properties']['part']], ['driven', 'ahead']);
        expect([for (final x in f) x['properties']['opacity']], [0.4, 1.0]);
        expect(f.first['geometry']['type'], 'LineString');
        await layers.clearRoute();
        expect(surface.features(MapLayers.routeSource), isEmpty);
      });
    });

    testWidgets('a second install also clears the route layers first', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        await layers.install(stops: const []);
        expect(surface.layers.keys.where((k) => k.startsWith('bb-route')), hasLength(2));
      });
    });
  });
```

- [ ] **Step 3: Run and watch them fail**

Run: `flutter test test/map/map_layers_test.dart`
Expected: compile errors, because `MarkerEmphasis`, `followedVehicleId`, `updateRoute` and the route ids don't exist.

- [ ] **Step 4: Implement**

**`map_surface.dart`.** Add to the interfaces:

```dart
  Future<void> addLineLayer(String sourceId, String layerId, LineLayerProperties properties);
```

on `MapSurface`, and:

```dart
  /// Shows both points with [padding] kept clear (sheet, chips).
  Future<void> fitBounds(LatLng a, LatLng b, {required EdgeInsets padding, required bool animate});
```

on `MapCamera`. Implement both in `MapLibreSurface`:

```dart
  @override
  Future<void> addLineLayer(String sourceId, String layerId, LineLayerProperties properties) =>
      controller.addLineLayer(sourceId, layerId, properties, enableInteraction: false);

  @override
  Future<void> fitBounds(LatLng a, LatLng b, {required EdgeInsets padding, required bool animate}) async {
    final bounds = LatLngBounds(
      southwest: LatLng(math.min(a.latitude, b.latitude), math.min(a.longitude, b.longitude)),
      northeast: LatLng(math.max(a.latitude, b.latitude), math.max(a.longitude, b.longitude)),
    );
    final update = CameraUpdate.newLatLngBounds(bounds, left: padding.left, top: padding.top, right: padding.right, bottom: padding.bottom);
    if (animate) {
      await controller.animateCamera(update);
    } else {
      await controller.moveCamera(update);
    }
  }
```

Add `import 'dart:math' as math;` and `import 'package:flutter/widgets.dart' show EdgeInsets;`.

**`map_layers.dart`:**
1. **`MarkerEmphasis` and `BusMarker`.** Add `enum MarkerEmphasis { normal, followed, dimmed }`, and `this.emphasis = MarkerEmphasis.normal` and `final MarkerEmphasis emphasis;` to `BusMarker`.
2. **`busMarkers`.** Add `String? followedVehicleId` and set `emphasis: followedVehicleId == null ? MarkerEmphasis.normal : (id == followedVehicleId ? MarkerEmphasis.followed : MarkerEmphasis.dimmed)`.
3. **`_busFeature`.** Add these properties:

```dart
      'scale': m.emphasis == MarkerEmphasis.followed ? 1.35 : 1.0,
      'opacity': m.emphasis == MarkerEmphasis.dimmed ? 0.35 : 1.0,
      'sort': m.emphasis == MarkerEmphasis.followed ? 2 : (m.stale ? 0 : 1),
```

   Also add `iconSize: [Expressions.get, 'scale'], iconOpacity: [Expressions.get, 'opacity']` to both the notch and badge `SymbolLayerProperties`. They are `const` today. Expression lists are still const-constructible, so keep `const` if the analyzer allows it.
4. **Route line.** Add the ids, install the route source and its two layers first, and include them in the clearing lists:

```dart
  static const routeSource = 'bb-route';
  static const routeCasingLayer = 'bb-route-casing';
  static const routeLineLayer = 'bb-route-line';
```

   In `install`, remove-lists become `[badgeLayer, notchLayer, myStopLayer, stopsLayer, routeLineLayer, routeCasingLayer]` and `[busesSource, myStopSource, stopsSource, routeSource]`. Right after the removals and image registration, before the stops source, add:

```dart
    await surface.addGeoJsonSource(routeSource, _collection(const []));
    await surface.addLineLayer(
      routeSource,
      routeCasingLayer,
      LineLayerProperties(
        lineColor: _hex(RoutePalette.ink),
        lineWidth: 9.0,
        lineOpacity: [Expressions.multiply, 0.3, [Expressions.get, 'opacity']],
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await surface.addLineLayer(
      routeSource,
      routeLineLayer,
      const LineLayerProperties(
        lineColor: [Expressions.get, 'color'],
        lineWidth: 6.0,
        lineOpacity: [Expressions.get, 'opacity'],
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
```

   If `Expressions.multiply` doesn't exist in maplibre_gl 0.27.1, use the literal `'*'`.

   Then add the update methods:

```dart
  /// The followed trip's line (spec §3.2): the part already driven at 40%.
  Future<void> updateRoute({required List<List<double>> driven, required List<List<double>> ahead, required Color color}) {
    Map<String, dynamic> line(List<List<double>> coords, String part, double opacity) => {
          'type': 'Feature',
          'geometry': {'type': 'LineString', 'coordinates': coords},
          'properties': {'part': part, 'opacity': opacity, 'color': _hex(color)},
        };
    return surface.setGeoJsonSource(routeSource, _collection([line(driven, 'driven', 0.4), line(ahead, 'ahead', 1.0)]));
  }

  Future<void> clearRoute() => surface.setGeoJsonSource(routeSource, _collection(const []));
```

- [ ] **Step 5: Run, analyze, commit**

Run: `flutter test test/map/ test/ui/ && flutter analyze lib test`
Expected: PASS, no issues. The existing install-order test now sees two route layers before the stops layer, so update its expected list to `[routeCasingLayer, routeLineLayer, stopsLayer, myStopLayer, notchLayer, badgeLayer]`.

```bash
git add lib/ui/map/map_surface.dart lib/ui/map/map_layers.dart test/map/support/fake_map_surface.dart test/map/map_layers_test.dart
git commit -m "feat(map): followed route line and followed/dimmed bus markers"
```

---

### Task 5: The follow card

**Files:**
- Create: `lib/ui/map/follow_card.dart`
- Test: `test/ui/follow_card_test.dart`; extend `test/ui/screen_overflow_test.dart`

**Interfaces:**
- Consumes:
  - `FollowSnapshot`, `TripStop` (Tasks 1–2)
  - `delayText` and `agoText` from `bus_card.dart`
  - `busLabel` from `map_layers.dart`
- Produces (plain widgets, no providers):
  - `FollowCardHeader({required FollowSnapshot snapshot, required String? yourStopName, required int? minutesToYourStop, required String? tripHeadsign, required VoidCallback onStop, required VoidCallback onSeeAll})`
  - `FollowCardBody({required FollowSnapshot snapshot})`: the all-stops timeline.
  - `String stopsToGoText(int? stopsTo, String? yourStopName)`
  - `String etaText(TripStop stop, int? schedDiffMins)`

**Copy:**

| State | Text |
|---|---|
| Stops to go | "2 stops to MUN Centre" / "1 stop to MUN Centre" / "Next stop: MUN Centre" (0, not arrived) |
| Stop not on this trip | "Your stop isn't on this trip" |
| Arrived | "Arrived at MUN Centre" |
| Finding | "Finding bus 2573…" (bus null, not ended) |
| Stale | the subtitle is "Bus 2573 · Last seen 1 min ago" |
| Buttons | *Stop following* (quiet) and *See all stops* (primary) |

**Behaviour:**
- **Stops-to-go line:** it sits in `Semantics(liveRegion: true, label: …)`. Its text changes only when the stop count changes, so it is announced at most once per stop (spec §3.5).
- **Minutes to your stop:** when non-null, show "N min" (or "Now" at 0) on the right of the header, in `soon` colour at 5 min or less.
- **Stop strip:** at most 7 dots, as a single `Row`:
  - the last driven stop, muted;
  - the bus, a `BBGlyph(BBGlyphKind.bus)` in the route line colour;
  - upcoming stops, as rings;
  - your stop, as a brand star.
  - It is excluded from semantics; the stops line says the same.
- **Timeline (body):**
  - Starting after `busIndex`, one row per stop: name, then ETA as "12:05" when the delay is known, or "12:03 sched".
  - Your stop's row is emphasised: brand colour, star, and the label "Your stop".
  - When `yourStopIndex` is null, it shows only the next 6 stops.

- [ ] **Step 1: Write the failing tests**

Create `test/ui/follow_card_test.dart`. Host it like `test/ui/map_cards_test.dart` does: a `MaterialApp` in the Harbour theme around a `CustomScrollView`, with no providers needed. Use this snapshot builder:

```dart
FollowSnapshot _snap({int busIndex = 0, int? yourIndex = 2, int? toGo = 2, bool arrived = false, bool stale = false, bool found = true, int? schedDiff = -1}) =>
    FollowSnapshot(
      vehicleId: '2573',
      bus: found ? _bus(stale: stale, schedDiff: schedDiff) : null,
      tripId: 't1',
      stale: stale,
      lastSeenAgo: stale ? const Duration(seconds: 75) : const Duration(seconds: 10),
      stops: _stops, // the four stops a, b, mun, c from Task 2's test, departures 12:00, 12:01, 12:02, 12:03
      busIndex: busIndex,
      yourStopIndex: yourIndex,
      stopsToYourStop: toGo,
      arrived: arrived,
      ended: null,
    );
```

Tests:
- **Copy helpers:** `stopsToGoText` gives `(2,'MUN Centre')` → "2 stops to MUN Centre", `(1, …)` → "1 stop to …", `(0, …)` → "Next stop: MUN Centre", `(null, …)` → "Your stop isn't on this trip".
- **`etaText`:** a stop at 43320 s (12:02) with schedDiff −1 (1 min late) → "12:03". With schedDiff null → "12:02 sched".
- **Header (normal):** shows "to Downtown", "Bus 2573 · 1 min late", "2 stops to MUN Centre" and "4 min" when `minutesToYourStop: 4`. The stops line is a live-region semantics node: `tester.getSemantics(find.text('2 stops to MUN Centre'))` has the `isLiveRegion` flag.
- **Header states:**
  - stale → "Bus 2573 · Last seen 1 min ago";
  - found false → "Finding bus 2573…";
  - arrived → "Arrived at MUN Centre".
- **Buttons:** tapping *Stop following* and *See all stops* calls the callbacks.
- **Body:** lists b, MUN Centre and c (not a, already driven) with their ETAs, and MUN Centre's row carries "Your stop".
- **Body, stop not on the trip:** given 10 stops and `yourStopIndex: null`, it shows exactly the next 6 after `busIndex` ("next six stops when your stop isn't on the trip").

Extend `test/ui/screen_overflow_test.dart` with the follow card (header plus body, 8 stops with long names) at 320 and 360 pt and text ×2.0.

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/ui/follow_card_test.dart`
Expected: a compile error, because `follow_card.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/ui/map/follow_card.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../../domain/map/follow_tracker.dart';
import '../../domain/map/route_geometry.dart';
import '../kit/kit.dart';
import 'bus_card.dart';
import 'map_layers.dart';

String stopsToGoText(int? stopsTo, String? yourStopName) {
  final name = yourStopName ?? 'your stop';
  return switch (stopsTo) {
    null => "Your stop isn't on this trip",
    0 => 'Next stop: $name',
    1 => '1 stop to $name',
    _ => '$stopsTo stops to $name',
  };
}

/// Scheduled departure shifted by the current delay (positive diff = early);
/// "sched" when the delay is unknown.
String etaText(TripStop stop, int? schedDiffMins) {
  final s = stop.departureSeconds;
  if (s == null) return '';
  final shifted = s - (schedDiffMins ?? 0) * 60;
  final h = (shifted ~/ 3600) % 24;
  final m = (shifted % 3600) ~/ 60;
  final clock = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  return schedDiffMins == null ? '$clock sched' : clock;
}

/// Follow card at peek (spec §3.5): who, where to, how far from your stop,
/// a stop strip, and the two actions.
class FollowCardHeader extends StatelessWidget {
  const FollowCardHeader({
    super.key,
    required this.snapshot,
    required this.yourStopName,
    required this.minutesToYourStop,
    required this.tripHeadsign,
    required this.onStop,
    required this.onSeeAll,
  });

  final FollowSnapshot snapshot;
  final String? yourStopName;
  final int? minutesToYourStop;
  final String? tripHeadsign;
  final VoidCallback onStop;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final bus = snapshot.bus;
    final id = snapshot.vehicleId;
    if (bus == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Finding bus $id…', style: bb.text.headline),
            const SizedBox(height: BBSpace.m),
            BBButton(label: 'Stop following', kind: BBButtonKind.quiet, expand: true, onPressed: onStop),
          ],
        ),
      );
    }
    final headsign = bus.headsign.isNotEmpty ? bus.headsign : tripHeadsign;
    final delay = delayText(bus.schedDiffMins);
    final subtitle = snapshot.stale
        ? 'Bus $id · Last seen ${agoText(snapshot.lastSeenAgo ?? Duration.zero).replaceFirst(' ago', '')} ago'
        : (delay.isEmpty ? 'Bus $id' : 'Bus $id · $delay');
    final line = snapshot.arrived ? 'Arrived at ${yourStopName ?? 'your stop'}' : stopsToGoText(snapshot.stopsToYourStop, yourStopName);
    final minutes = minutesToYourStop;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RouteBadge.name(busLabel(bus)),
              const SizedBox(width: BBSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headsign == null || headsign.isEmpty ? 'Route ${busLabel(bus)}' : 'to $headsign',
                        style: bb.text.headline, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(subtitle, style: bb.text.caption),
                  ],
                ),
              ),
              if (minutes != null && !snapshot.arrived) ...[
                const SizedBox(width: BBSpace.s),
                Text(minutes <= 0 ? 'Now' : '$minutes min',
                    style: bb.text.headline.copyWith(color: minutes <= 5 ? bb.colors.soon : bb.colors.ink)),
              ],
            ],
          ),
          const SizedBox(height: BBSpace.s),
          Semantics(liveRegion: true, label: line, excludeSemantics: true, child: Text(line, style: bb.text.body)),
          const SizedBox(height: BBSpace.s),
          ExcludeSemantics(child: _StopStrip(snapshot: snapshot, routeLabel: busLabel(bus))),
          const SizedBox(height: BBSpace.m),
          BBButton(label: 'See all stops', expand: true, onPressed: onSeeAll),
          const SizedBox(height: BBSpace.s),
          BBButton(label: 'Stop following', kind: BBButtonKind.quiet, expand: true, onPressed: onStop),
        ],
      ),
    );
  }
}

class _StopStrip extends StatelessWidget {
  const _StopStrip({required this.snapshot, required this.routeLabel});

  final FollowSnapshot snapshot;
  final String routeLabel;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final stops = snapshot.stops;
    if (stops.isEmpty) return const SizedBox.shrink();
    final from = (snapshot.busIndex).clamp(0, stops.length - 1);
    final until = snapshot.yourStopIndex ?? (from + 5).clamp(0, stops.length - 1);
    final end = until.clamp(from, (from + 6).clamp(0, stops.length - 1));
    final line = RoutePalette.ofName(routeLabel).line;
    Widget dot(Color color, {bool ring = false}) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: ring ? null : color,
            border: ring ? Border.all(color: color, width: 2) : null,
            shape: BoxShape.circle,
          ),
        );
    final children = <Widget>[];
    for (var i = from; i <= end; i++) {
      if (i > from) children.add(Expanded(child: Container(height: 2, color: i <= snapshot.busIndex ? bb.colors.line : line)));
      final isYours = i == snapshot.yourStopIndex;
      children.add(isYours
          ? Icon(BBIcons.star, size: 16, color: bb.colors.brand)
          : dot(i <= snapshot.busIndex ? bb.colors.muted : line, ring: i > snapshot.busIndex));
      if (i == snapshot.busIndex) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: BBSpace.xs),
          child: BBGlyph(BBGlyphKind.bus, size: 18, color: line),
        ));
      }
    }
    return SizedBox(height: 20, child: Row(children: children));
  }
}

/// See all stops (spec §3.5): from the bus to the end of its trip, ETAs from
/// the timetable shifted by the current delay; your stop emphasised. When your
/// stop isn't on this trip, the next six stops.
class FollowCardBody extends StatelessWidget {
  const FollowCardBody({super.key, required this.snapshot});

  final FollowSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final start = snapshot.busIndex + 1;
    final all = snapshot.stops;
    final upcoming = start >= all.length ? const <TripStop>[] : all.sublist(start);
    final shown = snapshot.yourStopIndex == null ? upcoming.take(6).toList() : upcoming;
    final diff = snapshot.bus?.schedDiffMins;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BBSectionHeader(title: 'Stops'),
          for (var k = 0; k < shown.length; k++)
            _TimelineRow(
              stop: shown[k],
              eta: etaText(shown[k], diff),
              yours: start + k == snapshot.yourStopIndex,
            ),
          if (shown.isEmpty) Text('No more stops on this trip', style: bb.text.caption),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.stop, required this.eta, required this.yours});

  final TripStop stop;
  final String eta;
  final bool yours;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final style = yours ? bb.text.label.copyWith(color: bb.colors.brandInk) : bb.text.body;
    return Semantics(
      label: '${stop.name}${yours ? ', your stop' : ''}, $eta',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BBSpace.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 20, child: yours ? Icon(BBIcons.star, size: 16, color: bb.colors.brand) : null),
            const SizedBox(width: BBSpace.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stop.name, style: style),
                  if (yours) Text('Your stop', style: bb.text.caption),
                ],
              ),
            ),
            const SizedBox(width: BBSpace.s),
            Text(eta, style: bb.text.caption),
          ],
        ),
      ),
    );
  }
}
```

`Container(decoration: BoxDecoration(shape: BoxShape.circle))` is from widgets and painting, so the kit guard allows it. The 3a ledger notes raw `BoxShape.circle` dots as a deferred minor. Use the kit's dot component if one exists by now. Make the stale subtitle read exactly "Last seen 1 min ago" for 75 s: `agoText` gives "1 min ago", so build the string directly as `'Bus $id · Last seen ${agoText(...)}'` rather than with the `replaceFirst` dance above.

- [ ] **Step 4: Run, analyze, commit**

Run: `flutter test test/ui/follow_card_test.dart test/ui/screen_overflow_test.dart && flutter analyze lib test`
Expected: PASS, no issues.

```bash
git add lib/ui/map/follow_card.dart test/ui/follow_card_test.dart test/ui/screen_overflow_test.dart
git commit -m "feat(map): follow card — stops to your stop, stop strip, all-stops timeline"
```

---

### Task 6: Following on the map screen

**Files:**
- Create: `lib/ui/map/follow_camera.dart`
- Modify: `lib/ui/map/map_screen.dart`
- Test: `test/map/follow_camera_test.dart`, `test/ui/map_screen_test.dart` (add a group)

**Interfaces:**
- Consumes:
  - `followProvider` (Task 3)
  - `FollowTracker` / `FollowSnapshot` / `FollowEnd` (Task 2)
  - `RouteGeometry.tripStops` / `splitShape` via `routeGeometryProvider`
  - `MapLayers.updateRoute` / `clearRoute` and `busMarkers(followedVehicleId:)` (Task 4)
  - `MapCamera.fitBounds` (Task 4)
  - `FollowCardHeader` / `FollowCardBody` (Task 5)
  - `stopArrivalsProvider` (3b-2)
  - `BBToast.show(context, message)`
- Produces:
  - `sealed class CameraMove`, with two cases: `FitMove(LatLng bus, LatLng stop)` and `CenterMove(LatLng target, double zoom)`.
  - `class FollowCamera { static const interval = Duration(seconds: 1); static const closeMeters = 250.0; static const nearZoom = 16.5; static const soloZoom = 15.5; CameraMove? next({required LatLng bus, LatLng? stop, required DateTime now}); void reset(); }`

**Screen behaviour:**
- **Starting a follow.** When `followProvider` becomes non-null:
  - make a `FollowTracker(vehicleId, stopsFor: geometry.tripStops)` and a `FollowCamera`;
  - clear `mapSelectionProvider`;
  - set `paused = false`.
  - The sheet re-keys to `'follow:<id>'`, shows `FollowCardHeader` and `FollowCardBody`, and opens at peek.
  - When `followProvider` becomes null: drop the tracker, clear the route, and stop moving the camera.
- **Each drawn frame while following:**
  1. Compute markers with `followedVehicleId`.
  2. Update the tracker with:
     - `bus: tracking[id]`
     - `drawnProgress: drawn[id]?.progress`
     - `yourStopId: settings.selectedStopId`
     - `now`
  3. When the snapshot differs from the last one (by `==`), `setState` it.
  4. Route line: when the snapshot's trip and shape are known and either the split moved by 20 m or more or a second has passed, `splitShape(shapeId, progress)` and then `updateRoute(color: RoutePalette.ofName(label).line)`.
  5. Camera: unless paused, `FollowCamera.next(...)`. Use the bus as drawn. Use your stop only when `yourStopIndex != null` and the bus has not arrived.
     - `FitMove` → `camera.fitBounds(bus, stop, padding: EdgeInsets.fromLTRB(48, controlsBottom + 16, 48, peekTop + 16), animate: !reduceMotion)`. Here `controlsBottom = padding.top + 8 + _controlsHeight` and `peekTop` is the screen's existing peek-top distance from the bottom.
     - `CenterMove` → `camera.moveTo(target, zoom, animate: !reduceMotion)`.
  6. On `ended`:
     - stop following (`followProvider.stop()`) and clear the route;
     - for any ending other than `arrived`, show a `BBToast` with the matching message.

     | `FollowEnd` | Toast |
     |---|---|
     | `passedYourStop` | "Bus 2573 has passed MUN Centre" |
     | `tripEnded` | "Bus 2573 has finished its trip" |
     | `lostContact` | "Lost contact with bus 2573" |
     | `notFound` | "Bus 2573 isn't reporting its position" |
- **Pause on gesture.** Wrap the map in `Listener(behavior: HitTestBehavior.translucent)`. While following, a pointer that moves more than 18 logical px from its down position sets `paused = true` (`setState`). A plain tap does not pause.
  - While paused, show a `BBChip(label: 'Back to bus 2573', icon: BBIcons.bus)` centred horizontally, just above the peeking sheet's top. Tapping it sets `paused = false`, `FollowCamera.reset()`, and moves the camera immediately on the next frame.
- **Top chip.** While following, the left chip becomes `BBChip(leading: BBGlyph(BBGlyphKind.liveDot, size: 12, color: bb.colors.live), label: 'Following bus 2573')`. Tapping it resumes, as the Back chip does, and collapses the sheet to peek.
- **Taps while following.** Bus and stop taps are ignored. A tap on empty map collapses the sheet to peek.
- **Your stop's minutes.** Watch `stopArrivalsProvider(selectedStopId)` and find the row whose `vehicleNumber == id`. Pass its `minutesAway`, or null.
- **Trip headsign.** If the bus has none, use `repo.tripsById[snapshot.tripId]?.tripHeadsign`.

- [ ] **Step 1: Write the failing camera test**

Create `test/map/follow_camera_test.dart`:

```dart
import 'package:busboard_nl/ui/map/follow_camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

final _t0 = DateTime(2026, 10, 5, 12);

void main() {
  const bus = LatLng(47.5600, -52.7100);
  const farStop = LatLng(47.5700, -52.7300);
  const nearStop = LatLng(47.5605, -52.7102);

  test('fits the bus and your stop when they are apart', () {
    final move = FollowCamera().next(bus: bus, stop: farStop, now: _t0);
    expect(move, isA<FitMove>());
  });

  test('zooms in on the bus as it reaches your stop', () {
    final move = FollowCamera().next(bus: bus, stop: nearStop, now: _t0) as CenterMove;
    expect(move.zoom, FollowCamera.nearZoom);
  });

  test('centres on the bus alone when there is no stop to show', () {
    final move = FollowCamera().next(bus: bus, stop: null, now: _t0) as CenterMove;
    expect((move.target, move.zoom), (bus, FollowCamera.soloZoom));
  });

  test('moves at most once a second; reset allows an immediate move', () {
    final cam = FollowCamera();
    expect(cam.next(bus: bus, stop: farStop, now: _t0), isNotNull);
    expect(cam.next(bus: bus, stop: farStop, now: _t0.add(const Duration(milliseconds: 500))), isNull);
    expect(cam.next(bus: bus, stop: farStop, now: _t0.add(const Duration(seconds: 1))), isNotNull);
    cam.reset();
    expect(cam.next(bus: bus, stop: farStop, now: _t0.add(const Duration(milliseconds: 1100))), isNotNull);
  });
}
```

- [ ] **Step 2: Implement `FollowCamera`**

Create `lib/ui/map/follow_camera.dart`:

```dart
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../domain/location/nearest_stop_service.dart';

sealed class CameraMove {
  const CameraMove();
}

class FitMove extends CameraMove {
  const FitMove(this.bus, this.stop);
  final LatLng bus;
  final LatLng stop;
}

class CenterMove extends CameraMove {
  const CenterMove(this.target, this.zoom);
  final LatLng target;
  final double zoom;
}

/// Where the follow camera goes (spec §3.5): the bus and your stop in view,
/// closing in as the bus arrives; at most one move a second.
class FollowCamera {
  static const interval = Duration(seconds: 1);
  static const double closeMeters = 250;
  static const double nearZoom = 16.5;
  static const double soloZoom = 15.5;

  DateTime? _last;

  void reset() => _last = null;

  CameraMove? next({required LatLng bus, LatLng? stop, required DateTime now}) {
    final last = _last;
    if (last != null && now.difference(last) < interval) return null;
    _last = now;
    if (stop == null) return CenterMove(bus, soloZoom);
    final d = NearestStopService.haversineDistance(bus.latitude, bus.longitude, stop.latitude, stop.longitude);
    if (d < closeMeters) {
      return CenterMove(LatLng((bus.latitude + stop.latitude) / 2, (bus.longitude + stop.longitude) / 2), nearZoom);
    }
    return FitMove(bus, stop);
  }
}
```

Run: `flutter test test/map/follow_camera_test.dart`
Expected: PASS.

- [ ] **Step 3: Write the failing screen tests**

Add a `group('follow mode', …)` to `test/ui/map_screen_test.dart`, using that file's existing stub map, `FakeMapSurface`, timed pumps and `tester.runAsync` interleaving for marker images. Drive `busTrackingStreamProvider` with a `StreamController` so tests can push updates. Override `routeGeometryProvider` with a `RouteGeometry` over a small repo that gives bus `2573`'s trip three stops including `1150`, or reuse `outAndBackRepo()` with your stop set to one of its stops.

The tests:
1. Setting `followProvider` to `2573` (through the container) shows "Following bus 2573" and the follow card ("stops to"). The sheet shows no stop or bus card.
2. A drag of 60 px on the stub map (`tester.dragFrom` on the stub's rect) shows "Back to bus 2573", and no further `fits` or `moves` reach the fake. Tapping the chip resumes, and a camera move follows within the next frames.
3. While following, the fake surface has a `bb-route` source with two features.
4. Reduce Motion (`MediaQuery(disableAnimations: true)`) gives `animate: false` on the recorded camera moves.
5. "a stale followed bus shows Last seen": push the bus with `status: BusStatus.stale` and `lastGpsTime` 75 s ago, and the card shows "Last seen 1 min ago".
6. Push the bus with a different `currentTripId`. A toast "Bus 2573 has finished its trip" appears, `followProvider` is null, and the route source is empty.
7. "after following ends, the camera stops and the Back chip goes": pan to pause, then end the follow by pushing a trip change. Afterwards there is no "Back to bus" chip and no new camera calls.
8. While following, a tap near a stop does not open a stop card.

- [ ] **Step 4: Integrate into `map_screen.dart`**

Implement the screen behaviour described above.
- **Keep `map_screen.dart` readable.** Put the follow state in a private `_Follow` holder class: tracker, camera, paused, last snapshot, last route update. Put the follow parts of `build` in small private methods: `_followChip`, `_backChip` and the follow sheet content.
- **One frame loop.** `_drawFrame` stays the one place that calls `renderAll`, and stays single-flight. Follow work runs inside it after `updateBuses`.
- **`setState` only on change.** Call `setState` for a snapshot only when it differs (`!=`).

- [ ] **Step 5: Run, analyze, commit**

Run: `flutter test test/map/ test/ui/ test/state/ test/kit/ && flutter analyze lib test`
Expected: PASS, no issues.

```bash
git add lib/ui/map/follow_camera.dart lib/ui/map/map_screen.dart test/map/follow_camera_test.dart test/ui/map_screen_test.dart
git commit -m "feat(map): follow mode on the map — camera, pause and Back chip, follow card, endings"
```

---

### Task 7: The followed vehicle never changes over a replay, and docs

**Files:**
- Create: `test/map/follow_replay_test.dart`
- Modify:
  - `README.md` (follow mode in the Live Map bullets)
  - `docs/superpowers/specs/2026-10-04-harbour-phase3-design.md` (§3.5 and §3.2 amendments)

**Interfaces:**
- Consumes: the replay harness in `test/map/motion_replay_test.dart` and `test/map/support/replay_clock.dart`; `BusTrackStore`, `DelayedTrackRenderer`, `busMarkers(followedVehicleId:)` and `FollowTracker`.

- [ ] **Step 1: Write the replay test**

Create `test/map/follow_replay_test.dart`. Load `test/fixtures/timetrack/replay_2026-10-04_22bus/` exactly the way `motion_replay_test.dart` does, using `ReplayClock` for timezone-independent times. Pick the vehicle that appears in the most frames. Then replay at 120 ms frames, as that test does. At every frame:
- build `busMarkers(..., followedVehicleId: v)`;
- assert that exactly zero or one marker has `MarkerEmphasis.followed`, and that its `vehicleId == v`;
- update a `FollowTracker(vehicleId: v, stopsFor: geometry.tripStops)` with `tracking[v]` (or null) and `drawn[v]?.progress`;
- assert `snapshot.vehicleId == v`, and `snapshot.bus == null || snapshot.bus!.vehicleId == v`.

Count the frames where `snapshot.bus != null` and assert that count is greater than 0. That proves the test exercised a real follow.

Run: `TZ=UTC flutter test test/map/follow_replay_test.dart && flutter test test/map/follow_replay_test.dart`
Expected: PASS in both timezones.

- [ ] **Step 2: Docs**

In `README.md`'s Live Map bullets, add follow mode:
- following starts from **Follow** on a bus card, or by tapping a live Board row;
- the route line and the emphasised bus;
- the camera keeps the bus and your stop in view, and a pan pauses it ("Back to bus");
- the follow card: stops to your stop, the stop strip, and *See all stops*;
- the endings.

In the spec's §3.5, add these amendments, each marked *(Amended in 3b-3)*:
- **State:** "`followProvider` is app-wide (the Board starts a follow from another tab); only the map acts on it."
- **Taps while following:** "While following, taps on other buses and stops are ignored; a tap on empty map collapses the card."
- **Not found:** "A bus that never appears in the map feed within 60 s ends the follow with a toast."

In §3.2, add: "Followed bus: `icon-size` 1.35, which scales the 2 px outline to 2.7 px; one bitmap per route. *(Amended in 3b-3.)*"

- [ ] **Step 3: Full suite, analyze, commit**

Run: `flutter analyze lib test && TZ=UTC flutter test && flutter test`
Expected: all pass, no issues.

```bash
git add test/map/follow_replay_test.dart README.md docs/superpowers/specs/2026-10-04-harbour-phase3-design.md
git commit -m "test(map): followed vehicle never changes over a replay; docs for follow mode"
```

---

## After the last task (controller)

- **Live parity, on both the iOS simulator and the Android emulator** (buses run from about 06:30 NDT):
  - follow from a bus card and from a Board row;
  - the route line in the route colour, with the driven part faded;
  - the followed bus larger and the other buses faded;
  - the camera keeps the bus and your stop in view and closes in as the bus nears;
  - a pan shows "Back to bus N", and tapping it resumes;
  - arrival shows "Arrived at …" and then ends;
  - *Stop following* clears everything.
  - Check light and dark mode, and text ×2.0.
- **Rush-hour fixture:** turn `test/fixtures/timetrack/capture_2026-10-05.json` into a replay fixture with `tool/build_replay_fixture.py --start <rush minute> --minutes 10`, and check that both replay tests pass on it. Also read the scheduled monitor's `DIAGNOSIS_2026-10-05.md` if it exists.
