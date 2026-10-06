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
    test('a bell from 4 to 60 minutes away', () {
      expect(canAlert(_row(minutes: 2)), isFalse);
      expect(canAlert(_row(minutes: 3)), isFalse);
      expect(leadChoicesFor(3), isEmpty);
      expect(canAlert(_row(minutes: 4)), isTrue);
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
    test('made at a time with microseconds, it is still the same alert after a JSON round trip', () {
      final t = DateTime(2026, 10, 6, 8, 0, 0, 123, 456);
      final a = ArrivalAlert.fromArrival(_row(), stopId: '1150', stopName: 'MUN Centre', leadMinutes: 5, now: t);
      final b = ArrivalAlert.decode(a.encode())!;
      expect(b.isSameAlert(a), isTrue);
      expect(b.lastSeenAt, a.lastSeenAt);
      expect(a.setAt, DateTime(2026, 10, 6, 8, 0, 0, 123));
    });
    test('garbage decodes to null', () {
      expect(ArrivalAlert.decode(null), isNull);
      expect(ArrivalAlert.decode('not json'), isNull);
      expect(ArrivalAlert.decode('{"stopId":1}'), isNull);
    });
  });
}
