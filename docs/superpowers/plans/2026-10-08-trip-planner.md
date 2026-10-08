# Trip Planner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An on-device trip planner (Leave now / Leave by / Arrive by at an exact minute, a stop or a map pin at each end) and saved trips with their next departures, for BusBoard NL 1.4.0.

**Architecture:** A pure-Dart engine in `lib/domain/trip_planner/` builds a per-service-day timetable index from the GTFS already in `GtfsRepository` and searches it with RAPTOR (forward for Leave by, reverse for Arrive by, at most 4 rides). Live GTFS-RT times overlay ride legs within the next hour, and a transfer they make too tight is planned again. Riverpod providers build the index in a background isolate. The UI adds a Plan tab, a journey detail, saved-trip cards, a map long-press sheet and a stop-card button.

**Tech Stack:** Flutter / Dart 3, Riverpod 3, go_router, maplibre_gl, shared_preferences (`SharedPreferencesAsync`), package:collection, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-08-trip-planner-design.md`

## Global Constraints

- Everything is worked out on the phone: no server, no paid maps or directions service, no address-search service, no account, no API keys. The only network use is the live GTFS-RT feed the app already reads (`TimeTrackApi.fetchLiveVehiclesResult`).
- Places are stops (by number, name, near me or on the map) or a pin dropped on the map. No street addresses.
- Walking: straight-line distance × 1.3 at 4.5 km/h, rounded up to the minute. Access/egress ≤ 800 m; transfer walk ≤ 400 m; a same-stop transfer needs ≥ 1 min. A `transfers.txt` `min_transfer_time` overrides the computed time; `transfer_type` 3 removes the link.
- Search: at most 4 rides (3 transfers). Show 3–5 results, chosen by earliest arrival, fewest rides and least walking, with no near-duplicates.
- Live times only for ride legs departing within 60 min, under the alert freshness rules: a fix under 5 min old, a known delay, and a visit within 15 min of the timetable.
- No shown plan has a transfer under 1 minute.
- Saved trips: up to 10, stored on the phone, ends and name only.
- A search takes < 100 ms once the index is built; the index builds in < 1 s, off the main thread.
- Accessibility: every new control has a screen-reader label; nothing overflows at 2× text.
- The arrival-alerts code (`lib/domain/arrival_alerts/`, `lib/platform/`) keeps behaving exactly as today.
- Never stage `analysis_options.yaml`, `tool/capture_raw_gtfsrt.dart`, anything under `test/fixtures/timetrack/` or `build/`. Never use bare `git stash`.
- Every commit message ends with exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Every task: `flutter analyze lib test tool` clean, the task's tests passing, and the full `flutter test` passing before its commit.

## Review Focus

1. **A query just after midnight** (Leave by 00:10) must find the late trips of the previous service day (times ≥ 24:00), not report "no buses". Pinned in Tasks 3, 4 and 6.
2. **A pin with no stop within 800 m** must give the "too far" state, saying which end, not an empty list or a crash. Pinned in Task 6.
3. **The same stop as From and To** must give no journey (not a zero-minute ride, not a crash). Pinned in Tasks 4 and 6.
4. **A live feed that lists the trip but not the leg's stop** must keep the timetable time for that end of the leg. Pinned in Task 9.
5. **A saved-trip store with a corrupt or old entry** must skip that entry and keep the rest. Pinned in Task 10.

---

### Task 1: Read `transfers.txt`

**Files:**
- Modify: `lib/data/gtfs/gtfs_models.dart` (add `TransferRule`)
- Modify: `lib/data/gtfs/gtfs_parser.dart` (add `parseTransfers`; strip a BOM from header names)
- Modify: `lib/data/gtfs/gtfs_repository.dart` (add `transfersByFromStop`, fill it in `loadFromDirectory`)
- Test: `test/gtfs_transfers_test.dart`

**Interfaces:**
- Produces: `class TransferRule { final String fromStopId; final String toStopId; final int transferType; final int? minTransferSeconds; }` and `GtfsRepository.transfersByFromStop` (`final Map<String, List<TransferRule>>`).

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';

import 'package:busboard_nl/data/gtfs/gtfs_parser.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gtfs_transfers');
    // Metrobus files can start with a UTF-8 BOM; the first column must still be found.
    await File('${dir.path}/transfers.txt').writeAsString(
      '﻿from_stop_id,to_stop_id,transfer_type,min_transfer_time\n'
      '1150,1150,1,\n'
      '1600,1601,2,180\n'
      '1700,1701,3,\n',
    );
  });
  tearDown(() => dir.delete(recursive: true));

  test('parses every row, the BOM, an empty min time and type 3', () async {
    final rules = await GtfsParser(dir.path).parseTransfers();
    expect(rules.length, 3);
    expect(rules[0].fromStopId, '1150');
    expect(rules[0].minTransferSeconds, isNull);
    expect(rules[1].transferType, 2);
    expect(rules[1].minTransferSeconds, 180);
    expect(rules[2].transferType, 3);
  });

  test('a missing transfers.txt gives no rules', () async {
    await File('${dir.path}/transfers.txt').delete();
    expect(await GtfsParser(dir.path).parseTransfers(), isEmpty);
  });

  test('the repository indexes rules by from stop', () async {
    final repo = GtfsRepository();
    await repo.loadFromDirectory(dir.path);
    expect(repo.transfersByFromStop['1600']!.single.toStopId, '1601');
  });
}
```

If `loadFromDirectory` throws on a directory with no other GTFS files, write minimal empty `stops.txt`, `routes.txt`, `trips.txt`, `stop_times.txt`, `calendar.txt` (header lines only, copied from `build/gtfs_current/`) in `setUp` too.

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/gtfs_transfers_test.dart`
Expected: FAIL, `parseTransfers` isn't defined.

- [ ] **Step 3: Implement**

In `gtfs_models.dart`:

```dart
/// One row of transfers.txt.
class TransferRule {
  final String fromStopId;
  final String toStopId;

  /// GTFS transfer_type: 0 recommended, 1 timed, 2 needs [minTransferSeconds], 3 not possible.
  final int transferType;
  final int? minTransferSeconds;

  const TransferRule({
    required this.fromStopId,
    required this.toStopId,
    required this.transferType,
    this.minTransferSeconds,
  });
}
```

In `gtfs_parser.dart`'s `_parseCsv`, strip a BOM from header names: where the header cells are turned into strings, use `e.toString().replaceFirst('﻿', '').trim()`. Then add after `parseCalendarDates`:

```dart
  // Parse transfers.txt into TransferRule list. A missing file gives none.
  Future<List<TransferRule>> parseTransfers() async {
    final rows = await _parseCsv('transfers.txt');
    return rows
        .map((row) => TransferRule(
              fromStopId: row['from_stop_id'] ?? '',
              toStopId: row['to_stop_id'] ?? '',
              transferType: int.tryParse(row['transfer_type'] ?? '') ?? 0,
              minTransferSeconds: int.tryParse(row['min_transfer_time'] ?? ''),
            ))
        .where((t) => t.fromStopId.isNotEmpty && t.toStopId.isNotEmpty)
        .toList();
  }
```

If `_parseCsv` throws on a missing file instead of returning `[]`, guard with `if (!await File('$dir/transfers.txt').exists()) return const [];` (match how the parser names its directory field).

In `gtfs_repository.dart`, next to `calendarDates`:

```dart
  /// transfers.txt rules, by from stop.
  final Map<String, List<TransferRule>> transfersByFromStop = {};
```

and in `loadFromDirectory`, after the calendar dates are parsed:

```dart
    transfersByFromStop.clear();
    for (final t in await parser.parseTransfers()) {
      transfersByFromStop.putIfAbsent(t.fromStopId, () => []).add(t);
    }
```

- [ ] **Step 4: Run the test and the existing GTFS tests**

Run: `flutter test test/gtfs_transfers_test.dart test/gtfs_routes_for_stop_test.dart test/gtfs_time_test.dart test/gtfs_download_test.dart`
Expected: PASS. The BOM change must not break any existing test.

- [ ] **Step 5: Commit**

```bash
git add lib/data/gtfs/gtfs_models.dart lib/data/gtfs/gtfs_parser.dart lib/data/gtfs/gtfs_repository.dart test/gtfs_transfers_test.dart
git commit -m "feat(gtfs): read transfers.txt

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Walking

**Files:**
- Create: `lib/domain/trip_planner/walking.dart`
- Test: `test/trip_planner/walking_test.dart`

**Interfaces:**
- Produces: constants `maxAccessMeters = 800.0`, `maxTransferMeters = 400.0`, `walkDetourFactor = 1.3`, `walkSpeedMetersPerSecond = 4.5 / 3.6`, `minTransferSeconds = 60`; `double haversineMeters(double lat1, double lon1, double lat2, double lon2)`; `int walkSeconds(double straightMeters)` (whole minutes, in seconds).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:busboard_nl/domain/trip_planner/walking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('haversine: 0.01339° north and 0.021821° west at 47.57° N is about 2.2 km', () {
    final d = haversineMeters(47.57337, -52.735682, 47.55998, -52.757503);
    expect(d, closeTo(2214, 15));
  });

  test('haversine: 0.004° of longitude at 47.57° N is about 300 m', () {
    expect(haversineMeters(47.57, -52.75, 47.57, -52.746), closeTo(300, 3));
  });

  test('walk time: ×1.3 at 4.5 km/h, rounded up to the minute', () {
    expect(walkSeconds(0), 0);
    expect(walkSeconds(1), 60); // any walk is at least a minute
    expect(walkSeconds(300), 360); // 390 m at 1.25 m/s = 312 s → 6 min
    expect(walkSeconds(400), 420); // 520 m → 416 s → 7 min
    expect(walkSeconds(800), 840); // 1040 m → 832 s → 14 min
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/trip_planner/walking_test.dart`
Expected: FAIL, the file doesn't exist.

- [ ] **Step 3: Implement**

```dart
import 'dart:math' as math;

/// The farthest a rider walks to their first stop or from their last (spec §3.2).
const maxAccessMeters = 800.0;

/// The farthest a rider walks between two stops to change buses.
const maxTransferMeters = 400.0;

/// Straight-line distance × this, for the streets in between.
const walkDetourFactor = 1.3;

/// 4.5 km/h.
const walkSpeedMetersPerSecond = 4.5 / 3.6;

/// Changing buses at the same stop takes at least this long.
const minTransferSeconds = 60;

double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Walking time for a straight-line distance, in seconds, rounded up to the whole minute.
int walkSeconds(double straightMeters) {
  if (straightMeters <= 0) return 0;
  final seconds = straightMeters * walkDetourFactor / walkSpeedMetersPerSecond;
  return (seconds / 60).ceil() * 60;
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `flutter test test/trip_planner/walking_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/trip_planner/walking.dart test/trip_planner/walking_test.dart
git commit -m "feat(planner): walking distances and times

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Timetable index

**Files:**
- Create: `lib/domain/trip_planner/timetable_index.dart`
- Create: `test/trip_planner/test_network.dart` (a tiny synthetic network shared by Tasks 3–14)
- Test: `test/trip_planner/timetable_index_test.dart`

**Interfaces:**
- Consumes: `GtfsRepository` (`stopsById`, `tripsById`, `stopTimesByStopId`, `transfersByFromStop`, `activeServiceIds(DateTime)`), `GtfsTime.parse(...).totalSeconds`, Task 2's walking functions.
- Produces:

```dart
class TransitPattern {               // trips of one route on one stop sequence that never overtake each other
  final String routeId;
  final List<int> stops;             // stop indices, in order
  final List<String> tripIds;        // sorted by departure at stops[0]
  final List<List<int>> departures;  // [trip][position], seconds from the service day's midnight (may be < 0 or ≥ 86400)
  final List<List<int>> arrivals;    // [trip][position]
}
class Footpath { final int other; final int seconds; }   // the stop at the other end of a walk
class TimetableIndex {
  final DateTime serviceDate;                      // date only
  final List<String> stopIds;
  final Map<String, int> stopIndex;
  final List<TransitPattern> patterns;
  late final List<List<(int, int)>> patternsAtStop; // (pattern, position)
  late final List<List<Footpath>> footpaths;        // walks out of a stop (≤ 400 m, transfers.txt applied)
  late final List<List<Footpath>> footpathsInto;    // the same walks, listed at the stop they end at
  late final List<int> sameStopTransferSeconds;     // ≥ minTransferSeconds
  static TimetableIndex build(GtfsRepository repo, DateTime serviceDate);
}
```

- [ ] **Step 1: Write the shared test network**

`test/trip_planner/test_network.dart`:

```dart
import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';

/// A tiny Metrobus-like network, built straight into a repository (as test/ui/arrival_board_screen_test.dart does).
///
///   Route 1:  A — B — C        trips leave A every 10 min from 08:00 (6 trips), 5 min between stops
///   Route 2:        C — D — E  trips leave C every 15 min from 08:05 (4 trips), 4 min between stops
///   Route 3:  F — E            one trip, F 08:40 → E 08:50
///   Route 9:  X — Y — Z        one late trip, X 23:50 → Y 24:20 → Z 24:50 (past midnight)
/// Stop G is about 300 m from C (a 6-minute walk); H is far from everything. Service runs every day of 2026.
class TestNetwork {
  final repo = GtfsRepository();
  static const serviceId = 'WK';

  TestNetwork() {
    _stop('A', 47.5600, -52.7500);
    _stop('B', 47.5650, -52.7500);
    _stop('C', 47.5700, -52.7500);
    _stop('D', 47.5750, -52.7500);
    _stop('E', 47.5800, -52.7500);
    _stop('F', 47.5900, -52.7600);
    _stop('G', 47.5700, -52.7460);
    _stop('H', 47.5400, -52.7000);
    _stop('X', 47.5000, -52.8000);
    _stop('Y', 47.5050, -52.8000);
    _stop('Z', 47.5100, -52.8000);
    for (final r in ['1', '2', '3', '9']) {
      repo.routesById[r] = RouteInfo(routeId: r, routeShortName: r, routeLongName: 'Route $r');
    }
    for (var i = 0; i < 6; i++) {
      addTrip('1-$i', '1', ['A', 'B', 'C'], 8 * 3600 + i * 600, 300);
    }
    for (var i = 0; i < 4; i++) {
      addTrip('2-$i', '2', ['C', 'D', 'E'], 8 * 3600 + 300 + i * 900, 240);
    }
    addTrip('3-0', '3', ['F', 'E'], 8 * 3600 + 2400, 600);
    addTrip('9-0', '9', ['X', 'Y', 'Z'], 23 * 3600 + 50 * 60, 1800);
    repo.calendarsById[serviceId] = ServiceCalendar(
      serviceId: serviceId,
      monday: true,
      tuesday: true,
      wednesday: true,
      thursday: true,
      friday: true,
      saturday: true,
      sunday: true,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
    );
  }

  void _stop(String id, double lat, double lon) =>
      repo.stopsById[id] = StopInfo(stopId: id, stopName: 'Stop $id', stopLat: lat, stopLon: lon);

  /// A trip leaving its first stop at [start] seconds after midnight, [hop] seconds between stops.
  void addTrip(String tripId, String routeId, List<String> stops, int start, int hop) {
    repo.tripsById[tripId] = TripInfo(
      tripId: tripId,
      routeId: routeId,
      serviceId: serviceId,
      tripHeadsign: stops.last,
      directionId: 0,
    );
    for (var i = 0; i < stops.length; i++) {
      final t = _hms(start + i * hop);
      repo.stopTimesByStopId.putIfAbsent(stops[i], () => []).add(
            StopTimeRow(tripId: tripId, arrivalTime: t, departureTime: t, stopId: stops[i], stopSequence: i + 1),
          );
    }
  }

  static String _hms(int s) => [s ~/ 3600, s % 3600 ~/ 60, s % 60].map((v) => v.toString().padLeft(2, '0')).join(':');
}

/// A Wednesday the test calendar covers.
final testDay = DateTime(2026, 10, 7);
```

Match the constructors to `gtfs_models.dart` exactly (named vs positional, `directionId` type, any other required fields); the network's shape must stay as described.

- [ ] **Step 2: Write the failing index test**

```dart
import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/domain/trip_planner/walking.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_network.dart';

void main() {
  test('one pattern per route stop sequence, trips sorted by first departure', () {
    final idx = TimetableIndex.build(TestNetwork().repo, testDay);
    final p1 = idx.patterns.singleWhere((p) => p.routeId == '1');
    expect(p1.stops.map((s) => idx.stopIds[s]), ['A', 'B', 'C']);
    expect(p1.tripIds.length, 6);
    expect(p1.departures[0][0], 8 * 3600);
    expect(p1.departures[1][0], 8 * 3600 + 600);
    expect(p1.arrivals[0][2], 8 * 3600 + 600);
  });

  test('stops know which patterns serve them', () {
    final idx = TimetableIndex.build(TestNetwork().repo, testDay);
    final c = idx.stopIndex['C']!;
    expect(idx.patternsAtStop[c].map((e) => idx.patterns[e.$1].routeId).toSet(), {'1', '2'});
  });

  test('walks within 400 m both ways, listed out and in; nothing to a far stop', () {
    final idx = TimetableIndex.build(TestNetwork().repo, testDay);
    final c = idx.stopIndex['C']!, g = idx.stopIndex['G']!, h = idx.stopIndex['H']!;
    expect(idx.footpaths[c].singleWhere((f) => f.other == g).seconds, 360);
    expect(idx.footpaths[g].any((f) => f.other == c), isTrue);
    expect(idx.footpathsInto[g].any((f) => f.other == c), isTrue);
    expect(idx.footpaths[c].any((f) => f.other == h), isFalse);
    expect(idx.sameStopTransferSeconds[c], minTransferSeconds);
  });

  test('transfers.txt: a min time overrides, type 3 removes the link', () {
    final net = TestNetwork();
    net.repo.transfersByFromStop['C'] = [
      const TransferRule(fromStopId: 'C', toStopId: 'C', transferType: 2, minTransferSeconds: 180),
      const TransferRule(fromStopId: 'C', toStopId: 'G', transferType: 3),
    ];
    final idx = TimetableIndex.build(net.repo, testDay);
    final c = idx.stopIndex['C']!, g = idx.stopIndex['G']!;
    expect(idx.sameStopTransferSeconds[c], 180);
    expect(idx.footpaths[c].any((f) => f.other == g), isFalse);
    expect(idx.footpathsInto[g].any((f) => f.other == c), isFalse);
    expect(idx.footpaths[g].any((f) => f.other == c), isTrue); // only that direction is removed
  });

  test("yesterday's late trip is in today's index, shifted back a day", () {
    final idx = TimetableIndex.build(TestNetwork().repo, testDay);
    final firsts = idx.patterns.where((p) => p.routeId == '9').expand((p) => p.departures).map((d) => d.first);
    // Today's own 23:50, and yesterday's 23:50 as −00:10.
    expect(firsts, containsAll([23 * 3600 + 3000, -600]));
  });

  test('a day with no service keeps only the night before', () {
    final net = TestNetwork();
    net.repo.calendarDates.add(
      CalendarDate(serviceId: TestNetwork.serviceId, date: testDay, exceptionType: ExceptionType.removed),
    );
    final idx = TimetableIndex.build(net.repo, testDay);
    expect(idx.patterns.expand((p) => p.tripIds), ['9-0']);
  });

  test('a trip that overtakes another gets its own pattern', () {
    final net = TestNetwork();
    // Leaves A at 08:01 and reaches B at 08:03, before the 08:00 does (08:05).
    net.addTrip('1-x', '1', ['A', 'B', 'C'], 8 * 3600 + 60, 120);
    final idx = TimetableIndex.build(net.repo, testDay);
    final route1 = idx.patterns.where((p) => p.routeId == '1').toList();
    expect(route1.length, 2);
    for (final p in route1) {
      for (var t = 1; t < p.tripIds.length; t++) {
        for (var pos = 0; pos < p.stops.length; pos++) {
          expect(p.arrivals[t][pos], greaterThanOrEqualTo(p.arrivals[t - 1][pos]));
          expect(p.departures[t][pos], greaterThanOrEqualTo(p.departures[t - 1][pos]));
        }
      }
    }
  });
}
```

- [ ] **Step 3: Run it to see it fail**

Run: `flutter test test/trip_planner/timetable_index_test.dart`
Expected: FAIL, `TimetableIndex` doesn't exist.

- [ ] **Step 4: Implement `timetable_index.dart`**

```dart
import '../../data/gtfs/gtfs_models.dart';
import '../../data/gtfs/gtfs_repository.dart';
import '../../data/gtfs/gtfs_time.dart';
import 'walking.dart';

/// Trips of one route that visit the same stops in the same order and never overtake each other (RAPTOR's "route").
class TransitPattern {
  TransitPattern(this.routeId, this.stops);
  final String routeId;
  final List<int> stops;
  final List<String> tripIds = [];
  final List<List<int>> departures = [];
  final List<List<int>> arrivals = [];

  /// [dep]/[arr] can follow the last trip without overtaking it at any stop.
  bool _canAppend(List<int> dep, List<int> arr) {
    if (tripIds.isEmpty) return true;
    final lastDep = departures.last, lastArr = arrivals.last;
    for (var i = 0; i < dep.length; i++) {
      if (dep[i] < lastDep[i] || arr[i] < lastArr[i]) return false;
    }
    return true;
  }
}

/// A walk to or from [other], in seconds.
class Footpath {
  const Footpath(this.other, this.seconds);
  final int other;
  final int seconds;
}

/// One service day's schedule, arranged for search (spec §3.1). Times are seconds from [serviceDate]'s midnight.
/// Yesterday's trips that run past midnight are included, shifted by −24 h, so a query at 00:10 finds them.
class TimetableIndex {
  TimetableIndex._(this.serviceDate, this.stopIds, this.stopIndex);

  final DateTime serviceDate;
  final List<String> stopIds;
  final Map<String, int> stopIndex;
  final List<TransitPattern> patterns = [];
  late final List<List<(int, int)>> patternsAtStop;
  late final List<List<Footpath>> footpaths;
  late final List<List<Footpath>> footpathsInto;
  late final List<int> sameStopTransferSeconds;

  static TimetableIndex build(GtfsRepository repo, DateTime serviceDate) {
    final day = DateTime(serviceDate.year, serviceDate.month, serviceDate.day);
    final stopIds = repo.stopsById.keys.toList()..sort();
    final stopIndex = {for (var i = 0; i < stopIds.length; i++) stopIds[i]: i};
    final idx = TimetableIndex._(day, stopIds, stopIndex);

    // Each trip's stop times, in sequence order.
    final rowsByTrip = <String, List<StopTimeRow>>{};
    for (final rows in repo.stopTimesByStopId.values) {
      for (final r in rows) {
        rowsByTrip.putIfAbsent(r.tripId, () => []).add(r);
      }
    }
    for (final rows in rowsByTrip.values) {
      rows.sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    }

    final today = repo.activeServiceIds(day);
    final yesterday = repo.activeServiceIds(day.subtract(const Duration(days: 1)));
    // Per route + stop sequence: (tripId, departures, arrivals), grouped before splitting overtakers.
    final groups = <String, (String, List<int>, List<(String, List<int>, List<int>)>)>{};

    void addTrip(TripInfo trip, List<StopTimeRow> rows, int shift) {
      final stops = <int>[];
      for (final r in rows) {
        final s = stopIndex[r.stopId];
        if (s == null) return; // a stop missing from stops.txt: skip the trip
        stops.add(s);
      }
      if (stops.length < 2) return;
      final key = '${trip.routeId}|${stops.join(',')}';
      final g = groups.putIfAbsent(key, () => (trip.routeId, stops, []));
      g.$3.add((
        trip.tripId,
        [for (final r in rows) GtfsTime.parse(r.departureTime).totalSeconds + shift],
        [for (final r in rows) GtfsTime.parse(r.arrivalTime).totalSeconds + shift],
      ));
    }

    for (final MapEntry(key: tripId, value: rows) in rowsByTrip.entries) {
      final trip = repo.tripsById[tripId];
      if (trip == null) continue;
      if (today.contains(trip.serviceId)) addTrip(trip, rows, 0);
      final pastMidnight = GtfsTime.parse(rows.last.arrivalTime).totalSeconds >= Duration.secondsPerDay;
      if (pastMidnight && yesterday.contains(trip.serviceId)) addTrip(trip, rows, -Duration.secondsPerDay);
    }

    // Trips sorted by first departure; one that would overtake goes to the next pattern that can take it.
    for (final (routeId, stops, trips) in groups.values) {
      trips.sort((a, b) => a.$2.first.compareTo(b.$2.first));
      final split = <TransitPattern>[];
      for (final (id, dep, arr) in trips) {
        var p = split.where((p) => p._canAppend(dep, arr)).firstOrNull;
        if (p == null) {
          p = TransitPattern(routeId, stops);
          split.add(p);
        }
        p.tripIds.add(id);
        p.departures.add(dep);
        p.arrivals.add(arr);
      }
      idx.patterns.addAll(split);
    }

    final n = stopIds.length;
    idx.patternsAtStop = List.generate(n, (_) => <(int, int)>[]);
    for (var pi = 0; pi < idx.patterns.length; pi++) {
      final stops = idx.patterns[pi].stops;
      for (var pos = 0; pos < stops.length; pos++) {
        idx.patternsAtStop[stops[pos]].add((pi, pos));
      }
    }

    // transfers.txt: "from>to" → override seconds, or removed.
    final removed = <String>{};
    final override = <String, int>{};
    for (final rules in repo.transfersByFromStop.values) {
      for (final t in rules) {
        final key = '${t.fromStopId}>${t.toStopId}';
        if (t.transferType == 3) {
          removed.add(key);
        } else if (t.minTransferSeconds != null) {
          override[key] = t.minTransferSeconds!;
        }
      }
    }

    idx.sameStopTransferSeconds = List.generate(n, (s) {
      final o = override['${stopIds[s]}>${stopIds[s]}'];
      return o == null || o < minTransferSeconds ? minTransferSeconds : o;
    });

    idx.footpaths = List.generate(n, (_) => <Footpath>[]);
    idx.footpathsInto = List.generate(n, (_) => <Footpath>[]);
    for (var a = 0; a < n; a++) {
      final sa = repo.stopsById[stopIds[a]]!;
      for (var b = 0; b < n; b++) {
        if (a == b) continue;
        final key = '${stopIds[a]}>${stopIds[b]}';
        if (removed.contains(key)) continue;
        final sb = repo.stopsById[stopIds[b]]!;
        final d = haversineMeters(sa.stopLat, sa.stopLon, sb.stopLat, sb.stopLon);
        if (d > maxTransferMeters) continue;
        final seconds = override[key] ?? walkSeconds(d);
        idx.footpaths[a].add(Footpath(b, seconds));
        idx.footpathsInto[b].add(Footpath(a, seconds));
      }
    }
    return idx;
  }
}
```

The footpath loop checks ~840 k stop pairs on the real feed (916 stops); Task 7 times it against the 1 s limit. If it's over, bucket stops into a 0.005° latitude/longitude grid and compare only neighbouring cells.

- [ ] **Step 5: Run it to see it pass**

Run: `flutter test test/trip_planner/timetable_index_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/trip_planner/timetable_index.dart test/trip_planner/test_network.dart test/trip_planner/timetable_index_test.dart
git commit -m "feat(planner): a per-day timetable index for trip search

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Journeys and forward RAPTOR (Leave by)

**Files:**
- Create: `lib/domain/trip_planner/journey.dart`
- Create: `lib/domain/trip_planner/raptor.dart`
- Test: `test/trip_planner/raptor_forward_test.dart`

**Interfaces:**
- Consumes: Task 3's `TimetableIndex`, `TransitPattern`, `Footpath`.
- Produces:

```dart
// journey.dart
sealed class Leg { int get startSeconds; int get endSeconds; }
class WalkLeg extends Leg { String? fromStopId; String? toStopId; int seconds; int startSeconds; }  // null stop = the pin end
class RideLeg extends Leg { String routeId, tripId, boardStopId, alightStopId; int departs, arrives, stopCount; bool live;
  RideLeg copyWithTimes({int? departs, int? arrives, bool? live}); }
class Journey { DateTime serviceDate; List<Leg> legs; bool replannedForLiveTimes;
  int get departs; int get arrives; int get rides; int get walkSeconds; bool get usesLive;
  DateTime at(int seconds); Journey copyWith({List<Leg>? legs, bool? replannedForLiveTimes}); }
class StopOffset { final int stop; final int seconds; }     // a walk between an end and a stop (0 for a stop end)
List<Leg> retimeWalks(List<Leg> legs);                     // walks before the first ride end as it leaves; others follow the leg before
int secondsInServiceDay(DateTime serviceDate, DateTime t); // wall-clock seconds from serviceDate's midnight (can be ≥ 86400)
// raptor.dart
const maxRides = 4;
List<Journey> raptorForward(TimetableIndex idx, {required List<StopOffset> access, required List<StopOffset> egress, required int departAt, int rides = maxRides});
```

`raptorForward` returns the Pareto set over (arrival, rides): one journey per round that improves the arrival, fewest rides first. Every journey has at least one ride. The search keeps two values per stop per round, "arrived by bus" and "arrived on foot", because only the first needs the same-stop transfer time before the next bus (Task 7's reference search makes the same distinction). A walk never follows a walk. A stop origin (0 s access) may first walk to a stop within 400 m; a pin's access walk is its only walk to the first stop. The same rules apply at the destination end.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/raptor.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_network.dart';

void main() {
  late TimetableIndex idx;
  int s(String id) => idx.stopIndex[id]!;
  setUp(() => idx = TimetableIndex.build(TestNetwork().repo, testDay));

  List<Journey> plan(String from, String to, int at) =>
      raptorForward(idx, access: [StopOffset(s(from), 0)], egress: [StopOffset(s(to), 0)], departAt: at);

  test('a direct ride takes the next trip', () {
    final ride = plan('A', 'C', 8 * 3600 + 60).single.legs.single as RideLeg;
    expect(ride.tripId, '1-1'); // the 08:10; the 08:00 has gone
    expect(ride.departs, 8 * 3600 + 600);
    expect(ride.arrives, 8 * 3600 + 1200);
    expect(ride.stopCount, 2);
  });

  test('a same-stop transfer waits at least a minute', () {
    // 1-0: A 08:00 → C 08:10. Route 2 leaves C at 08:05, 08:20, …: the 08:20 is the first one catchable.
    final j = plan('A', 'E', 8 * 3600).first;
    final rides = j.legs.whereType<RideLeg>().toList();
    expect(rides.map((r) => r.routeId), ['1', '2']);
    expect(rides[1].departs, 8 * 3600 + 1200);
    expect(j.arrives, 8 * 3600 + 1200 + 480);
  });

  test("a stop's longer transfer time sends the rider to a later bus", () {
    // 1-2 reaches C at 08:30; 2-2 leaves at 08:35. With a 6-minute rule at C, only 2-3 (08:50) works.
    idx.sameStopTransferSeconds[s('C')] = 360;
    final second = plan('A', 'E', 8 * 3600 + 1200).first.legs.whereType<RideLeg>().last;
    expect(second.departs, 8 * 3600 + 3000);
  });

  test('a walking transfer is used and shown as a walk leg', () {
    // G has no buses: ride to C, walk 300 m (6 min).
    final j = plan('A', 'G', 8 * 3600).single;
    expect(j.legs.first, isA<RideLeg>());
    final walk = j.legs.last as WalkLeg;
    expect((walk.fromStopId, walk.toStopId, walk.seconds), ('C', 'G', 360));
    expect(walk.startSeconds, 8 * 3600 + 600);
    expect(j.arrives, 8 * 3600 + 960);
  });

  test('access and egress walks count; the rider leaves as late as they can', () {
    final j = raptorForward(idx,
        access: [StopOffset(s('A'), 300)], egress: [StopOffset(s('C'), 120)], departAt: 8 * 3600).single;
    // At A by 08:05 earliest: the 08:00 has gone, so the 08:10. Leave at 08:05, walk 5 min.
    expect(j.departs, 8 * 3600 + 300);
    expect((j.legs.first as WalkLeg).seconds, 300);
    expect(j.arrives, 8 * 3600 + 1200 + 120);
  });

  test('a journey with fewer rides that arrives no earlier is not repeated', () {
    final js = plan('F', 'E', 8 * 3600);
    expect(js.length, 1);
    expect(js.single.rides, 1);
  });

  test('no journey when nothing runs', () {
    expect(plan('A', 'C', 23 * 3600), isEmpty);
    expect(plan('A', 'H', 8 * 3600), isEmpty);
  });

  test("just after midnight, last night's late trip is found", () {
    final j = plan('Y', 'Z', 600).single; // 00:10: the 23:50 from X reaches Y at 00:20
    expect(j.departs, 1200);
    expect(j.arrives, 3000);
  });

  test('the same stop as origin and destination gives no journey', () {
    expect(plan('A', 'A', 8 * 3600), isEmpty);
  });

  test('journey helpers: clock times and seconds in the service day', () {
    final j = plan('Y', 'Z', 600).single;
    expect(j.at(j.departs), DateTime(2026, 10, 7, 0, 20));
    expect(secondsInServiceDay(testDay, DateTime(2026, 10, 8, 0, 20)), 86400 + 1200);
    expect(secondsInServiceDay(testDay, DateTime(2026, 10, 7, 8, 5)), 8 * 3600 + 300);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/trip_planner/raptor_forward_test.dart`
Expected: FAIL, `raptorForward` doesn't exist.

- [ ] **Step 3: Implement `journey.dart`**

```dart
/// A step of a planned trip (spec §3.1). Times are seconds from the journey's service-day midnight.
sealed class Leg {
  int get startSeconds;
  int get endSeconds;
}

class WalkLeg extends Leg {
  WalkLeg({required this.fromStopId, required this.toStopId, required this.seconds, required this.startSeconds});

  /// Null at the pin end of the trip.
  final String? fromStopId;
  final String? toStopId;
  final int seconds;
  @override
  final int startSeconds;
  @override
  int get endSeconds => startSeconds + seconds;
}

class RideLeg extends Leg {
  RideLeg({
    required this.routeId,
    required this.tripId,
    required this.boardStopId,
    required this.alightStopId,
    required this.departs,
    required this.arrives,
    required this.stopCount,
    this.live = false,
  });

  final String routeId;
  final String tripId;
  final String boardStopId;
  final String alightStopId;
  final int departs;
  final int arrives;

  /// Stops ridden, counting the one the rider gets off at.
  final int stopCount;

  /// The times came from the live feed (spec §3.4).
  final bool live;

  @override
  int get startSeconds => departs;
  @override
  int get endSeconds => arrives;

  RideLeg copyWithTimes({int? departs, int? arrives, bool? live}) => RideLeg(
        routeId: routeId,
        tripId: tripId,
        boardStopId: boardStopId,
        alightStopId: alightStopId,
        departs: departs ?? this.departs,
        arrives: arrives ?? this.arrives,
        stopCount: stopCount,
        live: live ?? this.live,
      );
}

class Journey {
  Journey({required this.serviceDate, required this.legs, this.replannedForLiveTimes = false});

  /// Date only; leg times count from its midnight.
  final DateTime serviceDate;
  final List<Leg> legs;

  /// A transfer got too tight with live times, and the rest was planned again (spec §3.4).
  final bool replannedForLiveTimes;

  int get departs => legs.first.startSeconds;
  int get arrives => legs.last.endSeconds;
  int get rides => legs.whereType<RideLeg>().length;
  int get walkSeconds => legs.whereType<WalkLeg>().fold(0, (a, w) => a + w.seconds);
  bool get usesLive => legs.whereType<RideLeg>().any((r) => r.live);

  /// The clock time [seconds] after the service day's midnight (wall clock, as GTFS counts it).
  DateTime at(int seconds) => DateTime(serviceDate.year, serviceDate.month, serviceDate.day, 0, 0, seconds);

  Journey copyWith({List<Leg>? legs, bool? replannedForLiveTimes}) => Journey(
        serviceDate: serviceDate,
        legs: legs ?? this.legs,
        replannedForLiveTimes: replannedForLiveTimes ?? this.replannedForLiveTimes,
      );
}

/// A walk between an end of the trip and a stop, in seconds (0 when the end is that stop).
class StopOffset {
  const StopOffset(this.stop, this.seconds);
  final int stop;
  final int seconds;
}

/// Wall-clock seconds from [serviceDate]'s midnight to [t]; past midnight counts on (24:20 is 87600).
int secondsInServiceDay(DateTime serviceDate, DateTime t) {
  final days = DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(serviceDate.year, serviceDate.month, serviceDate.day)).inDays;
  return days * Duration.secondsPerDay + t.hour * 3600 + t.minute * 60 + t.second;
}

/// Gives each walk its start: walks before the first ride end just as it leaves (the rider leaves as late as they
/// can); every other walk starts when the leg before it ends.
List<Leg> retimeWalks(List<Leg> legs) {
  final firstRide = legs.indexWhere((l) => l is RideLeg);
  if (firstRide < 0) return legs;
  var t = legs[firstRide].startSeconds;
  for (var i = firstRide - 1; i >= 0; i--) {
    t -= (legs[i] as WalkLeg).seconds;
  }
  final out = <Leg>[];
  for (final leg in legs) {
    out.add(leg is WalkLeg
        ? WalkLeg(fromStopId: leg.fromStopId, toStopId: leg.toStopId, seconds: leg.seconds, startSeconds: t)
        : leg);
    t = out.last.endSeconds;
  }
  return out;
}
```

- [ ] **Step 4: Implement forward RAPTOR in `raptor.dart`**

```dart
import 'journey.dart';
import 'timetable_index.dart';

/// At most this many rides, so at most 3 transfers (spec §3.3).
const maxRides = 4;
const _inf = 1 << 40;

sealed class _Label {}

/// Round 0: the walk between the trip's end and this stop (0 s when the end is the stop).
class _Start extends _Label {
  _Start(this.walkSeconds);
  final int walkSeconds;
}

class _Ride extends _Label {
  _Ride(this.pattern, this.trip, this.boardPos, this.alightPos, {required this.viaRide});
  final int pattern, trip, boardPos, alightPos;

  /// The connecting stop (where the rider boarded, in a forward search; where they got off, in a reverse one) was
  /// reached or left by bus, so the same-stop transfer time applied there.
  final bool viaRide;
}

class _Walk extends _Label {
  _Walk(this.otherStop, this.seconds, {required this.atStart});
  final int otherStop, seconds;

  /// The other end is a round-0 start stop (the origin or destination stop itself), not a stop on a bus leg.
  final bool atStart;
}

/// A search's rounds. Each stop has two values per round, as in the reference search: by bus (`ride`) and on foot
/// (`walk`). Values and labels are copied into the next round before it starts.
class _State {
  _State(int rounds, int n, int fill)
      : ride = List.generate(rounds, (_) => List.filled(n, fill)),
        walk = List.generate(rounds, (_) => List.filled(n, fill)),
        rideLabel = List.generate(rounds, (_) => List<_Ride?>.filled(n, null)),
        walkLabel = List.generate(rounds, (_) => List<_Label?>.filled(n, null));
  final List<List<int>> ride, walk;
  final List<List<_Ride?>> rideLabel;
  final List<List<_Label?>> walkLabel;

  void copyRound(int k) {
    ride[k].setAll(0, ride[k - 1]);
    walk[k].setAll(0, walk[k - 1]);
    rideLabel[k].setAll(0, rideLabel[k - 1]);
    walkLabel[k].setAll(0, walkLabel[k - 1]);
  }
}

/// Leave by [departAt]: the earliest arrivals with 1..[rides] rides (spec §3.3).
List<Journey> raptorForward(
  TimetableIndex idx, {
  required List<StopOffset> access,
  required List<StopOffset> egress,
  required int departAt,
  int rides = maxRides,
}) {
  final n = idx.stopIds.length;
  final st = _State(rides + 1, n, _inf);
  final bestRide = List.filled(n, _inf);
  final bestWalk = List.filled(n, _inf);
  var bestTarget = _inf;
  final journeys = <Journey>[];

  // Round 0: at the start stops; from a stop origin, also walk to the stops near it.
  final marked = <int>{};
  for (final a in access) {
    final t = departAt + a.seconds;
    if (t < bestWalk[a.stop]) {
      st.walk[0][a.stop] = t;
      bestWalk[a.stop] = t;
      st.walkLabel[0][a.stop] = _Start(a.seconds);
      marked.add(a.stop);
    }
  }
  for (final a in access.where((a) => a.seconds == 0)) {
    for (final f in idx.footpaths[a.stop]) {
      final t = departAt + f.seconds;
      if (t < bestWalk[f.other]) {
        st.walk[0][f.other] = t;
        bestWalk[f.other] = t;
        st.walkLabel[0][f.other] = _Walk(a.stop, f.seconds, atStart: true);
        marked.add(f.other);
      }
    }
  }

  var current = marked;
  for (var k = 1; k <= rides && current.isNotEmpty; k++) {
    st.copyRound(k);
    // Each pattern is scanned from its earliest stop marked last round.
    final queue = <int, int>{};
    for (final s in current) {
      for (final (p, pos) in idx.patternsAtStop[s]) {
        final q = queue[p];
        if (q == null || pos < q) queue[p] = pos;
      }
    }
    final byBus = <int>{};
    for (final MapEntry(key: pi, value: from) in queue.entries) {
      final p = idx.patterns[pi];
      int? trip;
      var boardPos = -1;
      var viaRide = false;
      for (var pos = from; pos < p.stops.length; pos++) {
        final stop = p.stops[pos];
        if (trip != null) {
          final arr = p.arrivals[trip][pos];
          if (arr < bestRide[stop] && arr < bestTarget) {
            st.ride[k][stop] = arr;
            bestRide[stop] = arr;
            st.rideLabel[k][stop] = _Ride(pi, trip, boardPos, pos, viaRide: viaRide);
            byBus.add(stop);
          }
        }
        // Can an earlier trip of this pattern be caught here?
        final afterBus = st.ride[k - 1][stop] + idx.sameStopTransferSeconds[stop];
        final onFoot = st.walk[k - 1][stop];
        final ready = afterBus < onFoot ? afterBus : onFoot;
        if (ready >= _inf) continue;
        final t = _earliestTrip(p, pos, ready);
        if (t != null && (trip == null || t < trip)) {
          trip = t;
          boardPos = pos;
          viaRide = onFoot > p.departures[t][pos];
        }
      }
    }
    // Walk on from the stops reached by bus this round (never a walk after a walk).
    final onFootNow = <int>{};
    for (final s in byBus) {
      for (final f in idx.footpaths[s]) {
        final t = st.ride[k][s] + f.seconds;
        if (t < bestWalk[f.other] && t < bestTarget) {
          st.walk[k][f.other] = t;
          bestWalk[f.other] = t;
          st.walkLabel[k][f.other] = _Walk(s, f.seconds, atStart: false);
          onFootNow.add(f.other);
        }
      }
    }
    current = {...byBus, ...onFootNow};

    // A better arrival with k rides? Only values this round improved count; older ones were counted already.
    var roundBest = _inf, roundStop = -1, roundEgress = 0;
    var roundByBus = true;
    for (final e in egress) {
      final s = e.stop;
      if (st.ride[k][s] < st.ride[k - 1][s] && st.ride[k][s] + e.seconds < roundBest) {
        (roundBest, roundStop, roundEgress, roundByBus) = (st.ride[k][s] + e.seconds, s, e.seconds, true);
      }
      // On foot only at a stop destination: walking on to a pin would be two walks in a row.
      if (e.seconds == 0 && st.walk[k][s] < st.walk[k - 1][s] && st.walk[k][s] < roundBest) {
        (roundBest, roundStop, roundEgress, roundByBus) = (st.walk[k][s], s, 0, false);
      }
    }
    if (roundStop >= 0 && roundBest < bestTarget) {
      bestTarget = roundBest;
      journeys.add(_forwardJourney(idx, st, k, roundStop, roundByBus, roundEgress));
    }
  }
  return journeys;
}

/// The first trip leaving position [pos] at or after [ready] (trips are in order and don't overtake).
int? _earliestTrip(TransitPattern p, int pos, int ready) {
  for (var t = 0; t < p.departures.length; t++) {
    if (p.departures[t][pos] >= ready) return t;
  }
  return null;
}

WalkLeg _walkLeg(String? from, String? to, int seconds) =>
    WalkLeg(fromStopId: from, toStopId: to, seconds: seconds, startSeconds: 0);

RideLeg _rideLeg(TimetableIndex idx, _Ride r) {
  final p = idx.patterns[r.pattern];
  return RideLeg(
    routeId: p.routeId,
    tripId: p.tripIds[r.trip],
    boardStopId: idx.stopIds[p.stops[r.boardPos]],
    alightStopId: idx.stopIds[p.stops[r.alightPos]],
    departs: p.departures[r.trip][r.boardPos],
    arrives: p.arrivals[r.trip][r.alightPos],
    stopCount: r.alightPos - r.boardPos,
  );
}

/// Follows the labels back from the destination stop to the start.
Journey _forwardJourney(TimetableIndex idx, _State st, int k, int stop, bool byBus, int egressSeconds) {
  final legs = <Leg>[]; // last leg first
  if (egressSeconds > 0) legs.add(_walkLeg(idx.stopIds[stop], null, egressSeconds));
  var r = k, s = stop, onBus = byBus;
  while (true) {
    if (onBus) {
      final ride = st.rideLabel[r][s]!;
      legs.add(_rideLeg(idx, ride));
      s = idx.patterns[ride.pattern].stops[ride.boardPos];
      r -= 1;
      onBus = ride.viaRide;
      continue;
    }
    final label = st.walkLabel[r][s]!;
    if (label is _Start) {
      if (label.walkSeconds > 0) legs.add(_walkLeg(null, idx.stopIds[s], label.walkSeconds));
      break;
    }
    final w = label as _Walk;
    legs.add(_walkLeg(idx.stopIds[w.otherStop], idx.stopIds[s], w.seconds));
    s = w.otherStop;
    onBus = !w.atStart;
  }
  return Journey(serviceDate: idx.serviceDate, legs: retimeWalks(legs.reversed.toList()));
}
```

`_earliestTrip` is a linear scan; patterns have tens of trips. Switch it to a binary search only if Task 7's timing fails.

- [ ] **Step 5: Run it to see it pass**

Run: `flutter test test/trip_planner/raptor_forward_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/trip_planner/journey.dart lib/domain/trip_planner/raptor.dart test/trip_planner/raptor_forward_test.dart
git commit -m "feat(planner): journeys and the forward RAPTOR search (leave by)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Reverse RAPTOR (Arrive by)

**Files:**
- Modify: `lib/domain/trip_planner/raptor.dart` (add `raptorReverse`)
- Test: `test/trip_planner/raptor_reverse_test.dart`

**Interfaces:**
- Consumes: Task 4's private `_State`, `_Start`, `_Ride`, `_Walk`, `_walkLeg`, `_rideLeg`, `retimeWalks`; Task 3's `footpathsInto`.
- Produces: `List<Journey> raptorReverse(TimetableIndex idx, {required List<StopOffset> access, required List<StopOffset> egress, required int arriveBy, int rides = maxRides})`: the latest departures that still arrive by [arriveBy], one per round that improves the departure, fewest rides first. Legs are in travel order.

The reverse search mirrors the forward one. For each stop, `ride` holds the latest bus the rider can board there and still arrive in time; `walk` holds the latest time they can set off on foot from there. Someone who gets off a bus at a stop and boards another needs the transfer time; someone who walks on doesn't.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/raptor.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_network.dart';

void main() {
  late TimetableIndex idx;
  int s(String id) => idx.stopIndex[id]!;
  setUp(() => idx = TimetableIndex.build(TestNetwork().repo, testDay));

  List<Journey> plan(String from, String to, int by) =>
      raptorReverse(idx, access: [StopOffset(s(from), 0)], egress: [StopOffset(s(to), 0)], arriveBy: by);

  test('arrive by: the latest direct trip that makes it', () {
    // By 08:25 at C: the 08:10 from A arrives 08:20; the 08:20 arrives 08:30, too late.
    final ride = plan('A', 'C', 8 * 3600 + 1500).single.legs.single as RideLeg;
    expect(ride.departs, 8 * 3600 + 600);
    expect(ride.arrives, 8 * 3600 + 1200);
  });

  test('arrive by with a transfer keeps the 1-minute rule', () {
    // By 08:45 at E: 2-2 leaves C 08:35, reaches E 08:43. Its feeder must reach C by 08:34: 1-2 (A 08:20, C 08:30).
    final j = plan('A', 'E', 8 * 3600 + 2700).first;
    final rides = j.legs.whereType<RideLeg>().toList();
    expect(rides.map((r) => r.routeId), ['1', '2']);
    expect(rides[0].departs, 8 * 3600 + 1200);
    expect(rides[1].departs, 8 * 3600 + 2100);
    expect(j.arrives, 8 * 3600 + 2580);
  });

  test('legs are in travel order, with the walks where they happen', () {
    final j = raptorReverse(idx,
        access: [StopOffset(s('A'), 240)], egress: [StopOffset(s('C'), 120)], arriveBy: 8 * 3600 + 1500).single;
    expect(j.legs.map((l) => l.runtimeType), [WalkLeg, RideLeg, WalkLeg]);
    expect(j.departs, 8 * 3600 + 600 - 240);
    expect(j.arrives, 8 * 3600 + 1200 + 120);
  });

  test('a walk to a stop destination after the bus', () {
    // By 08:30 at G: ride to C by 08:24 (the 08:10, C 08:20), walk 6 min.
    final j = plan('A', 'G', 8 * 3600 + 1800).single;
    expect(j.legs.last, isA<WalkLeg>());
    expect(j.arrives, 8 * 3600 + 1560);
  });

  test('nothing arrives that early', () {
    expect(plan('A', 'C', 8 * 3600 + 300), isEmpty);
  });

  test('the same stop at both ends gives no journey', () {
    expect(plan('C', 'C', 9 * 3600), isEmpty);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/trip_planner/raptor_reverse_test.dart`
Expected: FAIL, `raptorReverse` doesn't exist.

- [ ] **Step 3: Implement**

Add to `raptor.dart`:

```dart
/// Arrive by [arriveBy]: the latest departures with 1..[rides] rides (spec §3.3).
List<Journey> raptorReverse(
  TimetableIndex idx, {
  required List<StopOffset> access,
  required List<StopOffset> egress,
  required int arriveBy,
  int rides = maxRides,
}) {
  final n = idx.stopIds.length;
  final st = _State(rides + 1, n, -_inf);
  final bestRide = List.filled(n, -_inf);
  final bestWalk = List.filled(n, -_inf);
  var bestOrigin = -_inf;
  final journeys = <Journey>[];

  // Round 0: at the destination stops; to a stop destination, also walk from the stops near it.
  final marked = <int>{};
  for (final e in egress) {
    final t = arriveBy - e.seconds;
    if (t > bestWalk[e.stop]) {
      st.walk[0][e.stop] = t;
      bestWalk[e.stop] = t;
      st.walkLabel[0][e.stop] = _Start(e.seconds);
      marked.add(e.stop);
    }
  }
  for (final e in egress.where((e) => e.seconds == 0)) {
    for (final f in idx.footpathsInto[e.stop]) {
      final t = arriveBy - f.seconds;
      if (t > bestWalk[f.other]) {
        st.walk[0][f.other] = t;
        bestWalk[f.other] = t;
        st.walkLabel[0][f.other] = _Walk(e.stop, f.seconds, atStart: true);
        marked.add(f.other);
      }
    }
  }

  var current = marked;
  for (var k = 1; k <= rides && current.isNotEmpty; k++) {
    st.copyRound(k);
    // Each pattern is scanned backward from its latest stop marked last round.
    final queue = <int, int>{};
    for (final s in current) {
      for (final (p, pos) in idx.patternsAtStop[s]) {
        final q = queue[p];
        if (q == null || pos > q) queue[p] = pos;
      }
    }
    final byBus = <int>{};
    for (final MapEntry(key: pi, value: from) in queue.entries) {
      final p = idx.patterns[pi];
      int? trip;
      var alightPos = -1;
      var viaRide = false;
      for (var pos = from; pos >= 0; pos--) {
        final stop = p.stops[pos];
        if (trip != null) {
          final dep = p.departures[trip][pos];
          if (dep > bestRide[stop] && dep > bestOrigin) {
            st.ride[k][stop] = dep;
            bestRide[stop] = dep;
            st.rideLabel[k][stop] = _Ride(pi, trip, pos, alightPos, viaRide: viaRide);
            byBus.add(stop);
          }
        }
        // Can a later trip of this pattern be taken, getting off here?
        final beforeBus = st.ride[k - 1][stop] - idx.sameStopTransferSeconds[stop];
        final onFoot = st.walk[k - 1][stop];
        final ready = beforeBus > onFoot ? beforeBus : onFoot;
        if (ready <= -_inf) continue;
        final t = _latestTrip(p, pos, ready);
        if (t != null && (trip == null || t > trip)) {
          trip = t;
          alightPos = pos;
          viaRide = onFoot < p.arrivals[t][pos];
        }
      }
    }
    // Walk back from the stops where a bus can be boarded this round (never a walk before a walk).
    final onFootNow = <int>{};
    for (final s in byBus) {
      for (final f in idx.footpathsInto[s]) {
        final t = st.ride[k][s] - f.seconds;
        if (t > bestWalk[f.other] && t > bestOrigin) {
          st.walk[k][f.other] = t;
          bestWalk[f.other] = t;
          st.walkLabel[k][f.other] = _Walk(s, f.seconds, atStart: false);
          onFootNow.add(f.other);
        }
      }
    }
    current = {...byBus, ...onFootNow};

    var roundBest = -_inf, roundStop = -1, roundAccess = 0;
    var roundByBus = true;
    for (final a in access) {
      final s = a.stop;
      if (st.ride[k][s] > st.ride[k - 1][s] && st.ride[k][s] - a.seconds > roundBest) {
        (roundBest, roundStop, roundAccess, roundByBus) = (st.ride[k][s] - a.seconds, s, a.seconds, true);
      }
      if (a.seconds == 0 && st.walk[k][s] > st.walk[k - 1][s] && st.walk[k][s] > roundBest) {
        (roundBest, roundStop, roundAccess, roundByBus) = (st.walk[k][s], s, 0, false);
      }
    }
    if (roundStop >= 0 && roundBest > bestOrigin) {
      bestOrigin = roundBest;
      journeys.add(_reverseJourney(idx, st, k, roundStop, roundByBus, roundAccess));
    }
  }
  return journeys;
}

/// The last trip reaching position [pos] at or before [ready].
int? _latestTrip(TransitPattern p, int pos, int ready) {
  for (var t = p.arrivals.length - 1; t >= 0; t--) {
    if (p.arrivals[t][pos] <= ready) return t;
  }
  return null;
}

/// Follows the labels forward from the origin stop to the destination.
Journey _reverseJourney(TimetableIndex idx, _State st, int k, int origin, bool byBus, int accessSeconds) {
  final legs = <Leg>[];
  if (accessSeconds > 0) legs.add(_walkLeg(null, idx.stopIds[origin], accessSeconds));
  var r = k, s = origin, onBus = byBus;
  while (true) {
    if (onBus) {
      final ride = st.rideLabel[r][s]!;
      legs.add(_rideLeg(idx, ride));
      s = idx.patterns[ride.pattern].stops[ride.alightPos];
      r -= 1;
      onBus = ride.viaRide;
      continue;
    }
    final label = st.walkLabel[r][s]!;
    if (label is _Start) {
      if (label.walkSeconds > 0) legs.add(_walkLeg(idx.stopIds[s], null, label.walkSeconds));
      break;
    }
    final w = label as _Walk;
    legs.add(_walkLeg(idx.stopIds[s], idx.stopIds[w.otherStop], w.seconds));
    s = w.otherStop;
    onBus = !w.atStart;
  }
  return Journey(serviceDate: idx.serviceDate, legs: retimeWalks(legs));
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `flutter test test/trip_planner/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/trip_planner/raptor.dart test/trip_planner/raptor_reverse_test.dart
git commit -m "feat(planner): the reverse RAPTOR search (arrive by)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Places, ranking and the planner facade

**Files:**
- Create: `lib/domain/trip_planner/place.dart`
- Create: `lib/domain/trip_planner/ranking.dart`
- Create: `lib/domain/trip_planner/trip_planner.dart`
- Test: `test/trip_planner/trip_planner_test.dart`

**Interfaces:**
- Consumes: Tasks 2–5.
- Produces:

```dart
// place.dart
sealed class Place { String get label; Map<String, Object?> toJson(); static Place? fromJson(Object? json); }
class StopPlace extends Place { StopPlace({required String stopId, required String name}); }   // == by stopId
class PinPlace extends Place { PinPlace({required double lat, required double lon, required String label}); } // == by lat/lon
// ranking.dart
List<Journey> rankJourneys(List<Journey> candidates, {int max = 5});
// trip_planner.dart
enum PlanMode { leaveNow, leaveBy, arriveBy }
class PlanQuery { const PlanQuery({required Place from, required Place to, required PlanMode mode, required DateTime time}); }
sealed class PlanOutcome {}
class PlanFound extends PlanOutcome { PlanFound(List<Journey> journeys); }
class PlanNoJourney extends PlanOutcome { PlanNoJourney({DateTime? nextDeparture, DateTime? firstArrival}); }
class PlanTooFar extends PlanOutcome { PlanTooFar({required bool fromEnd}); }  // which end has no stop within 800 m
class TripPlanner { TripPlanner(GtfsRepository repo, TimetableIndex index);
  List<StopOffset> offsetsFor(Place p); PlanOutcome plan(PlanQuery q); }
```

- `plan` gathers more than one search's worth of options. For Leave by it searches again from the earliest found departure + 1 min, up to 4 searches; for Arrive by, from the earliest found arrival − 1 min. Then `rankJourneys` picks what's shown.
- `PlanNoJourney.firstArrival` (Arrive by only): nothing gets there by that time, but this is the earliest anything does that day.
- `PlanNoJourney.nextDeparture` (Leave by): left null here; Task 11's provider fills it from tomorrow's schedule.
- `rankJourneys` drops a journey when another leaves no earlier, arrives no later and has no more rides or walking (it "covers" it), and drops near-duplicates (the same trips leaving within 2 min). Then it keeps the earliest arrival, the fewest rides and the least walking, fills up by departure to [max], and returns them sorted by departure.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/ranking.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_network.dart';

void main() {
  late TripPlanner planner;
  setUp(() {
    final net = TestNetwork();
    planner = TripPlanner(net.repo, TimetableIndex.build(net.repo, testDay));
  });
  StopPlace stop(String id) => StopPlace(stopId: id, name: 'Stop $id');
  DateTime at(int h, int m) => DateTime(testDay.year, testDay.month, testDay.day, h, m);
  PlanOutcome plan(Place from, Place to, PlanMode mode, DateTime time) =>
      planner.plan(PlanQuery(from: from, to: to, mode: mode, time: time));

  test('leave by: several options, in departure order, the first the next bus', () {
    final js = (plan(stop('A'), stop('C'), PlanMode.leaveBy, at(8, 1)) as PlanFound).journeys;
    expect(js.length, inInclusiveRange(3, 5));
    expect(js.first.departs, 8 * 3600 + 600);
    expect(js.map((j) => j.departs).toList(), [...js.map((j) => j.departs)]..sort());
  });

  test('arrive by: every option arrives in time', () {
    final js = (plan(stop('A'), stop('E'), PlanMode.arriveBy, at(8, 45)) as PlanFound).journeys;
    expect(js, isNotEmpty);
    expect(js.every((j) => j.arrives <= 8 * 3600 + 2700), isTrue);
  });

  test('a pin walks to every stop within 800 m', () {
    final ids = planner
        .offsetsFor(PinPlace(lat: 47.5702, lon: -52.7480, label: 'Pin'))
        .map((o) => planner.index.stopIds[o.stop])
        .toSet();
    expect(ids, containsAll(['C', 'G']));
    expect(ids, isNot(contains('H')));
  });

  test('a pin far from every stop is too far, and says which end', () {
    final far = PinPlace(lat: 48.5, lon: -53.5, label: 'Far');
    expect((plan(far, stop('C'), PlanMode.leaveNow, at(8, 0)) as PlanTooFar).fromEnd, isTrue);
    expect((plan(stop('A'), far, PlanMode.leaveNow, at(8, 0)) as PlanTooFar).fromEnd, isFalse);
  });

  test('the same stop at both ends gives no journey', () {
    expect(plan(stop('A'), stop('A'), PlanMode.leaveNow, at(8, 0)), isA<PlanNoJourney>());
  });

  test('nothing left today on leave by: no journey (tomorrow is the provider’s job)', () {
    final out = plan(stop('A'), stop('C'), PlanMode.leaveBy, at(22, 0)) as PlanNoJourney;
    expect(out.nextDeparture, isNull);
  });

  test('arrive by too early: no journey, with the earliest arrival that day', () {
    final out = plan(stop('A'), stop('C'), PlanMode.arriveBy, at(8, 5)) as PlanNoJourney;
    expect(out.firstArrival, at(8, 10));
  });

  test("just after midnight, last night's late bus is found", () {
    final j = (plan(stop('Y'), stop('Z'), PlanMode.leaveBy, at(0, 10)) as PlanFound).journeys.first;
    expect(j.at(j.departs), at(0, 20));
  });

  test('ranking: an option that leaves earlier for the same arrival is dropped', () {
    Journey j(int dep, int arr, String trip) => Journey(serviceDate: testDay, legs: [
          RideLeg(routeId: '1', tripId: trip, boardStopId: 'A', alightStopId: 'C', departs: dep, arrives: arr, stopCount: 2),
        ]);
    expect(rankJourneys([j(100, 1000, 'x'), j(400, 1000, 'y')]).map((r) => r.departs), [400]);
    expect(rankJourneys([j(400, 1000, 'y'), j(100, 1000, 'x')]).map((r) => r.departs), [400]);
  });

  test('ranking: no duplicates, and the same list twice ranks the same', () {
    final js = (plan(stop('A'), stop('E'), PlanMode.leaveBy, at(8, 0)) as PlanFound).journeys;
    final keys = js.map((j) => j.legs.whereType<RideLeg>().map((r) => r.tripId).join(',')).toSet();
    expect(keys.length, js.length);
    expect(rankJourneys([...js, ...js]).length, js.length);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/trip_planner/trip_planner_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `place.dart`**

```dart
/// One end of a trip: a stop, or a pin dropped on the map (spec §1).
sealed class Place {
  String get label;
  Map<String, Object?> toJson();

  /// Null for anything that isn't a well-formed stop or pin (an old or corrupt saved entry).
  static Place? fromJson(Object? json) {
    if (json is! Map) return null;
    return switch (json['kind']) {
      'stop' when json['stopId'] is String && json['name'] is String =>
        StopPlace(stopId: json['stopId'] as String, name: json['name'] as String),
      'pin' when json['lat'] is num && json['lon'] is num && json['label'] is String => PinPlace(
          lat: (json['lat'] as num).toDouble(),
          lon: (json['lon'] as num).toDouble(),
          label: json['label'] as String,
        ),
      _ => null,
    };
  }
}

class StopPlace extends Place {
  StopPlace({required this.stopId, required this.name});
  final String stopId;
  final String name;
  @override
  String get label => name;
  @override
  Map<String, Object?> toJson() => {'kind': 'stop', 'stopId': stopId, 'name': name};
  @override
  bool operator ==(Object other) => other is StopPlace && other.stopId == stopId;
  @override
  int get hashCode => stopId.hashCode;
}

class PinPlace extends Place {
  PinPlace({required this.lat, required this.lon, required this.label});
  final double lat;
  final double lon;
  @override
  final String label;
  @override
  Map<String, Object?> toJson() => {'kind': 'pin', 'lat': lat, 'lon': lon, 'label': label};
  @override
  bool operator ==(Object other) => other is PinPlace && other.lat == lat && other.lon == lon;
  @override
  int get hashCode => Object.hash(lat, lon);
}
```

- [ ] **Step 4: Implement `ranking.dart`**

```dart
import 'journey.dart';

/// [a] is at least as good as [b] in every way that matters to the rider.
bool _covers(Journey a, Journey b) =>
    a.departs >= b.departs && a.arrives <= b.arrives && a.rides <= b.rides && a.walkSeconds <= b.walkSeconds;

String _rideKey(Journey j) => j.legs.whereType<RideLeg>().map((r) => r.tripId).join(',');

/// The shown options (spec §3.1).
List<Journey> rankJourneys(List<Journey> candidates, {int max = 5}) {
  final kept = <Journey>[];
  for (final j in candidates) {
    final redundant = kept.any((u) => _covers(u, j) || _rideKey(u) == _rideKey(j) && (u.departs - j.departs).abs() <= 120);
    if (redundant) continue;
    kept.removeWhere((u) => _covers(j, u));
    kept.add(j);
  }
  if (kept.isEmpty) return const [];
  Journey best(int Function(Journey) key) =>
      kept.reduce((a, b) => key(a) < key(b) || key(a) == key(b) && a.arrives <= b.arrives ? a : b);
  final picked = <Journey>{best((j) => j.arrives), best((j) => j.rides), best((j) => j.walkSeconds)};
  final rest = kept.where((j) => !picked.contains(j)).toList()..sort((a, b) => a.departs.compareTo(b.departs));
  return [...picked, ...rest].take(max).toList()..sort((a, b) => a.departs.compareTo(b.departs));
}
```

- [ ] **Step 5: Implement `trip_planner.dart`**

```dart
import 'dart:math' as math;

import '../../data/gtfs/gtfs_repository.dart';
import 'journey.dart';
import 'place.dart';
import 'ranking.dart';
import 'raptor.dart';
import 'timetable_index.dart';
import 'walking.dart';

enum PlanMode { leaveNow, leaveBy, arriveBy }

class PlanQuery {
  const PlanQuery({required this.from, required this.to, required this.mode, required this.time});
  final Place from;
  final Place to;
  final PlanMode mode;

  /// Leave by / arrive by this; for Leave now, now.
  final DateTime time;
}

sealed class PlanOutcome {}

class PlanFound extends PlanOutcome {
  PlanFound(this.journeys);
  final List<Journey> journeys;
}

class PlanNoJourney extends PlanOutcome {
  PlanNoJourney({this.nextDeparture, this.firstArrival});

  /// Leave by: when the first bus that gets there leaves on the next service day (filled in by the provider).
  final DateTime? nextDeparture;

  /// Arrive by: the earliest anything gets there that day.
  final DateTime? firstArrival;
}

class PlanTooFar extends PlanOutcome {
  PlanTooFar({required this.fromEnd});

  /// True when the start has no stop within 800 m; false when the destination hasn't.
  final bool fromEnd;
}

/// Plans trips on one service day's index (spec §3.3).
class TripPlanner {
  TripPlanner(this.repo, this.index);
  final GtfsRepository repo;
  final TimetableIndex index;

  List<StopOffset> offsetsFor(Place p) {
    switch (p) {
      case StopPlace(:final stopId):
        final s = index.stopIndex[stopId];
        return s == null ? const [] : [StopOffset(s, 0)];
      case PinPlace(:final lat, :final lon):
        return [
          for (var i = 0; i < index.stopIds.length; i++)
            if (repo.stopsById[index.stopIds[i]] case final st?)
              if (haversineMeters(lat, lon, st.stopLat, st.stopLon) case final d when d <= maxAccessMeters)
                StopOffset(i, walkSeconds(d)),
        ];
    }
  }

  PlanOutcome plan(PlanQuery q) {
    final access = offsetsFor(q.from);
    if (access.isEmpty) return PlanTooFar(fromEnd: true);
    final egress = offsetsFor(q.to);
    if (egress.isEmpty) return PlanTooFar(fromEnd: false);
    if (q.from == q.to) return PlanNoJourney();

    final t = secondsInServiceDay(index.serviceDate, q.time);
    final candidates = <Journey>[];
    if (q.mode == PlanMode.arriveBy) {
      var by = t;
      for (var i = 0; i < 4; i++) {
        final found = raptorReverse(index, access: access, egress: egress, arriveBy: by);
        if (found.isEmpty) break;
        candidates.addAll(found);
        by = found.map((j) => j.arrives).reduce(math.min) - 60;
      }
      if (candidates.isEmpty) {
        final any = raptorForward(index, access: access, egress: egress, departAt: -Duration.secondsPerDay);
        if (any.isEmpty) return PlanNoJourney();
        return PlanNoJourney(firstArrival: any.first.at(any.map((j) => j.arrives).reduce(math.min)));
      }
    } else {
      var from = t;
      for (var i = 0; i < 4; i++) {
        final found = raptorForward(index, access: access, egress: egress, departAt: from);
        if (found.isEmpty) break;
        candidates.addAll(found);
        from = found.map((j) => j.departs).reduce(math.min) + 60;
      }
      if (candidates.isEmpty) return PlanNoJourney();
    }
    return PlanFound(rankJourneys(candidates));
  }
}
```

- [ ] **Step 6: Run it to see it pass**

Run: `flutter test test/trip_planner/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/domain/trip_planner/place.dart lib/domain/trip_planner/ranking.dart lib/domain/trip_planner/trip_planner.dart test/trip_planner/trip_planner_test.dart
git commit -m "feat(planner): places, ranking and the planner facade

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Reference check and speed on the real schedule

**Files:**
- Create: `test/trip_planner/reference_search.dart` (a slow, obvious earliest-arrival search, for tests only)
- Test: `test/trip_planner/real_schedule_test.dart`

**Interfaces:**
- Consumes: Tasks 3–4, `GtfsRepository.loadFromDirectory`.
- Produces: `int? referenceEarliestArrival(TimetableIndex idx, int from, int to, int departAt)`.

- [ ] **Step 1: Write the reference search**

```dart
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:collection/collection.dart';

const _inf = 1 << 40;

/// The earliest arrival at [to] by at least one bus, found the slow, obvious way: Dijkstra over (stop, mode) states.
/// Modes: 0 = not on a bus yet, 1 = just got off a bus, 2 = walked after a bus. The rules are the planner's:
/// a bus after a bus at the same stop needs the stop's transfer time; walking happens only from the origin before the
/// first bus, or right after a bus; never two walks in a row.
int? referenceEarliestArrival(TimetableIndex idx, int from, int to, int departAt) {
  if (from == to) return null;
  final best = <(int, int), int>{};
  final queue = PriorityQueue<(int, int, int)>((a, b) => a.$1.compareTo(b.$1));
  void push(int t, int s, int mode) {
    if (t < (best[(s, mode)] ?? _inf)) {
      best[(s, mode)] = t;
      queue.add((t, s, mode));
    }
  }

  push(departAt, from, 0);
  while (queue.isNotEmpty) {
    final (t, s, mode) = queue.removeFirst();
    if (t > best[(s, mode)]!) continue;
    if (s == to && mode != 0) return t; // the first one settled is the earliest
    final ready = t + (mode == 1 ? idx.sameStopTransferSeconds[s] : 0);
    for (final (pi, pos) in idx.patternsAtStop[s]) {
      final p = idx.patterns[pi];
      for (var trip = 0; trip < p.departures.length; trip++) {
        if (p.departures[trip][pos] < ready) continue;
        for (var q = pos + 1; q < p.stops.length; q++) {
          push(p.arrivals[trip][q], p.stops[q], 1);
        }
        break; // trips in a pattern don't overtake: the first catchable one is the best
      }
    }
    if (mode == 0 && s == from || mode == 1) {
      for (final f in idx.footpaths[s]) {
        push(t + f.seconds, f.other, mode == 0 ? 0 : 2);
      }
    }
  }
  return null;
}
```

- [ ] **Step 2: Write the real-schedule test**

```dart
import 'dart:io';
import 'dart:math';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/raptor.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reference_search.dart';

void main() {
  final dir = Platform.environment['PLANNER_GTFS'];
  test('RAPTOR matches the reference search on 200 random queries, within the speed limits', () async {
    final repo = GtfsRepository();
    await repo.loadFromDirectory(dir!);
    final day = DateTime(2026, 10, 7); // a Wednesday inside the feed (2026-09-07 … 2026-11-01)

    final sw = Stopwatch()..start();
    final idx = TimetableIndex.build(repo, day);
    final buildMs = sw.elapsedMilliseconds;

    final rnd = Random(20261008);
    final served = [for (var s = 0; s < idx.stopIds.length; s++) if (idx.patternsAtStop[s].isNotEmpty) s];
    final mismatches = <String>[];
    var compared = 0, found = 0, worstMs = 0;
    while (compared < 200) {
      final from = served[rnd.nextInt(served.length)];
      final to = served[rnd.nextInt(served.length)];
      if (from == to) continue;
      final at = 6 * 3600 + rnd.nextInt(16 * 3600);
      final ref = referenceEarliestArrival(idx, from, to, at);
      sw.reset();
      final js = raptorForward(idx, access: [StopOffset(from, 0)], egress: [StopOffset(to, 0)], departAt: at, rides: 8);
      worstMs = max(worstMs, sw.elapsedMilliseconds);
      final got = js.isEmpty ? null : js.map((j) => j.arrives).reduce(min);
      compared++;
      if (got != null) found++;
      if (got != ref) mismatches.add('${idx.stopIds[from]}→${idx.stopIds[to]} at $at: raptor $got, reference $ref');
    }
    // ignore: avoid_print
    print('compared $compared ($found with a journey), index ${buildMs}ms, worst search ${worstMs}ms');
    expect(mismatches, isEmpty, reason: mismatches.take(10).join('\n'));
    expect(found, greaterThan(150), reason: 'most random daytime pairs should be reachable');
    expect(buildMs, lessThan(1000), reason: 'index build');
    expect(worstMs, lessThan(100), reason: 'one search');
  }, skip: dir == null ? 'set PLANNER_GTFS=build/gtfs_current to run against the real schedule' : false);
}
```

The search timing here is the test VM's, a stand-in for the emulator figure in spec §1. Task 15's device check times a real search too.

- [ ] **Step 3: Run it**

Run: `PLANNER_GTFS=build/gtfs_current flutter test test/trip_planner/real_schedule_test.dart`
Expected: PASS, with the printed summary. A mismatch means a bug in `raptor.dart` or `timetable_index.dart`. Debug it (superpowers:systematic-debugging) and add a synthetic test in Task 4's file that reproduces it; never loosen this test. If the index build is over 1 s, add the grid bucketing from Task 3's note.

- [ ] **Step 4: Run it without the env var**

Run: `flutter test test/trip_planner/real_schedule_test.dart`
Expected: one skipped test, with the reason shown.

- [ ] **Step 5: Commit**

```bash
git add test/trip_planner/reference_search.dart test/trip_planner/real_schedule_test.dart
git commit -m "test(planner): RAPTOR against a reference search on the real schedule, with speed limits

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Also stage any `lib/domain/trip_planner/` fix (and its new synthetic test) that Step 3 needed.

---

### Task 8: Shared live-time helpers

**Files:**
- Modify: `lib/domain/arrival_alerts/gtfs_rt_source.dart` (expose the freshness and per-stop visit rules)
- Create: `test/helpers/feed_fixtures.dart` (the alert tests' vehicle and feed builders, moved)
- Modify: `test/arrival_alerts/gtfs_rt_source_test.dart` (use the moved builders; nothing else changes)

**Interfaces:**
- Produces, as public top-level functions in `gtfs_rt_source.dart`:
  - `bool liveTripUsable(TimeTrackFetchResult feed, String tripId, DateTime now)`: the trip has a vehicle with a fix under `liveFixMaxAge` and a known delay.
  - `DateTime? feedTimeAtStop(TimeTrackFetchResult feed, String tripId, String stopId, DateTime scheduledAt)`: the predicted time of the visit nearest `scheduledAt` within `AlertTracker.sameRunWindow`.
- Produces, in `test/helpers/feed_fixtures.dart`: `TimeTrackVehicle fakeVehicle({String trip = 't1', String id = '1415', int? diff = -6, required DateTime fix})` and `TimeTrackFetchResult fakeFeed(List<TimeTrackVehicle> v, {Map<String, Map<String, List<FeedStopTime>>>? stopTimes})`.
- `liveResultForAlert` behaves exactly as before.

- [ ] **Step 1: Refactor the source**

In `gtfs_rt_source.dart`, rename `_feedTimeAtStop(ArrivalAlert alert, TimeTrackFetchResult feed)` to

```dart
DateTime? feedTimeAtStop(TimeTrackFetchResult feed, String tripId, String stopId, DateTime scheduledAt) {
```

with the same body, `alert.tripId` / `alert.stopId` / `alert.scheduledAt` replaced by the parameters, and its doc comment reworded from "the alert's" to "the given". Add:

```dart
/// The trip's bus counts as live: a fix under [liveFixMaxAge] old and a known delay (also used by the trip planner).
bool liveTripUsable(TimeTrackFetchResult feed, String tripId, DateTime now) {
  if (!feed.succeeded || tripId.isEmpty) return false;
  final v = TimeTrackApi.buildTripIndex(feed.vehicles, now: now)[tripId];
  return v != null && _fresh(v, now) && _delayKnown(v);
}
```

In `liveResultForAlert`, keep the `vehicle` lookup (it feeds `_departure`), replace the `vehicle != null && _fresh(vehicle, now) && _delayKnown(vehicle)` test with `vehicle != null && liveTripUsable(feed, alert.tripId, now)`, and the `_feedTimeAtStop(alert, feed)` call with `feedTimeAtStop(feed, alert.tripId, alert.stopId, alert.scheduledAt)`.

- [ ] **Step 2: Move the fixtures**

Create `test/helpers/feed_fixtures.dart` with the imports `package:busboard_nl/data/realtime/timetrack_api.dart` and `package:busboard_nl/data/realtime/timetrack_models.dart`. Move `_vehicle` and `_feed` there verbatim (with their doc comments) from `test/arrival_alerts/gtfs_rt_source_test.dart`, renamed `fakeVehicle` and `fakeFeed`. In the alert test, import `../helpers/feed_fixtures.dart` and rename the calls:

```bash
perl -pi -e 's/\b_vehicle\(/fakeVehicle(/g; s/\b_feed\(/fakeFeed(/g' test/arrival_alerts/gtfs_rt_source_test.dart
```

Remove any import the alert test no longer uses.

- [ ] **Step 3: Run the alert tests**

Run: `flutter test test/arrival_alerts/`
Expected: PASS, unchanged (a pure refactor).

- [ ] **Step 4: Commit**

```bash
git add lib/domain/arrival_alerts/gtfs_rt_source.dart test/helpers/feed_fixtures.dart test/arrival_alerts/gtfs_rt_source_test.dart
git commit -m "refactor(alerts): share the live-trip and per-stop feed-time rules and the feed fixtures

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Live overlay and tight transfers

**Files:**
- Create: `lib/domain/trip_planner/live_overlay.dart`
- Modify: `lib/domain/trip_planner/trip_planner.dart` (add `applyLive`)
- Test: `test/trip_planner/live_overlay_test.dart`

**Interfaces:**
- Consumes: Task 8's `liveTripUsable`, `feedTimeAtStop`, `fakeVehicle`, `fakeFeed`; Task 4's `retimeWalks`, `secondsInServiceDay`; Task 6's `TripPlanner`, `PlanQuery`.
- Produces:
  - `Journey overlayLive(Journey j, TimeTrackFetchResult feed, DateTime now)`: ride legs departing within 60 min of `now`, on a usable live trip, take the feed's times at their board and alight stops. An end the feed doesn't list keeps its timetable time. A leg with neither end listed stays as it was and isn't marked live.
  - `int? firstTightLeg(Journey j)`: the index of the first ride that leaves less than 1 min after the bus before it arrives, or before the walk before it ends; null if none.
  - `List<Journey> TripPlanner.applyLive(PlanQuery q, List<Journey> js, TimeTrackFetchResult? feed, DateTime now)`: overlays each journey. A tight one keeps its legs up to the tight ride and is searched again from there to `q.to`, then flagged `replannedForLiveTimes`. One that can't be finished is dropped. With no feed, or a failed one, journeys come back unchanged.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/live_overlay.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/feed_fixtures.dart';
import 'test_network.dart';

/// A feed where each trip in [delays] (seconds late) has a fresh bus and a time at every stop but [omitStops].
TimeTrackFetchResult feedWith(TestNetwork net, Map<String, int> delays, DateTime now, {Set<String> omitStops = const {}}) {
  final stopTimes = <String, Map<String, List<FeedStopTime>>>{};
  for (final MapEntry(key: trip, value: delay) in delays.entries) {
    for (final rows in net.repo.stopTimesByStopId.values) {
      for (final r in rows.where((r) => r.tripId == trip && !omitStops.contains(r.stopId))) {
        final scheduled = GtfsTime.parse(r.departureTime).toDateTime(testDay);
        stopTimes.putIfAbsent(trip, () => {})[r.stopId] = [
          FeedStopTime(time: scheduled.add(Duration(seconds: delay)), delay: Duration(seconds: delay)),
        ];
      }
    }
  }
  return fakeFeed([
    for (final MapEntry(key: trip, value: delay) in delays.entries)
      fakeVehicle(trip: trip, id: 'bus-$trip', diff: -(delay ~/ 60), fix: now),
  ], stopTimes: stopTimes);
}

void main() {
  late TestNetwork net;
  late TripPlanner planner;
  final now = DateTime(testDay.year, testDay.month, testDay.day, 8, 0);
  final query = PlanQuery(
    from: StopPlace(stopId: 'A', name: 'Stop A'),
    to: StopPlace(stopId: 'E', name: 'Stop E'),
    mode: PlanMode.leaveBy,
    time: now,
  );
  setUp(() {
    net = TestNetwork();
    planner = TripPlanner(net.repo, TimetableIndex.build(net.repo, testDay));
  });

  /// 1-0 (A 08:00 → C 08:10), then 2-1 (C 08:20 → E 08:28).
  Journey firstAtoE() => (planner.plan(query) as PlanFound).journeys.first;

  test('a late bus shifts its leg and marks it live', () {
    final j = firstAtoE();
    final ride = j.legs.whereType<RideLeg>().first;
    final live = overlayLive(j, feedWith(net, {ride.tripId: 120}, now), now).legs.whereType<RideLeg>().first;
    expect(live.live, isTrue);
    expect(live.departs, ride.departs + 120);
    expect(live.arrives, ride.arrives + 120);
  });

  test('a leg more than 60 minutes away keeps the timetable', () {
    final early = DateTime(testDay.year, testDay.month, testDay.day, 6, 30);
    final j = firstAtoE();
    final out = overlayLive(j, feedWith(net, {j.legs.whereType<RideLeg>().first.tripId: 120}, early), early);
    expect(out.legs.whereType<RideLeg>().first.live, isFalse);
  });

  test("a trip in the feed without the leg's board stop keeps the timetable there", () {
    final j = firstAtoE();
    final ride = j.legs.whereType<RideLeg>().first;
    final live = overlayLive(j, feedWith(net, {ride.tripId: 120}, now, omitStops: {ride.boardStopId}), now)
        .legs
        .whereType<RideLeg>()
        .first;
    expect(live.departs, ride.departs);
    expect(live.arrives, ride.arrives + 120);
  });

  test('a stale bus does not count as live', () {
    final j = firstAtoE();
    final ride = j.legs.whereType<RideLeg>().first;
    final stale = feedWith(net, {ride.tripId: 120}, now.subtract(const Duration(minutes: 10)));
    expect(overlayLive(j, stale, now).legs.whereType<RideLeg>().first.live, isFalse);
  });

  test('a transfer made too tight is planned again, and flagged', () {
    // 1-0 ten minutes late reaches C at 08:20, as 2-1 leaves: the rest goes on 2-2 (C 08:35 → E 08:43).
    final j = firstAtoE();
    final first = j.legs.whereType<RideLeg>().first;
    final live = overlayLive(j, feedWith(net, {first.tripId: 600}, now), now);
    expect(firstTightLeg(live), isNotNull);
    final shown = planner.applyLive(query, [j], feedWith(net, {first.tripId: 600}, now), now).single;
    expect(shown.replannedForLiveTimes, isTrue);
    expect(firstTightLeg(shown), isNull);
    expect(shown.legs.whereType<RideLeg>().last.tripId, '2-2');
    expect(shown.arrives, 8 * 3600 + 2580);
  });

  test('no feed or a failed one: journeys unchanged', () {
    final j = firstAtoE();
    expect(planner.applyLive(query, [j], null, now).single.usesLive, isFalse);
    expect(planner.applyLive(query, [j], TimeTrackFetchResult.failure(), now).single.usesLive, isFalse);
  });
}
```

If `TimeTrackFetchResult` has no `failure()` constructor, build a failed result the way `test/timetrack_api_test.dart` or the alert tests do.

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/trip_planner/live_overlay_test.dart`
Expected: FAIL, `overlayLive` doesn't exist.

- [ ] **Step 3: Implement `live_overlay.dart`**

```dart
import '../../data/realtime/timetrack_api.dart';
import '../arrival_alerts/gtfs_rt_source.dart';
import 'journey.dart';
import 'walking.dart';

/// Ride legs leaving within this of now take live times (spec §3.4).
const liveHorizon = Duration(minutes: 60);

Journey overlayLive(Journey j, TimeTrackFetchResult feed, DateTime now) {
  final legs = <Leg>[
    for (final leg in j.legs)
      if (leg is RideLeg) _liveRide(j, leg, feed, now) else leg,
  ];
  return j.copyWith(legs: retimeWalks(legs));
}

RideLeg _liveRide(Journey j, RideLeg leg, TimeTrackFetchResult feed, DateTime now) {
  final departsAt = j.at(leg.departs);
  if (departsAt.difference(now) > liveHorizon || !liveTripUsable(feed, leg.tripId, now)) return leg;
  final dep = feedTimeAtStop(feed, leg.tripId, leg.boardStopId, departsAt);
  final arr = feedTimeAtStop(feed, leg.tripId, leg.alightStopId, j.at(leg.arrives));
  if (dep == null && arr == null) return leg;
  return leg.copyWithTimes(
    departs: dep == null ? null : secondsInServiceDay(j.serviceDate, dep),
    arrives: arr == null ? null : secondsInServiceDay(j.serviceDate, arr),
    live: true,
  );
}

/// The first ride that leaves less than [minTransferSeconds] after the bus before it arrives, or before the walk
/// before it ends; null when every connection works.
int? firstTightLeg(Journey j) {
  for (var i = 1; i < j.legs.length; i++) {
    final leg = j.legs[i];
    if (leg is! RideLeg) continue;
    final prev = j.legs[i - 1];
    final needed = prev is RideLeg ? minTransferSeconds : 0;
    if (leg.departs - prev.endSeconds < needed) return i;
  }
  return null;
}
```

- [ ] **Step 4: Implement `TripPlanner.applyLive`**

Add to `TripPlanner` in `trip_planner.dart`, importing `live_overlay.dart` and `../../data/realtime/timetrack_api.dart`:

```dart
  /// Live times for the shown journeys; a tight one is planned again from where it broke (spec §3.4).
  List<Journey> applyLive(PlanQuery q, List<Journey> js, TimeTrackFetchResult? feed, DateTime now) {
    if (feed == null || !feed.succeeded) return js;
    final out = <Journey>[];
    for (final j in js) {
      final live = overlayLive(j, feed, now);
      final cut = firstTightLeg(live);
      if (cut == null) {
        out.add(live);
        continue;
      }
      // Keep the legs before the tight ride; the rider is at the end of the last of them.
      final kept = live.legs.sublist(0, cut);
      final last = kept.last;
      final stopId = last is RideLeg ? last.alightStopId : (last as WalkLeg).toStopId;
      final from = stopId == null ? null : index.stopIndex[stopId];
      if (from == null) continue;
      final ready = last.endSeconds + (last is RideLeg ? minTransferSeconds : 0);
      final rest = raptorForward(index, access: [StopOffset(from, 0)], egress: offsetsFor(q.to), departAt: ready);
      if (rest.isEmpty) continue;
      final tail = rest.reduce((a, b) => a.arrives <= b.arrives ? a : b);
      out.add(Journey(serviceDate: j.serviceDate, legs: retimeWalks([...kept, ...tail.legs]), replannedForLiveTimes: true));
    }
    return out;
  }
```

- [ ] **Step 5: Run it to see it pass**

Run: `flutter test test/trip_planner/ test/arrival_alerts/`
Expected: PASS.

- [ ] **Step 6: Replay check against a capture (env-gated)**

Add to `live_overlay_test.dart` a test skipped unless both `ALERT_CAPTURE` and `ALERT_GTFS` are set (the same variables `test/arrival_alerts/alert_replay_test.dart` uses). It:
1. loads the schedule from `ALERT_GTFS` with `GtfsRepository.loadFromDirectory`;
2. loads the capture with `loadCapture(File(path).openRead().transform(utf8.decoder).transform(const LineSplitter()))`, imported via `import '../arrival_alerts/alert_replay_test.dart' show loadCapture, ReplayPoll;`;
3. takes the first poll whose `feed` is non-null and succeeded, and builds a `TripPlanner` for that poll's service day (`DateTime(poll.at.year, poll.at.month, poll.at.day)`);
4. plans 20 seeded (`Random(1006)`) stop-to-stop Leave by queries at `poll.at`, using stops that have patterns, and runs `applyLive` with `poll.feed` and `now: poll.at`.

It asserts that no shown journey has a `firstTightLeg`, that every `live` leg's departure is within 15 min of its timetable departure, and (print the count) that at least one leg is live. Run it with:

`TZ=America/St_Johns ALERT_CAPTURE=test/fixtures/timetrack/raw_gtfsrt_2026-10-06_midday.jsonl ALERT_GTFS=build/gtfs_current flutter test test/trip_planner/live_overlay_test.dart`

Expected: PASS. If no leg is live, report the count; don't weaken the assertions.

- [ ] **Step 7: Commit**

```bash
git add lib/domain/trip_planner/live_overlay.dart lib/domain/trip_planner/trip_planner.dart test/trip_planner/live_overlay_test.dart
git commit -m "feat(planner): live times for the next hour, re-planning a transfer they make too tight

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Saved trips store

**Files:**
- Create: `lib/data/trip_planner/saved_trip_store.dart`
- Test: `test/trip_planner/saved_trip_store_test.dart`

**Interfaces:**
- Consumes: Task 6's `Place` (`toJson` / `fromJson`).
- Produces:

```dart
const maxSavedTrips = 10;
class SavedTrip { const SavedTrip({required String id, required String name, required Place from, required Place to});
  SavedTrip renamed(String name); Map<String, Object?> toJson(); static SavedTrip? fromJson(Object? json); }
class SavedTripStore { SavedTripStore([SharedPreferencesAsync? prefs]);
  Future<List<SavedTrip>> read();
  Future<bool> add(SavedTrip t);   // false when full, or a trip with the same ends is saved
  Future<void> rename(String id, String name); Future<void> remove(String id); }
```

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';

import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  SavedTrip trip(String id, String a, String b) =>
      SavedTrip(id: id, name: '$a → $b', from: StopPlace(stopId: a, name: a), to: StopPlace(stopId: b, name: b));

  test('add, read, rename, remove; a pin end survives the round trip', () async {
    final store = SavedTripStore();
    expect(await store.add(trip('1', '1150', '1600')), isTrue);
    final pin = PinPlace(lat: 47.56, lon: -52.71, label: 'Home');
    expect(await store.add(SavedTrip(id: '2', name: 'Home → MUN', from: pin, to: StopPlace(stopId: '1150', name: 'MUN Centre'))), isTrue);
    final read = await store.read();
    expect(read.map((t) => t.name), ['1150 → 1600', 'Home → MUN']);
    expect(read[1].from, pin);
    expect(read[1].from.label, 'Home');
    await store.rename('1', 'Downtown → Avalon');
    expect((await store.read()).first.name, 'Downtown → Avalon');
    await store.remove('1');
    expect((await store.read()).single.id, '2');
  });

  test('the same ends twice is refused; so is an 11th trip', () async {
    final store = SavedTripStore();
    expect(await store.add(trip('1', 'A', 'B')), isTrue);
    expect(await store.add(trip('x', 'A', 'B')), isFalse);
    expect(await store.add(trip('r', 'B', 'A')), isTrue); // the way back is a different trip
    for (var i = 3; i <= maxSavedTrips; i++) {
      expect(await store.add(trip('$i', 'S$i', 'T$i')), isTrue);
    }
    expect(await store.add(trip('11', 'Y', 'Z')), isFalse);
    expect((await store.read()).length, maxSavedTrips);
  });

  test('a corrupt or unknown entry is skipped, the rest kept', () async {
    await SharedPreferencesAsync().setString('saved_trips.v1', jsonEncode([
      {'id': '1', 'name': 'ok', 'from': {'kind': 'stop', 'stopId': 'A', 'name': 'A'}, 'to': {'kind': 'stop', 'stopId': 'B', 'name': 'B'}},
      {'id': '2', 'name': 'bad', 'from': {'kind': 'nope'}, 'to': {'kind': 'stop', 'stopId': 'B', 'name': 'B'}},
      {'id': '3', 'name': 'no ends'},
      'garbage',
    ]));
    expect((await SavedTripStore().read()).map((t) => t.id), ['1']);
  });

  test('unreadable JSON reads as no trips, and saving still works after', () async {
    await SharedPreferencesAsync().setString('saved_trips.v1', '{not json');
    final store = SavedTripStore();
    expect(await store.read(), isEmpty);
    expect(await store.add(trip('1', 'A', 'B')), isTrue);
    expect((await store.read()).single.id, '1');
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/trip_planner/saved_trip_store_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/trip_planner/place.dart';

const maxSavedTrips = 10;

/// A trip the rider saved: its ends and a name, nothing else (spec §3.5).
class SavedTrip {
  const SavedTrip({required this.id, required this.name, required this.from, required this.to});
  final String id;
  final String name;
  final Place from;
  final Place to;

  SavedTrip renamed(String name) => SavedTrip(id: id, name: name, from: from, to: to);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'from': from.toJson(), 'to': to.toJson()};

  static SavedTrip? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || json['name'] is! String) return null;
    final from = Place.fromJson(json['from']);
    final to = Place.fromJson(json['to']);
    if (from == null || to == null) return null;
    return SavedTrip(id: json['id'] as String, name: json['name'] as String, from: from, to: to);
  }
}

/// Saved trips, on the phone only ([SharedPreferencesAsync], like the alert store).
class SavedTripStore {
  SavedTripStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _prefs;
  static const _key = 'saved_trips.v1';

  Future<List<SavedTrip>> read() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final e in list) ?SavedTrip.fromJson(e)];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _write(List<SavedTrip> trips) =>
      _prefs.setString(_key, jsonEncode([for (final t in trips) t.toJson()]));

  Future<bool> add(SavedTrip trip) async {
    final trips = await read();
    if (trips.length >= maxSavedTrips) return false;
    if (trips.any((t) => t.from == trip.from && t.to == trip.to)) return false;
    await _write([...trips, trip]);
    return true;
  }

  Future<void> rename(String id, String name) async =>
      _write([for (final t in await read()) t.id == id ? t.renamed(name) : t]);

  Future<void> remove(String id) async => _write([for (final t in await read()) if (t.id != id) t]);
}
```

`?expr` inside a collection literal is Dart's null-aware element (Dart 3.8+). If the project's SDK constraint is older, use `.whereType<SavedTrip>()` on a mapped list instead.

- [ ] **Step 4: Run it to see it pass**

Run: `flutter test test/trip_planner/saved_trip_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/trip_planner/saved_trip_store.dart test/trip_planner/saved_trip_store_test.dart
git commit -m "feat(planner): saved trips on the phone

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Providers

**Files:**
- Create: `lib/state/trip_planner_providers.dart`
- Test: `test/state/trip_planner_providers_test.dart`

**Interfaces:**
- Consumes: `gtfsRepositoryProvider`, `timetrackApiProvider` (`lib/state/providers.dart`); Tasks 3, 6, 9, 10.
- Produces:

```dart
final plannerClockProvider = Provider<DateTime Function()>(...);              // DateTime.now
typedef IndexBuilder = Future<TimetableIndex> Function(GtfsRepository repo, DateTime day);
Future<TimetableIndex> buildIndexInBackground(GtfsRepository repo, DateTime day);   // Isolate.run on a slim copy
final timetableIndexBuilderProvider = Provider<IndexBuilder>(...);            // tests override with a same-isolate build
final tripPlannerProvider = FutureProvider.autoDispose.family<TripPlanner, DateTime>(...); // keyed by date only
class PlanDraft { const PlanDraft({Place? from, Place? to, PlanMode mode = PlanMode.leaveNow, DateTime? time});
  PlanQuery? toQuery(DateTime now); }
class PlanQueryNotifier extends Notifier<PlanDraft> { void setFrom(Place?); void setTo(Place?); void swap();
  void setMode(PlanMode); void setTime(DateTime); void setTrip(Place from, Place to); }
final planQueryProvider = NotifierProvider<PlanQueryNotifier, PlanDraft>(PlanQueryNotifier.new);
final plannerLiveFeedProvider = FutureProvider.autoDispose<TimeTrackFetchResult?>(...); // refreshed every 30 s
final planResultsProvider = FutureProvider.autoDispose<PlanOutcome?>(...);  // null until both ends are set
final savedTripStoreProvider = Provider<SavedTripStore>(...);
class SavedTripsNotifier extends AsyncNotifier<List<SavedTrip>> { Future<bool> add(SavedTrip); Future<void> rename(String, String); Future<void> remove(String); }
final savedTripsProvider = AsyncNotifierProvider<SavedTripsNotifier, List<SavedTrip>>(SavedTripsNotifier.new);
final savedTripNextProvider = FutureProvider.autoDispose.family<List<Journey>, String>(...); // a saved trip's next ≤ 3, leave now
```

- [ ] **Step 1: Write the failing test**

```dart
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../trip_planner/test_network.dart';

void main() {
  late ProviderContainer c;
  DateTime at(int h, int m) => DateTime(testDay.year, testDay.month, testDay.day, h, m);
  StopPlace stop(String id) => StopPlace(stopId: id, name: 'Stop $id');

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final net = TestNetwork();
    c = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => net.repo),
      plannerClockProvider.overrideWithValue(() => at(8, 1)),
      timetableIndexBuilderProvider.overrideWithValue((repo, day) async => TimetableIndex.build(repo, day)),
      // The live feed is down: plans use the timetable.
      timetrackApiProvider.overrideWithValue(TimeTrackApi(client: MockClient((_) async => http.Response('', 503)))),
    ]);
  });
  tearDown(() => c.dispose());

  Future<T> read<T>(ProviderListenable<AsyncValue<T>> p, Future<T> Function() future) async {
    final sub = c.listen(p, (_, _) {});
    addTearDown(sub.close);
    return future();
  }

  Future<PlanOutcome?> results() => read(planResultsProvider, () => c.read(planResultsProvider.future));

  test('no plan until both ends are set; then leave now takes the next bus', () async {
    expect(await results(), isNull);
    c.read(planQueryProvider.notifier)
      ..setFrom(stop('A'))
      ..setTo(stop('C'));
    final out = await results() as PlanFound;
    expect(out.journeys.first.departs, 8 * 3600 + 600);
    expect(out.journeys.any((j) => j.usesLive), isFalse);
  });

  test('swap exchanges the ends', () {
    c.read(planQueryProvider.notifier)
      ..setFrom(stop('A'))
      ..setTo(stop('C'))
      ..swap();
    expect((c.read(planQueryProvider).from as StopPlace).stopId, 'C');
  });

  test('arrive by 8:25: every option arrives in time', () async {
    c.read(planQueryProvider.notifier)
      ..setFrom(stop('A'))
      ..setTo(stop('C'))
      ..setMode(PlanMode.arriveBy)
      ..setTime(at(8, 25));
    final out = await results() as PlanFound;
    expect(out.journeys.every((j) => j.arrives <= 8 * 3600 + 1500), isTrue);
  });

  test('leave by 22:00 with nothing left today: the first bus tomorrow', () async {
    c.read(planQueryProvider.notifier)
      ..setFrom(stop('A'))
      ..setTo(stop('C'))
      ..setMode(PlanMode.leaveBy)
      ..setTime(at(22, 0));
    final out = await results() as PlanNoJourney;
    expect(out.nextDeparture, DateTime(testDay.year, testDay.month, testDay.day + 1, 8, 0));
  });

  test('saved trips: add once; the same ends again stay one', () async {
    await read(savedTripsProvider, () => c.read(savedTripsProvider.future));
    final n = c.read(savedTripsProvider.notifier);
    expect(await n.add(SavedTrip(id: '1', name: 'A → C', from: stop('A'), to: stop('C'))), isTrue);
    expect(await n.add(SavedTrip(id: '2', name: 'again', from: stop('A'), to: stop('C'))), isFalse);
    expect((await c.read(savedTripsProvider.future)).map((t) => t.id), ['1']);
  });

  test("a saved trip's next departures: up to 3, the first the next bus", () async {
    await read(savedTripsProvider, () => c.read(savedTripsProvider.future));
    await c.read(savedTripsProvider.notifier).add(SavedTrip(id: '1', name: 'A → C', from: stop('A'), to: stop('C')));
    final next = await read(savedTripNextProvider('1'), () => c.read(savedTripNextProvider('1').future));
    expect(next.length, inInclusiveRange(1, 3));
    expect(next.first.departs, 8 * 3600 + 600);
  });
}
```

Match the override calls to the Riverpod version in `pubspec.lock` (look at `test/state/arrival_alert_controller_test.dart`). Keep each test's assertions.

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/state/trip_planner_providers_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `trip_planner_providers.dart`**

```dart
import 'dart:async';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/gtfs/gtfs_repository.dart';
import '../data/realtime/timetrack_api.dart';
import '../data/trip_planner/saved_trip_store.dart';
import '../domain/trip_planner/journey.dart';
import '../domain/trip_planner/place.dart';
import '../domain/trip_planner/ranking.dart';
import '../domain/trip_planner/timetable_index.dart';
import '../domain/trip_planner/trip_planner.dart';
import 'providers.dart';

final plannerClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

typedef IndexBuilder = Future<TimetableIndex> Function(GtfsRepository repo, DateTime day);

/// Builds a day's index in a background isolate (spec §3.3), sending it only what the index reads (no shapes).
Future<TimetableIndex> buildIndexInBackground(GtfsRepository repo, DateTime day) {
  final slim = GtfsRepository();
  slim.stopsById.addAll(repo.stopsById);
  slim.tripsById.addAll(repo.tripsById);
  slim.stopTimesByStopId.addAll(repo.stopTimesByStopId);
  slim.transfersByFromStop.addAll(repo.transfersByFromStop);
  slim.calendarsById.addAll(repo.calendarsById);
  slim.calendarDates.addAll(repo.calendarDates);
  return Isolate.run(() => TimetableIndex.build(slim, day));
}

final timetableIndexBuilderProvider = Provider<IndexBuilder>((ref) => buildIndexInBackground);

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// The planner for one service day ([day] is date-only), kept for 10 minutes after it was built.
final tripPlannerProvider = FutureProvider.autoDispose.family<TripPlanner, DateTime>((ref, day) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 10), link.close);
  ref.onDispose(timer.cancel);
  final repo = await ref.watch(gtfsRepositoryProvider.future);
  return TripPlanner(repo, await ref.read(timetableIndexBuilderProvider)(repo, day));
});

/// What the Plan form holds.
class PlanDraft {
  const PlanDraft({this.from, this.to, this.mode = PlanMode.leaveNow, this.time});
  final Place? from;
  final Place? to;
  final PlanMode mode;
  final DateTime? time;

  PlanQuery? toQuery(DateTime now) => from == null || to == null
      ? null
      : PlanQuery(from: from!, to: to!, mode: mode, time: mode == PlanMode.leaveNow ? now : time ?? now);
}

class PlanQueryNotifier extends Notifier<PlanDraft> {
  @override
  PlanDraft build() => const PlanDraft();

  void setFrom(Place? p) => state = PlanDraft(from: p, to: state.to, mode: state.mode, time: state.time);
  void setTo(Place? p) => state = PlanDraft(from: state.from, to: p, mode: state.mode, time: state.time);
  void swap() => state = PlanDraft(from: state.to, to: state.from, mode: state.mode, time: state.time);
  void setMode(PlanMode m) => state = PlanDraft(from: state.from, to: state.to, mode: m, time: state.time);
  void setTime(DateTime t) => state = PlanDraft(from: state.from, to: state.to, mode: state.mode, time: t);

  /// A saved trip opened from its card: its ends, leaving now.
  void setTrip(Place from, Place to) => state = PlanDraft(from: from, to: to);
}

final planQueryProvider = NotifierProvider<PlanQueryNotifier, PlanDraft>(PlanQueryNotifier.new);

/// The live feed for plans, fetched again every 30 s while anything watches it (spec §3.4); null when unreadable.
final plannerLiveFeedProvider = FutureProvider.autoDispose<TimeTrackFetchResult?>((ref) async {
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  try {
    return await ref.read(timetrackApiProvider).fetchLiveVehiclesResult();
  } catch (_) {
    return null;
  }
});

/// Plans [q] with live times. When nothing runs later today on Leave by / Leave now, finds tomorrow's first bus.
Future<PlanOutcome> _plan(Ref ref, PlanQuery q, TimeTrackFetchResult? feed, DateTime now) async {
  final planner = await ref.watch(tripPlannerProvider(_day(q.time)).future);
  final outcome = planner.plan(q);
  if (outcome is PlanNoJourney && q.mode != PlanMode.arriveBy && q.from != q.to) {
    final tomorrow = DateTime(q.time.year, q.time.month, q.time.day + 1);
    final next = (await ref.watch(tripPlannerProvider(tomorrow).future))
        .plan(PlanQuery(from: q.from, to: q.to, mode: PlanMode.leaveBy, time: tomorrow));
    if (next is PlanFound && next.journeys.isNotEmpty) {
      final first = next.journeys.first;
      return PlanNoJourney(nextDeparture: first.at(first.departs));
    }
    return outcome;
  }
  if (outcome is! PlanFound) return outcome;
  final live = rankJourneys(planner.applyLive(q, outcome.journeys, feed, now));
  return live.isEmpty ? PlanNoJourney() : PlanFound(live);
}

final planResultsProvider = FutureProvider.autoDispose<PlanOutcome?>((ref) async {
  final now = ref.read(plannerClockProvider)();
  final q = ref.watch(planQueryProvider).toQuery(now);
  if (q == null) return null;
  final feed = await ref.watch(plannerLiveFeedProvider.future);
  return _plan(ref, q, feed, now);
});

final savedTripStoreProvider = Provider<SavedTripStore>((ref) => SavedTripStore());

class SavedTripsNotifier extends AsyncNotifier<List<SavedTrip>> {
  SavedTripStore get _store => ref.read(savedTripStoreProvider);

  @override
  Future<List<SavedTrip>> build() => _store.read();

  Future<bool> add(SavedTrip trip) async {
    final ok = await _store.add(trip);
    state = AsyncData(await _store.read());
    return ok;
  }

  Future<void> rename(String id, String name) async {
    await _store.rename(id, name);
    state = AsyncData(await _store.read());
  }

  Future<void> remove(String id) async {
    await _store.remove(id);
    state = AsyncData(await _store.read());
  }
}

final savedTripsProvider = AsyncNotifierProvider<SavedTripsNotifier, List<SavedTrip>>(SavedTripsNotifier.new);

/// A saved trip's next departures, leaving now, with live times (spec §3.5).
final savedTripNextProvider = FutureProvider.autoDispose.family<List<Journey>, String>((ref, id) async {
  final trips = await ref.watch(savedTripsProvider.future);
  final trip = trips.where((t) => t.id == id).firstOrNull;
  if (trip == null) return const [];
  final now = ref.read(plannerClockProvider)();
  final feed = await ref.watch(plannerLiveFeedProvider.future);
  final out = await _plan(ref, PlanQuery(from: trip.from, to: trip.to, mode: PlanMode.leaveNow, time: now), feed, now);
  return out is PlanFound ? out.journeys.take(3).toList() : const [];
});
```

`buildIndexInBackground` keeps the isolate closure to `slim` and `day`, so nothing unsendable (`ref`, timers) is captured. If `Isolate.run` still fails to send a `GtfsRepository` field, report it with the error text. Don't silently fall back to the main isolate.

- [ ] **Step 4: Run it to see it pass**

Run: `flutter test test/state/trip_planner_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Add an isolate smoke test**

Append to the same test file a test that calls the real `buildIndexInBackground(TestNetwork().repo, testDay)` and checks the index has the route 1 pattern. (`Isolate.run` works in plain `test`, not in `testWidgets`.)

Run: `flutter test test/state/trip_planner_providers_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/state/trip_planner_providers.dart test/state/trip_planner_providers_test.dart
git commit -m "feat(planner): providers for plans, live refresh and saved trips

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: The Plan tab, place picker and results

**Files:**
- Modify: `lib/routing/router.dart` (a fourth `StatefulShellBranch`: `/plan`, with child `journey`)
- Modify: `lib/ui/shell/app_shell.dart` (a fourth `BBNavItem`, label `Plan`)
- Modify: `lib/ui/kit/bb_icons.dart` (add icons; code points from `phosphor_flutter-2.1.0/lib/src/phosphor_icons_regular.dart`)
- Create: `lib/ui/trip_planner/plan_screen.dart`
- Create: `lib/ui/trip_planner/place_picker_sheet.dart`
- Create: `lib/ui/trip_planner/journey_card.dart`
- Create: `lib/ui/trip_planner/journey_detail_screen.dart` (minimal here; Task 13 fills it)
- Create: `lib/ui/trip_planner/saved_trips_section.dart` (an empty placeholder here; Task 14 fills it)
- Create: `test/helpers/planner_app.dart` (pumps the app with the planner overrides; used by Tasks 12–14)
- Test: `test/ui/plan_screen_test.dart`

**Interfaces:**
- Consumes: Task 11's providers; the kit (`BBScaffold`, `BBTopBar`, `BBCard`, `BBPressable`, `BBIconButton`, `BBSegmented`, `BBSegment`, `BBTextField`, `BBEmptyState`, `BBLoading`, `BBPill`, `BBTime`, `RouteBadge`, `BBNavBar.reservedHeight`).
- Produces:
  - `PlanScreen` at `/plan`; `JourneyDetailScreen(journey:)` at `/plan/journey` (`state.extra` is the `Journey`).
  - `Future<PlacePick?> showPlacePicker(BuildContext context, {required bool forFrom})`, where `sealed class PlacePick`, `class PickedPlace extends PlacePick { final Place place; }` and `class PickOnMap extends PlacePick {}` (the Plan screen sends the rider to `/map?pick=from` or `/map?pick=to`; Task 13 does the map side).
  - `JourneyCard({required Journey journey, required VoidCallback onTap})`; `String journeySummary(Journey j, GtfsRepository repo)` for its screen-reader label.
  - `SavedTripsSection()`.
  - `BBIcons.plan` / `BBIcons.planFill` (`0xe39c`, Phosphor `path`), `BBIcons.swap` (`0xe098`, `arrowsDownUp`), `BBIcons.walk` (`0xe73a`, `personSimpleWalk`), following the existing regular/fill naming.

**The Plan screen** (spec §2.2), top to bottom, laid out like `lib/ui/stop_picker/stop_picker_screen.dart`:
1. `BBTopBar(title: 'Plan a trip', large: true)` with the Settings action that the stop picker's top bar has.
2. `SavedTripsSection()`.
3. A `BBCard` holding the form:
   - **From** and **To** rows: `BBPressable`s showing the place's label, or "Choose a starting point" / "Choose a destination" in the muted text style. Each opens `showPlacePicker`. Semantics labels: "From: <label>" / "From: not chosen", and the same for To.
   - A swap `BBIconButton(icon: BBIcons.swap, semanticLabel: 'Swap start and destination')` calling `swap()`.
   - `BBSegmented<PlanMode>` with segments "Leave now", "Leave by", "Arrive by".
   - When the mode isn't Leave now: a time button showing `BBTime.of(time)` that opens `showTimePicker` (minute precision) and sets the draft time on that day. Below it, a date button opens `showDatePicker` (today to the feed's end date) and shows "Today", "Tomorrow" or the weekday and date.
4. Results, from `ref.watch(planResultsProvider)`:
   - `AsyncData(null)`: muted text "Choose where you're going".
   - loading: `BBLoading`.
   - `PlanFound`: a `JourneyCard` per journey; a tap pushes `/plan/journey` with the journey as `extra`.
   - `PlanNoJourney`: `BBEmptyState(icon: BBIcons.noService, title: 'No buses get you there at that time', message: …)`. The message is "The next bus that gets you there leaves tomorrow at ${BBTime.of(next)}" when `nextDeparture` is set, "The earliest you can get there is ${BBTime.of(first)}" when `firstArrival` is set, and null otherwise.
   - `PlanTooFar`: `BBEmptyState(icon: BBIcons.warning, title: 'Too far from a bus stop', message: 'Pick a closer point for your ${fromEnd ? 'start' : 'destination'}.')`.
   - error: `BBEmptyState(icon: BBIcons.warning, title: "Couldn't plan that trip", message: 'Try again in a moment.')`.
5. A bottom gap of `BBNavBar.reservedHeight(context) + BBSpace.l`, as the Board has.

**JourneyCard:**
- "8:12 → 8:47" (`BBTime.of` of each), and "35 min" on the right.
- Below: `RouteBadge`s for the ride legs in order, joined by a `›` glyph, then `BBIcons.walk` with "5 min walk" when the walking total is at least 1 min.
- A `BBPill` in the live tone reading "Live" when `journey.usesLive`.
- "Changed for live times", with `BBIcons.warning`, when `replannedForLiveTimes`.
- The whole card is one button, with the semantics label `journeySummary`, e.g. "Leave 8:12, arrive 8:47, 35 minutes, route 10 then route 2, 5 minutes walking, live times". Copy the badge and time patterns from `lib/ui/board/arrival_row_tile.dart`.

**showPlacePicker:** a bottom sheet like `lib/ui/arrival_alerts/lead_time_sheet.dart`, with:
- A `BBTextField` (hint "Stop number or name", autofocus).
- Matches from `GtfsRepository.stopsById`: stop ids starting with the typed digits, or names containing the text case-insensitively; at most 20, sorted by stop id. Each row shows "Name (id)" and returns `PickedPlace(StopPlace(...))`.
- A "My location" row (`BBIcons.nearMe`) that gets the position with the same Geolocator call and permission handling `nearestStopsProvider` uses (`lib/state/providers.dart:232–260`) and returns `PickedPlace(PinPlace(lat, lon, label: 'My location'))`. When location is off or denied, the row reads "Location is off" and is disabled.
- A "Pick on map" row (`BBIcons.map`) that returns `PickOnMap()`.

**JourneyDetailScreen (minimal):** a `BBScaffold` with `BBTopBar(title: 'Your trip', onBack: …)` and one `Text` per leg ("Walk 6 min", "Route 1 · 8:10 → 8:20"). Task 13 replaces the body.

**test/helpers/planner_app.dart:** `Future<void> pumpPlannerApp(WidgetTester tester, {required TestNetwork net, required DateTime now, String initial = '/plan'})` pumps the real router the way `test/ui/app_shell_test.dart` does. Use that file's overrides, plus `gtfsRepositoryProvider` → `net.repo`, `plannerClockProvider` → `now`, `timetableIndexBuilderProvider` → a same-isolate build, `timetrackApiProvider` → a 503 `MockClient`, and the in-memory prefs (`useInMemoryAlertStore` from `test/helpers/fake_alerts.dart`, which also covers the saved-trip store). Stub the map with `mapViewBuilderProvider.overrideWithValue(...)`, as `test/ui/map_screen_test.dart` does.

- [ ] **Step 1: Write the failing widget tests** in `test/ui/plan_screen_test.dart`, all at `now` = 08:01 on `testDay` with `TestNetwork`:
  1. The nav bar has four items: Board, Map, Alerts, Plan. Tapping **Plan** shows "Plan a trip".
  2. Choose From: tap "Choose a starting point", type `A`, tap "Stop A (A)". Choose To the same way with `C`. A `JourneyCard` showing `8:10 → 8:20` appears.
  3. Tapping swap shows "Stop C" in the From row and "Stop A" in the To row.
  4. Select **Arrive by**; the time button appears. Tap it, switch the dialog to input mode, enter 8:25, confirm. Every shown card's arrival is no later than 8:25.
  5. With From A and To H (unreachable), "No buses get you there at that time" shows.
  6. At `MediaQuery` text scale 2.0, the empty form and a results list pump with `tester.takeException()` null.
  7. The From row, To row, swap button, each segment and a journey card all have non-empty semantics labels (`tester.getSemantics(find.byType(JourneyCard).first).label` contains "Leave 8:10").

  Update any existing shell test that expects three nav items (`test/ui/app_shell_test.dart`, and the overflow and golden tests if they count tabs) to expect four. Regenerate goldens only for screens whose nav bar changed (`flutter test --update-goldens test/ui/screen_golden_test.dart`), and say so in the report.

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/ui/plan_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement** the files above. Register the branch after the Alerts branch:

```dart
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/plan',
              builder: (context, state) => const PlanScreen(),
              routes: [
                GoRoute(
                  path: 'journey',
                  builder: (context, state) => JourneyDetailScreen(journey: state.extra! as Journey),
                ),
              ],
            ),
          ],
        ),
```

  In `app_shell.dart`, add `BBNavItem(label: 'Plan', icon: BBIcons.plan, activeIcon: BBIcons.planFill)` as the fourth item.

- [ ] **Step 4: Run all UI tests**

Run: `flutter test test/ui/ test/routing/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/routing/router.dart lib/ui/shell/app_shell.dart lib/ui/kit/bb_icons.dart lib/ui/trip_planner test/helpers/planner_app.dart test/ui
git commit -m "feat(planner): the Plan tab, place picker and results

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Journey detail and the map

**Files:**
- Modify: `lib/ui/trip_planner/journey_detail_screen.dart` (the full detail)
- Modify: `lib/ui/map/map_view.dart` (`MapViewConfig.onLongPress`, wired to `MapLibreMap.onMapLongClick`)
- Modify: `lib/ui/map/map_screen.dart` (long-press sheet; pick mode from `/map?pick=from|to`; drawing a journey)
- Modify: `lib/ui/map/stop_card.dart` (a "Plan a trip from here" button)
- Create: `lib/ui/trip_planner/map_plan_sheet.dart`
- Create: `lib/state/journey_on_map_provider.dart`
- Test: `test/ui/journey_detail_test.dart`; additions to `test/ui/map_screen_test.dart` and `test/ui/map_cards_test.dart`

**Interfaces:**
- Consumes: Task 12's routes, `planQueryProvider`, `savedTripsProvider`, `pumpPlannerApp`; `AlertBell` (`lib/ui/arrival_alerts/alert_bell.dart`) and the Board's follow entry (see how `ArrivalBoardScreen` / `ArrivalRowTile` start follow mode and build the bell's arrival).
- Produces:
  - `MapViewConfig.onLongPress: void Function(LatLng)?`.
  - `final journeyOnMapProvider = NotifierProvider<JourneyOnMapNotifier, Journey?>(...)` with `show(Journey)` and `clear()`.
  - `Future<void> showMapPlanSheet(BuildContext context, WidgetRef ref, LatLng at)`.

**Journey detail** (spec §2.3):
- A `BBTopBar(title: 'Your trip')` whose subtitle is "Leave 8:12 · arrive 8:47".
- A timeline, one row per leg:
  - a walk to a stop: "Walk 3 min to MUN Centre (1150)";
  - a walk to a pin: "Walk 4 min to your destination";
  - a walk from a pin: "Walk 4 min to MUN Centre (1150)", starting at the leg's start time;
  - a ride: a `RouteBadge`, "8:12 → 8:24 · 6 stops", the board and alight stop names, and a live `BBPill` when `live`;
  - last, "Arrive 8:47".
- Under the first ride leg: **Follow bus** and the **bell**, with the Board's own rules and widgets. Build the same arrival object the Board builds for that trip at that stop, for the leg's departure. If the bus isn't live, Follow is hidden, as on the Board.
- Buttons:
  - **Show on map**: `journeyOnMapProvider.show(journey)`, then `context.go('/map')`.
  - **Save trip** (`BBIcons.starOutline`, or `BBIcons.star` once saved): calls `savedTripsProvider.notifier.add` with the name "<from label> → <to label>" and a fresh id (`DateTime.now().microsecondsSinceEpoch.toString()`), then shows a toast: "Saved", "Already saved", or "You can save up to 10 trips". The ends come from `planQueryProvider`'s draft.

**Map:**
- `maplibreMapView` passes `onMapLongClick: (_, latLng) => config.onLongPress?.call(latLng)`.
- A long-press opens `showMapPlanSheet`. If a stop is within 50 m of the press, the sheet's title is its name and its place is `StopPlace`; otherwise the title is "Dropped pin" and the place is `PinPlace(label: 'Dropped pin')`. The sheet's two buttons, "Plan from here" and "Plan to here", set that end in `planQueryProvider` and `context.go('/plan')`.
- Pick mode: when the route is `/map?pick=from` or `/map?pick=to`, a banner reads "Tap the map to choose your starting point" (or "your destination") with a Cancel button that goes back to `/plan`. The next map tap sets that end, using the same 50 m stop rule, and goes to `/plan`.
- With a journey in `journeyOnMapProvider`:
  - draw each ride leg's part of its trip shape in the route colour, cut between its board and alight stops (reuse the follow-mode route line drawing for a single trip);
  - draw each walk leg as a dotted straight line;
  - fit the camera to the journey;
  - show a close button ("Hide trip", semantics label "Hide the trip from the map") that calls `clear()`.

**Stop card:** under "Open board", add a quiet `BBButton(label: 'Plan a trip from here', icon: BBIcons.plan)` that calls `setFrom(StopPlace(...))` and `context.go('/plan')`.

- [ ] **Step 1: Write the failing tests**, with `pumpPlannerApp` and the stub map extended to capture `onTap` and `onLongPress`:
  1. The detail lists the legs of A → E at 08:00 in order: "Route 1", "8:00 → 8:10", "Route 2", "8:20 → 8:28", "Arrive 8:28".
  2. Save trip shows "Saved", and a second tap shows "Already saved"; `savedTripsProvider` holds one trip named "Stop A → Stop E".
  3. Show on map sets `journeyOnMapProvider` and the Map tab is shown.
  4. A long-press on the stub map at C's coordinates opens a sheet titled "Stop C". "Plan to here" sets To to Stop C and shows "Plan a trip".
  5. A long-press far from stops gives "Dropped pin"; "Plan from here" sets a `PinPlace` From.
  6. `/map?pick=from` shows the banner; a stub tap at A's coordinates sets From to Stop A and returns to `/plan`.
  7. The stop card's "Plan a trip from here" sets From and shows the Plan tab.
  8. At 2× text the detail has no overflow.
- [ ] **Step 2: Run them to see them fail.** `flutter test test/ui/journey_detail_test.dart test/ui/map_screen_test.dart test/ui/map_cards_test.dart`
- [ ] **Step 3: Implement** as above.
- [ ] **Step 4: Run all UI and map tests.** `flutter test test/ui/ test/map/ test/state/` Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add lib/ui/trip_planner lib/ui/map lib/state/journey_on_map_provider.dart test/ui
git commit -m "feat(planner): journey detail, map long-press and pick, plans on the map, stop-card shortcut

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Saved-trip cards

**Files:**
- Modify: `lib/ui/trip_planner/saved_trips_section.dart` (replacing Task 12's placeholder)
- Test: `test/ui/saved_trips_test.dart`

**Interfaces:**
- Consumes: `savedTripsProvider`, `savedTripNextProvider`, `planQueryProvider.notifier.setTrip`, `pumpPlannerApp`, `BBDialog`, `BBSkeleton`.

**Each card** (spec §2.2):
- The trip's name (`BBTextStyle` title).
- A line of up to three next departures, each shown as the first ride's departure time:
  - the first with its route number and "live" when that leg is live, e.g. "8:12 · 10 · live";
  - then the others, comma-separated: "8:24, 8:41".
- While loading: a `BBSkeleton` line. With none: "No more buses today".
- Tap: `setTrip(trip.from, trip.to)`, and the results below show its plan.
- Long-press, or the card's "More" `BBIconButton`: a `BBDialog` with **Rename** (a text field, at most 40 characters; empty keeps the old name) and **Remove** (asks "Remove this saved trip?" with Cancel / Remove).
- Semantics label: "Saved trip <name>, next bus <time>, route <n>", or "…, no more buses today".
- The section shows nothing when there are no saved trips, and a section header "Saved trips" when there are.

- [ ] **Step 1: Write the failing tests** (TestNetwork, `now` 08:01, a saved trip "Stop A → Stop C"):
  1. The card shows "Stop A → Stop C" and "8:10 · 1".
  2. Tapping the card fills From and To, and a `JourneyCard` appears.
  3. Rename to "Work" shows "Work".
  4. Remove asks to confirm; after Remove the card is gone and "Saved trips" isn't shown.
  5. At 22:00 the card says "No more buses today".
  6. The semantics label is "Saved trip Stop A → Stop C, next bus 8:10, route 1".
  7. No overflow at 2× text.
- [ ] **Step 2: Run them to see them fail.** `flutter test test/ui/saved_trips_test.dart`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, then the full suite.** `flutter test` Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add lib/ui/trip_planner/saved_trips_section.dart test/ui/saved_trips_test.dart
git commit -m "feat(planner): saved-trip cards with their next departures

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: Spec status, release-note drafts and the device check

**Files:**
- Modify: `docs/superpowers/specs/2026-10-08-trip-planner-design.md` (status; anything the build changed)
- Create: `store/release-notes/1.4.0-draft.md` (drafts for the release step; not published)

- [ ] **Step 1:** In the spec, set the status to "Implemented on branch claude/trip-planner". Bring any section the build changed into line with the code; at least §3.3's midnight rule (yesterday's late trips in today's index; tomorrow checked only for "next bus" on Leave by) and §2.4's two no-journey messages.
- [ ] **Step 2:** Write `store/release-notes/1.4.0-draft.md` with:
  - Play and App Store "What's new" drafts in the style of `store/release-notes/google-play/en-US.txt`: plan a trip leaving now, leaving by or arriving by any minute; stops or a spot on the map at each end; save trips you take often and see their next buses; plans use live times for the next hour; everything is worked out on your phone;
  - the privacy-policy line for the portfolio site: "Saved trips: the trips you save are stored only on your device."
- [ ] **Step 3:** Run `flutter analyze lib test tool`, the full `flutter test`, and `PLANNER_GTFS=build/gtfs_current flutter test test/trip_planner/real_schedule_test.dart`. Put their summaries in the report.
- [ ] **Step 4:** Device check, on emulator-5554 (start it with `emulator -avd busboard_pixel -no-window -gpu host -cores 8 -memory 4096` if it isn't running) and the "BusBoard iPhone 17" simulator. Never use the physical phone.
  - Plan MUN Centre → Avalon Mall, Leave now, and save it, timing it (under 30 s).
  - Make an Arrive by plan.
  - Make a long-press pin plan.
  - Check the saved trip's next departures.
  - Log one search's time from a debug print and remove the print afterwards.

  Note anything off in the report.
- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-10-08-trip-planner-design.md store/release-notes/1.4.0-draft.md
git commit -m "docs(planner): spec matches the build; 1.4.0 release-note drafts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
