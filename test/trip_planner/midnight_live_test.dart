import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/domain/arrival/arrival_service.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/live_overlay.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:busboard_nl/ui/home/journey_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_overlay_test.dart' show feedWith;
import 'test_network.dart';

/// Last night's late bus, seen just after midnight: trip 9-1 runs on [testDay]'s service, X 23:45 → Y 24:15 →
/// Z 24:45, so it reaches Y at 00:15 the next morning. The clock reads 00:05, and the bus is a minute early.
void main() {
  late TestNetwork net;
  final today = DateTime(testDay.year, testDay.month, testDay.day + 1);
  final now = DateTime(today.year, today.month, today.day, 0, 5);
  final stopY = StopPlace(stopId: 'Y', name: 'Stop Y');
  final stopZ = StopPlace(stopId: 'Z', name: 'Stop Z');
  setUp(() {
    net = TestNetwork()..addTrip('9-1', '9', ['X', 'Y', 'Z'], 23 * 3600 + 45 * 60, 1800);
  });

  /// Bus 2445 on 9-1, a minute early, with a time at each stop (counted from [testDay], as the trip runs).
  TimeTrackFetchResult feed() => feedWith(net, {'9-1': -60}, now);

  group('the Board', () {
    test("lists last night's 00:15 bus at 00:05, 10 minutes out, live", () {
      final rows = ArrivalService(net.repo).getUpcomingArrivals(stopId: 'Y', now: now, liveVehicles: feed().vehicles);
      final row = rows.singleWhere((r) => r.tripId == '9-1');
      expect(row.scheduledTime.totalSeconds, 15 * 60, reason: "counted from today's midnight, as now is");
      expect(row.minutesAway, 9, reason: 'a minute early');
      expect(row.isLive, isTrue);
      expect(row.vehicleNumber, 'bus-9-1');
      expect(canAlert(row), isTrue, reason: 'the bell');
      final alert = ArrivalAlert.fromArrival(row, stopId: 'Y', stopName: 'Stop Y', leadMinutes: 3, now: now);
      expect(alert.scheduledAt, DateTime(today.year, today.month, today.day, 0, 15));
    });

    test("before midnight, tonight's 24:15 bus is 20 minutes out", () {
      final before = DateTime(testDay.year, testDay.month, testDay.day, 23, 55);
      final rows = ArrivalService(net.repo).getUpcomingArrivals(stopId: 'Y', now: before);
      final row = rows.singleWhere((r) => r.tripId == '9-1');
      expect(row.minutesAway, 20);
      final alert = ArrivalAlert.fromArrival(row, stopId: 'Y', stopName: 'Stop Y', leadMinutes: 3, now: before);
      expect(alert.scheduledAt, DateTime(today.year, today.month, today.day, 0, 15));
    });

    test("a late bus counts on the service day it runs on, not on the day before's", () {
      // 'tonight-only' runs on tonight's service alone; 'last-night-only' ran on last night's alone.
      net.repo.calendarDates.addAll([
        CalendarDate(serviceId: 'tonight', date: testDay, exceptionType: ExceptionType.added),
        CalendarDate(serviceId: 'last-night', date: DateTime(testDay.year, testDay.month, testDay.day - 1), exceptionType: ExceptionType.added),
      ]);
      for (final (trip, service) in [('tonight-only', 'tonight'), ('last-night-only', 'last-night')]) {
        net.addTrip(trip, '9', ['X', 'Y', 'Z'], 23 * 3600 + 45 * 60, 1800);
        final t = net.repo.tripsById[trip]!;
        net.repo.tripsById[trip] = TripInfo(
          tripId: trip,
          routeId: t.routeId,
          serviceId: service,
          tripHeadsign: t.tripHeadsign,
          directionId: t.directionId,
        );
      }
      final before = DateTime(testDay.year, testDay.month, testDay.day, 23, 55);
      final trips = ArrivalService(net.repo).getUpcomingArrivals(stopId: 'Y', now: before).map((r) => r.tripId);
      expect(trips, contains('tonight-only'));
      expect(trips, isNot(contains('last-night-only')), reason: 'it ran 24 hours ago');
    });
  });

  group('the planner', () {
    test("a plan made at 00:05 rides last night's bus on live times", () {
      final planner = TripPlanner(net.repo, TimetableIndex.build(net.repo, today));
      final q = PlanQuery(from: stopY, to: stopZ, mode: PlanMode.leaveNow, time: now);
      final js = planner.applyLive(q, (planner.plan(q) as PlanFound).journeys, feed(), now);
      final j = js.firstWhere((j) => j.legs.whereType<RideLeg>().single.tripId == '9-1');
      final ride = j.legs.whereType<RideLeg>().single;
      expect(ride.live, isTrue);
      expect(j.at(ride.departs), DateTime(today.year, today.month, today.day, 0, 14));
      final row = boardArrivalFor(j, ride, net.repo, feed(), now);
      expect(row, isNotNull, reason: 'Follow and the bell');
      expect(row!.isLive, isTrue);
      expect(row.vehicleNumber, 'bus-9-1');
      expect(canAlert(row), isTrue);
    });

    test('a plan made at 23:55 keeps its live times, Follow and the bell at 00:05', () {
      final planner = TripPlanner(net.repo, TimetableIndex.build(net.repo, testDay));
      final before = DateTime(testDay.year, testDay.month, testDay.day, 23, 55);
      final q = PlanQuery(from: stopY, to: stopZ, mode: PlanMode.leaveNow, time: before);
      final j = (planner.plan(q) as PlanFound).journeys.firstWhere(
            (j) => j.legs.whereType<RideLeg>().single.tripId == '9-1',
          );
      expect(j.serviceDate, testDay);
      final ride = j.legs.whereType<RideLeg>().single;
      expect(overlayLive(j, feed(), now).legs.whereType<RideLeg>().single.live, isTrue);
      final row = boardArrivalFor(j, ride, net.repo, feed(), now);
      expect(row, isNotNull, reason: 'Follow and the bell');
      expect(row!.isLive, isTrue);
      expect(row.vehicleNumber, 'bus-9-1');
      expect(canAlert(row), isTrue);
    });

    test('a journey whose ride has gone gets no Board row', () {
      final gone = Journey(serviceDate: testDay, legs: [
        RideLeg(
          routeId: '9',
          tripId: '9-0',
          boardStopId: 'X',
          alightStopId: 'Y',
          departs: 23 * 3600 + 50 * 60,
          arrives: 24 * 3600 + 20 * 60,
          stopCount: 1,
        ),
      ]);
      expect(boardArrivalFor(gone, gone.legs.single as RideLeg, net.repo, feed(), now), isNull);
    });

    test("yesterday's 8:00 ride is not today's 8:00 run of the same trip", () {
      final yesterdays = Journey(serviceDate: testDay, legs: [
        RideLeg(
          routeId: '1',
          tripId: '1-0',
          boardStopId: 'A',
          alightStopId: 'C',
          departs: 8 * 3600,
          arrives: 8 * 3600 + 600,
          stopCount: 2,
        ),
      ]);
      final at750 = DateTime(today.year, today.month, today.day, 7, 50);
      expect(
        ArrivalService(net.repo).getUpcomingArrivals(stopId: 'A', now: at750).map((r) => r.tripId),
        contains('1-0'),
        reason: "the Board lists today's run",
      );
      expect(boardArrivalFor(yesterdays, yesterdays.legs.single as RideLeg, net.repo, null, at750), isNull);
    });
  });
}
