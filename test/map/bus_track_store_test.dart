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
    // On the outbound pass (about 980 m), not the return pass (about 1055 m+).
    expect(t.fixes.last.progress, closeTo(980, 40));
  });

  for (final unknownTrip in ['', 'unknown-trip']) {
    test('a fix with ${unknownTrip.isEmpty ? 'a missing' : 'an unknown'} trip ID continues on the same pass', () {
      for (var i = 0; i < 3; i++) {
        poll(i, [fix(meters: 300.0 + i * 80, seconds: 43200 + i * 10)]);
      }
      poll(3, [fix(meters: 540, seconds: 43230, tripId: unknownTrip)]);
      final t = store.tracks['2573']!;
      expect(t.fixes, hasLength(4));
      expect(t.latest.progress, closeTo(540, 40));
      expect(t.latest.tripId, outAndBackTripId);
      expect(t.latest.shapeId, outAndBackShapeId);
    });
  }

  test('a frozen GPS timestamp goes stale, is dropped, and is never re-created', () {
    for (var i = 0; i <= 72; i++) {
      final now = start.add(Duration(seconds: i * 10));
      poll(i, [fix(meters: 100, seconds: 43200)]);
      final t = store.tracks['2573'];
      if (now.difference(start) > BusTrackStore.dropAfter) {
        expect(t, isNull, reason: 'at ${i * 10} s');
      } else {
        expect(t, isNotNull, reason: 'at ${i * 10} s');
        expect(store.isStale(t!, now), now.difference(start) > BusTrackStore.staleAfter, reason: 'at ${i * 10} s');
        expect(t.fixes, hasLength(1));
      }
    }
  });

  test('a first fix with a GPS time hours old creates no track', () {
    store.ingest([fix(meters: 100, seconds: 43200 - 3 * 3600)], start);
    expect(store.tracks, isEmpty);
  });

  test('a GPS time 10 minutes in the future is ignored', () {
    store.ingest([fix(meters: 100, seconds: 43200 + 600)], start);
    expect(store.tracks, isEmpty);
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

  group('a bus running its shape backward (a stale trip after a late feed switch)', () {
    // Westward along the outbound leg, 100 m a fix: every fix falls 100 m.
    void reverse(List<double> meters, {int from = 0, String tripId = outAndBackTripId}) {
      for (var i = 0; i < meters.length; i++) {
        poll(from + i, [fix(meters: meters[i], seconds: 43200 + (from + i) * 10, lat: nearOutboundCurb, speed: 0, tripId: tripId)]);
      }
    }

    // To the nearest 10 m (the snap sits a metre or so from the GPS).
    int? tens(double? m) => m == null ? null : (m / 10).round() * 10;

    test('three fixes in a row each more than 30 m behind the last: all but the first lose their progress', () {
      reverse([900, 800]);
      expect(tens(store.tracks['2573']!.fixes.last.progress), 800);
      reverse([700, 600, 500], from: 2);
      final f = store.tracks['2573']!.fixes;
      // 800 is withheld once 700 confirms the run.
      expect([for (final x in f) tens(x.progress)], [900, null, null, null, null]);
      // The snap is kept, so the next fix's window still follows the bus.
      expect([for (final x in f) tens(x.snapProgress)], [900, 800, 700, 600, 500]);
      // Withheld fixes are drawn on raw GPS: no snapped place either.
      for (final x in f.skip(1)) {
        expect(x.snappedLat, isNull);
        expect(x.offRoute, isFalse);
        expect(x.shapeId, outAndBackShapeId);
      }
      // The withheld copy of 800 is still that fix.
      expect(f[1].gpsTime, start.add(const Duration(seconds: 10)));
      expect(f[1].lon, lonAt(800));
    });

    test('progress stays withheld while the bus waits, and returns when it advances again', () {
      reverse([900, 800, 700, 690, 710, 800]);
      final f = store.tracks['2573']!.fixes;
      // 690 falls 10 m (jitter), 710 creeps 20 m: neither is a clear
      // advance. 800 advances 90 m: back on the shape.
      expect([for (final x in f) tens(x.progress)], [900, null, null, null, null, 800]);
    });

    test('one step back is not enough', () {
      reverse([900, 800, 860, 780, 840]);
      expect([for (final x in store.tracks['2573']!.fixes) tens(x.progress)], [900, 800, 860, 780, 840]);
    });

    test('small falls (30 m or less) do not count', () {
      reverse([900, 880, 860, 840, 820]);
      expect(store.tracks['2573']!.fixes.every((x) => x.progress != null), isTrue);
    });

    test('a trip change ends the run', () {
      final repo = outAndBackRepo();
      repo.tripsById['next-trip'] = repo.tripsById[outAndBackTripId]!.copyForTest(tripId: 'next-trip');
      store = BusTrackStore(RouteGeometry(repo));
      reverse([900, 800, 700]);
      reverse([600], from: 3, tripId: 'next-trip');
      final f = store.tracks['2573']!.fixes;
      expect([for (final x in f.take(3)) tens(x.progress)], [900, null, null]);
      expect(f[3].tripId, 'next-trip');
      expect(f[3].progress, isNotNull);
    });
  });

  test('schedDiffMins follows the reported delay and is null when none was reported', () {
    poll(0, [fix(meters: 100, seconds: 43200, deviation: '2 MINS BEHIND', schedDifferenceMins: -2)]);
    expect(store.tracks['2573']!.latest.schedDiffMins, -2);
    poll(1, [fix(meters: 180, seconds: 43210, deviation: '', schedDifferenceMins: 0)]);
    expect(store.tracks['2573']!.latest.schedDiffMins, isNull);
  });
}
