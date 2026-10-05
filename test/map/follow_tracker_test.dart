import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/domain/map/follow_tracker.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
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
}) => BusTrackingState(
  routeRun: 'Rt 10',
  vehicleId: id,
  routeNumber: 10,
  headsign: 'Downtown',
  currentTripId: trip,
  shapeId: 's',
  lat: 47.56,
  lon: -52.71,
  heading: 90,
  progress: progress,
  speedKmh: 30,
  lastGpsTime: gps ?? _t0,
  status: status,
  lastUpdateTime: gps ?? _t0,
);

FollowTracker _tracker([List<TripStop> stops = _stops]) =>
    FollowTracker(vehicleId: '2573', stopsFor: (_, _) => stops);

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
