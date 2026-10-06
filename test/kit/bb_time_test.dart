import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BBTime.clock (seconds since midnight)', () {
    test('24-hour: zero-padded HH:mm, optional seconds', () {
      expect(BBTime.clock(9 * 3600 + 52 * 60, use24h: true), '09:52');
      expect(BBTime.clock(16 * 3600 + 11 * 60 + 12, use24h: true, seconds: true), '16:11:12');
      expect(BBTime.clock(0, use24h: true), '00:00');
    });

    test('12-hour: h:mm AM/PM, optional seconds', () {
      expect(BBTime.clock(9 * 3600 + 52 * 60, use24h: false), '9:52 AM');
      expect(BBTime.clock(16 * 3600 + 14 * 60 + 21, use24h: false, seconds: true), '4:14:21 PM');
      expect(BBTime.clock(0, use24h: false), '12:00 AM');
      expect(BBTime.clock(12 * 3600 + 44 * 60, use24h: false), '12:44 PM');
    });

    test('GTFS after-midnight seconds wrap to the clock', () {
      expect(BBTime.clock(25 * 3600 + 10 * 60, use24h: true), '01:10');
      expect(BBTime.clock(25 * 3600 + 10 * 60, use24h: false), '1:10 AM');
      expect(BBTime.clock(-60, use24h: true), '23:59');
    });
  });

  test('BBTime.of formats a DateTime', () {
    final t = DateTime(2026, 10, 4, 16, 11, 12);
    expect(BBTime.of(t, use24h: true), '16:11');
    expect(BBTime.of(t, use24h: false, seconds: true), '4:11:12 PM');
  });

  test('BBTime.dated prefixes the date, optionally with the year', () {
    final t = DateTime(2026, 11, 1, 12, 44);
    expect(BBTime.dated(t, use24h: false), 'Nov 1, 12:44 PM');
    expect(BBTime.dated(t, use24h: true), 'Nov 1, 12:44');
    expect(BBTime.dated(t, use24h: true, year: true), 'Nov 1, 2026 12:44');
    expect(BBTime.dated(t, use24h: false, year: true), 'Nov 1, 2026 12:44 PM');
  });

  testWidgets('BBTime.use24h reads the device setting', (tester) async {
    late bool seen;
    Widget host(bool on) => MediaQuery(
          data: MediaQueryData(alwaysUse24HourFormat: on),
          child: Builder(builder: (context) {
            seen = BBTime.use24h(context);
            return const SizedBox();
          }),
        );
    await tester.pumpWidget(host(true));
    expect(seen, isTrue);
    await tester.pumpWidget(host(false));
    expect(seen, isFalse);
  });
}
