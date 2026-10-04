import 'package:busboard_nl/domain/map/bus_track.dart';
import 'package:busboard_nl/domain/map/delayed_track_renderer.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/out_and_back.dart';

final _t0 = DateTime(2026, 10, 4, 12, 0);
final _geometry = RouteGeometry(outAndBackRepo());

TrackFix _fix(int s, double progress, {String trip = outAndBackTripId, bool offRoute = false, double? lat, double? lon}) {
  final pose = _geometry.poseAt(outAndBackShapeId, progress)!;
  return TrackFix(
    gpsTime: _t0.add(Duration(seconds: s)),
    fetchTime: _t0.add(Duration(seconds: s + 2)),
    lat: lat ?? pose.lat,
    lon: lon ?? pose.lon,
    heading: pose.heading,
    speedKmh: 30,
    tripId: trip,
    shapeId: offRoute ? null : outAndBackShapeId,
    progress: offRoute ? null : progress,
    snappedLat: offRoute ? null : pose.lat,
    snappedLon: offRoute ? null : pose.lon,
    offRoute: offRoute,
  );
}

BusTrack _track(List<TrackFix> fixes) => BusTrack(
      vehicleId: '2573', routeNumber: 10, routeRun: 'Rt 10', headsign: 'Loop',
      fixes: fixes, lastFixAt: fixes.last.fetchTime);

void main() {
  test('delay is the median fix interval plus 2 s, clamped to 8..20 s', () {
    final r = DelayedTrackRenderer(_geometry);
    expect(r.delayFor(_track([_fix(0, 100)])), DelayedTrackRenderer.defaultDelay);
    expect(r.delayFor(_track([_fix(0, 100), _fix(10, 180), _fix(20, 260), _fix(40, 420)])), const Duration(seconds: 12));
    expect(r.delayFor(_track([_fix(0, 100), _fix(2, 110), _fix(4, 120)])), DelayedTrackRenderer.minDelay);
    expect(r.delayFor(_track([_fix(0, 100), _fix(60, 400), _fix(120, 700)])), DelayedTrackRenderer.maxDelay);
  });

  test('draws the bus between two fixes, along the shape, at now − D', () {
    final r = DelayedTrackRenderer(_geometry);
    final track = _track([_fix(0, 100), _fix(10, 180), _fix(20, 260)]);
    // D = 12 s; at now = 27 s the render time is 15 s: halfway 180 → 260.
    final bus = r.render(track, _t0.add(const Duration(seconds: 27)));
    expect(bus.progress, closeTo(220, 0.5));
    expect(bus.shapeId, outAndBackShapeId);
    final pose = _geometry.poseAt(outAndBackShapeId, 220)!;
    expect(bus.lat, closeTo(pose.lat, 1e-9));
    expect(bus.lon, closeTo(pose.lon, 1e-9));
  });

  test('moves every frame while the fixes show movement', () {
    final r = DelayedTrackRenderer(_geometry);
    final track = _track([_fix(0, 100), _fix(10, 180), _fix(20, 260), _fix(30, 340)]);
    double? last;
    for (var ms = 22000; ms < 40000; ms += 120) {
      final p = r.render(track, _t0.add(Duration(milliseconds: ms))).progress!;
      if (last != null) expect(p, greaterThan(last), reason: 'frame at $ms ms');
      last = p;
    }
  });

  test('GPS that runs backward holds the bus instead of sliding it back', () {
    final r = DelayedTrackRenderer(_geometry);
    final track = _track([_fix(0, 300), _fix(10, 400), _fix(20, 330), _fix(30, 450)]);
    double highWater = 0;
    // D = 12 s; render times run 0 s .. 30 s (the last fix), so no
    // extrapolation is involved.
    for (var ms = 12000; ms <= 42000; ms += 120) {
      final p = r.render(track, _t0.add(Duration(milliseconds: ms))).progress!;
      expect(p, greaterThanOrEqualTo(highWater - 1e-6), reason: 'frame at $ms ms');
      if (p > highWater) highWater = p;
    }
    expect(highWater, closeTo(450, 0.5));
  });

  test('a repeated GPS timestamp holds the bus after at most 5 s of extrapolation', () {
    final r = DelayedTrackRenderer(_geometry);
    final track = _track([_fix(0, 100), _fix(10, 180)]);
    // D = 12 s. Render time passes the last fix (10 s) at now = 22 s.
    final at27 = r.render(track, _t0.add(const Duration(seconds: 27))).progress!; // 5 s past
    final at60 = r.render(track, _t0.add(const Duration(seconds: 60))).progress!;
    expect(at27, closeTo(180 + 8 * 5, 1)); // last segment speed 8 m/s
    expect(at60, at27);
  });

  test('a trip change crosses the terminal in plain geography', () {
    final r = DelayedTrackRenderer(_geometry);
    final a = _fix(0, 1000);
    final b = _fix(10, 1100, trip: 'next-trip');
    final bus = r.render(_track([a, b]), _t0.add(const Duration(seconds: 17))); // render time 5 s
    expect(bus.lat, closeTo((a.lat + b.lat) / 2, 1e-9));
    expect(bus.lon, closeTo((a.lon + b.lon) / 2, 1e-9));
  });

  test('a new trip resets the never-backward rule', () {
    final r = DelayedTrackRenderer(_geometry);
    final track = _track([_fix(0, 1500), _fix(10, 1600), _fix(20, 50, trip: 'next-trip'), _fix(30, 130, trip: 'next-trip')]);
    // Render time 8 s: 1580 m on the first trip sets that trip's high-water mark.
    expect(r.render(track, _t0.add(const Duration(seconds: 20))).progress, closeTo(1580, 1));
    final bus = r.render(track, _t0.add(const Duration(seconds: 37)));
    expect(bus.tripId, 'next-trip');
    expect(bus.progress, closeTo(90, 1));
  });

  test('off-route fixes are interpolated in a straight line', () {
    final r = DelayedTrackRenderer(_geometry);
    final a = _fix(0, 0, offRoute: true, lat: 47.570, lon: -52.750);
    final b = _fix(10, 0, offRoute: true, lat: 47.571, lon: -52.749);
    final bus = r.render(_track([a, b]), _t0.add(const Duration(seconds: 17)));
    expect(bus.lat, closeTo(47.5705, 1e-9));
    expect(bus.lon, closeTo(-52.7495, 1e-9));
    expect(bus.progress, isNull);
  });

  test('before the first fix the bus sits at that fix', () {
    final r = DelayedTrackRenderer(_geometry);
    final bus = r.render(_track([_fix(0, 100)]), _t0.add(const Duration(seconds: 3)));
    expect(bus.progress, closeTo(100, 1e-6));
  });

  test('renderAll draws every track and forget clears one bus', () {
    final r = DelayedTrackRenderer(_geometry);
    final one = _track([_fix(0, 100), _fix(10, 180)]);
    final all = r.renderAll([one], _t0.add(const Duration(seconds: 20)));
    expect(all.keys, ['2573']);
    r.forget('2573');
    expect(r.render(one, _t0.add(const Duration(seconds: 13))).progress, lessThan(all['2573']!.progress!));
  });
}
