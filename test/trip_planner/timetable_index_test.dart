import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:busboard_nl/domain/trip_planner/walking.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_network.dart';

void main() {
  test('one pattern per route stop sequence, trips sorted by first departure', () {
    final idx = TimetableIndex.build(TestNetwork().repo, testDay);
    final p1 = idx.patterns.singleWhere((p) => p.routeId == '1');
    expect(p1.stops.map((s) => idx.stopIds[s]), ['A', 'B', 'C']);
    expect(p1.tripIds.length, 6);
    expect(p1.departures[0][0], 8 * 3600);
    expect(p1.departures[1][0], 8 * 3600 + 600);
    expect(p1.arrivals[0][2], 8 * 3600 + 600);
  });

  test('a trip with a blank or malformed stop time is left out; the rest still plan', () {
    final net = TestNetwork();
    // 1-1 has no arrival time at B; 1-2 has a garbled departure at A.
    void breakRow(String stop, String trip, {String? arrival, String? departure}) {
      final rows = net.repo.stopTimesByStopId[stop]!;
      final i = rows.indexWhere((r) => r.tripId == trip);
      final r = rows[i];
      rows[i] = StopTimeRow(
        tripId: r.tripId,
        arrivalTime: arrival ?? r.arrivalTime,
        departureTime: departure ?? r.departureTime,
        stopId: r.stopId,
        stopSequence: r.stopSequence,
      );
    }

    breakRow('B', '1-1', arrival: '');
    breakRow('A', '1-2', departure: '08:2O:00');
    final idx = TimetableIndex.build(net.repo, testDay);
    final p1 = idx.patterns.singleWhere((p) => p.routeId == '1');
    expect(p1.tripIds, ['1-0', '1-3', '1-4', '1-5']);

    final out = TripPlanner(net.repo, idx).plan(
      PlanQuery(
        from: StopPlace(stopId: 'A', name: 'Stop A'),
        to: StopPlace(stopId: 'C', name: 'Stop C'),
        mode: PlanMode.leaveBy,
        time: DateTime(testDay.year, testDay.month, testDay.day, 8, 5),
      ),
    );
    expect((out as PlanFound).journeys.first.departs, 8 * 3600 + 1800);
  });

  test('stops know which patterns serve them', () {
    final idx = TimetableIndex.build(TestNetwork().repo, testDay);
    final c = idx.stopIndex['C']!;
    expect(idx.patternsAtStop[c].map((e) => idx.patterns[e.$1].routeId).toSet(), {'1', '2'});
  });

  test('walks within 400 m both ways, listed out and in; nothing to a far stop', () {
    final idx = TimetableIndex.build(TestNetwork().repo, testDay);
    final c = idx.stopIndex['C']!, g = idx.stopIndex['G']!, h = idx.stopIndex['H']!;
    expect(idx.footpaths[c].singleWhere((f) => f.other == g).seconds, 360);
    expect(idx.footpaths[g].any((f) => f.other == c), isTrue);
    expect(idx.footpathsInto[g].any((f) => f.other == c), isTrue);
    expect(idx.footpaths[c].any((f) => f.other == h), isFalse);
    expect(idx.sameStopTransferSeconds[c], minTransferSeconds);
  });

  test('transfers.txt: a min time overrides, type 3 removes the link', () {
    final net = TestNetwork();
    net.repo.transfersByFromStop['C'] = [
      const TransferRule(fromStopId: 'C', toStopId: 'C', transferType: 2, minTransferSeconds: 180),
      const TransferRule(fromStopId: 'C', toStopId: 'G', transferType: 3),
    ];
    final idx = TimetableIndex.build(net.repo, testDay);
    final c = idx.stopIndex['C']!, g = idx.stopIndex['G']!;
    expect(idx.sameStopTransferSeconds[c], 180);
    expect(idx.footpaths[c].any((f) => f.other == g), isFalse);
    expect(idx.footpathsInto[g].any((f) => f.other == c), isFalse);
    expect(idx.footpaths[g].any((f) => f.other == c), isTrue); // only that direction is removed
  });

  test("yesterday's late trip is in today's index, shifted back a day", () {
    final idx = TimetableIndex.build(TestNetwork().repo, testDay);
    final firsts = idx.patterns.where((p) => p.routeId == '9').expand((p) => p.departures).map((d) => d.first);
    // Today's own 23:50, and yesterday's 23:50 as −00:10.
    expect(firsts, containsAll([23 * 3600 + 3000, -600]));
  });

  test('a day with no service keeps only the night before', () {
    final net = TestNetwork();
    net.repo.calendarDates.add(
      CalendarDate(serviceId: TestNetwork.serviceId, date: testDay, exceptionType: ExceptionType.removed),
    );
    final idx = TimetableIndex.build(net.repo, testDay);
    expect(idx.patterns.expand((p) => p.tripIds), ['9-0']);
  });

  test('a trip that overtakes another gets its own pattern', () {
    final net = TestNetwork();
    // Leaves A at 08:01 and reaches B at 08:03, before the 08:00 does (08:05).
    net.addTrip('1-x', '1', ['A', 'B', 'C'], 8 * 3600 + 60, 120);
    final idx = TimetableIndex.build(net.repo, testDay);
    final route1 = idx.patterns.where((p) => p.routeId == '1').toList();
    expect(route1.length, 2);
    for (final p in route1) {
      for (var t = 1; t < p.tripIds.length; t++) {
        for (var pos = 0; pos < p.stops.length; pos++) {
          expect(p.arrivals[t][pos], greaterThanOrEqualTo(p.arrivals[t - 1][pos]));
          expect(p.departures[t][pos], greaterThanOrEqualTo(p.departures[t - 1][pos]));
        }
      }
    }
  });

  test('stops at the same spot are still a full minute apart on foot, both ways', () {
    final net = TestNetwork();
    net.repo.stopsById['A2'] = StopInfo(stopId: 'A2', stopName: 'Stop A2', stopLat: 47.5600, stopLon: -52.7500);
    final idx = TimetableIndex.build(net.repo, testDay);
    final a = idx.stopIndex['A']!, a2 = idx.stopIndex['A2']!;
    expect(idx.footpaths[a].singleWhere((f) => f.other == a2).seconds, minTransferSeconds);
    expect(idx.footpaths[a2].singleWhere((f) => f.other == a).seconds, minTransferSeconds);
    expect(idx.footpathsInto[a].singleWhere((f) => f.other == a2).seconds, minTransferSeconds);
    expect(idx.footpathsInto[a2].singleWhere((f) => f.other == a).seconds, minTransferSeconds);
  });
}
