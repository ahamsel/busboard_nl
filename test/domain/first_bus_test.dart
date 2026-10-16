import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
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

/// The test network's data in a repository that counts how often it is asked which services run on a day.
class _CountingRepo extends GtfsRepository {
  _CountingRepo(GtfsRepository from) {
    stopsById.addAll(from.stopsById);
    routesById.addAll(from.routesById);
    tripsById.addAll(from.tripsById);
    stopTimesByStopId.addAll(from.stopTimesByStopId);
    calendarsById.addAll(from.calendarsById);
    calendarDates.addAll(from.calendarDates);
  }

  int serviceLookups = 0;

  @override
  Set<String> activeServiceIds(DateTime date) {
    serviceLookups++;
    return super.activeServiceIds(date);
  }
}

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
    net.repo.clearDerivedCaches(); // what a reload of the data does
    expect(firstBusAfter(net.repo, 'A', _at(13, 0)), _at(8, 0, day: 7), reason: 'the seventh day is in range');
  });

  test('a stop with no stop times, or an unknown one, has no first bus', () {
    expect(firstBusAfter(TestNetwork().repo, 'H', _at(5, 0)), isNull);
    expect(firstBusAfter(TestNetwork().repo, 'nowhere', _at(5, 0)), isNull);
  });

  test('rebuilds do not rescan: a stop and service date is worked out once, whatever the minute', () {
    final repo = _CountingRepo(_weekdays().repo);
    final first = firstBusAfter(repo, 'A', _at(22, 0, day: 2));
    expect(first, _at(8, 0, day: 5));
    final lookups = repo.serviceLookups;
    expect(lookups, greaterThan(0));
    // The stop line rebuilds all night (and every minute): the same answer, and no further scan of the stop's times.
    for (var minute = 0; minute < 120; minute++) {
      expect(firstBusAfter(repo, 'A', _at(22, 0, day: 2).add(Duration(minutes: minute))), first);
    }
    expect(repo.serviceLookups, lookups, reason: 'no day was rescanned');
    // Another stop is its own entry.
    firstBusAfter(repo, 'B', _at(22, 0, day: 2));
    expect(repo.serviceLookups, greaterThan(lookups));
  });

  test('a repository that is loaded again forgets what it worked out', () {
    final net = _weekdays();
    expect(firstBusAfter(net.repo, 'A', _at(22, 0, day: 2)), _at(8, 0, day: 5));
    _noServiceOn(net, _at(0, 0, day: 5));
    net.repo.clearDerivedCaches();
    expect(firstBusAfter(net.repo, 'A', _at(22, 0, day: 2)), _at(8, 0, day: 6));
  });

  group('firstBusNote', () {
    final first = _at(6, 28, day: 5); // Monday
    test("the day's first bus, the same day or the next morning, needs no weekday", () {
      expect(firstBusNote(_at(8, 0), _at(5, 0), use24h: true), 'First bus 08:00');
      expect(firstBusNote(_at(6, 30, day: 1), _at(22, 0), use24h: false), 'First bus 6:30 AM');
    });

    test('two or more days away it names the weekday, in full for a screen reader', () {
      expect(firstBusNote(first, _at(22, 0, day: 2), use24h: false), 'First bus Mon 6:28 AM');
      expect(firstBusNote(first, _at(22, 0, day: 2), use24h: false, spoken: true), 'First bus Monday 6:28 AM');
      expect(firstBusNote(first, _at(22, 0, day: 2), use24h: true), 'First bus Mon 06:28');
    });

    test('the day count is by calendar date, not 24-hour spans', () {
      expect(firstBusNote(_at(6, 0, day: 2), _at(23, 59), use24h: true), 'First bus Fri 06:00');
      expect(firstBusNote(_at(6, 0, day: 1), _at(23, 59), use24h: true), 'First bus 06:00');
    });
  });
}
