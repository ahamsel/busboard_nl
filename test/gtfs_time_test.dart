import 'package:flutter_test/flutter_test.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';

void main() {
  group('GtfsTime parsing', () {
    test('parses normal time correctly', () {
      final t = GtfsTime.parse('08:30:00');
      expect(t.hours, 8);
      expect(t.minutes, 30);
      expect(t.seconds, 0);
      expect(t.isNextDay, false);
      expect(t.totalSeconds, 8 * 3600 + 30 * 60);
    });

    test('parses midnight correctly', () {
      final t = GtfsTime.parse('00:00:00');
      expect(t.hours, 0);
      expect(t.minutes, 0);
      expect(t.totalSeconds, 0);
      expect(t.isNextDay, false);
    });

    test('parses time just before midnight', () {
      final t = GtfsTime.parse('23:59:59');
      expect(t.hours, 23);
      expect(t.minutes, 59);
      expect(t.seconds, 59);
      expect(t.isNextDay, false);
    });

    test('parses GTFS >24h time correctly (25:10:00)', () {
      final t = GtfsTime.parse('25:10:00');
      expect(t.hours, 25);
      expect(t.minutes, 10);
      expect(t.seconds, 0);
      expect(t.isNextDay, true);
      expect(t.totalSeconds, 25 * 3600 + 10 * 60);
    });

    test('parses GTFS >24h time correctly (24:00:00)', () {
      final t = GtfsTime.parse('24:00:00');
      expect(t.isNextDay, true);
      expect(t.totalSeconds, 24 * 3600);
    });

    test('parses GTFS >24h time correctly (26:45:30)', () {
      final t = GtfsTime.parse('26:45:30');
      expect(t.hours, 26);
      expect(t.minutes, 45);
      expect(t.seconds, 30);
      expect(t.isNextDay, true);
    });

    test('throws on invalid format', () {
      expect(() => GtfsTime.parse('invalid'), throwsFormatException);
      expect(() => GtfsTime.parse('12:30'), throwsFormatException);
    });
  });

  group('GtfsTime display', () {
    test('displays normalised HH:MM', () {
      expect(GtfsTime.parse('08:30:00').toDisplayString(), '08:30');
      expect(GtfsTime.parse('23:50:00').toDisplayString(), '23:50');
    });

    test('displays normalised HH:MM for >24h times', () {
      // 25:10:00 should display as 01:10 (normalised)
      expect(GtfsTime.parse('25:10:00').toDisplayString(), '01:10');
      // 24:30:00 should display as 00:30
      expect(GtfsTime.parse('24:30:00').toDisplayString(), '00:30');
    });
  });

  group('GtfsTime toDateTime', () {
    test('converts normal time to DateTime on service date', () {
      final t = GtfsTime.parse('14:30:00');
      final serviceDate = DateTime(2026, 2, 14);
      final dt = t.toDateTime(serviceDate);
      expect(dt, DateTime(2026, 2, 14, 14, 30, 0));
    });

    test('converts >24h time to next calendar day', () {
      final t = GtfsTime.parse('25:10:00');
      final serviceDate = DateTime(2026, 2, 14);
      final dt = t.toDateTime(serviceDate);
      // 25:10 on Feb 14 → Feb 15, 01:10
      expect(dt, DateTime(2026, 2, 15, 1, 10, 0));
    });

    test('converts 24:00:00 to next day midnight', () {
      final t = GtfsTime.parse('24:00:00');
      final serviceDate = DateTime(2026, 2, 14);
      final dt = t.toDateTime(serviceDate);
      expect(dt, DateTime(2026, 2, 15, 0, 0, 0));
    });
  });

  group('GtfsTime comparison and sorting', () {
    test('compares correctly', () {
      final a = GtfsTime.parse('08:30:00');
      final b = GtfsTime.parse('09:00:00');
      final c = GtfsTime.parse('25:00:00');

      expect(a < b, true);
      expect(b < c, true);
      expect(a < c, true);
      expect(c > a, true);
    });

    test('sorts correctly including >24h times', () {
      final times = [
        GtfsTime.parse('25:10:00'),
        GtfsTime.parse('08:30:00'),
        GtfsTime.parse('23:50:00'),
        GtfsTime.parse('14:00:00'),
        GtfsTime.parse('24:30:00'),
      ];
      times.sort();

      expect(times[0].toString(), '08:30:00');
      expect(times[1].toString(), '14:00:00');
      expect(times[2].toString(), '23:50:00');
      expect(times[3].toString(), '24:30:00');
      expect(times[4].toString(), '25:10:00');
    });

    test('sorts "23:50 today" vs "now" correctly', () {
      // If now is 22:00, 23:50 should be after
      final now = GtfsTime.parse('22:00:00');
      final later = GtfsTime.parse('23:50:00');
      expect(later.minutesFrom(now), 110); // 1h50m = 110 min
    });

    test('sorts "25:10 next day" vs "now 22:00" correctly', () {
      final now = GtfsTime.parse('22:00:00');
      final nextDay = GtfsTime.parse('25:10:00');
      // 25:10 - 22:00 = 3h10m = 190 min
      expect(nextDay.minutesFrom(now), 190);
    });
  });
}
