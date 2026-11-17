import 'package:busboard_nl/data/realtime/timetrack_models.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/arrival/arrival_service.dart';
import 'package:busboard_nl/domain/arrival_alerts/gtfs_rt_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/feed_fixtures.dart';
import 'trip_planner/test_network.dart';

/// Metrobus's tracking froze on 2026-11-14: for three days the feed kept answering with every bus's last fix, all of
/// them days old, on trip ids that run again every day.
void main() {
  final now = DateTime(testDay.year, testDay.month, testDay.day, 12);

  group('a fix counts as live', () {
    test('when it is under 5 minutes old, by its full timestamp', () {
      expect(isLiveFix(fakeVehicle(fix: now.subtract(const Duration(minutes: 1))), now), isTrue);
      expect(isLiveFix(fakeVehicle(fix: now.subtract(const Duration(days: 3))), now), isFalse);
    });

    // The TimeTrack fallback gives a clock time only ('6:37 AM') and its seconds of the day.
    TimeTrackVehicle clock(String time, int seconds) => TimeTrackVehicle.fromJson({
          'vehicle': '1202',
          'routeNumber': 1,
          'routeRun': 'Rt 1-1',
          'busLat': 47.54,
          'busLon': -52.73,
          'positionTime': time,
          'positionTimeSeconds': seconds,
          'gtfsTripId': '248349',
        });

    test('by its clock time when that is all the feed gives', () {
      expect(isLiveFix(clock('6:37 AM', 6 * 3600 + 37 * 60), now), isFalse, reason: 'frozen since the morning');
      expect(isLiveFix(clock('11:59 AM', 11 * 3600 + 59 * 60), now), isTrue);
    });

    test('when the feed gives no time at all, as before', () {
      expect(isLiveFix(clock('', 0), now), isTrue);
    });
  });

  group('the Board', () {
    late TestNetwork net;
    setUp(() => net = TestNetwork()..addTrip('9-1', '9', ['X', 'Y', 'Z'], 12 * 3600 + 10 * 60, 1800));

    TimeTrackVehicle bus(Duration age) => fakeVehicle(trip: '9-1', id: '1206', diff: -2, fix: now.subtract(age));
    ArrivalRow rowFor(TimeTrackVehicle v) => ArrivalService(net.repo)
        .getUpcomingArrivals(stopId: 'Y', now: now, liveVehicles: [v])
        .singleWhere((r) => r.tripId == '9-1');

    test("does not tie today's trip to a bus whose last fix is days old", () {
      final row = rowFor(bus(const Duration(days: 3)));
      expect(row.isLive, isFalse);
      expect(row.vehicleNumber, isNull);
    });

    test('still uses a bus that reported a minute ago', () {
      final row = rowFor(bus(const Duration(minutes: 1)));
      expect(row.isLive, isTrue);
      expect(row.vehicleNumber, '1206');
    });
  });
}
