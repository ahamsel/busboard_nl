import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/domain/arrival/first_bus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../trip_planner/test_network.dart';

DateTime _at(int h, int m, {int day = 0}) => DateTime(testDay.year, testDay.month, testDay.day + day, h, m);

/// The test network on weekdays only (testDay is a Wednesday: day 2 is Friday, day 5 Monday).
TestNetwork _weekdays() {
  final net = TestNetwork();
  final all = net.repo.calendarsById[TestNetwork.serviceId]!;
  net.repo.calendarsById[TestNetwork.serviceId] = ServiceCalendar(
    serviceId: all.serviceId,
    monday: true,
    tuesday: true,
    wednesday: true,
    thursday: true,
    friday: true,
    saturday: false,
    sunday: false,
    startDate: all.startDate,
    endDate: all.endDate,
  );
  return net;
}

void _noServiceOn(TestNetwork net, DateTime day) => net.repo.calendarDates.add(
      CalendarDate(serviceId: TestNetwork.serviceId, date: day, exceptionType: ExceptionType.removed),
    );

void main() {
  // TestNetwork: stop A's buses leave 08:00 to 08:50; service runs every day of 2026.
  test('before the morning service: the first bus today', () {
    expect(firstBusAfter(TestNetwork().repo, 'A', _at(5, 0)), _at(8, 0));
  });

  test('after the last bus: the first bus tomorrow', () {
    expect(firstBusAfter(TestNetwork().repo, 'A', _at(13, 0)), _at(8, 0, day: 1));
  });

  test('a gap in the middle of the day is not a first bus', () {
    final net = TestNetwork()..addTrip('A-late', '1', ['A', 'B'], 14 * 3600, 300);
    expect(firstBusAfter(net.repo, 'A', _at(9, 30)), isNull);
  });

  test('a trip past midnight counts on its own service day', () {
    // Route 9 reaches Y at 24:20, its only stop time there: the first (and only) bus of the day at Y.
    expect(firstBusAfter(TestNetwork().repo, 'Y', _at(23, 55)), _at(0, 20, day: 1));
  });

  test("over a weekend: Friday night finds Monday morning's first bus", () {
    expect(firstBusAfter(_weekdays().repo, 'A', _at(22, 0, day: 2)), _at(8, 0, day: 5));
    expect(firstBusAfter(_weekdays().repo, 'A', _at(10, 0, day: 4)), _at(8, 0, day: 5), reason: 'Sunday morning');
  });

  test('a long weekend with a Monday holiday: Tuesday morning', () {
    final net = _weekdays();
    _noServiceOn(net, _at(0, 0, day: 5));
    expect(firstBusAfter(net.repo, 'A', _at(22, 0, day: 2)), _at(8, 0, day: 6));
  });

  test('looks a week ahead, and no further', () {
    final net = TestNetwork();
    for (var d = 1; d <= 7; d++) {
      _noServiceOn(net, _at(0, 0, day: d));
    }
    expect(firstBusAfter(net.repo, 'A', _at(13, 0)), isNull, reason: 'nothing within 7 days');
    net.repo.calendarDates.removeLast();
    expect(firstBusAfter(net.repo, 'A', _at(13, 0)), _at(8, 0, day: 7), reason: 'the seventh day is in range');
  });

  test('a stop with no stop times, or an unknown one, has no first bus', () {
    expect(firstBusAfter(TestNetwork().repo, 'H', _at(5, 0)), isNull);
    expect(firstBusAfter(TestNetwork().repo, 'nowhere', _at(5, 0)), isNull);
  });
}
