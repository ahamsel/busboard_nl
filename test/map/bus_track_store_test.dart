import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/domain/map/bus_track_store.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/out_and_back.dart';

void main() {
  final start = DateTime(2026, 10, 4, 12, 0);
  final total = cumulativeFor(outAndBackPoints()).last;
  late BusTrackStore store;

  setUp(() => store = BusTrackStore(RouteGeometry(outAndBackRepo())));

  void poll(int i, List<dynamic> vehicles) =>
      store.ingest(vehicles.cast(), start.add(Duration(seconds: i * 10)));

  test('one track per physical vehicle, even on the same route run', () {
    poll(0, [
      fix(meters: 100, seconds: 43200, vehicle: '859', routeRun: 'Rt 10-1'),
      fix(meters: 300, seconds: 43200, vehicle: '861', routeRun: 'Rt 10-1'),
    ]);
    expect(store.tracks.keys, containsAll(['859', '861']));
  });

  test('duplicate interlined assignments keep one physical bus', () {
    final noData = fix(meters: 100, seconds: 43200, vehicle: '859', routeNumber: 6, routeRun: 'Rt 6-1', tripId: '');
    final live = fix(meters: 100, seconds: 43200, vehicle: '859', routeRun: 'Rt 10-1');
    store.ingest([
      noData.copyForTest(status: 'NO DATA', shortStatus: 'A3'),
      live,
    ], start);
    expect(store.tracks, hasLength(1));
    expect(store.tracks['859']!.routeNumber, 10);
    expect(store.duplicateAssignments, 1);
  });

  test('a replacement vehicle never inherits another bus\'s track', () {
    poll(0, [fix(meters: 100, seconds: 43200, vehicle: '859')]);
    poll(1, [fix(meters: 300, seconds: 43210, vehicle: '861')]);
    expect(store.tracks['861']!.fixes, hasLength(1));
    expect(store.tracks['859']!.fixes, hasLength(1));
  });

  test('a flapping routeRun on the same route keeps the track', () {
    for (var i = 0; i < 6; i++) {
      poll(i, [fix(meters: 100.0 + i * 80, seconds: 43200 + i * 10, routeRun: i.isEven ? 'Rt 10-1' : 'Rt 10')]);
    }
    expect(store.tracks['2573']!.fixes, hasLength(6));
  });

  test('a route-number change starts a new track', () {
    poll(0, [fix(meters: 100, seconds: 43200)]);
    poll(1, [fix(meters: 180, seconds: 43210)]);
    poll(2, [fix(meters: 190, seconds: 43220, routeNumber: 6, routeRun: 'Rt 6-1', tripId: '')]);
    final t = store.tracks['2573']!;
    expect(t.routeNumber, 6);
    expect(t.fixes, hasLength(1));
  });

  test('a trip change continues the same track', () {
    final repo = outAndBackRepo();
    repo.tripsById['next-trip'] = repo.tripsById[outAndBackTripId]!.copyForTest(tripId: 'next-trip');
    store = BusTrackStore(RouteGeometry(repo));
    poll(0, [fix(meters: 900, seconds: 43200)]);
    poll(1, [fix(meters: 980, seconds: 43210, tripId: 'next-trip')]);
    final t = store.tracks['2573']!;
    expect(t.fixes, hasLength(2));
    expect(t.fixes.last.tripId, 'next-trip');
  });

  test('duplicate and out-of-order GPS timestamps are ignored', () {
    poll(0, [fix(meters: 100, seconds: 43200)]);
    poll(1, [fix(meters: 100, seconds: 43200)]); // same GPS time
    poll(2, [fix(meters: 50, seconds: 43190)]); // older GPS time
    expect(store.tracks['2573']!.fixes, hasLength(1));
  });

  test('a fix just after midnight follows one just before it', () {
    final late = DateTime(2026, 10, 4, 23, 59, 55);
    store.ingest([fix(meters: 100, seconds: 86395)], late);
    store.ingest([fix(meters: 140, seconds: 5)], late.add(const Duration(seconds: 10)));
    final fixes = store.tracks['2573']!.fixes;
    expect(fixes, hasLength(2));
    expect(fixes[1].gpsTime.difference(fixes[0].gpsTime), const Duration(seconds: 10));
  });

  test('a bus on the outbound leg stays on its pass when GPS sits nearer the return leg', () {
    for (var i = 0; i < 9; i++) {
      poll(i, [fix(meters: 100.0 + i * 80, seconds: 43200 + i * 10, lat: i.isEven ? nearReturnCurb : nearOutboundCurb)]);
      final p = store.tracks['2573']!.latest.progress!;
      expect(p, closeTo(100.0 + i * 80, 40), reason: 'poll $i progress $p');
    }
  });

  test('the first fix uses the next stop, else the timetable, to pick the pass', () {
    poll(0, [fix(meters: 400, seconds: 43250, departureTimeAtClosestStop: 43260)]);
    expect(store.tracks['2573']!.latest.progress, closeTo(400, 40));
    final other = BusTrackStore(RouteGeometry(outAndBackRepo()));
    other.ingest([fix(meters: 400, seconds: 43240, vehicle: '9')], start);
    expect(other.tracks['9']!.latest.progress, closeTo(400, 40));
    expect(other.tracks['9']!.latest.progress, lessThan(total / 2));
  });

  test('a fix far from the route is off route and carries no progress', () {
    poll(0, [fix(meters: 400, seconds: 43200, lat: 47.5700)]); // ~1 km north
    final f = store.tracks['2573']!.latest;
    expect(f.offRoute, isTrue);
    expect(f.progress, isNull);
  });

  test('stale after 90 s without a new fix; dropped after 5 minutes', () {
    poll(0, [fix(meters: 100, seconds: 43200)]);
    final t = store.tracks['2573']!;
    expect(store.isStale(t, start.add(const Duration(seconds: 89))), isFalse);
    expect(store.isStale(t, start.add(const Duration(seconds: 91))), isTrue);
    store.ingest([], start.add(const Duration(minutes: 4)));
    expect(store.tracks, contains('2573'));
    store.ingest([], start.add(const Duration(minutes: 5, seconds: 1)));
    expect(store.tracks, isNot(contains('2573')));
  });

  test('a vehicle without coordinates is skipped', () {
    store.ingest([fix(meters: 100, seconds: 43200).copyForTest(lat: 0, lon: 0)], start);
    expect(store.tracks, isEmpty);
  });

  test('an unknown trip still tracks a bus without a shape', () {
    store = BusTrackStore(RouteGeometry(GtfsRepository()));
    poll(0, [fix(meters: 100, seconds: 43200)]);
    final f = store.tracks['2573']!.latest;
    expect(f.shapeId, isNull);
    expect(f.progress, isNull);
    expect(f.offRoute, isFalse);
  });
}
