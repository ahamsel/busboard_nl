import 'package:busboard_nl/domain/arrival/first_bus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../trip_planner/test_network.dart';

DateTime _at(int h, int m, {int day = 0}) => DateTime(testDay.year, testDay.month, testDay.day + day, h, m);

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

  test('a stop with no stop times, or an unknown one, has no first bus', () {
    expect(firstBusAfter(TestNetwork().repo, 'H', _at(5, 0)), isNull);
    expect(firstBusAfter(TestNetwork().repo, 'nowhere', _at(5, 0)), isNull);
  });
}
