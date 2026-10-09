import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/ranking.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_network.dart';

void main() {
  late TripPlanner planner;
  setUp(() {
    final net = TestNetwork();
    planner = TripPlanner(net.repo, TimetableIndex.build(net.repo, testDay));
  });
  StopPlace stop(String id) => StopPlace(stopId: id, name: 'Stop $id');
  DateTime at(int h, int m) => DateTime(testDay.year, testDay.month, testDay.day, h, m);
  PlanOutcome plan(Place from, Place to, PlanMode mode, DateTime time) =>
      planner.plan(PlanQuery(from: from, to: to, mode: mode, time: time));

  test('leave by: several options, in departure order, the first the next bus', () {
    final js = (plan(stop('A'), stop('C'), PlanMode.leaveBy, at(8, 1)) as PlanFound).journeys;
    expect(js.length, inInclusiveRange(3, 5));
    expect(js.first.departs, 8 * 3600 + 600);
    expect(js.map((j) => j.departs).toList(), [...js.map((j) => j.departs)]..sort());
  });

  test('arrive by: every option arrives in time', () {
    final js = (plan(stop('A'), stop('E'), PlanMode.arriveBy, at(8, 45)) as PlanFound).journeys;
    expect(js, isNotEmpty);
    expect(js.every((j) => j.arrives <= 8 * 3600 + 2700), isTrue);
  });

  test('a pin walks to every stop within 800 m', () {
    final ids = planner
        .offsetsFor(PinPlace(lat: 47.5702, lon: -52.7480, label: 'Pin'))
        .map((o) => planner.index.stopIds[o.stop])
        .toSet();
    expect(ids, containsAll(['C', 'G']));
    expect(ids, isNot(contains('H')));
  });

  test('a pin far from every stop is too far, and says which end', () {
    final far = PinPlace(lat: 48.5, lon: -53.5, label: 'Far');
    expect((plan(far, stop('C'), PlanMode.leaveNow, at(8, 0)) as PlanTooFar).fromEnd, isTrue);
    expect((plan(stop('A'), far, PlanMode.leaveNow, at(8, 0)) as PlanTooFar).fromEnd, isFalse);
  });

  test('the same stop at both ends gives no journey', () {
    expect(plan(stop('A'), stop('A'), PlanMode.leaveNow, at(8, 0)), isA<PlanNoJourney>());
  });

  test('nothing left today on leave by: no journey (tomorrow is the provider’s job)', () {
    final out = plan(stop('A'), stop('C'), PlanMode.leaveBy, at(22, 0)) as PlanNoJourney;
    expect(out.nextDeparture, isNull);
  });

  test('arrive by too early: no journey, with the earliest arrival that day', () {
    final out = plan(stop('A'), stop('C'), PlanMode.arriveBy, at(8, 5)) as PlanNoJourney;
    expect(out.firstArrival, at(8, 10));
  });

  group('arrive by against now', () {
    test('a deadline near now: no journey that has already left', () {
      final out = planner.plan(
        PlanQuery(from: stop('A'), to: stop('C'), mode: PlanMode.arriveBy, time: at(8, 40)),
        now: at(8, 30),
      );
      final js = (out as PlanFound).journeys;
      expect(js.map((j) => j.departs), [8 * 3600 + 1800]);
    });

    test('a walk to the first stop counts: a pin start whose walk began before now is dropped', () {
      // About 55 m south of A: a short walk, so the 8:30 bus means leaving just before 8:30.
      final pin = PinPlace(lat: 47.5595, lon: -52.7500, label: 'Pin');
      final out = planner.plan(
        PlanQuery(from: pin, to: stop('C'), mode: PlanMode.arriveBy, time: at(8, 40)),
        now: at(8, 30),
      );
      expect(out, isA<PlanNoJourney>());
      expect((out as PlanNoJourney).firstArrival, at(8, 50));
    });

    test('nothing makes the deadline any more: no journey, with the earliest arrival from now', () {
      final out = planner.plan(
        PlanQuery(from: stop('A'), to: stop('C'), mode: PlanMode.arriveBy, time: at(8, 25)),
        now: at(8, 30),
      );
      expect(out, isA<PlanNoJourney>());
      final first = (out as PlanNoJourney).firstArrival!;
      expect(first.isBefore(at(8, 30)), isFalse);
      expect(first, at(8, 40));
    });

    test("asked before midnight for the next day: last night's late bus that has left is not offered", () {
      // 9-0 leaves X at 23:50 and reaches Z at 00:50. Asked at 23:55, it has gone.
      final tomorrow = DateTime(testDay.year, testDay.month, testDay.day + 1);
      final net = TestNetwork();
      final next = TripPlanner(net.repo, TimetableIndex.build(net.repo, tomorrow));
      final out = next.plan(
        PlanQuery(
          from: stop('X'),
          to: stop('Z'),
          mode: PlanMode.arriveBy,
          time: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 1, 0),
        ),
        now: at(23, 55),
      );
      expect(out, isA<PlanNoJourney>());
    });

    test("a later day's arrive by is not cut by today's now", () {
      final tomorrow = DateTime(testDay.year, testDay.month, testDay.day + 1);
      final net = TestNetwork();
      final next = TripPlanner(net.repo, TimetableIndex.build(net.repo, tomorrow));
      final out = next.plan(
        PlanQuery(
          from: stop('A'),
          to: stop('C'),
          mode: PlanMode.arriveBy,
          time: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8, 40),
        ),
        now: at(8, 30),
      );
      final js = (out as PlanFound).journeys;
      expect(js.first.departs, lessThan(8 * 3600 + 1800));
      expect(js.last.departs, 8 * 3600 + 1800);
    });
  });

  group('arrive by: the fastest way for each departure', () {
    // Route L leaves O at 8:00 and loops past the pin: P1 8:05 (2-minute walk, there 8:07), then P2 8:10 (14 min,
    // 8:24), P3 8:15 (12 min, 8:27), P4 8:20 (8 min, 8:28), P5 8:25 (4 min, 8:29). Rebuilding the latest departure
    // gets off at the last stop that still makes the deadline, and each fill pass only moves one stop back.
    const pinLat = 47.6000, pinLon = -52.6000;
    const mPerLat = 111195.0, mPerLon = 74970.0;
    late TripPlanner p;
    setUp(() {
      final net = TestNetwork();
      void stopAt(String id, double north, double east) => net.repo.stopsById[id] = StopInfo(
            stopId: id,
            stopName: 'Stop $id',
            stopLat: pinLat + north / mPerLat,
            stopLon: pinLon + east / mPerLon,
          );
      stopAt('O', 0, 2300);
      stopAt('P1', 100, 0);
      stopAt('P2', -780, 0);
      stopAt('P3', 0, 660);
      stopAt('P4', 0, -440);
      stopAt('P5', -200, 0);
      net.repo.routesById['L'] = RouteInfo(routeId: 'L', routeShortName: 'L', routeLongName: 'Route L');
      net.addTrip('L-0', 'L', ['O', 'P1', 'P2', 'P3', 'P4', 'P5'], 8 * 3600, 300);
      p = TripPlanner(net.repo, TimetableIndex.build(net.repo, testDay));
    });

    test('the 8:00 option is the one that gets there at 8:07', () {
      final pin = PinPlace(lat: pinLat, lon: pinLon, label: 'Pin');
      final walks = {for (final o in p.offsetsFor(pin)) p.index.stopIds[o.stop]: o.seconds ~/ 60};
      expect(walks, {'P1': 2, 'P2': 14, 'P3': 12, 'P4': 8, 'P5': 4});
      final out = p.plan(PlanQuery(from: stop('O'), to: pin, mode: PlanMode.arriveBy, time: at(8, 30)), now: at(7, 50));
      final at800 = (out as PlanFound).journeys.where((j) => j.departs == 8 * 3600).toList();
      expect(at800, hasLength(1));
      expect(at800.single.arrives, 8 * 3600 + 420);
      expect(at800.single.legs.whereType<RideLeg>().single.alightStopId, 'P1');
    });
  });

  test("just after midnight, last night's late bus is found", () {
    final j = (plan(stop('Y'), stop('Z'), PlanMode.leaveBy, at(0, 10)) as PlanFound).journeys.first;
    expect(j.at(j.departs), at(0, 20));
  });

  test('ranking: an option that leaves earlier for the same arrival is dropped', () {
    Journey j(int dep, int arr, String trip) => Journey(
      serviceDate: testDay,
      legs: [
        RideLeg(
          routeId: '1',
          tripId: trip,
          boardStopId: 'A',
          alightStopId: 'C',
          departs: dep,
          arrives: arr,
          stopCount: 2,
        ),
      ],
    );
    expect(rankJourneys([j(100, 1000, 'x'), j(400, 1000, 'y')]).map((r) => r.departs), [400]);
    expect(rankJourneys([j(400, 1000, 'y'), j(100, 1000, 'x')]).map((r) => r.departs), [400]);
  });

  test('ranking: of two equal options, the one not changed for live times stays', () {
    Journey j(int dep, int arr, {required bool replanned}) => Journey(
      serviceDate: testDay,
      replannedForLiveTimes: replanned,
      legs: [
        RideLeg(
          routeId: '1',
          tripId: 'x',
          boardStopId: 'A',
          alightStopId: 'C',
          departs: dep,
          arrives: arr,
          stopCount: 2,
        ),
      ],
    );
    // The same journey both ways round, and a near-duplicate (same trip, a minute apart).
    for (final other in [j(400, 1000, replanned: false), j(460, 1000, replanned: false)]) {
      for (final list in [
        [j(400, 1000, replanned: true), other],
        [other, j(400, 1000, replanned: true)],
      ]) {
        final ranked = rankJourneys(list);
        expect(ranked.map((r) => r.replannedForLiveTimes), [false], reason: '${list.map((r) => r.departs)}');
      }
    }
  });

  test('ranking: no duplicates, and the same list twice ranks the same', () {
    final js = (plan(stop('A'), stop('E'), PlanMode.leaveBy, at(8, 0)) as PlanFound).journeys;
    final keys = js.map((j) => j.legs.whereType<RideLeg>().map((r) => r.tripId).join(',')).toSet();
    expect(keys.length, js.length);
    expect(rankJourneys([...js, ...js]).length, js.length);
  });

  group('ranking: trimming to max', () {
    // Seven one-ride, no-walk options, 600 s each, none covering another.
    final seven = [
      for (var i = 1; i <= 7; i++)
        Journey(
          serviceDate: testDay,
          legs: [
            RideLeg(
              routeId: '1',
              tripId: 't$i',
              boardStopId: 'A',
              alightStopId: 'C',
              departs: i * 100,
              arrives: i * 100 + 600,
              stopCount: 2,
            ),
          ],
        ),
    ];

    test('arrive by keeps the latest departures, in departure order', () {
      expect(rankJourneys(seven, arriveBy: true).map((r) => r.departs), [300, 400, 500, 600, 700]);
      expect(rankJourneys(seven.reversed.toList(), arriveBy: true).map((r) => r.departs), [300, 400, 500, 600, 700]);
    });

    test('leave by keeps the earliest departures, in departure order', () {
      expect(rankJourneys(seven).map((r) => r.departs), [100, 200, 300, 400, 500]);
    });
  });

  test('places round-trip through JSON; malformed entries give null', () {
    final s = stop('A');
    final p = PinPlace(lat: 47.5, lon: -52.7, label: 'Pin');
    expect(Place.fromJson(s.toJson()), s);
    expect(Place.fromJson(p.toJson()), p);
    expect(Place.fromJson(null), isNull);
    expect(Place.fromJson({'kind': 'stop', 'stopId': 1, 'name': 'x'}), isNull);
    expect(Place.fromJson({'kind': 'pin', 'lat': 'a', 'lon': 1, 'label': 'x'}), isNull);
    expect(Place.fromJson({'kind': 'other'}), isNull);
  });
}
