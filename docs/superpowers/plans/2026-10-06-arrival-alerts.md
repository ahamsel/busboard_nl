# Arrival Alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A rider taps a bell on an arrival and gets a notification when that bus is 3, 5 or 10 minutes away. Android watches the live feed in a foreground service; iPhone schedules an estimate.

**Architecture:**
- **Pure core:** `AlertTracker` takes an alert, one stop's Metrobus predictions and the time, and decides what to do. It's shared by both platforms and unit-tested and replayed.
- **Android:** a `flutter_foreground_task` handler runs the tracker every 30 s and drives an ongoing notification. There's also a backup scheduled notification.
- **iPhone:** a scheduler re-times one `flutter_local_notifications` notification whenever the app sees a newer prediction or goes to the background.
- **App side:** a Riverpod controller owns the active alert and talks to a platform `AlertRunner`.

**Tech Stack:** Flutter 3.47 / Dart 3.13, Riverpod 3, `flutter_local_notifications` 22.3.1, `flutter_foreground_task` 11.0.3, `timezone` 0.11.1, `shared_preferences` (`SharedPreferencesAsync`).

**Spec:** `docs/superpowers/specs/2026-10-06-arrival-alerts-design.md`

## Global Constraints

- No server, no push service, no account, no API keys; the only network calls are the Metrobus requests the app already makes.
- Free, no ads.
- Every new control has a screen-reader label; nothing overflows at 320 pt width and 2× text.
- One small request per 30 s while an alert runs; the watcher never runs longer than 90 minutes.
- Lead times are exactly 3, 5 and 10 min. No bell under 3 min away or over 60 min away. One alert at a time.
- Android foreground service type `specialUse`, subtype text exactly: `A live transit arrival alert the user starts; it ends when the bus arrives (90 min max)`.
- iOS: notification permission only; no background modes; never start the foreground service on iOS.
- Screens use `package:flutter/widgets.dart` and the kit only (`test/kit/kit_boundary_test.dart`): no Material/Cupertino imports or widgets, no `Colors.`, no `Icons.` under `lib/ui/`.
- Every time shown uses `BBTime` (24-hour or 12-hour per the device).
- Never stage `analysis_options.yaml`, `tool/capture_raw_gtfsrt.dart`, or the untracked files under `test/fixtures/timetrack/`.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Ruling (paths):** the spec puts files in `lib/domain/alerts/`, `lib/data/alerts/` and `lib/ui/alerts/`. `lib/ui/alerts/` is already the service-alerts tab, so this plan uses `arrival_alerts` folders everywhere (`lib/domain/arrival_alerts/`, `lib/data/arrival_alerts/`, `lib/ui/arrival_alerts/`), plus `lib/platform/` for the two platform runners. If this is wrong, the cost is a rename.

**Ruling (notification tap):** the spec says tapping the Android countdown opens that stop's Board. `FlutterForegroundTask.launchApp()` brings the app to the front where it was; routing a cold start to `/board/<id>` would need router changes outside this phase. The tap opens the app. If this is wrong, the cost is one follow-up task.

## Review Focus

1. **After-midnight trips:** a GTFS time past 24:00, or a bus set at 23:55 for 00:10, gets the right instant (not 24 h off). Pinned in Task 1.
2. **Two buses on one route minutes apart:** when our trip drops out of the feed, the tracker must not latch onto the other route-10 bus. Pinned in Task 2.
3. **The app is killed or restarted while an Android alert runs:** the Board still shows the alert from the store, and a stale stored alert (past its window, e.g. after a reboot) is cleared on launch. Pinned in Task 7.
4. **The rider denies notification permission:** no service starts, nothing is stored, and the sheet offers the phone's settings. Pinned in Tasks 7 and 8.
5. **A cancel arrives while a watcher check is in flight:** the check must not write the alert back after the cancel cleared it. Pinned in Task 5.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/domain/arrival_alerts/arrival_alert.dart` | `ArrivalAlert` value + JSON, `instantOfServiceTime`, lead-time rules |
| `lib/domain/arrival_alerts/alert_tracker.dart` | `AlertTracker`, `AlertStep`, `AlertSource`: the matching ladder and every §2.4 rule |
| `lib/domain/arrival_alerts/alert_copy.dart` | Every notification string (§2.2–2.3) |
| `lib/data/arrival_alerts/alert_store.dart` | The one active alert + last lead time, in `SharedPreferencesAsync` |
| `lib/data/arrival_alerts/alert_notifications.dart` | `AlertNotifications` interface + `LocalAlertNotifications` (`flutter_local_notifications`) |
| `lib/platform/alert_runner.dart` | `AlertRunner` interface |
| `lib/platform/android_alert_watcher.dart` | `WatcherCore` (testable), the task handler, `AndroidAlertRunner` |
| `lib/platform/ios_alert_scheduler.dart` | `AlertScheduler` (testable), `IosAlertRunner` |
| `lib/state/arrival_alert_providers.dart` | Providers + `ArrivalAlertController` |
| `lib/ui/arrival_alerts/alert_bell.dart` | The bell button for a row or the follow card |
| `lib/ui/arrival_alerts/lead_time_sheet.dart` | The 3 / 5 / 10 sheet, permission line, denied state |
| `lib/ui/arrival_alerts/alert_strip.dart` | "Alert set · Route 10 · 5 min before · Cancel" |
| `tool/capture_stop_predictions.dart` | Records one stop's Metrobus JSON every 30 s |
| Modified | `lib/ui/board/arrival_row_tile.dart`, `lib/ui/board/arrival_board_screen.dart`, `lib/ui/map/follow_card.dart`, `lib/ui/map/map_screen.dart`, `lib/ui/kit/bb_icons.dart`, `lib/main.dart`, `pubspec.yaml`, Android manifest + gradle + res, `ios/Runner/AppDelegate.swift` |

---

### Task 1: The alert value and its time rules

**Files:**
- Create: `lib/domain/arrival_alerts/arrival_alert.dart`
- Test: `test/arrival_alerts/arrival_alert_test.dart`

**Interfaces:**
- Consumes: `GtfsTime` (`lib/data/gtfs/gtfs_time.dart`: `totalSeconds`, `GtfsTime.fromSeconds`, `GtfsTime.fromDateTime`), `ArrivalRow` (`lib/domain/arrival/arrival_models.dart`: `routeShortName`, `headsign`, `scheduledTime`, `predictedTime`, `displayTime`, `minutesAway`, `isLive`, `tripId`, `vehicleNumber`, `routeRun`).
- Produces:
  - `const alertLeadChoices = <int>[3, 5, 10]`, `const alertMinMinutesAway = 3`, `const alertMaxMinutesAway = 60`
  - `bool canAlert(ArrivalRow row)`; `List<int> leadChoicesFor(int minutesAway)`
  - `DateTime instantOfServiceTime(GtfsTime t, DateTime now)`
  - `class ArrivalAlert` with fields `stopId, stopName, routeShortName, headsign, tripId (String), routeRun (String?), vehicle (String?), scheduledAt, expectedAt (DateTime), live (bool), leadMinutes (int), setAt (DateTime), lastSeenAt (DateTime?), firedAt (DateTime?)`; getter `DateTime alertAt`; `copyWith({DateTime? expectedAt, bool? live, String? routeRun, String? vehicle, DateTime? lastSeenAt, DateTime? firedAt})`; `bool isSameAlert(ArrivalAlert other)`; `Map<String, Object?> toJson()`; `static ArrivalAlert? fromJson(Map<String, Object?>)`; `String encode()`; `static ArrivalAlert? decode(String? s)`; `factory ArrivalAlert.fromArrival(ArrivalRow row, {required String stopId, required String stopName, required int leadMinutes, required DateTime now})`

- [ ] **Step 1: Write the failing test**

```dart
// test/arrival_alerts/arrival_alert_test.dart
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:flutter_test/flutter_test.dart';

ArrivalRow _row({int minutes = 12, bool live = true, int scheduled = 8 * 3600 + 12 * 60, int? predicted}) => ArrivalRow(
      routeShortName: '10',
      headsign: 'MUN-CNA-MI',
      scheduledTime: GtfsTime.fromSeconds(scheduled),
      predictedTime: live ? GtfsTime.fromSeconds(predicted ?? scheduled + 120) : null,
      minutesAway: minutes,
      isLive: live,
      tripId: 't1',
      vehicleNumber: live ? '1415' : null,
      routeRun: '10-4',
    );

void main() {
  final now = DateTime(2026, 10, 6, 8, 0);

  group('instantOfServiceTime', () {
    test('a time later today', () {
      expect(instantOfServiceTime(GtfsTime.fromSeconds(8 * 3600 + 12 * 60), now), DateTime(2026, 10, 6, 8, 12));
    });
    test('23:55 now, 24:10 is 15 minutes later, tomorrow', () {
      expect(instantOfServiceTime(GtfsTime.fromSeconds(24 * 3600 + 10 * 60), DateTime(2026, 10, 6, 23, 55)),
          DateTime(2026, 10, 7, 0, 10));
    });
    test('00:10 now, 24:20 (last night\'s service) is 10 minutes later', () {
      expect(instantOfServiceTime(GtfsTime.fromSeconds(24 * 3600 + 20 * 60), DateTime(2026, 10, 7, 0, 10)),
          DateTime(2026, 10, 7, 0, 20));
    });
    test('00:10 now, 23:55 is 15 minutes ago', () {
      expect(instantOfServiceTime(GtfsTime.fromSeconds(23 * 3600 + 55 * 60), DateTime(2026, 10, 7, 0, 10)),
          DateTime(2026, 10, 6, 23, 55));
    });
  });

  group('lead rules', () {
    test('a bell from 3 to 60 minutes away', () {
      expect(canAlert(_row(minutes: 2)), isFalse);
      expect(canAlert(_row(minutes: 3)), isTrue);
      expect(canAlert(_row(minutes: 60)), isTrue);
      expect(canAlert(_row(minutes: 61)), isFalse);
    });
    test('only lead times shorter than the minutes away', () {
      expect(leadChoicesFor(4), [3]);
      expect(leadChoicesFor(5), [3]);
      expect(leadChoicesFor(6), [3, 5]);
      expect(leadChoicesFor(30), [3, 5, 10]);
    });
  });

  group('ArrivalAlert', () {
    test('from a live row: expected is the prediction, last seen is now', () {
      final a = ArrivalAlert.fromArrival(_row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5, now: now);
      expect(a.scheduledAt, DateTime(2026, 10, 6, 8, 12));
      expect(a.expectedAt, DateTime(2026, 10, 6, 8, 14));
      expect(a.live, isTrue);
      expect(a.lastSeenAt, now);
      expect(a.alertAt, DateTime(2026, 10, 6, 8, 9));
      expect(a.vehicle, '1415');
      expect(a.routeRun, '10-4');
    });
    test('from a timetable row: expected is the schedule, never seen live', () {
      final a = ArrivalAlert.fromArrival(_row(live: false), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 3, now: now);
      expect(a.expectedAt, a.scheduledAt);
      expect(a.live, isFalse);
      expect(a.lastSeenAt, isNull);
    });
    test('JSON round trip keeps every field', () {
      final a = ArrivalAlert.fromArrival(_row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5, now: now)
          .copyWith(firedAt: DateTime(2026, 10, 6, 8, 9));
      final b = ArrivalAlert.decode(a.encode())!;
      expect(b.toJson(), a.toJson());
      expect(b.isSameAlert(a), isTrue);
    });
    test('garbage decodes to null', () {
      expect(ArrivalAlert.decode(null), isNull);
      expect(ArrivalAlert.decode('not json'), isNull);
      expect(ArrivalAlert.decode('{"stopId":1}'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/arrival_alerts/arrival_alert_test.dart`
Expected: FAIL (`arrival_alert.dart` does not exist)

- [ ] **Step 3: Write the implementation**

```dart
// lib/domain/arrival_alerts/arrival_alert.dart
import 'dart:convert';

import '../../data/gtfs/gtfs_time.dart';
import '../arrival/arrival_models.dart';

/// Lead times a rider can pick, in minutes (spec §2.1).
const alertLeadChoices = <int>[3, 5, 10];

/// No bell for a bus closer than this ("Arriving now") or farther than [alertMaxMinutesAway].
const alertMinMinutesAway = 3;
const alertMaxMinutesAway = 60;

/// Whether [row] gets a bell.
bool canAlert(ArrivalRow row) => row.minutesAway >= alertMinMinutesAway && row.minutesAway <= alertMaxMinutesAway;

/// The lead times still possible for a bus [minutesAway] out: only those shorter than the wait.
List<int> leadChoicesFor(int minutesAway) => [for (final m in alertLeadChoices) if (m < minutesAway) m];

/// A service-day time as an instant near [now], counted the way the Board counts minutes (same clock
/// day), moved by a day when that leaves it more than 12 h away: 24:10 at 23:55 is tomorrow 00:10.
DateTime instantOfServiceTime(GtfsTime t, DateTime now) {
  var delta = t.totalSeconds - GtfsTime.fromDateTime(now).totalSeconds;
  while (delta > 12 * 3600) {
    delta -= 24 * 3600;
  }
  while (delta < -12 * 3600) {
    delta += 24 * 3600;
  }
  final base = DateTime(now.year, now.month, now.day, now.hour, now.minute, now.second);
  return base.add(Duration(seconds: delta));
}

/// The one arrival alert a rider has set (spec §3.1).
class ArrivalAlert {
  const ArrivalAlert({
    required this.stopId,
    required this.stopName,
    required this.routeShortName,
    required this.headsign,
    required this.tripId,
    this.routeRun,
    this.vehicle,
    required this.scheduledAt,
    required this.expectedAt,
    required this.live,
    required this.leadMinutes,
    required this.setAt,
    this.lastSeenAt,
    this.firedAt,
  });

  factory ArrivalAlert.fromArrival(
    ArrivalRow row, {
    required String stopId,
    required String stopName,
    required int leadMinutes,
    required DateTime now,
  }) {
    final scheduledAt = instantOfServiceTime(row.scheduledTime, now);
    final live = row.isLive && row.predictedTime != null;
    return ArrivalAlert(
      stopId: stopId,
      stopName: stopName,
      routeShortName: row.routeShortName,
      headsign: row.headsign,
      tripId: row.tripId,
      routeRun: row.routeRun,
      vehicle: row.vehicleNumber,
      scheduledAt: scheduledAt,
      expectedAt: live ? instantOfServiceTime(row.displayTime, now) : scheduledAt,
      live: live,
      leadMinutes: leadMinutes,
      setAt: now,
      lastSeenAt: live ? now : null,
    );
  }

  final String stopId;
  final String stopName;
  final String routeShortName;
  final String headsign;

  /// The GTFS trip at this stop.
  final String tripId;

  /// Metrobus's route-run (e.g. "10-4") and bus number, when known.
  final String? routeRun;
  final String? vehicle;

  /// The timetable departure at the stop.
  final DateTime scheduledAt;

  /// The latest expected departure: a live prediction, or [scheduledAt].
  final DateTime expectedAt;

  /// Whether [expectedAt] came from a live prediction.
  final bool live;
  final int leadMinutes;
  final DateTime setAt;

  /// When a live prediction for this trip was last seen.
  final DateTime? lastSeenAt;

  /// When the alert fired; it fires once.
  final DateTime? firedAt;

  /// When the rider wants the heads-up.
  DateTime get alertAt => expectedAt.subtract(Duration(minutes: leadMinutes));

  /// The same alert (not a replacement), whatever its timing.
  bool isSameAlert(ArrivalAlert other) =>
      other.setAt == setAt && other.tripId == tripId && other.stopId == stopId;

  ArrivalAlert copyWith({
    DateTime? expectedAt,
    bool? live,
    String? routeRun,
    String? vehicle,
    DateTime? lastSeenAt,
    DateTime? firedAt,
  }) =>
      ArrivalAlert(
        stopId: stopId,
        stopName: stopName,
        routeShortName: routeShortName,
        headsign: headsign,
        tripId: tripId,
        routeRun: routeRun ?? this.routeRun,
        vehicle: vehicle ?? this.vehicle,
        scheduledAt: scheduledAt,
        expectedAt: expectedAt ?? this.expectedAt,
        live: live ?? this.live,
        leadMinutes: leadMinutes,
        setAt: setAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        firedAt: firedAt ?? this.firedAt,
      );

  Map<String, Object?> toJson() => {
        'stopId': stopId,
        'stopName': stopName,
        'routeShortName': routeShortName,
        'headsign': headsign,
        'tripId': tripId,
        'routeRun': routeRun,
        'vehicle': vehicle,
        'scheduledAt': scheduledAt.millisecondsSinceEpoch,
        'expectedAt': expectedAt.millisecondsSinceEpoch,
        'live': live,
        'leadMinutes': leadMinutes,
        'setAt': setAt.millisecondsSinceEpoch,
        'lastSeenAt': lastSeenAt?.millisecondsSinceEpoch,
        'firedAt': firedAt?.millisecondsSinceEpoch,
      };

  static ArrivalAlert? fromJson(Map<String, Object?> j) {
    DateTime? at(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    final stopId = j['stopId'], stopName = j['stopName'], route = j['routeShortName'];
    final headsign = j['headsign'], tripId = j['tripId'], lead = j['leadMinutes'], live = j['live'];
    final scheduledAt = at(j['scheduledAt']), expectedAt = at(j['expectedAt']), setAt = at(j['setAt']);
    if (stopId is! String || stopName is! String || route is! String || headsign is! String || tripId is! String) {
      return null;
    }
    if (lead is! int || live is! bool || scheduledAt == null || expectedAt == null || setAt == null) return null;
    final run = j['routeRun'], vehicle = j['vehicle'];
    return ArrivalAlert(
      stopId: stopId,
      stopName: stopName,
      routeShortName: route,
      headsign: headsign,
      tripId: tripId,
      routeRun: run is String ? run : null,
      vehicle: vehicle is String ? vehicle : null,
      scheduledAt: scheduledAt,
      expectedAt: expectedAt,
      live: live,
      leadMinutes: lead,
      setAt: setAt,
      lastSeenAt: at(j['lastSeenAt']),
      firedAt: at(j['firedAt']),
    );
  }

  String encode() => jsonEncode(toJson());

  static ArrivalAlert? decode(String? s) {
    if (s == null) return null;
    try {
      final j = jsonDecode(s);
      return j is Map<String, Object?> ? fromJson(j) : null;
    } on FormatException {
      return null;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/arrival_alerts/arrival_alert_test.dart`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add lib/domain/arrival_alerts/arrival_alert.dart test/arrival_alerts/arrival_alert_test.dart
git commit -m "feat(alerts): the arrival alert value and its time rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: AlertTracker, the rules engine

**Files:**
- Create: `lib/domain/arrival_alerts/alert_tracker.dart`
- Test: `test/arrival_alerts/alert_tracker_test.dart`

**Interfaces:**
- Consumes: Task 1's `ArrivalAlert` and `instantOfServiceTime`. From `lib/data/realtime/metrobus_mobile_api.dart`:
  - `MetrobusDeparturesResult` (`departures`, `succeeded`);
  - `MetrobusDeparture` (`tripId`, `routeRun`, `routeShortName`, `vehicle`, `isRealtime`, `scheduledGtfsTime`, `predictedGtfsTime`).
- Produces:
  - `enum AlertSource { live, timetable, lost }`
  - `class AlertStep { final ArrivalAlert alert; final int minutesAway; final AlertSource source; final bool fire; final bool finished; }`
  - `class AlertTracker { const AlertTracker(); static const lostAfter = Duration(minutes: 2); static const maxRun = Duration(minutes: 90); AlertStep step(ArrivalAlert alert, MetrobusDeparturesResult? result, DateTime now); MetrobusDeparture? find(ArrivalAlert alert, List<MetrobusDeparture> rows, {DateTime? now}); }`

Rules (spec §2.4, §3.2):
- **Matching ladder:** same trip id; else same route-run on the same route; else same vehicle on the same route; else same route within ±2 min of the scheduled time.
  - Rungs 2–3 also need the row's schedule within 15 min of ours: runs and buses do later trips too.
  - Rungs 2–4 skip any row whose trip id is set and differs from ours: that is a different bus.
- **A live match** sets `expectedAt` from its prediction, `live: true`, `lastSeenAt: now`.
- **No live match:**
  - within `lostAfter` of `lastSeenAt`, keep the last expected time (source `live`);
  - after that, if the alert was ever seen live, source `lost` and `expectedAt = scheduledAt`;
  - if never seen live, source `timetable` and `expectedAt = scheduledAt`.
  - A failed fetch (`null` or `succeeded == false`) counts as no match.
- **Firing:** `fire` when not yet fired and `now >= alertAt`; it sets `firedAt: now`.
- **Finishing:** `finished` when (fired and `now >= expectedAt`) or `now - setAt >= maxRun`.
- **Minutes away:** `minutesAway = max(0, expectedAt.difference(now).inSeconds ~/ 60)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/arrival_alerts/alert_tracker_test.dart
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_tracker.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 10, 6, 8, 0);
int sec(int h, int m) => h * 3600 + m * 60;

MetrobusDeparture dep({
  String trip = 't1',
  String run = '10-4',
  String vehicle = '1415',
  String route = '10',
  required int pred,
  int? sched,
  bool live = true,
}) =>
    MetrobusDeparture(
      routeRun: run,
      routeShortName: route,
      vehicle: vehicle,
      scheduledTime: '',
      predictedTime: '',
      headsign: 'MUN-CNA-MI',
      currentLocation: '',
      isTracked: live,
      tripId: trip,
      scheduledDepartureSeconds: sched ?? sec(8, 12),
      predictedDepartureSeconds: pred,
      isRealtime: live,
    );

MetrobusDeparturesResult res(List<MetrobusDeparture> d, {bool ok = true}) => MetrobusDeparturesResult(
      departures: d,
      succeeded: ok,
      realtimeAvailable: true,
      serviceOperating: true,
      fetchedAt: t0,
    );

ArrivalAlert alert({bool live = true, int lead = 5, String trip = 't1', String? run = '10-4', String? vehicle = '1415'}) =>
    ArrivalAlert(
      stopId: '1150',
      stopName: 'MUN Centre',
      routeShortName: '10',
      headsign: 'MUN-CNA-MI',
      tripId: trip,
      routeRun: run,
      vehicle: vehicle,
      scheduledAt: DateTime(2026, 10, 6, 8, 12),
      expectedAt: DateTime(2026, 10, 6, 8, 12),
      live: live,
      leadMinutes: lead,
      setAt: t0,
      lastSeenAt: live ? t0 : null,
    );

void main() {
  const tracker = AlertTracker();
  DateTime at(int m, [int s = 0]) => t0.add(Duration(minutes: m, seconds: s));

  test('a live match re-times the alert', () {
    final s = tracker.step(alert(), res([dep(pred: sec(8, 14))]), at(0, 30));
    expect(s.source, AlertSource.live);
    expect(s.alert.expectedAt, DateTime(2026, 10, 6, 8, 14));
    expect(s.alert.lastSeenAt, at(0, 30));
    expect(s.minutesAway, 13);
    expect(s.fire, isFalse);
    expect(s.finished, isFalse);
  });

  test('fires once at expected − lead', () {
    final first = tracker.step(alert(), res([dep(pred: sec(8, 14))]), at(9));
    expect(first.fire, isTrue);
    expect(first.alert.firedAt, at(9));
    final again = tracker.step(first.alert, res([dep(pred: sec(8, 14))]), at(9, 30));
    expect(again.fire, isFalse);
  });

  test('a bus that jumps ahead fires at once with the real minutes', () {
    final s = tracker.step(alert(), res([dep(pred: sec(8, 3))]), at(1));
    expect(s.fire, isTrue);
    expect(s.minutesAway, 2);
  });

  test('a later bus waits: the alert re-times itself', () {
    final s = tracker.step(alert(), res([dep(pred: sec(8, 20))]), at(8));
    expect(s.fire, isFalse);
    expect(s.alert.alertAt, DateTime(2026, 10, 6, 8, 15));
  });

  group('matching ladder', () {
    test('trip id first, even with a different run', () {
      final s = tracker.step(alert(), res([dep(run: '10-9', vehicle: '9999', pred: sec(8, 16))]), at(1));
      expect(s.alert.expectedAt, DateTime(2026, 10, 6, 8, 16));
    });
    test('route-run when the feed has no trip ids', () {
      final s = tracker.step(alert(), res([dep(trip: '', vehicle: '9999', pred: sec(8, 15))]), at(1));
      expect(s.source, AlertSource.live);
      expect(s.alert.expectedAt, DateTime(2026, 10, 6, 8, 15));
    });
    test('vehicle when trip and run are missing', () {
      final s = tracker.step(alert(), res([dep(trip: '', run: '', pred: sec(8, 15))]), at(1));
      expect(s.alert.expectedAt, DateTime(2026, 10, 6, 8, 15));
    });
    test('same route within ±2 min of the schedule as the last resort', () {
      final s = tracker.step(alert(run: null, vehicle: null),
          res([dep(trip: '', run: '', vehicle: '', pred: sec(8, 13), sched: sec(8, 13))]), at(1));
      expect(s.alert.expectedAt, DateTime(2026, 10, 6, 8, 13));
    });
    test('the same run on a trip an hour later is not this bus', () {
      final s = tracker.step(alert(), res([dep(trip: '', vehicle: '', pred: sec(9, 12), sched: sec(9, 12))]), at(3));
      expect(s.source, isNot(AlertSource.live));
    });
    test('another route-10 bus a minute behind ours is never taken for it', () {
      // Our trip t1 dropped out; t2 (another bus, its own trip id) is close in time.
      final s = tracker.step(alert(),
          res([dep(trip: 't2', run: '10-5', vehicle: '2222', pred: sec(8, 13), sched: sec(8, 13))]), at(3));
      expect(s.source, AlertSource.lost);
      expect(s.alert.expectedAt, DateTime(2026, 10, 6, 8, 12));
    });
    test('a different route is never matched', () {
      expect(tracker.find(alert(run: null, vehicle: null), [dep(trip: '', run: '', vehicle: '', route: '1', pred: sec(8, 12))]),
          isNull);
    });
  });

  group('losing the bus', () {
    test('a short gap keeps the last live time', () {
      final live = tracker.step(alert(), res([dep(pred: sec(8, 15))]), at(0));
      final gap = tracker.step(live.alert, res([]), at(1));
      expect(gap.source, AlertSource.live);
      expect(gap.alert.expectedAt, DateTime(2026, 10, 6, 8, 15));
    });
    test('after 2 minutes it falls back to the timetable', () {
      final live = tracker.step(alert(), res([dep(pred: sec(8, 15))]), at(0));
      final lost = tracker.step(live.alert, res([]), at(2, 30));
      expect(lost.source, AlertSource.lost);
      expect(lost.alert.expectedAt, DateTime(2026, 10, 6, 8, 12));
    });
    test('a failed fetch counts as no match', () {
      final s = tracker.step(alert(), res([], ok: false), at(3));
      expect(s.source, AlertSource.lost);
      expect(tracker.step(alert(), null, at(3)).source, AlertSource.lost);
    });
    test('a row that is not realtime does not count as live', () {
      final s = tracker.step(alert(), res([dep(pred: sec(8, 20), live: false)]), at(3));
      expect(s.source, AlertSource.lost);
    });
  });

  group('timetable-only alerts', () {
    test('use the schedule and fire at schedule − lead', () {
      final a = alert(live: false, lead: 3);
      expect(tracker.step(a, res([]), at(8)).fire, isFalse);
      final s = tracker.step(a, res([]), at(9));
      expect(s.source, AlertSource.timetable);
      expect(s.fire, isTrue);
    });
    test('become live when the bus shows up', () {
      final s = tracker.step(alert(live: false), res([dep(pred: sec(8, 14))]), at(2));
      expect(s.source, AlertSource.live);
      expect(s.alert.live, isTrue);
    });
  });

  group('finishing', () {
    test('once fired, it ends when the bus is due', () {
      final fired = tracker.step(alert(), res([dep(pred: sec(8, 12))]), at(8));
      expect(fired.finished, isFalse);
      final due = tracker.step(fired.alert, res([dep(pred: sec(8, 12))]), at(12));
      expect(due.finished, isTrue);
      expect(due.minutesAway, 0);
    });
    test('never runs past 90 minutes', () {
      final s = tracker.step(alert(), res([dep(pred: sec(10, 0), sched: sec(8, 12))]), at(90));
      expect(s.finished, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/arrival_alerts/alert_tracker_test.dart`
Expected: FAIL (`alert_tracker.dart` does not exist)

- [ ] **Step 3: Write the implementation**

```dart
// lib/domain/arrival_alerts/alert_tracker.dart
import 'dart:math' as math;

import '../../data/realtime/metrobus_mobile_api.dart';
import 'arrival_alert.dart';

/// Where an alert's expected time came from on a check.
enum AlertSource { live, timetable, lost }

/// What one check decided (spec §2.4).
class AlertStep {
  const AlertStep({
    required this.alert,
    required this.minutesAway,
    required this.source,
    required this.fire,
    required this.finished,
  });

  /// The alert after this check: re-timed, and with `firedAt` set when [fire].
  final ArrivalAlert alert;
  final int minutesAway;
  final AlertSource source;

  /// Show the alert now (true on exactly one check).
  final bool fire;

  /// Stop watching: the bus is due after the alert, or the 90-minute cap passed.
  final bool finished;
}

/// Pure rules for one arrival alert. Both the Android watcher and the iPhone scheduler run it.
class AlertTracker {
  const AlertTracker();

  /// How long a live bus may be missing before the alert falls back to the timetable.
  static const lostAfter = Duration(minutes: 2);

  /// The longest an alert ever runs.
  static const maxRun = Duration(minutes: 90);

  static const _sameTime = Duration(minutes: 2);
  static const _sameRunWindow = Duration(minutes: 15);

  AlertStep step(ArrivalAlert alert, MetrobusDeparturesResult? result, DateTime now) {
    final rows = result != null && result.succeeded ? result.departures : const <MetrobusDeparture>[];
    final match = find(alert, rows, now: now);
    var a = alert;
    final AlertSource source;
    final predicted = match == null || !match.isRealtime ? null : (match.predictedGtfsTime ?? match.scheduledGtfsTime);
    if (match != null && predicted != null) {
      a = a.copyWith(
        expectedAt: instantOfServiceTime(predicted, now),
        live: true,
        lastSeenAt: now,
        routeRun: match.routeRun.isEmpty ? null : match.routeRun,
        vehicle: match.vehicle.isEmpty ? null : match.vehicle,
      );
      source = AlertSource.live;
    } else if (a.lastSeenAt != null && now.difference(a.lastSeenAt!) < lostAfter) {
      source = AlertSource.live;
    } else if (a.lastSeenAt != null) {
      a = a.copyWith(expectedAt: a.scheduledAt, live: false);
      source = AlertSource.lost;
    } else {
      a = a.copyWith(expectedAt: a.scheduledAt, live: false);
      source = AlertSource.timetable;
    }

    final fire = a.firedAt == null && !now.isBefore(a.alertAt);
    if (fire) a = a.copyWith(firedAt: now);
    final finished = (a.firedAt != null && !now.isBefore(a.expectedAt)) || now.difference(a.setAt) >= maxRun;
    final minutesAway = math.max(0, a.expectedAt.difference(now).inSeconds ~/ 60);
    return AlertStep(alert: a, minutesAway: minutesAway, source: source, fire: fire, finished: finished);
  }

  /// The alert's departure among one stop's predictions (spec §3.2), or null.
  MetrobusDeparture? find(ArrivalAlert alert, List<MetrobusDeparture> rows, {DateTime? now}) {
    final when = now ?? alert.setAt;
    if (alert.tripId.isNotEmpty) {
      for (final d in rows) {
        if (d.tripId == alert.tripId) return d;
      }
    }
    // A row with its own, different trip id is another bus, whatever else it shares.
    bool otherTrip(MetrobusDeparture d) => alert.tripId.isNotEmpty && d.tripId.isNotEmpty && d.tripId != alert.tripId;
    Duration? offSchedule(MetrobusDeparture d) {
      final s = d.scheduledGtfsTime;
      return s == null ? null : instantOfServiceTime(s, when).difference(alert.scheduledAt).abs();
    }

    final candidates = rows.where((d) => d.routeShortName == alert.routeShortName && !otherTrip(d)).toList();
    bool near(MetrobusDeparture d, Duration window) {
      final off = offSchedule(d);
      return off != null && off <= window;
    }

    final run = alert.routeRun;
    if (run != null && run.isNotEmpty) {
      for (final d in candidates) {
        if (d.routeRun == run && near(d, _sameRunWindow)) return d;
      }
    }
    final bus = alert.vehicle;
    if (bus != null && bus.isNotEmpty) {
      for (final d in candidates) {
        if (d.vehicle == bus && near(d, _sameRunWindow)) return d;
      }
    }
    MetrobusDeparture? best;
    Duration? bestOff;
    for (final d in candidates) {
      final off = offSchedule(d);
      if (off == null || off > _sameTime) continue;
      if (bestOff == null || off < bestOff) {
        best = d;
        bestOff = off;
      }
    }
    return best;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/arrival_alerts/alert_tracker_test.dart`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add lib/domain/arrival_alerts/alert_tracker.dart test/arrival_alerts/alert_tracker_test.dart
git commit -m "feat(alerts): AlertTracker, the matching ladder and alert rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: AlertStore

**Files:**
- Create: `lib/data/arrival_alerts/alert_store.dart`
- Modify: `pubspec.yaml` (dev_dependencies: add `shared_preferences_platform_interface: ^2.4.1`)
- Test: `test/arrival_alerts/alert_store_test.dart`

**Interfaces:**
- Consumes: Task 1's `ArrivalAlert.encode/decode`.
- Produces: `class AlertStore { AlertStore([SharedPreferencesAsync? prefs]); Future<ArrivalAlert?> read(); Future<void> write(ArrivalAlert a); Future<void> clear(); Future<int> lastLead(); Future<void> saveLead(int minutes); }`. `lastLead` defaults to 5.

`SharedPreferencesAsync` reads from the platform on every call (no cache), so the main isolate and the Android watcher's isolate see each other's writes.

- [ ] **Step 1: Add the dev dependency**

In `pubspec.yaml` under `dev_dependencies:` add the line `  shared_preferences_platform_interface: ^2.4.1`, then run `flutter pub get`.

- [ ] **Step 2: Write the failing test**

```dart
// test/arrival_alerts/alert_store_test.dart
import 'package:busboard_nl/data/arrival_alerts/alert_store.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final _alert = ArrivalAlert(
  stopId: '1150',
  stopName: 'MUN Centre',
  routeShortName: '10',
  headsign: 'MUN-CNA-MI',
  tripId: 't1',
  scheduledAt: DateTime(2026, 10, 6, 8, 12),
  expectedAt: DateTime(2026, 10, 6, 8, 14),
  live: true,
  leadMinutes: 5,
  setAt: DateTime(2026, 10, 6, 8, 0),
);

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  test('empty store: no alert, lead 5', () async {
    final store = AlertStore();
    expect(await store.read(), isNull);
    expect(await store.lastLead(), 5);
  });

  test('write, read, clear', () async {
    final store = AlertStore();
    await store.write(_alert);
    expect((await store.read())!.toJson(), _alert.toJson());
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('a second store instance (another isolate) sees the same alert', () async {
    await AlertStore().write(_alert);
    expect((await AlertStore().read())!.tripId, 't1');
  });

  test('remembers the last lead time', () async {
    final store = AlertStore();
    await store.saveLead(10);
    expect(await store.lastLead(), 10);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/arrival_alerts/alert_store_test.dart`
Expected: FAIL (`alert_store.dart` does not exist)

- [ ] **Step 4: Write the implementation**

```dart
// lib/data/arrival_alerts/alert_store.dart
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/arrival_alerts/arrival_alert.dart';

/// The one active arrival alert and the rider's last lead time. Uses [SharedPreferencesAsync],
/// which has no cache, so the Android watcher's isolate and the app see each other's writes.
class AlertStore {
  AlertStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;
  static const _alertKey = 'arrival_alert.v1';
  static const _leadKey = 'arrival_alert.lead_minutes';

  Future<ArrivalAlert?> read() async => ArrivalAlert.decode(await _prefs.getString(_alertKey));

  Future<void> write(ArrivalAlert alert) => _prefs.setString(_alertKey, alert.encode());

  Future<void> clear() => _prefs.remove(_alertKey);

  Future<int> lastLead() async {
    final v = await _prefs.getInt(_leadKey);
    return v != null && alertLeadChoices.contains(v) ? v : 5;
  }

  Future<void> saveLead(int minutes) => _prefs.setInt(_leadKey, minutes);
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/arrival_alerts/alert_store_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/data/arrival_alerts/alert_store.dart test/arrival_alerts/alert_store_test.dart
git commit -m "feat(alerts): AlertStore shared between the app and the watcher

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Notification copy, the notifications wrapper, and platform setup

**Files:**
- Create: `lib/domain/arrival_alerts/alert_copy.dart`, `lib/data/arrival_alerts/alert_notifications.dart`, `android/app/src/main/res/drawable/ic_notification.xml`, `android/app/src/main/res/raw/keep.xml`
- Modify: `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`, `ios/Runner/AppDelegate.swift`
- Test: `test/arrival_alerts/alert_copy_test.dart`, `test/android_alert_setup_test.dart`

**Interfaces:**
- Consumes: Tasks 1–2 (`ArrivalAlert`, `AlertStep`, `AlertSource`); `BBTime.of(DateTime, use24h:)` from `lib/ui/kit/bb_time.dart`.
- Produces:
  - `class AlertMessage { const AlertMessage(this.title, this.body); final String title; final String body; }`
  - `AlertMessage alertMessage(ArrivalAlert a, {required AlertSource source, required int minutesAway, DateTime? estimateFrom, required bool use24h})`. With `estimateFrom` set, it's the iPhone estimate wording.
  - `String ongoingTitle(ArrivalAlert a)`; `String ongoingText(AlertStep s)`
  - `abstract class AlertNotifications { Future<void> init(); Future<bool> permissionGranted(); Future<bool> requestPermission(); Future<void> show(AlertMessage m); Future<void> schedule(AlertMessage m, DateTime at); Future<void> cancelScheduled(); }`
  - `class LocalAlertNotifications implements AlertNotifications` with `static const shownId = 4101, scheduledId = 4102`.

Copy (spec §2.2–2.3):
- **Live alert:** "Route 10 is about 5 min away" / "MUN Centre (stop 1150)".
- **iPhone estimate:** "Route 10 should be about 5 min away" / "Estimate from 8:02 AM. Open BusBoard for the latest."
- **Timetable or lost:** "Route 10 is scheduled in about 5 min" / "MUN Centre (stop 1150) · no live tracking for this trip".
- **Zero minutes:** "Route 10 is due now".
- **Ongoing title:** "Route 10 to MUN-CNA-MI".
- **Ongoing text:**
  - live: "About 12 min · live";
  - timetable: "About 12 min · scheduled";
  - lost: "Live tracking lost · using the timetable · about 12 min";
  - due: "Due now".

- [ ] **Step 1: Add the packages**

In `pubspec.yaml` under `dependencies:` add:

```yaml
  flutter_foreground_task: ^11.0.3
  flutter_local_notifications: ^22.3.1
  timezone: ^0.11.1
```

Run: `flutter pub get`. Expected: resolves without conflicts.

- [ ] **Step 2: Write the failing copy test**

```dart
// test/arrival_alerts/alert_copy_test.dart
import 'package:busboard_nl/domain/arrival_alerts/alert_copy.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_tracker.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:flutter_test/flutter_test.dart';

final _a = ArrivalAlert(
  stopId: '1150',
  stopName: 'MUN Centre',
  routeShortName: '10',
  headsign: 'MUN-CNA-MI',
  tripId: 't1',
  scheduledAt: DateTime(2026, 10, 6, 8, 12),
  expectedAt: DateTime(2026, 10, 6, 8, 12),
  live: true,
  leadMinutes: 5,
  setAt: DateTime(2026, 10, 6, 8, 0),
);

AlertStep _step(AlertSource s, int m) => AlertStep(alert: _a, minutesAway: m, source: s, fire: false, finished: false);

void main() {
  test('live alert', () {
    final m = alertMessage(_a, source: AlertSource.live, minutesAway: 5, use24h: true);
    expect(m.title, 'Route 10 is about 5 min away');
    expect(m.body, 'MUN Centre (stop 1150)');
  });
  test('iPhone estimate, 12- and 24-hour', () {
    final m = alertMessage(_a,
        source: AlertSource.live, minutesAway: 5, estimateFrom: DateTime(2026, 10, 6, 8, 2), use24h: false);
    expect(m.title, 'Route 10 should be about 5 min away');
    expect(m.body, 'Estimate from 8:02 AM. Open BusBoard for the latest.');
    expect(
        alertMessage(_a, source: AlertSource.live, minutesAway: 5, estimateFrom: DateTime(2026, 10, 6, 16, 2), use24h: true)
            .body,
        'Estimate from 16:02. Open BusBoard for the latest.');
  });
  test('timetable and lost', () {
    for (final s in [AlertSource.timetable, AlertSource.lost]) {
      final m = alertMessage(_a, source: s, minutesAway: 3, use24h: true);
      expect(m.title, 'Route 10 is scheduled in about 3 min');
      expect(m.body, 'MUN Centre (stop 1150) · no live tracking for this trip');
    }
  });
  test('due now', () {
    expect(alertMessage(_a, source: AlertSource.live, minutesAway: 0, use24h: true).title, 'Route 10 is due now');
  });
  test('ongoing notification', () {
    expect(ongoingTitle(_a), 'Route 10 to MUN-CNA-MI');
    expect(ongoingText(_step(AlertSource.live, 12)), 'About 12 min · live');
    expect(ongoingText(_step(AlertSource.timetable, 12)), 'About 12 min · scheduled');
    expect(ongoingText(_step(AlertSource.lost, 12)), 'Live tracking lost · using the timetable · about 12 min');
    expect(ongoingText(_step(AlertSource.live, 0)), 'Due now');
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/arrival_alerts/alert_copy_test.dart`
Expected: FAIL (`alert_copy.dart` does not exist)

- [ ] **Step 4: Write the copy**

```dart
// lib/domain/arrival_alerts/alert_copy.dart
import '../../ui/kit/bb_time.dart';
import 'alert_tracker.dart';
import 'arrival_alert.dart';

/// One notification's text.
class AlertMessage {
  const AlertMessage(this.title, this.body);
  final String title;
  final String body;
}

String _mins(int m) => m == 1 ? '1 min' : '$m min';

/// The alert itself (spec §2.3). [estimateFrom] makes it the iPhone's scheduled estimate.
AlertMessage alertMessage(
  ArrivalAlert a, {
  required AlertSource source,
  required int minutesAway,
  DateTime? estimateFrom,
  required bool use24h,
}) {
  final route = 'Route ${a.routeShortName}';
  final place = '${a.stopName} (stop ${a.stopId})';
  final timetable = source != AlertSource.live;
  final String title;
  if (minutesAway <= 0) {
    title = '$route is due now';
  } else if (timetable) {
    title = '$route is scheduled in about ${_mins(minutesAway)}';
  } else if (estimateFrom != null) {
    title = '$route should be about ${_mins(minutesAway)} away';
  } else {
    title = '$route is about ${_mins(minutesAway)} away';
  }
  final String body;
  if (timetable) {
    body = '$place · no live tracking for this trip';
  } else if (estimateFrom != null) {
    body = 'Estimate from ${BBTime.of(estimateFrom, use24h: use24h)}. Open BusBoard for the latest.';
  } else {
    body = place;
  }
  return AlertMessage(title, body);
}

/// The Android countdown's title (spec §2.2).
String ongoingTitle(ArrivalAlert a) => 'Route ${a.routeShortName} to ${a.headsign}';

/// The Android countdown's line.
String ongoingText(AlertStep s) {
  if (s.minutesAway <= 0) return 'Due now';
  final about = 'about ${_mins(s.minutesAway)}';
  return switch (s.source) {
    AlertSource.live => 'About ${_mins(s.minutesAway)} · live',
    AlertSource.timetable => 'About ${_mins(s.minutesAway)} · scheduled',
    AlertSource.lost => 'Live tracking lost · using the timetable · $about',
  };
}
```

- [ ] **Step 5: Run the copy test**

Run: `flutter test test/arrival_alerts/alert_copy_test.dart`
Expected: PASS

- [ ] **Step 6: Write the notifications wrapper**

```dart
// lib/data/arrival_alerts/alert_notifications.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../domain/arrival_alerts/alert_copy.dart';

/// The notifications an arrival alert needs; a fake replaces it in tests.
abstract class AlertNotifications {
  Future<void> init();
  Future<bool> permissionGranted();

  /// Asks the phone for permission; true when granted.
  Future<bool> requestPermission();

  /// Shows the alert now.
  Future<void> show(AlertMessage m);

  /// Schedules the one pending alert (iPhone estimate, Android backup) at [at], replacing any earlier one.
  Future<void> schedule(AlertMessage m, DateTime at);
  Future<void> cancelScheduled();
}

/// [AlertNotifications] on `flutter_local_notifications`. Android posts to the high-importance
/// "Arrival alerts" channel; the silent "Live tracking" channel belongs to the foreground service.
class LocalAlertNotifications implements AlertNotifications {
  LocalAlertNotifications([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  static const shownId = 4101;
  static const scheduledId = 4102;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'arrival_alerts',
      'Arrival alerts',
      channelDescription: 'A heads-up when your bus is a few minutes away.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      icon: 'ic_notification',
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentList: true, presentSound: true),
  );

  bool _ready = false;

  @override
  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> permissionGranted() async {
    await init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.areNotificationsEnabled() ??
          false;
    }
    final options = await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.checkPermissions();
    return options?.isEnabled ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: true) ??
        false;
  }

  @override
  Future<void> show(AlertMessage m) async {
    await init();
    await _plugin.show(id: shownId, title: m.title, body: m.body, notificationDetails: _details);
  }

  @override
  Future<void> schedule(AlertMessage m, DateTime at) async {
    await init();
    // A UTC instant needs no time-zone lookup: tz.UTC is built into the timezone package.
    await _plugin.zonedSchedule(
      id: scheduledId,
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: m.title,
      body: m.body,
    );
  }

  @override
  Future<void> cancelScheduled() async {
    await init();
    await _plugin.cancel(id: scheduledId);
  }
}
```

- [ ] **Step 7: Android setup**

In `android/app/src/main/AndroidManifest.xml`:
1. After the `ACCESS_COARSE_LOCATION` permission line, add:

```xml
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
```

2. Inside `<application>`, after the geolocator `<service …/>`, add:

```xml
        <!-- Arrival alerts (spec §3.4): the watcher runs only while an alert the rider set is live. -->
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="specialUse"
            android:exported="false">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="A live transit arrival alert the user starts; it ends when the bus arrives (90 min max)"/>
        </service>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <meta-data
            android:name="com.ahamsel.busboard_nl.NOTIFICATION_ICON"
            android:resource="@drawable/ic_notification"/>
```

In `android/app/build.gradle.kts`:
1. Inside `compileOptions { … }` add `isCoreLibraryDesugaringEnabled = true`.
2. At the end of the file add:

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Create `android/app/src/main/res/drawable/ic_notification.xml`, a white bus glyph (Android tints it):

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF"
        android:pathData="M6,3h12a3,3 0,0 1,3 3v10a2,2 0,0 1,-1 1.7V20a1,1 0,0 1,-1 1h-1a1,1 0,0 1,-1 -1v-2H7v2a1,1 0,0 1,-1 1H5a1,1 0,0 1,-1 -1v-2.3A2,2 0,0 1,3 16V6a3,3 0,0 1,3 -3zM5,7v4h14V7zM7.5,13a1.5,1.5 0,1 0,0 3a1.5,1.5 0,0 0,0 -3zM16.5,13a1.5,1.5 0,1 0,0 3a1.5,1.5 0,0 0,0 -3z"/>
</vector>
```

Create `android/app/src/main/res/raw/keep.xml`. The release build shrinks resources, and the icon is only named in Dart and in manifest meta-data:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@drawable/ic_notification"/>
```

- [ ] **Step 8: Pin the Android setup in a test**

```dart
// test/android_alert_setup_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('the alert watcher is a specialUse foreground service with the spec subtype', () {
    expect(manifest, contains('android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"'));
    expect(manifest, contains('android:foregroundServiceType="specialUse"'));
    expect(manifest,
        contains('A live transit arrival alert the user starts; it ends when the bus arrives (90 min max)'));
    expect(manifest, contains('android:name="android.permission.POST_NOTIFICATIONS"'));
  });

  test('no dataSync, boot or exact-alarm permissions', () {
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_DATA_SYNC')));
    expect(manifest, isNot(contains('RECEIVE_BOOT_COMPLETED')));
    expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
  });

  test('the notification icon survives resource shrinking', () {
    expect(File('android/app/src/main/res/drawable/ic_notification.xml').existsSync(), isTrue);
    expect(File('android/app/src/main/res/raw/keep.xml').readAsStringSync(), contains('@drawable/ic_notification'));
  });
}
```

Run: `flutter test test/android_alert_setup_test.dart`
Expected: PASS

- [ ] **Step 9: iOS setup**

Replace `ios/Runner/AppDelegate.swift` with:

```swift
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Lets arrival alerts show while the app is open (flutter_local_notifications).
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

- [ ] **Step 10: Build both platforms**

Run:

```bash
export JAVA_HOME=~/.sdkman/candidates/java/21.0.10-tem GRADLE_OPTS=-Dorg.gradle.java.home=$HOME/.sdkman/candidates/java/21.0.10-tem
flutter build apk --debug
flutter build ios --debug --no-codesign
```

Expected: both builds succeed. Then run `flutter analyze lib test` (expected: no issues) and `flutter test` (expected: all pass).

- [ ] **Step 11: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/domain/arrival_alerts/alert_copy.dart lib/data/arrival_alerts/alert_notifications.dart \
  android/app/src/main/AndroidManifest.xml android/app/build.gradle.kts android/app/src/main/res/drawable/ic_notification.xml \
  android/app/src/main/res/raw/keep.xml ios/Runner/AppDelegate.swift test/arrival_alerts/alert_copy_test.dart test/android_alert_setup_test.dart
git commit -m "feat(alerts): notification copy, the notifications wrapper, platform setup

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The Android watcher

**Files:**
- Create: `lib/platform/alert_runner.dart`, `lib/platform/android_alert_watcher.dart`
- Modify: `lib/main.dart`
- Test: `test/arrival_alerts/watcher_core_test.dart`

**Interfaces:**
- Consumes:
  - Tasks 1–4: `ArrivalAlert`, `AlertTracker`, `AlertStep`, `AlertStore`, `AlertNotifications`, `alertMessage`, `ongoingTitle`, `ongoingText`.
  - `MetrobusMobileApi().fetchDeparturesResult(stopId, forceRefresh: true)`.
- Produces:
  - `abstract class AlertRunner { bool get watchesLive; Future<void> start(ArrivalAlert alert); Future<void> update(ArrivalAlert alert); Future<void> onBackground(ArrivalAlert alert); Future<void> stop(); Stream<void> get finished; }`
  - `class WatcherCore { WatcherCore({required AlertStore store, required Future<MetrobusDeparturesResult> Function(String stopId) fetch, required AlertNotifications notifications, required Future<void> Function(String title, String text) updateOngoing, required DateTime Function() clock, required bool use24h}); Future<bool> check(); }`. `check` returns false when the watcher should stop.
  - `@pragma('vm:entry-point') void arrivalAlertWatcherStart()`
  - `class AndroidAlertRunner implements AlertRunner { AndroidAlertRunner(AlertNotifications notifications); }`
  - `const backupGrace = Duration(minutes: 2)`

`WatcherCore.check` (spec §2.2–2.4, §3.3):
1. Read the store. If there's no alert, return false.
2. Fetch the stop; any exception means `null`.
3. Run `step`.
4. Re-read the store. If it's empty, or `!isSameAlert`, the rider cancelled or replaced the alert mid-check: return false without writing (Review Focus 5).
5. If `step.fire`: show `alertMessage(step.alert, source:, minutesAway:, use24h:)` and cancel the backup.
6. If `step.finished`: clear the store, cancel the backup, and return false.
7. Otherwise:
   - write `step.alert` to the store;
   - if not fired yet, schedule the backup at `alertAt + backupGrace`, with the message `alertMessage(…, source: AlertSource.timetable, minutesAway: alert.leadMinutes, …)`;
   - call `updateOngoing(ongoingTitle, ongoingText)`;
   - return true.

- [ ] **Step 1: Write the failing test**

```dart
// test/arrival_alerts/watcher_core_test.dart
import 'package:busboard_nl/data/arrival_alerts/alert_notifications.dart';
import 'package:busboard_nl/data/arrival_alerts/alert_store.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_copy.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/platform/android_alert_watcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class FakeNotifications implements AlertNotifications {
  final shown = <AlertMessage>[];
  final scheduled = <(AlertMessage, DateTime)>[];
  int cancels = 0;
  @override
  Future<void> init() async {}
  @override
  Future<bool> permissionGranted() async => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> show(AlertMessage m) async => shown.add(m);
  @override
  Future<void> schedule(AlertMessage m, DateTime at) async => scheduled.add((m, at));
  @override
  Future<void> cancelScheduled() async => cancels++;
}

final t0 = DateTime(2026, 10, 6, 8, 0);
final _alert = ArrivalAlert(
  stopId: '1150',
  stopName: 'MUN Centre',
  routeShortName: '10',
  headsign: 'MUN-CNA-MI',
  tripId: 't1',
  scheduledAt: DateTime(2026, 10, 6, 8, 12),
  expectedAt: DateTime(2026, 10, 6, 8, 12),
  live: true,
  leadMinutes: 5,
  setAt: t0,
  lastSeenAt: t0,
);

MetrobusDeparturesResult _live(int h, int m) => MetrobusDeparturesResult(
      departures: [
        MetrobusDeparture(
          routeRun: '10-4',
          routeShortName: '10',
          vehicle: '1415',
          scheduledTime: '',
          predictedTime: '',
          headsign: 'MUN-CNA-MI',
          currentLocation: '',
          isTracked: true,
          tripId: 't1',
          scheduledDepartureSeconds: 8 * 3600 + 12 * 60,
          predictedDepartureSeconds: h * 3600 + m * 60,
          isRealtime: true,
        ),
      ],
      succeeded: true,
      realtimeAvailable: true,
      serviceOperating: true,
      fetchedAt: t0,
    );

void main() {
  late AlertStore store;
  late FakeNotifications notes;
  late List<(String, String)> ongoing;
  late DateTime now;

  WatcherCore core(Future<MetrobusDeparturesResult> Function(String) fetch) => WatcherCore(
        store: store,
        fetch: fetch,
        notifications: notes,
        updateOngoing: (t, x) async => ongoing.add((t, x)),
        clock: () => now,
        use24h: true,
      );

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    store = AlertStore();
    notes = FakeNotifications();
    ongoing = [];
    now = t0.add(const Duration(minutes: 1));
    await store.write(_alert);
  });

  test('a check updates the countdown, re-times the store and the backup', () async {
    expect(await core((_) async => _live(8, 14)).check(), isTrue);
    expect(ongoing.single, ('Route 10 to MUN-CNA-MI', 'About 13 min · live'));
    expect((await store.read())!.expectedAt, DateTime(2026, 10, 6, 8, 14));
    expect(notes.scheduled.single.$2, DateTime(2026, 10, 6, 8, 11)); // 8:14 − 5 + 2 min grace
    expect(notes.shown, isEmpty);
  });

  test('fires once, cancels the backup, keeps counting until due', () async {
    now = DateTime(2026, 10, 6, 8, 9);
    final c = core((_) async => _live(8, 14));
    expect(await c.check(), isTrue);
    expect(notes.shown.single.title, 'Route 10 is about 5 min away');
    expect(notes.cancels, 1);
    now = DateTime(2026, 10, 6, 8, 10);
    expect(await c.check(), isTrue);
    expect(notes.shown, hasLength(1));
    now = DateTime(2026, 10, 6, 8, 14);
    expect(await c.check(), isFalse);
    expect(await store.read(), isNull);
  });

  test('a failing feed still checks (and falls back after 2 minutes)', () async {
    now = t0.add(const Duration(minutes: 3));
    expect(await core((_) async => throw Exception('down')).check(), isTrue);
    expect(ongoing.single.$2, startsWith('Live tracking lost'));
  });

  test('a cancel during the fetch is not undone by the check', () async {
    final c = core((_) async {
      await store.clear(); // the rider taps Cancel while the request is in flight
      return _live(8, 14);
    });
    expect(await c.check(), isFalse);
    expect(await store.read(), isNull);
    expect(ongoing, isEmpty);
  });

  test('a replacement during the fetch stops this check without touching the new alert', () async {
    final replacement = _alert.copyWith().toJson()..['setAt'] = t0.add(const Duration(minutes: 1)).millisecondsSinceEpoch;
    final c = core((_) async {
      await store.write(ArrivalAlert.fromJson(replacement)!);
      return _live(8, 14);
    });
    expect(await c.check(), isFalse);
    expect((await store.read())!.setAt, t0.add(const Duration(minutes: 1)));
  });

  test('no stored alert: stop', () async {
    await store.clear();
    expect(await core((_) async => _live(8, 14)).check(), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/arrival_alerts/watcher_core_test.dart`
Expected: FAIL (`android_alert_watcher.dart` does not exist)

- [ ] **Step 3: Write `lib/platform/alert_runner.dart`**

```dart
// lib/platform/alert_runner.dart
import '../domain/arrival_alerts/arrival_alert.dart';

/// Runs the active arrival alert on this platform: the Android watcher or the iPhone scheduler.
abstract class AlertRunner {
  /// True on Android: the watcher owns the alert's timing and the store while it runs, so the app
  /// must not re-time or rewrite it.
  bool get watchesLive;

  /// Starts [alert], replacing any running one. The alert is already in the store.
  Future<void> start(ArrivalAlert alert);

  /// The app saw a newer prediction for [alert] (iPhone re-schedules; Android ignores it).
  Future<void> update(ArrivalAlert alert);

  /// The app is going to the background with [alert] set.
  Future<void> onBackground(ArrivalAlert alert);

  Future<void> stop();

  /// Fires when the platform side ended the alert itself (the bus was due, the cap, or Cancel on the notification).
  Stream<void> get finished;
}
```

- [ ] **Step 4: Write `lib/platform/android_alert_watcher.dart`**

```dart
// lib/platform/android_alert_watcher.dart
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../data/arrival_alerts/alert_notifications.dart';
import '../data/arrival_alerts/alert_store.dart';
import '../data/realtime/metrobus_mobile_api.dart';
import '../domain/arrival_alerts/alert_copy.dart';
import '../domain/arrival_alerts/alert_tracker.dart';
import '../domain/arrival_alerts/arrival_alert.dart';
import 'alert_runner.dart';

/// The backup alert comes this long after the live one would, so a live watcher always fires first (spec §3.3).
const backupGrace = Duration(minutes: 2);

const _serviceId = 4100;
const _cancelButton = 'cancel';
const _finishedEvent = 'arrival_alert.finished';

/// One watcher check, with every outside effect passed in so tests can run it.
class WatcherCore {
  WatcherCore({
    required this.store,
    required this.fetch,
    required this.notifications,
    required this.updateOngoing,
    required this.clock,
    required this.use24h,
  });

  final AlertStore store;
  final Future<MetrobusDeparturesResult> Function(String stopId) fetch;
  final AlertNotifications notifications;
  final Future<void> Function(String title, String text) updateOngoing;
  final DateTime Function() clock;
  final bool use24h;
  final AlertTracker _tracker = const AlertTracker();

  /// Returns false when the watcher should stop.
  Future<bool> check() async {
    final alert = await store.read();
    if (alert == null) return false;
    MetrobusDeparturesResult? result;
    try {
      result = await fetch(alert.stopId);
    } catch (_) {
      result = null;
    }
    final step = _tracker.step(alert, result, clock());
    // The rider may have cancelled or replaced the alert while the request was in flight.
    final current = await store.read();
    if (current == null || !current.isSameAlert(alert)) return false;
    if (step.fire) {
      await notifications.show(alertMessage(step.alert, source: step.source, minutesAway: step.minutesAway, use24h: use24h));
      await notifications.cancelScheduled();
    }
    if (step.finished) {
      await store.clear();
      await notifications.cancelScheduled();
      return false;
    }
    await store.write(step.alert);
    if (step.alert.firedAt == null) {
      await notifications.schedule(
        alertMessage(step.alert, source: AlertSource.timetable, minutesAway: step.alert.leadMinutes, use24h: use24h),
        step.alert.alertAt.add(backupGrace),
      );
    }
    await updateOngoing(ongoingTitle(step.alert), ongoingText(step));
    return true;
  }
}

@pragma('vm:entry-point')
void arrivalAlertWatcherStart() => FlutterForegroundTask.setTaskHandler(_ArrivalAlertTaskHandler());

class _ArrivalAlertTaskHandler extends TaskHandler {
  final _store = AlertStore();
  final _notifications = LocalAlertNotifications();
  final _api = MetrobusMobileApi();
  late final WatcherCore _core = WatcherCore(
    store: _store,
    fetch: (stopId) => _api.fetchDeparturesResult(stopId, forceRefresh: true),
    notifications: _notifications,
    updateOngoing: (title, text) =>
        FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text),
    clock: DateTime.now,
    use24h: PlatformDispatcher.instance.alwaysUse24HourFormat,
  );
  bool _busy = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _notifications.init();
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) => unawaited(_tick());

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      if (!await _core.check()) await _end();
    } finally {
      _busy = false;
    }
  }

  Future<void> _end() async {
    FlutterForegroundTask.sendDataToMain(_finishedEvent);
    await FlutterForegroundTask.stopService();
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id != _cancelButton) return;
    unawaited(() async {
      await _store.clear();
      await _notifications.cancelScheduled();
      await _end();
    }());
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Android: a `specialUse` foreground service that checks the stop every 30 s (spec §3.1).
class AndroidAlertRunner implements AlertRunner {
  AndroidAlertRunner(this._notifications) {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  final AlertNotifications _notifications;
  final _finished = StreamController<void>.broadcast();

  void _onTaskData(Object data) {
    if (data == _finishedEvent) _finished.add(null);
  }

  @override
  bool get watchesLive => true;

  @override
  Stream<void> get finished => _finished.stream;

  void _init() => FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'live_tracking',
          channelName: 'Live tracking',
          channelDescription: 'The countdown while an arrival alert runs.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(30000),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: false,
        ),
      );

  @override
  Future<void> start(ArrivalAlert alert) async {
    _init();
    await _notifications.schedule(
      alertMessage(alert,
          source: AlertSource.timetable,
          minutesAway: alert.leadMinutes,
          use24h: PlatformDispatcher.instance.alwaysUse24HourFormat),
      alert.alertAt.add(backupGrace),
    );
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.specialUse],
      notificationTitle: ongoingTitle(alert),
      notificationText: 'Checking the live feed…',
      notificationIcon: const NotificationIcon(metaDataName: 'com.ahamsel.busboard_nl.NOTIFICATION_ICON'),
      notificationButtons: const [NotificationButton(id: _cancelButton, text: 'Cancel alert')],
      callback: arrivalAlertWatcherStart,
    );
  }

  @override
  Future<void> update(ArrivalAlert alert) async {}

  @override
  Future<void> onBackground(ArrivalAlert alert) async {}

  @override
  Future<void> stop() async {
    await _notifications.cancelScheduled();
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
  }
}
```

- [ ] **Step 5: Open the task communication port at launch**

In `lib/main.dart`:
1. Add the import `import 'package:flutter_foreground_task/flutter_foreground_task.dart';`.
2. In `main()`, right after `registerAppLicenses();`, add:

```dart
  // The Android arrival-alert watcher reports back to the app on this port.
  FlutterForegroundTask.initCommunicationPort();
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/arrival_alerts/watcher_core_test.dart` (expected: PASS). Then `flutter analyze lib test` (expected: no issues).

- [ ] **Step 7: Commit**

```bash
git add lib/platform/alert_runner.dart lib/platform/android_alert_watcher.dart lib/main.dart test/arrival_alerts/watcher_core_test.dart
git commit -m "feat(alerts): the Android watcher, a specialUse foreground service

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The iPhone scheduler

**Files:**
- Create: `lib/platform/ios_alert_scheduler.dart`
- Test: `test/arrival_alerts/alert_scheduler_test.dart`

**Interfaces:**
- Consumes: Task 4's `AlertNotifications`, `alertMessage`; Task 5's `AlertRunner`; Task 1's `ArrivalAlert`.
- Produces:
  - `class AlertScheduler { AlertScheduler({required AlertNotifications notifications, required DateTime Function() clock, required bool Function() use24h}); Future<void> scheduleFor(ArrivalAlert alert); Future<void> cancel(); }`
  - `class IosAlertRunner implements AlertRunner { IosAlertRunner(AlertScheduler scheduler); }`

`scheduleFor`:
- **Time already passed** (`now >= alertAt`): show now, with `alertMessage(alert, source: alert.live ? live : timetable, minutesAway: max(0, minutes to expectedAt), use24h:)`, then cancel the scheduled one.
- **Otherwise:** schedule at `alertAt`, with `alertMessage(alert, source: alert.live ? live : timetable, minutesAway: alert.leadMinutes, estimateFrom: alert.live ? now : null, use24h:)`.

`IosAlertRunner`:
- `start`, `update` and `onBackground` all call `scheduleFor`; `stop` calls `cancel`.
- `watchesLive` is false; `finished` is an empty stream.

- [ ] **Step 1: Write the failing test**

```dart
// test/arrival_alerts/alert_scheduler_test.dart
import 'package:busboard_nl/data/arrival_alerts/alert_notifications.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_copy.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/platform/ios_alert_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNotifications implements AlertNotifications {
  final shown = <AlertMessage>[];
  final scheduled = <(AlertMessage, DateTime)>[];
  int cancels = 0;
  @override
  Future<void> init() async {}
  @override
  Future<bool> permissionGranted() async => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> show(AlertMessage m) async => shown.add(m);
  @override
  Future<void> schedule(AlertMessage m, DateTime at) async => scheduled.add((m, at));
  @override
  Future<void> cancelScheduled() async => cancels++;
}

ArrivalAlert _alert({bool live = true, DateTime? expected}) => ArrivalAlert(
      stopId: '1150',
      stopName: 'MUN Centre',
      routeShortName: '10',
      headsign: 'MUN-CNA-MI',
      tripId: 't1',
      scheduledAt: DateTime(2026, 10, 6, 8, 12),
      expectedAt: expected ?? DateTime(2026, 10, 6, 8, 14),
      live: live,
      leadMinutes: 5,
      setAt: DateTime(2026, 10, 6, 8, 0),
    );

void main() {
  late FakeNotifications notes;
  late DateTime now;
  AlertScheduler scheduler() => AlertScheduler(notifications: notes, clock: () => now, use24h: () => false);

  setUp(() {
    notes = FakeNotifications();
    now = DateTime(2026, 10, 6, 8, 2);
  });

  test('schedules the estimate at expected − lead', () async {
    await scheduler().scheduleFor(_alert());
    final (m, at) = notes.scheduled.single;
    expect(at, DateTime(2026, 10, 6, 8, 9));
    expect(m.title, 'Route 10 should be about 5 min away');
    expect(m.body, 'Estimate from 8:02 AM. Open BusBoard for the latest.');
  });

  test('a newer prediction replaces the schedule', () async {
    final s = scheduler();
    await s.scheduleFor(_alert());
    await s.scheduleFor(_alert(expected: DateTime(2026, 10, 6, 8, 20)));
    expect(notes.scheduled.last.$2, DateTime(2026, 10, 6, 8, 15));
  });

  test('a timetable alert says so', () async {
    await scheduler().scheduleFor(_alert(live: false, expected: DateTime(2026, 10, 6, 8, 12)));
    expect(notes.scheduled.single.$1.title, 'Route 10 is scheduled in about 5 min');
  });

  test('already past: notifies at once with the real minutes', () async {
    now = DateTime(2026, 10, 6, 8, 11);
    await scheduler().scheduleFor(_alert());
    expect(notes.shown.single.title, 'Route 10 is about 3 min away');
    expect(notes.scheduled, isEmpty);
    expect(notes.cancels, 1);
  });

  test('the runner re-schedules on going to the background and cancels on stop', () async {
    final runner = IosAlertRunner(scheduler());
    expect(runner.watchesLive, isFalse);
    await runner.onBackground(_alert());
    expect(notes.scheduled, hasLength(1));
    await runner.stop();
    expect(notes.cancels, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/arrival_alerts/alert_scheduler_test.dart`
Expected: FAIL (`ios_alert_scheduler.dart` does not exist)

- [ ] **Step 3: Write the implementation**

```dart
// lib/platform/ios_alert_scheduler.dart
import 'dart:math' as math;

import '../data/arrival_alerts/alert_notifications.dart';
import '../domain/arrival_alerts/alert_copy.dart';
import '../domain/arrival_alerts/alert_tracker.dart';
import '../domain/arrival_alerts/arrival_alert.dart';
import 'alert_runner.dart';

/// iPhone: one notification at "expected − lead", re-timed whenever the app learns more (spec §3.1).
class AlertScheduler {
  AlertScheduler({required this.notifications, required this.clock, required this.use24h});

  final AlertNotifications notifications;
  final DateTime Function() clock;
  final bool Function() use24h;

  Future<void> scheduleFor(ArrivalAlert alert) async {
    final now = clock();
    final source = alert.live ? AlertSource.live : AlertSource.timetable;
    if (!now.isBefore(alert.alertAt)) {
      final minutes = math.max(0, alert.expectedAt.difference(now).inSeconds ~/ 60);
      await notifications.show(alertMessage(alert, source: source, minutesAway: minutes, use24h: use24h()));
      await notifications.cancelScheduled();
      return;
    }
    await notifications.schedule(
      alertMessage(alert,
          source: source, minutesAway: alert.leadMinutes, estimateFrom: alert.live ? now : null, use24h: use24h()),
      alert.alertAt,
    );
  }

  Future<void> cancel() => notifications.cancelScheduled();
}

class IosAlertRunner implements AlertRunner {
  IosAlertRunner(this._scheduler);

  final AlertScheduler _scheduler;

  @override
  bool get watchesLive => false;

  @override
  Stream<void> get finished => const Stream.empty();

  @override
  Future<void> start(ArrivalAlert alert) => _scheduler.scheduleFor(alert);

  @override
  Future<void> update(ArrivalAlert alert) => _scheduler.scheduleFor(alert);

  @override
  Future<void> onBackground(ArrivalAlert alert) => _scheduler.scheduleFor(alert);

  @override
  Future<void> stop() => _scheduler.cancel();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/arrival_alerts/alert_scheduler_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/platform/ios_alert_scheduler.dart test/arrival_alerts/alert_scheduler_test.dart
git commit -m "feat(alerts): the iPhone scheduler

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The alert controller

**Files:**
- Create: `lib/state/arrival_alert_providers.dart`
- Test: `test/state/arrival_alert_controller_test.dart`

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces:
  - `final alertStoreProvider = Provider<AlertStore>(…)`
  - `final alertNotificationsProvider = Provider<AlertNotifications>(…)`
  - `final alertRunnerProvider = Provider<AlertRunner>(…)`: Android gets `AndroidAlertRunner`, everything else `IosAlertRunner`.
  - `final alertClockProvider = Provider<DateTime Function()>((ref) => DateTime.now)`
  - `final arrivalAlertProvider = AsyncNotifierProvider<ArrivalAlertController, ArrivalAlert?>(ArrivalAlertController.new)`
  - `enum SetAlertResult { set, permissionDenied }`
  - `ArrivalAlertController`:
    - `Future<SetAlertResult> set(ArrivalRow row, {required String stopId, required String stopName, required int leadMinutes})`
    - `Future<void> cancel()`
    - `void onBoardArrivals(String stopId, List<ArrivalRow> rows)`
    - `Future<int> lastLead()`
    - `Future<bool> permissionGranted()`

Controller rules:
- **`build`:**
  - read the store;
  - clear a stale alert, meaning `now - setAt >= AlertTracker.maxRun` or `now > expectedAt + 2 min` (Review Focus 3);
  - subscribe to `runner.finished`, which clears state and the store;
  - add an `AppLifecycleListener`: `onPause` calls `runner.onBackground(alert)`; `onResume` re-reads the store, because the watcher may have ended while the app was paused.
- **`set`:**
  - `requestPermission()`; if denied, return `permissionDenied` and change nothing (Review Focus 4);
  - otherwise build `ArrivalAlert.fromArrival`, write it to the store, `saveLead`, `runner.start`, set the state, and return `set`.
- **`cancel`:** `runner.stop`, `store.clear`, state null.
- **`onBoardArrivals`:**
  - if the runner `watchesLive`, there's no alert, or the stop differs: do nothing;
  - otherwise find the row with the alert's `tripId`. If it's live, re-time `expectedAt` (and `lastSeenAt`) from it, write the store, call `runner.update`, and set the state.

- [ ] **Step 1: Write the failing test**

```dart
// test/state/arrival_alert_controller_test.dart
import 'dart:async';

import 'package:busboard_nl/data/arrival_alerts/alert_notifications.dart';
import 'package:busboard_nl/data/arrival_alerts/alert_store.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_copy.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/platform/alert_runner.dart';
import 'package:busboard_nl/state/arrival_alert_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class FakeNotifications implements AlertNotifications {
  FakeNotifications({this.grant = true});
  bool grant;
  @override
  Future<void> init() async {}
  @override
  Future<bool> permissionGranted() async => grant;
  @override
  Future<bool> requestPermission() async => grant;
  @override
  Future<void> show(AlertMessage m) async {}
  @override
  Future<void> schedule(AlertMessage m, DateTime at) async {}
  @override
  Future<void> cancelScheduled() async {}
}

class FakeRunner implements AlertRunner {
  FakeRunner({this.watchesLive = false});
  @override
  final bool watchesLive;
  final started = <ArrivalAlert>[];
  final updated = <ArrivalAlert>[];
  int stops = 0;
  final finishedController = StreamController<void>.broadcast();
  @override
  Stream<void> get finished => finishedController.stream;
  @override
  Future<void> start(ArrivalAlert alert) async => started.add(alert);
  @override
  Future<void> update(ArrivalAlert alert) async => updated.add(alert);
  @override
  Future<void> onBackground(ArrivalAlert alert) async {}
  @override
  Future<void> stop() async => stops++;
}

final now = DateTime(2026, 10, 6, 8, 0);
ArrivalRow row({int predicted = 8 * 3600 + 14 * 60, String trip = 't1'}) => ArrivalRow(
      routeShortName: '10',
      headsign: 'MUN-CNA-MI',
      scheduledTime: GtfsTime.fromSeconds(8 * 3600 + 12 * 60),
      predictedTime: GtfsTime.fromSeconds(predicted),
      minutesAway: (predicted - 8 * 3600) ~/ 60,
      isLive: true,
      tripId: trip,
      vehicleNumber: '1415',
      routeRun: '10-4',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRunner runner;
  late FakeNotifications notes;

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      alertRunnerProvider.overrideWithValue(runner),
      alertNotificationsProvider.overrideWithValue(notes),
      alertClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    runner = FakeRunner();
    notes = FakeNotifications();
  });

  test('set stores the alert, remembers the lead and starts the runner', () async {
    final c = container();
    await c.read(arrivalAlertProvider.future);
    final result = await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 10);
    expect(result, SetAlertResult.set);
    expect(c.read(arrivalAlertProvider).value!.tripId, 't1');
    expect((await AlertStore().read())!.leadMinutes, 10);
    expect(await AlertStore().lastLead(), 10);
    expect(runner.started.single.expectedAt, DateTime(2026, 10, 6, 8, 14));
  });

  test('permission denied: nothing stored, nothing started', () async {
    notes.grant = false;
    final c = container();
    await c.read(arrivalAlertProvider.future);
    final result = await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    expect(result, SetAlertResult.permissionDenied);
    expect(c.read(arrivalAlertProvider).value, isNull);
    expect(await AlertStore().read(), isNull);
    expect(runner.started, isEmpty);
  });

  test('cancel stops the runner and clears everything', () async {
    final c = container();
    await c.read(arrivalAlertProvider.future);
    await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    await c.read(arrivalAlertProvider.notifier).cancel();
    expect(runner.stops, 1);
    expect(c.read(arrivalAlertProvider).value, isNull);
    expect(await AlertStore().read(), isNull);
  });

  test('a stored alert comes back after an app restart', () async {
    await AlertStore().write(ArrivalAlert.fromArrival(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5, now: now));
    final c = container();
    expect((await c.read(arrivalAlertProvider.future))!.tripId, 't1');
  });

  test('a stale stored alert (past its window) is cleared at launch', () async {
    await AlertStore().write(ArrivalAlert.fromArrival(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5,
        now: now.subtract(const Duration(hours: 3))));
    final c = container();
    expect(await c.read(arrivalAlertProvider.future), isNull);
    expect(await AlertStore().read(), isNull);
  });

  test('the runner finishing clears the alert', () async {
    final c = container();
    await c.read(arrivalAlertProvider.future);
    await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    await AlertStore().clear();
    runner.finishedController.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(arrivalAlertProvider).value, isNull);
  });

  test('iPhone: a newer Board prediction re-times and re-schedules', () async {
    final c = container();
    await c.read(arrivalAlertProvider.future);
    await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    c.read(arrivalAlertProvider.notifier).onBoardArrivals('1150', [row(predicted: 8 * 3600 + 18 * 60)]);
    await Future<void>.delayed(Duration.zero);
    expect(runner.updated.single.expectedAt, DateTime(2026, 10, 6, 8, 18));
  });

  test('Android: the Board never re-times a watched alert', () async {
    runner = FakeRunner(watchesLive: true);
    final c = container();
    await c.read(arrivalAlertProvider.future);
    await c.read(arrivalAlertProvider.notifier).set(row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5);
    c.read(arrivalAlertProvider.notifier).onBoardArrivals('1150', [row(predicted: 8 * 3600 + 18 * 60)]);
    await Future<void>.delayed(Duration.zero);
    expect(runner.updated, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/arrival_alert_controller_test.dart`
Expected: FAIL (`arrival_alert_providers.dart` does not exist)

- [ ] **Step 3: Write the implementation**

```dart
// lib/state/arrival_alert_providers.dart
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/arrival_alerts/alert_notifications.dart';
import '../data/arrival_alerts/alert_store.dart';
import '../domain/arrival/arrival_models.dart';
import '../domain/arrival_alerts/alert_tracker.dart';
import '../domain/arrival_alerts/arrival_alert.dart';
import '../platform/alert_runner.dart';
import '../platform/android_alert_watcher.dart';
import '../platform/ios_alert_scheduler.dart';

final alertStoreProvider = Provider<AlertStore>((ref) => AlertStore());
final alertNotificationsProvider = Provider<AlertNotifications>((ref) => LocalAlertNotifications());
final alertClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final alertRunnerProvider = Provider<AlertRunner>((ref) {
  final notifications = ref.watch(alertNotificationsProvider);
  if (defaultTargetPlatform == TargetPlatform.android) return AndroidAlertRunner(notifications);
  return IosAlertRunner(AlertScheduler(
    notifications: notifications,
    clock: ref.watch(alertClockProvider),
    use24h: () => PlatformDispatcher.instance.alwaysUse24HourFormat,
  ));
});

enum SetAlertResult { set, permissionDenied }

/// The one active arrival alert (spec §2).
final arrivalAlertProvider =
    AsyncNotifierProvider<ArrivalAlertController, ArrivalAlert?>(ArrivalAlertController.new);

class ArrivalAlertController extends AsyncNotifier<ArrivalAlert?> {
  AlertStore get _store => ref.read(alertStoreProvider);
  AlertRunner get _runner => ref.read(alertRunnerProvider);
  DateTime _now() => ref.read(alertClockProvider)();

  @override
  Future<ArrivalAlert?> build() async {
    final sub = _runner.finished.listen((_) async {
      await _store.clear();
      state = const AsyncData(null);
    });
    final lifecycle = AppLifecycleListener(
      onPause: () {
        final a = state.value;
        if (a != null) unawaited(_runner.onBackground(a));
      },
      onResume: () => unawaited(_reload()),
    );
    ref.onDispose(() {
      unawaited(sub.cancel());
      lifecycle.dispose();
    });
    return _loadFresh();
  }

  Future<ArrivalAlert?> _loadFresh() async {
    final a = await _store.read();
    if (a == null) return null;
    final now = _now();
    final stale = now.difference(a.setAt) >= AlertTracker.maxRun ||
        now.isAfter(a.expectedAt.add(const Duration(minutes: 2)));
    if (!stale) return a;
    await _store.clear();
    return null;
  }

  Future<void> _reload() async => state = AsyncData(await _loadFresh());

  Future<int> lastLead() => _store.lastLead();

  Future<bool> permissionGranted() => ref.read(alertNotificationsProvider).permissionGranted();

  Future<SetAlertResult> set(ArrivalRow row, {required String stopId, required String stopName, required int leadMinutes}) async {
    if (!await ref.read(alertNotificationsProvider).requestPermission()) return SetAlertResult.permissionDenied;
    final alert = ArrivalAlert.fromArrival(row, stopId: stopId, stopName: stopName, leadMinutes: leadMinutes, now: _now());
    await _store.write(alert);
    await _store.saveLead(leadMinutes);
    await _runner.start(alert);
    state = AsyncData(alert);
    return SetAlertResult.set;
  }

  Future<void> cancel() async {
    await _runner.stop();
    await _store.clear();
    state = const AsyncData(null);
  }

  /// The Board refreshed [stopId]. On iPhone a newer live prediction re-times the alert.
  void onBoardArrivals(String stopId, List<ArrivalRow> rows) {
    final a = state.value;
    if (a == null || a.stopId != stopId || _runner.watchesLive) return;
    for (final r in rows) {
      if (r.tripId != a.tripId || !r.isLive || r.predictedTime == null) continue;
      final now = _now();
      final retimed = a.copyWith(expectedAt: instantOfServiceTime(r.displayTime, now), live: true, lastSeenAt: now);
      if (retimed.expectedAt == a.expectedAt) return;
      state = AsyncData(retimed);
      unawaited(_store.write(retimed));
      unawaited(_runner.update(retimed));
      return;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/state/arrival_alert_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/state/arrival_alert_providers.dart test/state/arrival_alert_controller_test.dart
git commit -m "feat(alerts): the alert controller

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The bell, the lead-time sheet and the strip on the Board

**Files:**
- Create: `lib/ui/arrival_alerts/alert_bell.dart`, `lib/ui/arrival_alerts/lead_time_sheet.dart`, `lib/ui/arrival_alerts/alert_strip.dart`
- Modify:
  - `lib/ui/kit/bb_icons.dart`: add `bell` and `bellFill`;
  - `test/kit/icons_test.dart`: add them to `_all`;
  - `lib/ui/board/arrival_row_tile.dart`: an `action` slot;
  - `lib/ui/board/arrival_board_screen.dart`: the bell, the strip, and `onBoardArrivals`.
- Test: `test/ui/arrival_alerts_ui_test.dart`

**Interfaces:**
- Consumes: Task 7 (`arrivalAlertProvider`, `ArrivalAlertController.set/cancel/onBoardArrivals/lastLead/permissionGranted`, `SetAlertResult`); Task 1 (`canAlert`, `leadChoicesFor`).
  - Kit: `BBIconButton(icon:, semanticLabel:, onPressed:, color:)`, `BBChip(label:, selected:, onTap:, semanticLabel:)`, `BBButton(label:, onPressed:, kind:, expand:)`, `BBDialog.show<T>(context, title:, message:, actions: [BBDialogAction(label:, value:, primary:)])`, `bb.floating(radius: BBRadius.sheet)`, `BBMotion`.
  - `Geolocator.openAppSettings()` (package `geolocator`, already a dependency).
- Produces:
  - `class AlertBell extends ConsumerWidget { const AlertBell({super.key, required this.arrival, required this.stopId, required this.stopName}); }`: renders nothing when `!canAlert(arrival)`.
  - `Future<int?> showLeadTimeSheet(BuildContext context, {required ArrivalRow arrival, required int initialLead, required bool explainPermission})`
  - `class AlertStrip extends ConsumerWidget`
  - `ArrivalRowTile({…, Widget? action})`

Behaviour (spec §2.1):
- **Bell icons:** `BBIcons.bell` = `IconData(0xe0ce, fontFamily: 'PhosphorRegular')` and `BBIcons.bellFill` = `IconData(0xe0ce, fontFamily: 'PhosphorFill')`.
- **Bell label:** "Alert me before route 10 arrives"; when this row's alert is active, "Alert set for route 10. Cancel alert".
- **Tapping an active bell:** asks "Cancel your alert for route 10?" (actions Keep / Cancel alert) and calls `cancel()` on confirm.
- **Tapping any other bell:**
  - if a different alert exists, ask "Replace your alert for route X?" (Keep / Replace);
  - then open the sheet with `initialLead = await lastLead()` (moved to the largest allowed choice if it isn't allowed), and `explainPermission = !await permissionGranted()`;
  - on a chosen lead, call `set`; on `permissionDenied`, show the denied dialog: "Alerts need notifications", "Turn on notifications for BusBoard in Settings.", actions Not now / Open settings (`Geolocator.openAppSettings()`).
- **The sheet:**
  - title "Alert me when route 10 is";
  - a `BBChip` per `alertLeadChoices` reading "3 min" / "5 min" / "10 min". Choices not in `leadChoicesFor(minutesAway)` are drawn at 0.4 opacity with `onTap: null`;
  - when `explainPermission`, the line "BusBoard will ask to send notifications, so it can alert you.";
  - buttons **Set alert** (primary, returns the lead) and **Cancel** (quiet, returns null).
- **The strip:** shown at the top of the Board's list when an alert exists. It reads "Alert set · Route 10 · 5 min before", with a quiet **Cancel** button that calls `cancel()` directly.

- [ ] **Step 1: Add the icons**

In `lib/ui/kit/bb_icons.dart`, after the `remove` line, add:

```dart
  static const IconData bell = IconData(0xe0ce, fontFamily: 'PhosphorRegular'); // bell
  static const IconData bellFill = IconData(0xe0ce, fontFamily: 'PhosphorFill'); // bell
```

In `test/kit/icons_test.dart`, append `BBIcons.bell, BBIcons.bellFill,` to the `_all` list.

- [ ] **Step 2: Write the failing widget tests**

```dart
// test/ui/arrival_alerts_ui_test.dart
import 'dart:async';

import 'package:busboard_nl/data/arrival_alerts/alert_notifications.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_copy.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/platform/alert_runner.dart';
import 'package:busboard_nl/state/arrival_alert_providers.dart';
import 'package:busboard_nl/ui/arrival_alerts/alert_bell.dart';
import 'package:busboard_nl/ui/arrival_alerts/alert_strip.dart';
import 'package:busboard_nl/ui/arrival_alerts/lead_time_sheet.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../kit/kit_test_helpers.dart';

class _Notes implements AlertNotifications {
  _Notes(this.grant);
  final bool grant;
  @override
  Future<void> init() async {}
  @override
  Future<bool> permissionGranted() async => grant;
  @override
  Future<bool> requestPermission() async => grant;
  @override
  Future<void> show(AlertMessage m) async {}
  @override
  Future<void> schedule(AlertMessage m, DateTime at) async {}
  @override
  Future<void> cancelScheduled() async {}
}

class _Runner implements AlertRunner {
  final started = <ArrivalAlert>[];
  @override
  bool get watchesLive => true;
  @override
  Stream<void> get finished => const Stream.empty();
  @override
  Future<void> start(ArrivalAlert alert) async => started.add(alert);
  @override
  Future<void> update(ArrivalAlert alert) async {}
  @override
  Future<void> onBackground(ArrivalAlert alert) async {}
  @override
  Future<void> stop() async {}
}

ArrivalRow _row(int minutes, {String trip = 't1', String route = '10'}) => ArrivalRow(
      routeShortName: route,
      headsign: 'MUN-CNA-MI',
      scheduledTime: GtfsTime.fromSeconds(8 * 3600 + minutes * 60),
      predictedTime: GtfsTime.fromSeconds(8 * 3600 + minutes * 60),
      minutesAway: minutes,
      isLive: true,
      tripId: trip,
      vehicleNumber: '1415',
    );

Future<_Runner> _pump(WidgetTester tester, Widget child, {bool grant = true, double textScale = 1, double width = 390}) async {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  final runner = _Runner();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      alertRunnerProvider.overrideWithValue(runner),
      alertNotificationsProvider.overrideWithValue(_Notes(grant)),
    ],
    child: kitHost(child, textScale: textScale, width: width),
  ));
  await tester.pumpAndSettle();
  return runner;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('no bell under 3 or over 60 minutes', (tester) async {
    await _pump(tester, Column(children: [
      AlertBell(arrival: _row(2), stopId: '1150', stopName: 'MUN Centre'),
      AlertBell(arrival: _row(61), stopId: '1150', stopName: 'MUN Centre'),
    ]));
    expect(find.byIcon(BBIcons.bell), findsNothing);
  });

  testWidgets('bell → sheet → Set alert starts an alert with the chosen lead', (tester) async {
    final handle = tester.ensureSemantics();
    final runner = await _pump(tester, AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre'));
    expect(find.bySemanticsLabel('Alert me before route 10 arrives'), findsOneWidget);
    await tester.tap(find.byIcon(BBIcons.bell));
    await tester.pumpAndSettle();
    expect(find.text('Alert me when route 10 is'), findsOneWidget);
    expect(find.text('BusBoard will ask to send notifications, so it can alert you.'), findsNothing);
    await tester.tap(find.text('10 min'));
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    expect(runner.started.single.leadMinutes, 10);
    expect(find.byIcon(BBIcons.bellFill), findsOneWidget);
    expect(find.bySemanticsLabel('Alert set for route 10. Cancel alert'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a bus 4 minutes away offers only 3 min', (tester) async {
    await _pump(tester, AlertBell(arrival: _row(4), stopId: '1150', stopName: 'MUN Centre'));
    await tester.tap(find.byIcon(BBIcons.bell));
    await tester.pumpAndSettle();
    final ten = tester.widget<BBChip>(find.widgetWithText(BBChip, '10 min'));
    final three = tester.widget<BBChip>(find.widgetWithText(BBChip, '3 min'));
    expect(ten.onTap, isNull);
    expect(three.onTap, isNotNull);
  });

  testWidgets('permission denied: nothing starts, and Settings is offered', (tester) async {
    final runner = await _pump(tester, AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre'), grant: false);
    await tester.tap(find.byIcon(BBIcons.bell));
    await tester.pumpAndSettle();
    expect(find.text('BusBoard will ask to send notifications, so it can alert you.'), findsOneWidget);
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    expect(runner.started, isEmpty);
    expect(find.text('Alerts need notifications'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('a second bell asks before replacing', (tester) async {
    final runner = await _pump(tester, Column(children: [
      AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre'),
      AlertBell(arrival: _row(25, trip: 't2', route: '1'), stopId: '1150', stopName: 'MUN Centre'),
    ]));
    await tester.tap(find.byIcon(BBIcons.bell).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(BBIcons.bell).last);
    await tester.pumpAndSettle();
    expect(find.text('Replace your alert for route 10?'), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    expect(runner.started.map((a) => a.routeShortName), ['10', '1']);
  });

  testWidgets('the strip shows the alert and cancels it', (tester) async {
    await _pump(tester, Column(children: [
      const AlertStrip(),
      AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre'),
    ]));
    expect(find.textContaining('Alert set'), findsNothing);
    await tester.tap(find.byIcon(BBIcons.bell));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set alert'));
    await tester.pumpAndSettle();
    expect(find.text('Alert set · Route 10 · 5 min before'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Alert set'), findsNothing);
  });

  testWidgets('a row with its bell does not overflow at 320 pt and 2× text', (tester) async {
    await _pump(
      tester,
      ArrivalRowTile(arrival: _row(20), action: AlertBell(arrival: _row(20), stopId: '1150', stopName: 'MUN Centre')),
      textScale: 2,
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet does not overflow at 320 pt and 2× text', (tester) async {
    await _pump(tester, Builder(builder: (context) => BBButton(
          label: 'open',
          onPressed: () => showLeadTimeSheet(context, arrival: _row(20), initialLead: 5, explainPermission: true),
        )), textScale: 2, width: 320);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/ui/arrival_alerts_ui_test.dart`
Expected: FAIL (the `arrival_alerts` UI files do not exist)

- [ ] **Step 4: Write the lead-time sheet**

```dart
// lib/ui/arrival_alerts/lead_time_sheet.dart
import 'package:flutter/widgets.dart';

import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival_alerts/arrival_alert.dart';
import '../kit/kit.dart';

/// "Alert me when route 10 is 3 / 5 / 10 min away" (spec §2.1). Returns the lead, or null.
Future<int?> showLeadTimeSheet(
  BuildContext context, {
  required ArrivalRow arrival,
  required int initialLead,
  required bool explainPermission,
}) {
  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x331C2A3A),
    transitionDuration: BBMotion.of(context, BBMotion.standard),
    pageBuilder: (_, _, _) =>
        _LeadTimeCard(arrival: arrival, initialLead: initialLead, explainPermission: explainPermission),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: animation, curve: BBMotion.curve), child: child),
  );
}

class _LeadTimeCard extends StatefulWidget {
  const _LeadTimeCard({required this.arrival, required this.initialLead, required this.explainPermission});

  final ArrivalRow arrival;
  final int initialLead;
  final bool explainPermission;

  @override
  State<_LeadTimeCard> createState() => _LeadTimeCardState();
}

class _LeadTimeCardState extends State<_LeadTimeCard> {
  late final List<int> _allowed = leadChoicesFor(widget.arrival.minutesAway);
  late int _lead = _allowed.contains(widget.initialLead) ? widget.initialLead : _allowed.last;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final nav = Navigator.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(BBSpace.l),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: DecoratedBox(
              decoration: bb.floating(radius: BBRadius.sheet),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(BBSpace.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Alert me when route ${widget.arrival.routeShortName} is', style: bb.text.headline),
                    ),
                    const SizedBox(height: BBSpace.m),
                    Wrap(
                      spacing: BBSpace.s,
                      runSpacing: BBSpace.s,
                      children: [
                        for (final m in alertLeadChoices)
                          Opacity(
                            opacity: _allowed.contains(m) ? 1 : 0.4,
                            child: BBChip(
                              label: '$m min',
                              selected: m == _lead,
                              semanticLabel: _allowed.contains(m) ? '$m minutes away' : '$m minutes, too late for this bus',
                              onTap: _allowed.contains(m) ? () => setState(() => _lead = m) : null,
                            ),
                          ),
                      ],
                    ),
                    if (widget.explainPermission) ...[
                      const SizedBox(height: BBSpace.m),
                      Text('BusBoard will ask to send notifications, so it can alert you.', style: bb.text.caption),
                    ],
                    const SizedBox(height: BBSpace.l),
                    BBButton(label: 'Set alert', expand: true, onPressed: () => nav.pop(_lead)),
                    const SizedBox(height: BBSpace.s),
                    BBButton(label: 'Cancel', kind: BBButtonKind.quiet, expand: true, onPressed: () => nav.pop()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Write the bell**

```dart
// lib/ui/arrival_alerts/alert_bell.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival_alerts/arrival_alert.dart';
import '../../state/arrival_alert_providers.dart';
import '../kit/kit.dart';
import 'lead_time_sheet.dart';

/// The bell on an arrival (spec §2.1). Nothing for a bus under 3 or over 60 minutes away.
class AlertBell extends ConsumerWidget {
  const AlertBell({super.key, required this.arrival, required this.stopId, required this.stopName});

  final ArrivalRow arrival;
  final String stopId;
  final String stopName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(arrivalAlertProvider).value;
    final active = current != null && current.stopId == stopId && current.tripId == arrival.tripId;
    if (!active && !canAlert(arrival)) return const SizedBox.shrink();
    final route = arrival.routeShortName;
    return BBIconButton(
      icon: active ? BBIcons.bellFill : BBIcons.bell,
      color: active ? context.bb.colors.liveInk : null,
      semanticLabel: active ? 'Alert set for route $route. Cancel alert' : 'Alert me before route $route arrives',
      onPressed: () => active ? _confirmCancel(context, ref) : _set(context, ref, current),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final yes = await BBDialog.show<bool>(
      context,
      title: 'Cancel your alert for route ${arrival.routeShortName}?',
      actions: const [
        BBDialogAction(label: 'Keep', value: false),
        BBDialogAction(label: 'Cancel alert', value: true, primary: true),
      ],
    );
    if (yes == true) await ref.read(arrivalAlertProvider.notifier).cancel();
  }

  Future<void> _set(BuildContext context, WidgetRef ref, ArrivalAlert? current) async {
    final controller = ref.read(arrivalAlertProvider.notifier);
    if (current != null) {
      final replace = await BBDialog.show<bool>(
        context,
        title: 'Replace your alert for route ${current.routeShortName}?',
        actions: const [
          BBDialogAction(label: 'Keep', value: false),
          BBDialogAction(label: 'Replace', value: true, primary: true),
        ],
      );
      if (replace != true || !context.mounted) return;
    }
    final initial = await controller.lastLead();
    final explain = !await controller.permissionGranted();
    if (!context.mounted) return;
    final lead = await showLeadTimeSheet(context, arrival: arrival, initialLead: initial, explainPermission: explain);
    if (lead == null) return;
    final result = await controller.set(arrival, stopId: stopId, stopName: stopName, leadMinutes: lead);
    if (result == SetAlertResult.permissionDenied && context.mounted) {
      final open = await BBDialog.show<bool>(
        context,
        title: 'Alerts need notifications',
        message: 'Turn on notifications for BusBoard in Settings.',
        actions: const [
          BBDialogAction(label: 'Not now', value: false),
          BBDialogAction(label: 'Open settings', value: true, primary: true),
        ],
      );
      if (open == true) await Geolocator.openAppSettings();
    }
  }
}
```

(`BBDialog.show`'s `message` is optional. `bb.colors.liveInk` is the colour `NearMeList` uses for its icon.)

- [ ] **Step 6: Write the strip**

```dart
// lib/ui/arrival_alerts/alert_strip.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/arrival_alert_providers.dart';
import '../kit/kit.dart';

/// "Alert set · Route 10 · 5 min before · Cancel" at the top of the Board (spec §2.1).
class AlertStrip extends ConsumerWidget {
  const AlertStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(arrivalAlertProvider).value;
    if (a == null) return const SizedBox.shrink();
    final bb = context.bb;
    return BBCard(
      child: Row(children: [
        Icon(BBIcons.bellFill, size: 20, color: bb.colors.liveInk),
        const SizedBox(width: BBSpace.s),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text('Alert set · Route ${a.routeShortName} · ${a.leadMinutes} min before', style: bb.text.body),
          ),
        ),
        BBButton(
          label: 'Cancel',
          kind: BBButtonKind.quiet,
          onPressed: () => ref.read(arrivalAlertProvider.notifier).cancel(),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 7: Give `ArrivalRowTile` an action slot**

In `lib/ui/board/arrival_row_tile.dart`:
1. Constructor and field:

```dart
  const ArrivalRowTile({super.key, required this.arrival, this.onTap, this.action});

  /// A trailing control with its own semantics (the alert bell).
  final Widget? action;
```

2. In `build`, the `Semantics(label:…, excludeSemantics: true, …)` wraps the whole `BBCard` today, which would hide the bell from screen readers. Make the card the outer widget, and put the semantics on the content only. The existing `LayoutBuilder(builder: (context, box) => Row(children: [...]))` becomes the `content` below, unchanged:

```dart
    final content = LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          // … the existing badge, text column and minutes column, unchanged …
        ],
      ),
    );
    return BBCard(
      onTap: onTap,
      child: Row(children: [
        Expanded(
          child: Semantics(
            label: semanticsLabel(a, use24h: use24h),
            excludeSemantics: true,
            button: onTap != null ? true : null,
            onTap: onTap,
            onTapHint: onTap == null ? null : 'follow bus ${a.vehicleNumber} on the map',
            child: content,
          ),
        ),
        if (action != null) action!,
      ]),
    );
```

3. Run `flutter test test/ui/arrival_row_tile_test.dart test/ui/arrival_board_screen_test.dart`. Expected: they still pass (the row's label and tap are unchanged).

- [ ] **Step 8: Put the bell and the strip on the Board**

In `lib/ui/board/arrival_board_screen.dart`:
1. Imports: `../../state/arrival_alert_providers.dart`, `../arrival_alerts/alert_bell.dart`, `../arrival_alerts/alert_strip.dart`.
2. In `_refreshData`, right after `final arrivals = service.getUpcomingArrivals(…);`, add `ref.read(arrivalAlertProvider.notifier).onBoardArrivals(widget.stopId, arrivals);`.
3. In `_buildArrivalsList`:
   - add a `stopName` parameter, passed from `build` as the `stopName` local;
   - make the leading items `[if alert strip, ?alertBlock]` by building `final strip = const Padding(padding: EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.s, BBSpace.screen, 0), child: AlertStrip());` and prepending it to every list state (loading, error, empty and the list);
   - `leading` counts it.
4. Each `ArrivalRowTile(...)` gets `action: AlertBell(arrival: _arrivals[index - leading], stopId: widget.stopId, stopName: stopName)`.
5. Test harnesses that build a Board must not start real plugins. Create `test/helpers/fake_alerts.dart`:

```dart
// test/helpers/fake_alerts.dart
import 'package:busboard_nl/data/arrival_alerts/alert_notifications.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_copy.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/platform/alert_runner.dart';
import 'package:busboard_nl/state/arrival_alert_providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _QuietNotifications implements AlertNotifications {
  @override
  Future<void> init() async {}
  @override
  Future<bool> permissionGranted() async => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> show(AlertMessage m) async {}
  @override
  Future<void> schedule(AlertMessage m, DateTime at) async {}
  @override
  Future<void> cancelScheduled() async {}
}

class _QuietRunner implements AlertRunner {
  @override
  bool get watchesLive => true;
  @override
  Stream<void> get finished => const Stream.empty();
  @override
  Future<void> start(ArrivalAlert alert) async {}
  @override
  Future<void> update(ArrivalAlert alert) async {}
  @override
  Future<void> onBackground(ArrivalAlert alert) async {}
  @override
  Future<void> stop() async {}
}

/// Overrides that keep arrival alerts away from real plugins in screen tests.
final fakeAlertOverrides = [
  alertRunnerProvider.overrideWithValue(_QuietRunner()),
  alertNotificationsProvider.overrideWithValue(_QuietNotifications()),
];

/// Call in setUp: an in-memory store for SharedPreferencesAsync.
void useInMemoryAlertStore() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
```

   - Add `...fakeAlertOverrides` to the `ProviderContainer`/`ProviderScope` overrides in `test/ui/arrival_board_screen_test.dart`, `test/ui/screen_overflow_test.dart` and `test/ui/screen_golden_test.dart`, wherever a Board is built.
   - Call `useInMemoryAlertStore()` at the start of their pump helpers.

- [ ] **Step 9: Run the tests**

Run: `flutter test test/ui/arrival_alerts_ui_test.dart test/kit/icons_test.dart test/kit/kit_boundary_test.dart`, then the whole suite: `flutter test`.
Expected: all pass. If a board golden changed because of the bell, regenerate only those goldens with `flutter test --update-goldens test/ui/screen_golden_test.dart`, look at each changed image, and confirm the only difference is the bell.

- [ ] **Step 10: Commit**

```bash
git add lib/ui/kit/bb_icons.dart test/kit/icons_test.dart lib/ui/arrival_alerts lib/ui/board test/ui
git commit -m "feat(alerts): the bell, the lead-time sheet and the Alert set strip on the Board

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: The bell on the follow card

**Files:**
- Modify: `lib/ui/map/follow_card.dart`, `lib/ui/map/map_screen.dart`
- Test: `test/ui/follow_card_test.dart` (add a test)

**Interfaces:**
- Consumes: Task 8's `AlertBell`.
  - `FollowCardHeader` (its constructor: `snapshot`, `yourStopName`, `minutesToYourStop`, `tripHeadsign`, `routeLabel`, `onStop`, `onSeeAll`, `actionsFirst`, `actionsKey`).
  - In `map_screen.dart`, `_followHeader(...)`: `final live = yourStopArrivals.where((a) => a.vehicleNumber == f.vehicleId);` and `myStop` (`StopInfo?`: `stopId`, `stopName`).
- Produces: `FollowCardHeader({…, Widget? alertAction})`, shown at the end of the title row (next to the minutes) when the bus has not arrived.

- [ ] **Step 1: Write the failing test**

In `test/ui/follow_card_test.dart`:
1. Give the `_host` helper a `Widget? alertAction` parameter and pass it as `alertAction: alertAction` to `FollowCardHeader`.
2. Add:

```dart
  testWidgets('header: the alert bell shows until the bus has arrived', (tester) async {
    await _host(tester, _snap(), alertAction: const Text('BELL'));
    expect(find.text('BELL'), findsOneWidget);
    await _host(tester, _snap(busIndex: 2, toGo: 0, arrived: true), alertAction: const Text('BELL'));
    expect(find.text('BELL'), findsNothing);
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/ui/follow_card_test.dart`
Expected: FAIL (no `alertAction` parameter)

- [ ] **Step 3: Implement**

- **`follow_card.dart`:** add `this.alertAction` and `final Widget? alertAction;`. In the title row, after the minutes column, add `if (alertAction != null && !arrived) alertAction!`.
- **`map_screen.dart` `_followHeader`:** pass `alertAction: live.isEmpty || myStop == null ? null : AlertBell(arrival: live.first, stopId: myStop.stopId, stopName: myStop.stopName)`, importing `../arrival_alerts/alert_bell.dart`.
- **Map test harnesses:** in `test/ui/map_screen_test.dart`, and any golden that pumps the map, add `...fakeAlertOverrides` from `test/helpers/fake_alerts.dart` (Task 8) to the overrides, and call `useInMemoryAlertStore()` in the pump helper.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/ui/follow_card_test.dart test/ui/map_screen_test.dart`, then `flutter test`.
Expected: all pass, including the existing "follow mode no overflow at 320 pt and text x2.0" test.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/map/follow_card.dart lib/ui/map/map_screen.dart test/ui
git commit -m "feat(alerts): the bell on the follow card

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Recording a stop and the replay test

**Files:**
- Create: `tool/capture_stop_predictions.dart`, `test/arrival_alerts/alert_replay_test.dart`

**Interfaces:**
- Consumes:
  - `MetrobusMobileApi(client:)` and `fetchDeparturesResult(stopId, forceRefresh: true)`;
  - `package:http/testing.dart` `MockClient`;
  - Task 2's `AlertTracker`; Task 1's `ArrivalAlert`, `instantOfServiceTime`, `alertLeadChoices`.
- Produces:
  - **Capture tool:** `dart run tool/capture_stop_predictions.dart <stopId> <minutes>` prints one JSON line per 30 s, `{"t":"<ISO local time>","body":"<raw response>"}`.
  - **Replay test:** reads the file named by the environment variable `ALERT_CAPTURE` and skips when it's unset.

Replay method:
- **Samples:** each capture line becomes one result, via a `MockClient` that returns that line's body.
- **Real departure** of a trip: the predicted departure in the last sample where the trip appeared as realtime.
- **Alert setup:** for every trip seen live, and every lead `L` in 3/5/10, set an alert at the first sample where the trip is live and at least `L + 1` min away. Build it from that sample's row (`expectedAt` = its prediction, `lastSeenAt` = sample time, `scheduledAt` = its schedule).
- **Run:** step the tracker through every later sample until it fires.
- **Error:** `firedAt − (realDeparture − L)`.
- **Assertions (spec §1):**
  - at least 90% of errors are within ±60 s;
  - none is later than +180 s;
  - print a summary line (count, share within ±60 s, worst late) for the release notes.

- [ ] **Step 1: Write the capture tool**

```dart
// tool/capture_stop_predictions.dart
// Records one stop's Metrobus stop predictions every 30 s, as JSON lines, for the alert replay test.
//   dart run tool/capture_stop_predictions.dart 1150 120 > test/fixtures/arrival_alerts/stop_1150_<date>.jsonl
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: dart run tool/capture_stop_predictions.dart <stopId> <minutes>');
    exit(64);
  }
  final stopId = args[0];
  final end = DateTime.now().add(Duration(minutes: int.parse(args[1])));
  final url = Uri.parse('https://www.metrobusmobile.com/NextBus/fleetview.asp').replace(queryParameters: {
    'type': 'timetrackjson',
    'stopid': stopId,
    'lookaheadMinutes': '120',
  });
  final client = http.Client();
  while (DateTime.now().isBefore(end)) {
    final t = DateTime.now();
    try {
      final r = await client.get(url).timeout(const Duration(seconds: 10));
      stdout.writeln(jsonEncode({'t': t.toIso8601String(), 'status': r.statusCode, 'body': r.body}));
    } catch (e) {
      stdout.writeln(jsonEncode({'t': t.toIso8601String(), 'status': 0, 'body': ''}));
      stderr.writeln('$t $e');
    }
    await Future<void>.delayed(const Duration(seconds: 30) - DateTime.now().difference(t));
  }
  client.close();
}
```

- [ ] **Step 2: Write the replay test**

```dart
// test/arrival_alerts/alert_replay_test.dart
// ALERT_CAPTURE=test/fixtures/arrival_alerts/stop_1150_<date>.jsonl flutter test test/arrival_alerts/alert_replay_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_tracker.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final path = Platform.environment['ALERT_CAPTURE'];

  test('replayed alerts fire within ±1 min of real departure − lead (spec §1)', () async {
    final samples = <(DateTime, MetrobusDeparturesResult)>[];
    for (final line in File(path!).readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
      final j = jsonDecode(line) as Map<String, dynamic>;
      final body = j['body'] as String;
      final status = j['status'] as int? ?? 200;
      final api = MetrobusMobileApi(client: MockClient((_) async => http.Response(body, status == 0 ? 500 : status)));
      samples.add((DateTime.parse(j['t'] as String), await api.fetchDeparturesResult('1150', forceRefresh: true)));
    }

    DateTime? predictedAt(MetrobusDeparture d, DateTime t) {
      final g = d.predictedGtfsTime ?? d.scheduledGtfsTime;
      return g == null ? null : instantOfServiceTime(g, t);
    }

    // Real departure: the last realtime prediction for each trip.
    final real = <String, DateTime>{};
    for (final (t, r) in samples) {
      for (final d in r.departures.where((d) => d.isRealtime && d.tripId.isNotEmpty)) {
        final p = predictedAt(d, t);
        if (p != null) real[d.tripId] = p;
      }
    }

    const tracker = AlertTracker();
    final errors = <Duration>[];
    for (final trip in real.keys) {
      for (final lead in alertLeadChoices) {
        final start = samples.indexWhere((s) => s.$2.departures.any((d) {
              final p = d.tripId == trip && d.isRealtime ? predictedAt(d, s.$1) : null;
              return p != null && p.difference(s.$1) >= Duration(minutes: lead + 1);
            }));
        if (start < 0) continue;
        final (t0, r0) = samples[start];
        final d0 = r0.departures.firstWhere((d) => d.tripId == trip);
        var alert = ArrivalAlert(
          stopId: '1150',
          stopName: 'Stop',
          routeShortName: d0.routeShortName,
          headsign: d0.headsign,
          tripId: trip,
          routeRun: d0.routeRun,
          vehicle: d0.vehicle,
          scheduledAt: instantOfServiceTime(d0.scheduledGtfsTime!, t0),
          expectedAt: predictedAt(d0, t0)!,
          live: true,
          leadMinutes: lead,
          setAt: t0,
          lastSeenAt: t0,
        );
        for (final (t, r) in samples.skip(start + 1)) {
          final s = tracker.step(alert, r, t);
          alert = s.alert;
          if (s.fire) {
            errors.add(t.difference(real[trip]!.subtract(Duration(minutes: lead))));
            break;
          }
          if (s.finished) break;
        }
      }
    }

    expect(errors, isNotEmpty);
    final within = errors.where((e) => e.inSeconds.abs() <= 60).length / errors.length;
    final worstLate = errors.map((e) => e.inSeconds).reduce((a, b) => a > b ? a : b);
    // ignore: avoid_print
    print('alerts: ${errors.length}, within ±60 s: ${(within * 100).toStringAsFixed(1)}%, worst late: $worstLate s');
    expect(within, greaterThanOrEqualTo(0.9));
    expect(worstLate, lessThanOrEqualTo(180));
  }, skip: path == null ? 'set ALERT_CAPTURE to a capture made with tool/capture_stop_predictions.dart' : false);
}
```

- [ ] **Step 3: Check the test skips cleanly**

Run: `flutter test test/arrival_alerts/alert_replay_test.dart`
Expected: 1 test skipped, no failures.

- [ ] **Step 4: Commit**

```bash
git add tool/capture_stop_predictions.dart test/arrival_alerts/alert_replay_test.dart
git commit -m "test(alerts): stop capture tool and alert replay test

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5 (controller, at the next weekday rush hour): record and replay**

```bash
mkdir -p test/fixtures/arrival_alerts
dart run tool/capture_stop_predictions.dart 1150 120 > test/fixtures/arrival_alerts/stop_1150_$(date +%F).jsonl
ALERT_CAPTURE=test/fixtures/arrival_alerts/stop_1150_$(date +%F).jsonl flutter test test/arrival_alerts/alert_replay_test.dart
```

Expected: PASS, and the printed summary line goes in the ledger. If it fails, the failure is a tracker finding to fix in `alert_tracker.dart` with a new unit test, before release. Commit the fixture with the test's result in the message.

---

### Task 11: Device verification (controller)

No new code; this is done by the controller with the user's emulator and simulator. Record each result in the ledger.

- [ ] **Android emulator** (`emulator-5554`, profile build):
  1. Set a 3-min alert on a live arrival. The ongoing "Route N to … · About M min · live" notification appears, with **Cancel alert**.
  2. Lock the screen. The countdown text updates about every 30 s.
  3. Run `adb shell dumpsys deviceidle force-idle`, then wait. The countdown keeps updating and the alert arrives.
  4. Set another alert, then tap **Cancel alert** in the notification. The ongoing notification disappears and the Board's strip clears on return.
  5. Swipe the app away from recents while an alert runs. The countdown keeps running. Reopen the app: the strip shows the alert.
  6. Afterwards: `adb shell dumpsys deviceidle unforce`, and leave the emulator as found.
- [ ] **iOS simulator:**
  1. Set a 3-min alert. Allow notifications at the prompt.
  2. Background the app. The "should be about 3 min away (estimate from …)" notification arrives at the right time.
  3. Set and cancel an alert. Nothing arrives.
- [ ] **Both:** `flutter analyze lib test` is clean and `flutter test` passes.
- [ ] **Release prep, separately and only with the user's go-ahead:**
  - version 1.3.0 and store notes;
  - the privacy-policy line (the portfolio repo's `public/apps/privacy-policy/busboard-nl`);
  - the Play Console foreground-service declaration and video;
  - the real-bus recording.
