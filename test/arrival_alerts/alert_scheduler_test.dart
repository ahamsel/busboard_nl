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
  @override
  Future<String?> launchRoute() async => null;
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
      lastSeenAt: live ? DateTime(2026, 10, 6, 8, 1) : null,
    );

void main() {
  late FakeNotifications notes;
  late DateTime now;
  AlertScheduler scheduler() => AlertScheduler(notifications: notes, clock: () => now, use24h: () => false);

  setUp(() {
    notes = FakeNotifications();
    now = DateTime(2026, 10, 6, 8, 2);
  });

  test('schedules the estimate at expected − lead − margin, dated from the last live sighting', () async {
    await scheduler().scheduleFor(_alert());
    final (m, at) = notes.scheduled.single;
    expect(at, DateTime(2026, 10, 6, 8, 8)); // 08:14 − 5 − 1 min margin
    expect(m.title, 'Route 10 should be about 5 min away', reason: 'the lead, not the 6 min still predicted');
    expect(m.body, 'Estimate from 8:01 AM. Open BusBoard for the latest.');
  });

  test('a newer prediction replaces the schedule', () async {
    final s = scheduler();
    await s.scheduleFor(_alert());
    await s.scheduleFor(_alert(expected: DateTime(2026, 10, 6, 8, 20)));
    expect(notes.scheduled.last.$2, DateTime(2026, 10, 6, 8, 14));
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

  test('just past the alert time: notifies at once with the lead, not the minute of margin', () async {
    now = DateTime(2026, 10, 6, 8, 8);
    await scheduler().scheduleFor(_alert());
    expect(notes.shown.single.title, 'Route 10 is about 5 min away');
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
