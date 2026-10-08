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

  List<Journey> plan(String from, String to, int by) =>
      raptorReverse(idx, access: [StopOffset(s(from), 0)], egress: [StopOffset(s(to), 0)], arriveBy: by);

  test('arrive by: the latest direct trip that makes it', () {
    // By 08:25 at C: the 08:10 from A arrives 08:20; the 08:20 arrives 08:30, too late.
    final ride = plan('A', 'C', 8 * 3600 + 1500).single.legs.single as RideLeg;
    expect(ride.departs, 8 * 3600 + 600);
    expect(ride.arrives, 8 * 3600 + 1200);
  });

  test('arrive by with a transfer keeps the 1-minute rule', () {
    // By 08:45 at E: 2-2 leaves C 08:35, reaches E 08:43. Its feeder must reach C by 08:34: 1-2 (A 08:20, C 08:30).
    final j = plan('A', 'E', 8 * 3600 + 2700).first;
    final rides = j.legs.whereType<RideLeg>().toList();
    expect(rides.map((r) => r.routeId), ['1', '2']);
    expect(rides[0].departs, 8 * 3600 + 1200);
    expect(rides[1].departs, 8 * 3600 + 2100);
    expect(j.arrives, 8 * 3600 + 2580);
  });

  test('legs are in travel order, with the walks where they happen', () {
    final j = raptorReverse(idx,
        access: [StopOffset(s('A'), 240)], egress: [StopOffset(s('C'), 120)], arriveBy: 8 * 3600 + 1500).single;
    expect(j.legs.map((l) => l.runtimeType), [WalkLeg, RideLeg, WalkLeg]);
    expect(j.departs, 8 * 3600 + 600 - 240);
    expect(j.arrives, 8 * 3600 + 1200 + 120);
  });

  test('a walk to a stop destination after the bus', () {
    // By 08:30 at G: ride to C by 08:24 (the 08:10, C 08:20), walk 6 min.
    final j = plan('A', 'G', 8 * 3600 + 1800).single;
    expect(j.legs.last, isA<WalkLeg>());
    expect(j.arrives, 8 * 3600 + 1560);
  });

  test('nothing arrives that early', () {
    expect(plan('A', 'C', 8 * 3600 + 300), isEmpty);
  });

  test('the same stop at both ends gives no journey', () {
    expect(plan('C', 'C', 9 * 3600), isEmpty);
  });

  test('an origin near the destination is still left by a walk, then the bus', () {
    // P and Q are 100 m apart; the only bus runs N, out to M and back to P. N is 200 m from Q.
    final net = TestNetwork();
    void stop(String id, double lat, double lon) =>
        net.repo.stopsById[id] = StopInfo(stopId: id, stopName: 'Stop $id', stopLat: lat, stopLon: lon);
    stop('P', 47.5300, -52.7000);
    stop('Q', 47.5300, -52.6987);
    stop('M', 47.5390, -52.7000);
    stop('N', 47.5318, -52.6987);
    net.repo.routesById['7'] = RouteInfo(routeId: '7', routeShortName: '7', routeLongName: 'Route 7');
    net.addTrip('7-0', '7', ['N', 'M', 'P'], 8 * 3600, 120);
    idx = TimetableIndex.build(net.repo, testDay);

    final j = plan('Q', 'P', 8 * 3600 + 1800).single;
    final walk = j.legs.first as WalkLeg;
    expect((walk.fromStopId, walk.toStopId), ('Q', 'N'));
    final ride = j.legs.whereType<RideLeg>().single;
    expect((ride.boardStopId, ride.alightStopId), ('N', 'P'));
    expect(ride.departs, 8 * 3600);
    expect(walk.startSeconds, 8 * 3600 - walk.seconds);
    expect(j.departs, 8 * 3600 - walk.seconds);
  });
}
