import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/raptor.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_network.dart';

void main() {
  late TimetableIndex idx;
  int s(String id) => idx.stopIndex[id]!;
  setUp(() => idx = TimetableIndex.build(TestNetwork().repo, testDay));

  List<Journey> plan(String from, String to, int at) =>
      raptorForward(idx, access: [StopOffset(s(from), 0)], egress: [StopOffset(s(to), 0)], departAt: at);

  test('a direct ride takes the next trip', () {
    final ride = plan('A', 'C', 8 * 3600 + 60).single.legs.single as RideLeg;
    expect(ride.tripId, '1-1'); // the 08:10; the 08:00 has gone
    expect(ride.departs, 8 * 3600 + 600);
    expect(ride.arrives, 8 * 3600 + 1200);
    expect(ride.stopCount, 2);
  });

  test('a same-stop transfer waits at least a minute', () {
    // 1-0: A 08:00 → C 08:10. Route 2 leaves C at 08:05, 08:20, …: the 08:20 is the first one catchable.
    final j = plan('A', 'E', 8 * 3600).first;
    final rides = j.legs.whereType<RideLeg>().toList();
    expect(rides.map((r) => r.routeId), ['1', '2']);
    expect(rides[1].departs, 8 * 3600 + 1200);
    expect(j.arrives, 8 * 3600 + 1200 + 480);
  });

  test("a stop's longer transfer time sends the rider to a later bus", () {
    // 1-2 reaches C at 08:30; 2-2 leaves at 08:35. With a 6-minute rule at C, only 2-3 (08:50) works.
    idx.sameStopTransferSeconds[s('C')] = 360;
    final second = plan('A', 'E', 8 * 3600 + 1200).first.legs.whereType<RideLeg>().last;
    expect(second.departs, 8 * 3600 + 3000);
  });

  test('a walking transfer is used and shown as a walk leg', () {
    // G has no buses: ride to C, walk 300 m (6 min).
    final j = plan('A', 'G', 8 * 3600).single;
    expect(j.legs.first, isA<RideLeg>());
    final walk = j.legs.last as WalkLeg;
    expect((walk.fromStopId, walk.toStopId, walk.seconds), ('C', 'G', 360));
    expect(walk.startSeconds, 8 * 3600 + 600);
    expect(j.arrives, 8 * 3600 + 960);
  });

  test('access and egress walks count; the rider leaves as late as they can', () {
    final j = raptorForward(idx,
        access: [StopOffset(s('A'), 300)], egress: [StopOffset(s('C'), 120)], departAt: 8 * 3600).single;
    // At A by 08:05 earliest: the 08:00 has gone, so the 08:10. Leave at 08:05, walk 5 min.
    expect(j.departs, 8 * 3600 + 300);
    expect((j.legs.first as WalkLeg).seconds, 300);
    expect(j.arrives, 8 * 3600 + 1200 + 120);
  });

  test('a journey with fewer rides that arrives no earlier is not repeated', () {
    final js = plan('F', 'E', 8 * 3600);
    expect(js.length, 1);
    expect(js.single.rides, 1);
  });

  test('no journey when nothing runs', () {
    expect(plan('A', 'C', 23 * 3600), isEmpty);
    expect(plan('A', 'H', 8 * 3600), isEmpty);
  });

  test("just after midnight, last night's late trip is found", () {
    final j = plan('Y', 'Z', 600).single; // 00:10: the 23:50 from X reaches Y at 00:20
    expect(j.departs, 1200);
    expect(j.arrives, 3000);
  });

  test('the same stop as origin and destination gives no journey', () {
    expect(plan('A', 'A', 8 * 3600), isEmpty);
  });

  test('journey helpers: clock times and seconds in the service day', () {
    final j = plan('Y', 'Z', 600).single;
    expect(j.at(j.departs), DateTime(2026, 10, 7, 0, 20));
    expect(secondsInServiceDay(testDay, DateTime(2026, 10, 8, 0, 20)), 86400 + 1200);
    expect(secondsInServiceDay(testDay, DateTime(2026, 10, 7, 8, 5)), 8 * 3600 + 300);
  });

  test('a destination near the origin is still reached by bus, then a walk', () {
    // P and Q are 100 m apart; the only bus leaves P, loops out to M and comes back to N, 200 m from Q.
    final net = TestNetwork();
    void stop(String id, double lat, double lon) =>
        net.repo.stopsById[id] = StopInfo(stopId: id, stopName: 'Stop $id', stopLat: lat, stopLon: lon);
    stop('P', 47.5300, -52.7000);
    stop('Q', 47.5309, -52.7000);
    stop('M', 47.5390, -52.7000);
    stop('N', 47.5309, -52.6973);
    net.repo.routesById['7'] = RouteInfo(routeId: '7', routeShortName: '7', routeLongName: 'Route 7');
    net.addTrip('7-0', '7', ['P', 'M', 'N'], 8 * 3600, 120);
    idx = TimetableIndex.build(net.repo, testDay);

    final j = plan('P', 'Q', 8 * 3600).single;
    expect(j.legs.whereType<RideLeg>().single.alightStopId, 'N');
    final walk = j.legs.last as WalkLeg;
    expect((walk.fromStopId, walk.toStopId), ('N', 'Q'));
    expect(walk.startSeconds, 8 * 3600 + 240);
    expect(j.arrives, 8 * 3600 + 240 + walk.seconds);
  });
}
