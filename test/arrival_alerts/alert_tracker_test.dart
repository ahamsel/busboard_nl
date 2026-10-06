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
