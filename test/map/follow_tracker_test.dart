import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/domain/map/follow_tracker.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:busboard_nl/domain/map/shape_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 5, 12);
DateTime _at(int s) => _t0.add(Duration(seconds: s));

const _stops = [
  TripStop(
    stopId: 'a',
    name: 'A',
    sequence: 1,
    progress: 0,
    departureSeconds: 43200,
  ),
  TripStop(
    stopId: 'b',
    name: 'B',
    sequence: 2,
    progress: 400,
    departureSeconds: 43260,
  ),
  TripStop(
    stopId: 'mun',
    name: 'MUN Centre',
    sequence: 3,
    progress: 800,
    departureSeconds: 43320,
  ),
  TripStop(
    stopId: 'c',
    name: 'C',
    sequence: 4,
    progress: 1200,
    departureSeconds: 43380,
  ),
];

BusTrackingState _bus({
  double progress = 100,
  String trip = 't1',
  BusStatus status = BusStatus.active,
  DateTime? gps,
  String id = '2573',
  String shape = 's',
  String headsign = 'Downtown',
  double lat = 47.56,
  double lon = -52.71,
}) => BusTrackingState(
  routeRun: 'Rt 10',
  vehicleId: id,
  routeNumber: 10,
  headsign: headsign,
  currentTripId: trip,
  shapeId: shape,
  lat: lat,
  lon: lon,
  heading: 90,
  progress: progress,
  speedKmh: 30,
  lastGpsTime: gps ?? _t0,
  status: status,
  lastUpdateTime: gps ?? _t0,
);

/// [stops] are trip t1's; any other trip has [others]' stops, or none.
FollowTracker _tracker([List<TripStop> stops = _stops, Map<String, List<TripStop>> others = const {}]) =>
    FollowTracker(vehicleId: '2573', stopsFor: (trip, _) => trip == 't1' ? stops : (others[trip] ?? const []));

/// A straight old shape 's' where a fix's [BusTrackingState.lon] is metres
/// along it and [BusTrackingState.lat] metres off it.
SnapResult? _fakeSnap(double lat, double lon, String shapeId, {double? expectedAlong, double? minAlong, double? maxAlong}) =>
    shapeId != 's'
        ? null
        : SnapResult(snappedLat: 0, snappedLon: lon, distanceAlongRoute: lon.clamp(0, 1200).toDouble(), perpendicularDistance: lat.abs());

FollowTracker _snapping([List<TripStop> stops = _stops, Map<String, List<TripStop>> others = const {}]) => FollowTracker(
      vehicleId: '2573',
      stopsFor: (trip, _) => trip == 't1' ? stops : (others[trip] ?? const []),
      snap: _fakeSnap,
    );

/// The bus labelled with trip t2 (shape 's2') while its fix is [along] metres
/// along the old shape and [off] metres from it; [progress] is on 's2'.
BusTrackingState _relabelled({required double along, double off = 0, double progress = 5, DateTime? gps}) =>
    _bus(trip: 't2', shape: 's2', progress: progress, lat: off, lon: along, gps: gps);

const _returnTrip = [
  TripStop(stopId: 'x', name: 'X', sequence: 1, progress: 0, departureSeconds: 44000),
  TripStop(stopId: 'mun', name: 'MUN Centre', sequence: 2, progress: 600, departureSeconds: 44100),
  TripStop(stopId: 'y', name: 'Y', sequence: 3, progress: 1000, departureSeconds: 44200),
];

void main() {
  test('counts stops to your stop as the bus advances', () {
    final t = _tracker();
    var s = t.update(
      bus: _bus(progress: 100),
      drawnProgress: 100,
      yourStopId: 'mun',
      now: _t0,
    );
    expect((s.busIndex, s.yourStopIndex, s.stopsToYourStop), (0, 2, 2));
    s = t.update(
      bus: _bus(progress: 420),
      drawnProgress: 420,
      yourStopId: 'mun',
      now: _at(30),
    );
    expect(s.stopsToYourStop, 1);
    expect(s.arrived, isFalse);
    expect(s.ended, isNull);
  });

  test('arrival shows for 10 s, then the follow ends', () {
    final t = _tracker();
    t.update(
      bus: _bus(progress: 700),
      drawnProgress: 700,
      yourStopId: 'mun',
      now: _t0,
    );
    var s = t.update(
      bus: _bus(progress: 790),
      drawnProgress: 790,
      yourStopId: 'mun',
      now: _at(1),
    );
    expect(s.arrived, isTrue);
    expect(s.ended, isNull);
    s = t.update(
      bus: _bus(progress: 900),
      drawnProgress: 900,
      yourStopId: 'mun',
      now: _at(10),
    );
    expect(s.ended, isNull, reason: 'still within the 10 s linger');
    s = t.update(
      bus: _bus(progress: 950),
      drawnProgress: 950,
      yourStopId: 'mun',
      now: _at(11),
    );
    expect(s.ended, FollowEnd.arrived);
  });

  test('while the arrival lingers your stop stays the one arrived at', () {
    final t = _tracker();
    t.update(bus: _bus(progress: 790), drawnProgress: 790, yourStopId: 'mun', now: _t0);
    final s = t.update(bus: _bus(progress: 1000), drawnProgress: 1000, yourStopId: 'mun', now: _at(5));
    expect((s.arrived, s.yourStopIndex, s.ended), (true, 2, null));
  });

  test('a trip change right after arrival still ends as arrived', () {
    final t = _tracker();
    t.update(bus: _bus(progress: 790), drawnProgress: 790, yourStopId: 'mun', now: _at(1));
    var s = t.update(bus: _bus(trip: 't2', progress: 5), drawnProgress: 5, yourStopId: 'mun', now: _at(3));
    expect((s.arrived, s.ended), (true, null));
    s = t.update(bus: _bus(trip: 't2', progress: 10), drawnProgress: 10, yourStopId: 'mun', now: _at(11));
    expect(s.ended, FollowEnd.arrived);
  });

  test('a trip change just short of a last-stop your stop counts as arrival', () {
    const terminus = [
      TripStop(stopId: 'a', name: 'A', sequence: 1, progress: 0, departureSeconds: 43200),
      TripStop(stopId: 'mun', name: 'MUN Centre', sequence: 2, progress: 800, departureSeconds: 43320),
    ];
    final t = _tracker(terminus);
    t.update(bus: _bus(progress: 750), drawnProgress: 750, yourStopId: 'mun', now: _t0);
    var s = t.update(bus: _bus(trip: 't2', progress: 5), drawnProgress: 5, yourStopId: 'mun', now: _at(2));
    expect((s.arrived, s.ended, s.stopsToYourStop), (true, null, 0));
    s = t.update(bus: _bus(trip: 't2', progress: 8), drawnProgress: 8, yourStopId: 'mun', now: _at(12));
    expect(s.ended, FollowEnd.arrived);
  });

  test('a trip change far from your stop is trip ended', () {
    final t = _tracker();
    t.update(bus: _bus(progress: 100), drawnProgress: 100, yourStopId: 'mun', now: _t0);
    final s = t.update(bus: _bus(trip: 't2', progress: 5), drawnProgress: 5, yourStopId: 'mun', now: _at(2));
    expect((s.arrived, s.ended), (false, FollowEnd.tripEnded));
  });

  test('jitter at your stop never un-arrives or flickers', () {
    final t = _tracker();
    var s = t.update(bus: _bus(progress: 765), drawnProgress: 765, yourStopId: 'mun', now: _t0);
    expect(s.arrived, isFalse);
    int? busIndex;
    var now = 1;
    for (final p in [775.0, 765.0, 775.0, 768.0, 772.0, 700.0, 775.0]) {
      s = t.update(bus: _bus(progress: p), drawnProgress: p, yourStopId: 'mun', now: _at(now++));
      expect((s.arrived, s.stopsToYourStop, s.yourStopIndex, s.ended), (true, 0, 2, null), reason: 'p=$p');
      busIndex ??= s.busIndex;
      expect(s.busIndex, busIndex, reason: 'p=$p');
    }
  });

  test('stops load once per trip and shape, and equal frames compare equal', () {
    var calls = 0;
    final t = FollowTracker(
      vehicleId: '2573',
      stopsFor: (_, _) {
        calls++;
        return <TripStop>[];
      },
    );
    FollowSnapshot? prev;
    for (var i = 0; i < 5; i++) {
      final s = t.update(bus: _bus(progress: 100), drawnProgress: 100, yourStopId: 'mun', now: _at(i));
      if (prev != null) expect(s, prev);
      prev = s;
    }
    expect(calls, 1);
  });

  test('a bus already past your stop ends as passed', () {
    final s = _tracker().update(
      bus: _bus(progress: 1100),
      drawnProgress: 1100,
      yourStopId: 'mun',
      now: _t0,
    );
    expect(s.ended, FollowEnd.passedYourStop);
  });

  test(
    'the bus starting another trip ends the follow; it never switches vehicle',
    () {
      final t = _tracker();
      t.update(
        bus: _bus(trip: 't1'),
        drawnProgress: 100,
        yourStopId: 'mun',
        now: _t0,
      );
      final s = t.update(
        bus: _bus(trip: 't2', progress: 10),
        drawnProgress: 10,
        yourStopId: 'mun',
        now: _at(20),
      );
      expect(s.ended, FollowEnd.tripEnded);
      expect(s.vehicleId, '2573');
    },
  );

  test('a bus that stops reporting is lost after the store drops it', () {
    final t = _tracker();
    t.update(bus: _bus(), drawnProgress: 100, yourStopId: 'mun', now: _t0);
    var s = t.update(
      bus: _bus(status: BusStatus.stale),
      drawnProgress: 100,
      yourStopId: 'mun',
      now: _at(95),
    );
    expect(s.stale, isTrue);
    expect(s.lastSeenAgo, const Duration(seconds: 95));
    expect(s.ended, isNull);
    s = t.update(
      bus: null,
      drawnProgress: null,
      yourStopId: 'mun',
      now: _at(301),
    );
    expect(s.ended, FollowEnd.lostContact);
  });

  test('a GPS time older than 5 min is lost even if the track lingers', () {
    final s = _tracker().update(
      bus: _bus(gps: _t0),
      drawnProgress: 100,
      yourStopId: 'mun',
      now: _at(301),
    );
    expect(s.ended, FollowEnd.lostContact);
  });

  test('a bus that never appears ends as not found after 60 s', () {
    final t = _tracker();
    expect(
      t
          .update(bus: null, drawnProgress: null, yourStopId: 'mun', now: _t0)
          .ended,
      isNull,
    );
    expect(
      t
          .update(
            bus: null,
            drawnProgress: null,
            yourStopId: 'mun',
            now: _at(59),
          )
          .ended,
      isNull,
    );
    expect(
      t
          .update(
            bus: null,
            drawnProgress: null,
            yourStopId: 'mun',
            now: _at(61),
          )
          .ended,
      FollowEnd.notFound,
    );
  });

  test('your stop not on the trip: no arrival, ends at the trip end', () {
    final t = _tracker();
    var s = t.update(
      bus: _bus(progress: 900),
      drawnProgress: 900,
      yourStopId: 'elsewhere',
      now: _t0,
    );
    expect(
      (s.yourStopIndex, s.stopsToYourStop, s.arrived, s.ended),
      (null, null, false, null),
    );
    s = t.update(
      bus: _bus(progress: 1180),
      drawnProgress: 1180,
      yourStopId: 'elsewhere',
      now: _at(60),
    );
    expect(s.ended, FollowEnd.tripEnded);
  });

  test('a stop visited twice uses the upcoming visit', () {
    const loop = [
      TripStop(
        stopId: 'mun',
        name: 'MUN Centre',
        sequence: 1,
        progress: 0,
        departureSeconds: 43200,
      ),
      TripStop(
        stopId: 'b',
        name: 'B',
        sequence: 2,
        progress: 600,
        departureSeconds: 43300,
      ),
      TripStop(
        stopId: 'mun',
        name: 'MUN Centre',
        sequence: 3,
        progress: 1500,
        departureSeconds: 43500,
      ),
    ];
    final s = _tracker(loop).update(
      bus: _bus(progress: 700),
      drawnProgress: 700,
      yourStopId: 'mun',
      now: _t0,
    );
    expect(s.yourStopIndex, 2);
    expect(s.stopsToYourStop, 1);
    expect(s.ended, isNull);
  });

  test('off route keeps the last known position; endings are sticky', () {
    final t = _tracker();
    t.update(
      bus: _bus(progress: 420),
      drawnProgress: 420,
      yourStopId: 'mun',
      now: _t0,
    );
    var s = t.update(
      bus: _bus(progress: 0).copyWithoutProgress(),
      drawnProgress: null,
      yourStopId: 'mun',
      now: _at(5),
    );
    expect(s.stopsToYourStop, 1);
    s = t.update(
      bus: _bus(progress: 1100),
      drawnProgress: 1100,
      yourStopId: 'mun',
      now: _at(6),
    );
    s = t.update(
      bus: _bus(progress: 100),
      drawnProgress: 100,
      yourStopId: 'mun',
      now: _at(7),
    );
    expect(s.ended, isNotNull);
  });

  group('a trip change before arrival (I1/I2)', () {
    test('a trip change while the fix is still on the old shape keeps following the old trip', () {
      final t = _snapping();
      t.update(bus: _bus(progress: 300), drawnProgress: 300, yourStopId: 'mun', now: _t0);
      // Early, clock-driven switch: 500 m before your stop, the feed relabels.
      var s = t.update(bus: _relabelled(along: 420), drawnProgress: 5, drawnTripId: 't2', yourStopId: 'mun', now: _at(2));
      expect((s.ended, s.tripId, s.yourStopIndex, s.stopsToYourStop), (null, 't1', 2, 1));
      expect(identical(s.stops, _stops), isTrue, reason: 'the old stops are kept');
      expect(s.progress, 420, reason: 'progress comes from the live fix on the old shape');
      expect(s.onTrip, isTrue);
      s = t.update(bus: _relabelled(along: 790), drawnProgress: 10, drawnTripId: 't2', yourStopId: 'mun', now: _at(40));
      expect((s.arrived, s.ended), (true, null));
      s = t.update(bus: _relabelled(along: 900), drawnProgress: 20, drawnTripId: 't2', yourStopId: 'mun', now: _at(51));
      expect(s.ended, FollowEnd.arrived);
    });

    test('a terminus switch while the drawn bus lags is an arrival, not trip ended', () {
      final t = _snapping();
      // The drawn bus is 200 m behind the live one when the feed rolls over.
      t.update(bus: _bus(progress: 1000), drawnProgress: 1000, yourStopId: 'c', now: _t0);
      var s = t.update(bus: _relabelled(along: 1195), drawnProgress: 1010, yourStopId: 'c', now: _at(1));
      expect((s.arrived, s.ended), (true, null));
      s = t.update(bus: _relabelled(along: 1200), drawnProgress: 1020, yourStopId: 'c', now: _at(12));
      expect(s.ended, FollowEnd.arrived);
    });

    test('a trip change first seen after a long frame gap is judged on the live fix', () {
      final t = _snapping();
      t.update(bus: _bus(progress: 500), drawnProgress: 500, yourStopId: 'c', now: _t0);
      // The map was offstage for 4 min; the bus is now at the terminal.
      final back = _at(240);
      final s = t.update(bus: _relabelled(along: 1198, gps: back), drawnProgress: 3, yourStopId: 'c', now: back);
      expect((s.arrived, s.ended), (true, null));
    });

    test('a held fix that jumps across your stop between two fixes has arrived there', () {
      final t = _snapping();
      t.update(bus: _bus(progress: 300), drawnProgress: 300, yourStopId: 'mun', now: _t0);
      var s = t.update(bus: _relabelled(along: 700), drawnProgress: 5, yourStopId: 'mun', now: _at(2));
      expect((s.arrived, s.ended), (false, null));
      // 26 s to the next fix: the bus went through MUN Centre (800) meanwhile.
      s = t.update(bus: _relabelled(along: 1000), drawnProgress: 5, yourStopId: 'mun', now: _at(28));
      expect((s.arrived, s.ended, s.yourStopIndex), (true, null, 2));
    });

    test('a trip change once the fix has left the old shape ends as trip ended', () {
      final t = _snapping();
      t.update(bus: _bus(progress: 300), drawnProgress: 300, yourStopId: 'mun', now: _t0);
      final s = t.update(bus: _relabelled(along: 320, off: 400), drawnProgress: 5, yourStopId: 'mun', now: _at(2));
      expect(s.ended, FollowEnd.tripEnded);
    });

    test('a fix behind the old progress has left the old trip', () {
      final t = _snapping();
      t.update(bus: _bus(progress: 600), drawnProgress: 600, yourStopId: 'mun', now: _t0);
      final s = t.update(bus: _relabelled(along: 500), drawnProgress: 5, yourStopId: 'mun', now: _at(2));
      expect(s.ended, FollowEnd.tripEnded);
    });

    test('holding on the old shape is capped at 3 min', () {
      final t = _snapping();
      t.update(bus: _bus(progress: 300), drawnProgress: 300, yourStopId: 'mun', now: _t0);
      var s = t.update(bus: _relabelled(along: 320), drawnProgress: 5, yourStopId: 'mun', now: _at(1));
      expect(s.ended, isNull);
      s = t.update(bus: _relabelled(along: 330, gps: _at(180)), drawnProgress: 5, yourStopId: 'mun', now: _at(180));
      expect(s.ended, isNull, reason: 'still within the grace');
      s = t.update(bus: _relabelled(along: 330, gps: _at(182)), drawnProgress: 5, yourStopId: 'mun', now: _at(182));
      expect(s.ended, FollowEnd.tripEnded);
    });

    test('off the old shape with your stop ahead on the new trip, it follows the new trip', () {
      // The bus carried its finished trip's label; the feed now relabels it
      // with the trip that serves your stop.
      final t = _snapping(_stops, {'t2': _returnTrip});
      var s = t.update(bus: _bus(progress: 1200), drawnProgress: 1150, yourStopId: 'y', now: _t0);
      expect((s.ended, s.yourStopIndex), (null, null), reason: "your stop isn't on the old trip");
      s = t.update(bus: _relabelled(along: 900, off: 600, progress: 100), drawnProgress: 1160, drawnTripId: 't1', yourStopId: 'y', now: _at(2));
      expect((s.ended, s.tripId, s.yourStopIndex, s.busIndex, s.stopsToYourStop), (null, 't2', 2, 0, 2));
      expect(identical(s.stops, _returnTrip), isTrue);
      expect(s.progress, 100, reason: 'the drawn bus is still on the old trip, so its progress is not used');
      s = t.update(bus: _relabelled(along: 900, off: 600, progress: 990), drawnProgress: 990, drawnTripId: 't2', yourStopId: 'y', now: _at(60));
      expect((s.arrived, s.ended), (true, null));
    });

    test('off the old shape with your stop behind the bus on the new trip, the follow ends', () {
      final t = _snapping(_stops, {'t2': _returnTrip});
      t.update(bus: _bus(progress: 300), drawnProgress: 300, yourStopId: 'mun', now: _t0);
      final s = t.update(bus: _relabelled(along: 0, off: 600, progress: 800), drawnProgress: 5, yourStopId: 'mun', now: _at(2));
      expect(s.ended, FollowEnd.tripEnded);
    });

    test('without the new trip serving your stop, leaving the old shape ends the follow', () {
      final t = _snapping(_stops, {'t2': _returnTrip});
      t.update(bus: _bus(progress: 300), drawnProgress: 300, yourStopId: 'b', now: _t0);
      final s = t.update(bus: _relabelled(along: 0, off: 600, progress: 0), drawnProgress: 5, yourStopId: 'b', now: _at(2));
      expect(s.ended, FollowEnd.tripEnded);
    });
  });

  test('restarting the clock gives a bus not seen yet another 60 s', () {
    final t = _tracker();
    t.update(bus: null, drawnProgress: null, yourStopId: 'mun', now: _t0);
    t.restartClock(_at(360));
    expect(t.update(bus: null, drawnProgress: null, yourStopId: 'mun', now: _at(361)).ended, isNull);
    expect(t.update(bus: null, drawnProgress: null, yourStopId: 'mun', now: _at(421)).ended, FollowEnd.notFound);
  });

  test('a headsign change makes a new snapshot', () {
    final t = _tracker();
    final a = t.update(bus: _bus(), drawnProgress: 100, yourStopId: 'mun', now: _t0);
    final b = t.update(bus: _bus(headsign: 'Village'), drawnProgress: 100, yourStopId: 'mun', now: _at(1));
    expect(a == b, isFalse);
  });
}

extension on BusTrackingState {
  BusTrackingState copyWithoutProgress() => BusTrackingState(
    routeRun: routeRun,
    vehicleId: vehicleId,
    routeNumber: routeNumber,
    headsign: headsign,
    currentTripId: currentTripId,
    shapeId: shapeId,
    lat: lat,
    lon: lon,
    heading: heading,
    speedKmh: speedKmh,
    lastGpsTime: lastGpsTime,
    status: BusStatus.offRoute,
    lastUpdateTime: lastUpdateTime,
  );
}
