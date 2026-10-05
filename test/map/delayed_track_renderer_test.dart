import 'dart:math' as math;

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/map/bus_track.dart';
import 'package:busboard_nl/domain/map/delayed_track_renderer.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/out_and_back.dart';

final _t0 = DateTime(2026, 10, 4, 12, 0);
final _geometry = RouteGeometry(outAndBackRepo());

TrackFix _fix(int s, double progress, {String trip = outAndBackTripId, bool offRoute = false, double? lat, double? lon, int fetchLag = 1}) {
  final pose = _geometry.poseAt(outAndBackShapeId, progress)!;
  return TrackFix(
    gpsTime: _t0.add(Duration(seconds: s)),
    fetchTime: _t0.add(Duration(seconds: s + fetchLag)),
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
  test('delay covers feed latency plus the fix interval, clamped to 8..30 s', () {
    final r = DelayedTrackRenderer(_geometry);
    // One fix: its age on arrival (5 s) plus 15 s.
    expect(r.delayFor(_track([_fix(0, 100, fetchLag: 5)])), const Duration(seconds: 20));
    // Lag of a pair = next fetch - previous GPS time: 10, 16 and 12 s. The
    // second-largest (12) plus 1 s. (The helper's default fetch lag of 1 s
    // makes a 10 s interval a 12 s delay, as the other tests assume.)
    expect(
      r.delayFor(_track([_fix(0, 100), _fix(10, 180, fetchLag: 0), _fix(20, 260, fetchLag: 6), _fix(30, 340, fetchLag: 2)])),
      const Duration(seconds: 13),
    );
    // Two fixes make one pair: the largest (14) plus 1 s.
    expect(r.delayFor(_track([_fix(0, 100), _fix(10, 180, fetchLag: 4)])), const Duration(seconds: 15));
    // One late fix among nine does not set the delay (lags 40, then 10 s).
    expect(
      r.delayFor(_track([
        _fix(0, 100, fetchLag: 0),
        _fix(30, 190, fetchLag: 10),
        for (var i = 2; i <= 8; i++) _fix(30 + (i - 1) * 10, 190.0 + i * 30, fetchLag: 0),
      ])),
      const Duration(seconds: 11),
    );
    // Fast, low-latency fixes hit the 8 s floor (lags 3 s).
    expect(r.delayFor(_track([_fix(0, 100, fetchLag: 1), _fix(2, 110, fetchLag: 1), _fix(4, 120, fetchLag: 1)])), DelayedTrackRenderer.minDelay);
    // Slow fixes hit the 30 s ceiling (lags 62 s).
    expect(r.delayFor(_track([_fix(0, 100), _fix(60, 400), _fix(120, 700)])), DelayedTrackRenderer.maxDelay);
    expect(DelayedTrackRenderer.maxDelay, const Duration(seconds: 30));
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

  test('extrapolation past the newest fix is capped at 5 s, then the bus holds', () {
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

  group('fix round 1', () {
    // Renders [track] every 120 ms of render time from [fromAt] to [toAt]
    // (seconds); D is 12 s for the 10 s-interval tracks used below.
    List<({double at, RenderedBus bus})> sweep(DelayedTrackRenderer r, BusTrack track, double fromAt, double toAt, {int delayS = 12}) {
      final frames = <({double at, RenderedBus bus})>[];
      for (var ms = (fromAt * 1000).round(); ms <= (toAt * 1000).round(); ms += 120) {
        final bus = r.render(track, _t0.add(Duration(milliseconds: ms + delayS * 1000)));
        frames.add((at: ms / 1000, bus: bus));
      }
      return frames;
    }

    test('jitter of 30 m backward holds at the high-water mark', () {
      final r = DelayedTrackRenderer(_geometry);
      final track = _track([_fix(0, 300), _fix(10, 400), _fix(20, 370), _fix(30, 450)]);
      for (final f in sweep(r, track, 10, 22)) {
        expect(f.bus.progress, closeTo(400, 1e-6), reason: 'at ${f.at} s');
      }
      expect(r.render(track, _t0.add(const Duration(seconds: 42))).progress, closeTo(450, 1e-6));
    });

    // Metres from (lat, lon) to the segment a–b, on a local flat projection.
    double metersToSegment(double lat, double lon, ShapePose a, ShapePose b) {
      final kx = 111320 * math.cos(a.lat * math.pi / 180);
      const ky = 110574.0;
      final px = (lon - a.lon) * kx, py = (lat - a.lat) * ky;
      final bx = (b.lon - a.lon) * kx, by = (b.lat - a.lat) * ky;
      final len2 = bx * bx + by * by;
      final t = len2 == 0 ? 0.0 : ((px * bx + py * by) / len2).clamp(0.0, 1.0);
      return math.sqrt(math.pow(px - bx * t, 2) + math.pow(py - by * t, 2));
    }

    // The longest stretch of render time (s) over which the drawn place does not change.
    double longestFrozen(List<({double at, RenderedBus bus})> frames) {
      var longest = 0.0;
      var since = frames.first.at;
      for (var i = 1; i < frames.length; i++) {
        final moved = frames[i].bus.lat != frames[i - 1].bus.lat || frames[i].bus.lon != frames[i - 1].bus.lon;
        if (moved) {
          since = frames[i].at;
        } else {
          longest = math.max(longest, frames[i].at - since);
        }
      }
      return longest;
    }

    test('a wrong-pass fix glides geographically to the right pass, never frozen', () {
      final r = DelayedTrackRenderer(_geometry);
      final track = _track([_fix(0, 1500), _fix(10, 1560), _fix(20, 300), _fix(30, 380), _fix(40, 460)]);
      final frames = sweep(r, track, 0, 40);
      final from = _geometry.poseAt(outAndBackShapeId, 1560)!;
      final to = _geometry.poseAt(outAndBackShapeId, 300)!;
      for (final f in frames.where((f) => f.at > 10.2 && f.at < 19.9)) {
        expect(f.bus.progress, isNull, reason: 'glide at ${f.at} s');
        expect(metersToSegment(f.bus.lat, f.bus.lon, from, to), lessThan(50), reason: 'at ${f.at} s');
      }
      expect(longestFrozen(frames), lessThanOrEqualTo(10.0));
      // Past the 300 fix the bus tracks its true progress again.
      for (final f in frames.where((f) => f.at >= 20.2)) {
        expect(f.bus.progress, closeTo(300 + 8 * (f.at - 20), 1), reason: 'at ${f.at} s');
      }
    });

    test('a forward glitch (260 → 650 → 340) glides back instead of freezing', () {
      final r = DelayedTrackRenderer(_geometry);
      final track = _track([_fix(0, 260), _fix(10, 650), _fix(20, 340), _fix(30, 420), _fix(40, 500)]);
      final frames = sweep(r, track, 0, 40);
      expect(longestFrozen(frames), lessThanOrEqualTo(10.0));
      expect(frames.firstWhere((f) => f.at >= 30).bus.progress, closeTo(420, 1));
    });

    test('a backstep of 60-150 m holds until the bus passes the mark, however long', () {
      final r = DelayedTrackRenderer(_geometry);
      final track = _track([_fix(0, 300), _fix(10, 500), _fix(20, 380), _fix(70, 380), _fix(80, 400)]);
      // 120 m back along the shape: held at the 500 m mark, and still held
      // 60 s later (the old rule released it after 15 s).
      final frames = sweep(r, track, 10, 80);
      final mark = frames.first.bus.progress!;
      expect(mark, closeTo(500, 1e-6));
      for (final f in frames.where((f) => f.at >= 15)) {
        expect(f.bus.progress, closeTo(500, 1e-6), reason: 'held at ${f.at} s');
      }
      expect(frames.last.at, greaterThan(15 + 60));
    });

    test('a backstep of more than 150 m is still accepted after a 15 s hold', () {
      final r = DelayedTrackRenderer(_geometry);
      // No single pair steps back more than 150 m (so none glides), but the
      // bus ends 160 m below its mark.
      final track = _track([_fix(0, 300), _fix(10, 500), _fix(20, 400), _fix(30, 340), _fix(70, 335)]);
      final frames = sweep(r, track, 10, 45);
      expect(frames.first.bus.progress, closeTo(500, 1e-6));
      final held = frames.where((f) => f.bus.progress != null && (f.bus.progress! - 500).abs() < 1e-6).map((f) => f.at);
      expect(held.last, inInclusiveRange(29.0, 33.0));
      // The accepted position is reached at 30 m/s (a straight-line walk with
      // no progress), so by the end of the sweep the bus is on its way or there.
      final end = frames.last.bus;
      expect(end.progress == null || end.progress! < 500, isTrue);
      expect(NearestStopService.haversineDistance(end.lat, end.lon, _geometry.poseAt(outAndBackShapeId, 500)!.lat, _geometry.poseAt(outAndBackShapeId, 500)!.lon), greaterThan(100));
    });

    test('a pass relabel within 40 m is accepted at once: progress jumps, the dot barely moves', () {
      final r = DelayedTrackRenderer(_geometry);
      // Render time 15 s: 5 s past the newest fix, the bus is extrapolated
      // along the return pass to 1550 m.
      final early = _track([_fix(0, 1400), _fix(10, 1500)]);
      final before = r.render(early, _t0.add(const Duration(seconds: 27)));
      expect(before.progress, closeTo(1550, 1));
      // A late fix puts the bus on the outbound pass (7.8 m of curb apart).
      final late = _track([_fix(0, 1400), _fix(10, 1500), _fix(12, 490), _fix(22, 510)]);
      final after = r.render(late, _t0.add(const Duration(seconds: 29))); // render time 17 s
      expect(after.progress, closeTo(500, 1e-6));
      expect(NearestStopService.haversineDistance(before.lat, before.lon, after.lat, after.lon), lessThanOrEqualTo(40));
    });

    test('a relabel ends the hold: the next backstep starts a fresh 15 s', () {
      final r = DelayedTrackRenderer(_geometry);
      DateTime nowAt(int atS) => _t0.add(Duration(seconds: atS + 12));
      // Mark 1550 by extrapolation (render time 15 s).
      r.render(_track([_fix(0, 1400), _fix(10, 1500)]), nowAt(15));
      // A backstep of 80 m below the mark begins a hold at 16 s.
      final held = r.render(_track([_fix(0, 1400), _fix(10, 1500), _fix(20, 1450)]), nowAt(16));
      expect(held.progress, closeTo(1550, 1e-6));
      // The bus is then seen on the other pass: relabel to 500.
      final relabel = r.render(_track([_fix(0, 1400), _fix(10, 1500), _fix(12, 490), _fix(22, 510)]), nowAt(17));
      expect(relabel.progress, closeTo(500, 1e-6));
      // 94 m below the new mark at 38 s (22 s after the first hold began):
      // it is a new hold, so it holds rather than being released at once.
      final next = r.render(_track([_fix(0, 1400), _fix(10, 1500), _fix(12, 490), _fix(22, 510), _fix(42, 380)]), nowAt(38));
      expect(next.progress, closeTo(500, 1e-6));
    });

    test('the same trip ID a day later draws at the true position', () {
      final r = DelayedTrackRenderer(_geometry);
      final yesterday = _track([_fix(0, 1900), _fix(10, 1950)]);
      expect(r.render(yesterday, _t0.add(const Duration(seconds: 22))).progress, closeTo(1950, 1e-6));
      const day = 86400;
      final today = _track([_fix(day, 100), _fix(day + 10, 180)]);
      final bus = r.render(today, _t0.add(const Duration(seconds: day + 17)));
      expect(bus.progress, closeTo(140, 1)); // render time 5 s into 100 → 180
    });

    test('a clock that jumps back draws the bus where it was at that time', () {
      final r = DelayedTrackRenderer(_geometry);
      final track = _track([_fix(0, 100), _fix(10, 180), _fix(20, 260), _fix(30, 340)]);
      expect(r.render(track, _t0.add(const Duration(seconds: 42))).progress, closeTo(340, 1e-6));
      final back = r.render(track, _t0.add(const Duration(seconds: 42 - 100)));
      expect(back.progress, closeTo(100, 1e-6)); // before the first fix
    });

    test('renderAll prunes state for vehicles it was not given; forget clears one', () {
      final r = DelayedTrackRenderer(_geometry);
      BusTrack named(String id) => BusTrack(
            vehicleId: id, routeNumber: 10, routeRun: 'Rt 10', headsign: 'Loop',
            fixes: [_fix(0, 100), _fix(10, 180)], lastFixAt: _t0.add(const Duration(seconds: 12)));
      final now = _t0.add(const Duration(seconds: 20));
      r.renderAll([named('a'), named('b')], now);
      expect(r.debugStateCount, 2);
      r.renderAll([named('a')], now.add(const Duration(seconds: 1)));
      expect(r.debugStateCount, 1);
      r.forget('a');
      expect(r.debugStateCount, 0);
    });

    test('an off-route stretch clears the never-backward mark', () {
      final r = DelayedTrackRenderer(_geometry);
      final track = _track([
        _fix(0, 500),
        _fix(10, 580),
        _fix(20, 0, offRoute: true, lat: 47.5700, lon: -52.7500),
        _fix(30, 400),
      ]);
      // The straight-line stretch from the off-route fix may be longer than
      // the 30 m/s limiter allows in 10 s, so give the bus time to arrive.
      final frames = sweep(r, track, 0, 60);
      expect(frames.last.bus.progress, closeTo(400, 1e-6));
    });

    test('extrapolation never runs past the end of the shape', () {
      final r = DelayedTrackRenderer(_geometry);
      final len = _geometry.shapeLength(outAndBackShapeId)!;
      expect(len, greaterThan(2000));
      expect(_geometry.shapeLength('nope'), isNull);
      final track = _track([_fix(0, len - 140), _fix(10, len - 20)]);
      final bus = r.render(track, _t0.add(const Duration(seconds: 27))); // 5 s past: +60 m
      expect(bus.progress, closeTo(len, 1e-6));
      expect(bus.progress!, lessThanOrEqualTo(len));
    });

    test('the delay moves toward its target by at most 0.1 s per second', () {
      final r = DelayedTrackRenderer(_geometry);
      // 10 s interval: D = 12 s.
      final steady = _track([_fix(0, 100), _fix(10, 180), _fix(20, 260), _fix(30, 340)]);
      // 20 s interval: D = 22 s.
      final slow = _track([_fix(0, 100), _fix(20, 260), _fix(40, 420), _fix(60, 580)]);
      expect(r.delayFor(steady), const Duration(seconds: 12));
      expect(r.delayFor(slow), const Duration(seconds: 22));
      expect(r.currentDelayFor('2573'), isNull);
      var now = _t0.add(const Duration(seconds: 40));
      r.render(steady, now);
      expect(r.currentDelayFor('2573'), const Duration(seconds: 12));
      var last = 12.0;
      for (var i = 0; i < 80; i++) {
        now = now.add(const Duration(seconds: 2));
        r.render(slow, now);
        final d = r.currentDelayFor('2573')!.inMicroseconds / 1e6;
        expect(d - last, inInclusiveRange(0.0, 0.2 + 1e-6), reason: 'step $i');
        last = d;
      }
      expect(last, closeTo(22, 1e-6)); // reached after 100 s of wall time
      // And back down, at the same pace.
      now = now.add(const Duration(seconds: 10));
      r.render(steady, now);
      expect(r.currentDelayFor('2573')!.inMicroseconds / 1e6, closeTo(21, 1e-6));
    });

    test('two fixes with the same GPS time never divide by zero', () {
      final r = DelayedTrackRenderer(_geometry);
      // The store would drop the duplicate; built directly here.
      final track = _track([_fix(10, 100), _fix(10, 180)]);
      // D = 8 s (lag 1 s + 1 s, clamped up).
      expect(r.render(track, _t0.add(const Duration(seconds: 15))).progress, closeTo(100, 1e-6)); // before
      expect(r.render(track, _t0.add(const Duration(seconds: 18))).progress, closeTo(100, 1e-6)); // at
      final after = r.render(track, _t0.add(const Duration(seconds: 25))).progress!;
      expect(after.isFinite, isTrue);
      expect(after, closeTo(180, 1e-6));
    });
  });

  group('fix round 3: continuity limiter', () {
    const frame = Duration(milliseconds: 120);
    const stepMax = 30 * 0.12 + 1e-6;

    test('a start-up jump becomes a catch-up at no more than 30 m/s', () {
      final r = DelayedTrackRenderer(_geometry);
      // One fix: drawn where it is. Its age on arrival is 1 s, so D = 16 s.
      final first = _track([_fix(0, 1000)]);
      var now = _t0.add(const Duration(seconds: 30));
      final start = r.render(first, now);
      expect(start.progress, closeTo(1000, 1e-6));
      // The second fix arrives; render time is now inside the pair, 141 m on.
      final both = _track([_fix(0, 1000), _fix(16, 1160)]);
      var last = start.progress!;
      var firstStep = true;
      for (var i = 0; i < 150; i++) {
        now = now.add(frame);
        final p = r.render(both, now).progress!;
        expect(p - last, inInclusiveRange(0.0, stepMax), reason: 'frame $i');
        if (firstStep) expect(p - last, closeTo(3.6, 1e-6));
        firstStep = false;
        last = p;
      }
      // Eventually on target: the unlimited place at the last frame (held
      // 5 s past the newest fix, at 1160 + 10 m/s * 5 s).
      expect(last, closeTo(1210, 1e-6));
    });

    test('a skipped fix followed by a jump catches up at no more than 30 m/s', () {
      final r = DelayedTrackRenderer(_geometry);
      final late = _track([_fix(0, 100), _fix(10, 180)]);
      // Past the newest fix by more than 5 s: extrapolated, then held.
      var now = _t0.add(const Duration(seconds: 27));
      var last = r.render(late, now).progress!;
      expect(last, closeTo(220, 1e-6));
      for (var i = 0; i < 10; i++) {
        now = now.add(frame);
        last = r.render(late, now).progress!;
        expect(last, closeTo(220, 1e-6));
      }
      // The next fix is 30 s after the last: render time lands 57 m ahead.
      final next = _track([_fix(0, 100), _fix(10, 180), _fix(40, 600)]);
      var steps = 0;
      var movedBack = false;
      while (steps < 60) {
        now = now.add(frame);
        final p = r.render(next, now).progress!;
        expect(p - last, lessThanOrEqualTo(stepMax), reason: 'frame $steps');
        if (p < last) movedBack = true;
        last = p;
        steps++;
      }
      expect(movedBack, isFalse);
      // 60 frames * 3.6 m = 216 m of catch-up at most; the first frame moved 3.6 m.
      expect(last, greaterThan(220 + 100));
    });

    test('a render gap of more than 2 s snaps to the target', () {
      final r = DelayedTrackRenderer(_geometry);
      final late = _track([_fix(0, 100), _fix(10, 180)]);
      expect(r.render(late, _t0.add(const Duration(seconds: 27))).progress, closeTo(220, 1e-6));
      final far = _track([_fix(0, 100), _fix(10, 180), _fix(30, 900)]);
      // 2.5 s later the slewed delay is 12.25 s, render time 17.25 s:
      // 180 + 720 * 7.25 / 20 = 441 m, a 221 m jump, snapped.
      final bus = r.render(far, _t0.add(const Duration(milliseconds: 29500)));
      expect(bus.progress, closeTo(441, 1e-6));
    });

    test('a gap of 2 s or less is limited', () {
      final r = DelayedTrackRenderer(_geometry);
      final late = _track([_fix(0, 100), _fix(10, 180)]);
      expect(r.render(late, _t0.add(const Duration(seconds: 27))).progress, closeTo(220, 1e-6));
      final far = _track([_fix(0, 100), _fix(10, 180), _fix(30, 900)]);
      final bus = r.render(far, _t0.add(const Duration(seconds: 29)));
      expect(bus.progress, closeTo(220 + 60, 1e-6)); // 30 m/s * 2 s
    });

    test('a geographic jump (trip change) also catches up at no more than 30 m/s', () {
      final r = DelayedTrackRenderer(_geometry);
      final single = _track([_fix(0, 1000)]);
      var now = _t0.add(const Duration(seconds: 20));
      final before = r.render(single, now);
      final changed = _track([_fix(0, 1000), _fix(10, 600, trip: 'next-trip')]);
      now = now.add(frame);
      final after = r.render(changed, now);
      final moved = NearestStopService.haversineDistance(before.lat, before.lon, after.lat, after.lon);
      expect(moved, closeTo(3.6, 0.05));
      expect(after.progress, isNull);
      expect(after.tripId, outAndBackTripId); // the pair's first trip until halfway
    });

    test('forget clears the limiter state', () {
      final r = DelayedTrackRenderer(_geometry);
      final late = _track([_fix(0, 100), _fix(10, 180)]);
      expect(r.render(late, _t0.add(const Duration(seconds: 45))).progress, closeTo(220, 1e-6));
      r.forget('2573');
      final far = _track([_fix(0, 100), _fix(10, 180), _fix(30, 900)]);
      // No state: delay 22 s at once, render time 23.12 s, straight to the
      // target 180 + 720 * 13.12 / 20 m. (Limited it would be 223.6 m.)
      final bus = r.render(far, _t0.add(const Duration(milliseconds: 45120)));
      expect(bus.progress, closeTo(180 + 720 * 13.12 / 20, 1e-6));
    });

    test('two renders at the same now return the same bus, whatever the track says', () {
      final r = DelayedTrackRenderer(_geometry);
      final late = _track([_fix(0, 100), _fix(10, 180)]);
      final now = _t0.add(const Duration(seconds: 27));
      final first = r.render(late, now);
      final delay = r.currentDelayFor('2573');
      // A fix arrives between two frames drawn at the same instant: the
      // second call must not recompute (it would jump to the new target).
      final far = _track([_fix(0, 100), _fix(10, 180), _fix(30, 900)]);
      final again = r.render(far, now);
      expect(again.lat, first.lat);
      expect(again.lon, first.lon);
      expect(again.progress, first.progress);
      expect(r.currentDelayFor('2573'), delay);
      // And the next real frame still moves at most 30 m/s from there.
      final next = r.render(far, now.add(frame));
      expect(next.progress! - first.progress!, inInclusiveRange(0.0, stepMax));
    });

    test('a trip-change glide starts at the drawn (extrapolated) point, not behind it', () {
      final r = DelayedTrackRenderer(_geometry);
      final before = _track([_fix(0, 1000), _fix(10, 1080)]);
      var now = _t0.add(const Duration(seconds: 27)); // render time 15 s: 5 s past the last fix
      final extrapolated = r.render(before, now);
      expect(extrapolated.progress, closeTo(1120, 1e-6));
      // The next fix is 20 s after the last, on a new trip further along: the
      // pair a -> b is a trip change, drawn geographically from where the bus
      // already is, never from the older fix behind it.
      final after = _track([_fix(0, 1000), _fix(10, 1080), _fix(30, 1200, trip: 'next-trip')]);
      for (var i = 0; i < 20; i++) {
        now = now.add(frame);
        final bus = r.render(after, now);
        final along = _geometry.snap(bus.lat, bus.lon, outAndBackShapeId, expectedAlong: 1120, minAlong: 1000, maxAlong: 1400)!.distanceAlongRoute;
        expect(along, greaterThanOrEqualTo(1120 - 0.5), reason: 'frame $i');
      }
    });
  });

  group('final fix wave', () {
    const frame = Duration(milliseconds: 120);

    test('a 2 min gap on the same trip glides at up to 60 m/s instead of snapping', () {
      final r = DelayedTrackRenderer(_geometry);
      final before = _track([_fix(0, 100), _fix(10, 180)]);
      var now = _t0.add(const Duration(seconds: 112)); // render time 100 s: past the last fix
      var last = r.render(before, now).progress!;
      // A fix 2 min after the last arrives; render time (100 s) is 75% along
      // the pair, 500+ m ahead of where the bus is drawn.
      final after = _track([_fix(0, 100), _fix(10, 180), _fix(130, 1000)]);
      const fastStep = 60 * 0.12;
      var fast = 0;
      double? firstStep;
      var step = 0.0;
      for (var i = 0; i < 400; i++) {
        now = now.add(frame);
        final p = r.render(after, now).progress!;
        step = p - last;
        firstStep ??= step;
        expect(step, inInclusiveRange(0.0, fastStep + 1e-6), reason: 'frame $i');
        if (step > 30 * 0.12 + 1e-6) fast++;
        last = p;
      }
      expect(firstStep, closeTo(fastStep, 1e-6));
      expect(fast, greaterThan(50));
      // Caught up: the bus then moves at its own pace (820 m in 120 s).
      expect(step, lessThan(1.5));
    });

    test('a gap fix behind the mark of the same trip is held, never snapped back', () {
      final r = DelayedTrackRenderer(_geometry);
      // Render time 75 s: past the last fix, a slow bus, drawn near 400 m.
      final before = _track([_fix(0, 390), _fix(10, 400)]);
      var now = _t0.add(const Duration(seconds: 87));
      final mark = r.render(before, now).progress!;
      expect(mark, inInclusiveRange(400, 410));
      // 70 s later the bus is seen 145 m back: render time 75 s is ~140 m
      // behind the mark. The old rule snapped there.
      final after = _track([_fix(0, 390), _fix(10, 400), _fix(80, 255)]);
      for (var i = 0; i < 20; i++) {
        now = now.add(frame);
        expect(r.render(after, now).progress, closeTo(mark, 1e-6), reason: 'frame $i');
      }
    });

    test('a trip change after a 90 s gap glides too, in a straight line', () {
      final r = DelayedTrackRenderer(_geometry);
      final before = _track([_fix(0, 900), _fix(10, 950)]);
      var now = _t0.add(const Duration(seconds: 92)); // render time 80 s
      final start = r.render(before, now);
      // The next fix, 90 s on, is on the next trip 400 m back along the shape
      // (the return leg, on the map ~400 m west): no snap, a glide.
      final after = _track([_fix(0, 900), _fix(10, 950), _fix(100, 1500, trip: 'next-trip')]);
      now = now.add(frame);
      final bus = r.render(after, now);
      expect(NearestStopService.haversineDistance(start.lat, start.lon, bus.lat, bus.lon), closeTo(60 * 0.12, 0.05));
    });

    test('a gap of more than 3 min still snaps to the target', () {
      final r = DelayedTrackRenderer(_geometry);
      final before = _track([_fix(0, 100), _fix(10, 180)]);
      var now = _t0.add(const Duration(seconds: 212)); // render time 200 s
      r.render(before, now);
      final after = _track([_fix(0, 100), _fix(10, 180), _fix(250, 1000)]);
      now = now.add(frame);
      final bus = r.render(after, now);
      // Render time ~200 s (the delay is slewing), ~79% along the pair.
      expect(bus.progress, closeTo(180 + 820 * (200.12 - 10) / 240, 5));
    });

    test('a data-gap snap still holds a target within 60 m behind the mark of the same trip', () {
      final r = DelayedTrackRenderer(_geometry);
      final before = _track([_fix(0, 100), _fix(10, 180)]);
      var now = _t0.add(const Duration(seconds: 112));
      expect(r.render(before, now).progress, closeTo(220, 1e-6)); // extrapolated 40 m past the last fix
      // The fix 2 min later says the bus is only at about 190: the 30 m
      // extrapolation overshoot is held, not drawn backward.
      final after = _track([_fix(0, 100), _fix(10, 180), _fix(130, 190)]);
      now = now.add(frame);
      expect(r.render(after, now).progress, closeTo(220, 1e-6));
    });

    test('a 20 s gap in the fixes still glides at no more than 30 m/s', () {
      final r = DelayedTrackRenderer(_geometry);
      final before = _track([_fix(0, 100), _fix(10, 180)]);
      var now = _t0.add(const Duration(seconds: 112));
      expect(r.render(before, now).progress, closeTo(220, 1e-6));
      final after = _track([_fix(0, 100), _fix(10, 180), _fix(30, 1000)]);
      now = now.add(frame);
      expect(r.render(after, now).progress, closeTo(220 + 3.6, 1e-6));
    });

    test('a re-created track (same vehicle) snaps and does not reuse the old mark', () {
      final r = DelayedTrackRenderer(_geometry);
      final old = _track([_fix(0, 100), _fix(10, 180)]);
      var now = _t0.add(const Duration(seconds: 27)); // render time 15 s: mark 220
      expect(r.render(old, now).progress, closeTo(220, 1e-6));
      // The vehicle's route changed: a new track with one fix on the same
      // trip ID, 100 m behind the old mark. Neither the mark (hold at 220)
      // nor the limiter (3.6 m a frame) may apply.
      final fresh = _track([_fix(30, 120)]);
      now = now.add(frame);
      expect(r.render(fresh, now).progress, closeTo(120, 1e-6));
    });

    test('a track that only drops its oldest fixes is not re-created', () {
      final r = DelayedTrackRenderer(_geometry);
      final full = _track([_fix(0, 100), _fix(10, 180), _fix(20, 260)]);
      var now = _t0.add(const Duration(seconds: 37)); // render time 25 s: 5 s past the last fix
      expect(r.render(full, now).progress, closeTo(300, 1e-6));
      // A fix arrives and the store trims the oldest one: the first fix
      // differs, yet this is the same track, limited as usual.
      final trimmed = _track([_fix(10, 180), _fix(20, 260), _fix(30, 1000)]);
      now = now.add(frame);
      expect(r.render(trimmed, now).progress, closeTo(300 + 3.6, 1e-6));
    });

    group('marks are scoped to their shape', () {
      final repo = outAndBackRepo();
      final points = [
        for (final p in outAndBackPoints()) ShapePoint(shapeId: 'other', lat: p.lat, lon: p.lon, sequence: p.sequence),
      ];
      repo.shapesById['other'] = points;
      repo.shapeCumulativeDistances['other'] = cumulativeFor(points);
      final geometry2 = RouteGeometry(repo);

      // A fix with no trip ID on [shape].
      TrackFix onShape(String shape, int s, double progress, {String? trip}) {
        final pose = geometry2.poseAt(shape, progress)!;
        return TrackFix(
          gpsTime: _t0.add(Duration(seconds: s)),
          fetchTime: _t0.add(Duration(seconds: s + 1)),
          lat: pose.lat, lon: pose.lon, heading: pose.heading, speedKmh: 30,
          tripId: trip, shapeId: shape, progress: progress,
          snappedLat: pose.lat, snappedLon: pose.lon,
        );
      }

      test('a bus that changes shape is not held at the old shape\'s progress', () {
        final r = DelayedTrackRenderer(geometry2);
        final onFirst = _track([onShape(outAndBackShapeId, 0, 1400), onShape(outAndBackShapeId, 10, 1500)]);
        expect(r.render(onFirst, _t0.add(const Duration(seconds: 27))).progress, closeTo(1550, 1e-6));
        // The same track now carries fixes on another shape (null trip IDs
        // match, so only the shape tells the two apart). Render time 18.x s
        // is inside the new shape's pair, at about 150 m.
        final onSecond = _track([
          onShape(outAndBackShapeId, 0, 1400),
          onShape(outAndBackShapeId, 10, 1500),
          onShape('other', 12, 100),
          onShape('other', 22, 180),
        ]);
        final bus = r.render(onSecond, _t0.add(const Duration(seconds: 30)));
        expect(bus.shapeId, 'other');
        expect(bus.progress, inInclusiveRange(100, 180));
      });

      test('a glide does not start from an anchor on another shape', () {
        final r = DelayedTrackRenderer(geometry2);
        final onFirst = _track([onShape(outAndBackShapeId, 0, 1400), onShape(outAndBackShapeId, 10, 1500)]);
        expect(r.render(onFirst, _t0.add(const Duration(seconds: 27))).progress, closeTo(1550, 1e-6));
        // A pair across a trip change on the other shape: a straight line
        // from its first fix (1000 m), not from the old shape's 1550 m.
        final changed = _track([
          onShape(outAndBackShapeId, 0, 1400),
          onShape(outAndBackShapeId, 10, 1500),
          onShape('other', 12, 1000),
          onShape('other', 22, 1100, trip: 'next-trip'),
        ]);
        final bus = r.render(changed, _t0.add(const Duration(seconds: 30))); // render time 18 s: 60% along the pair
        final a = geometry2.poseAt('other', 1000)!;
        final b = geometry2.poseAt('other', 1100)!;
        final wantLat = a.lat + (b.lat - a.lat) * 0.6;
        final wantLon = a.lon + (b.lon - a.lon) * 0.6;
        expect(NearestStopService.haversineDistance(bus.lat, bus.lon, wantLat, wantLon), lessThan(1));
      });
    });
  });

  group('3b-4: a step along the shape must fit the map distance', () {
    // On the out-and-back shape (far end at about 1015 m), 700 m outbound
    // and 1300 m on the return leg are under 40 m apart on the map but 600 m
    // apart along the shape.
    test('a pair whose progress jumps far more than the bus moved glides across the map', () {
      final r = DelayedTrackRenderer(_geometry);
      final track = _track([_fix(0, 700), _fix(10, 1300)]);
      final bus = r.render(track, _t0.add(const Duration(seconds: 17))); // render time 5 s
      final from = _geometry.poseAt(outAndBackShapeId, 700)!;
      final to = _geometry.poseAt(outAndBackShapeId, 1300)!;
      expect(NearestStopService.haversineDistance(from.lat, from.lon, to.lat, to.lon), lessThan(40));
      expect(bus.progress, isNull);
      // Halfway along the straight line, not out at the far end.
      expect(NearestStopService.haversineDistance(bus.lat, bus.lon, (from.lat + to.lat) / 2, (from.lon + to.lon) / 2), lessThan(1));
    });

    test('a plausible pair still runs along the shape', () {
      final r = DelayedTrackRenderer(_geometry);
      // 900 -> 1100 round the far end: 200 m along, 8 m apart, within the
      // 200 m slack.
      final bus = r.render(_track([_fix(0, 900), _fix(10, 1100)]), _t0.add(const Duration(seconds: 17)));
      expect(bus.progress, closeTo(1000, 1));
    });

    test('the limiter does not walk round a spur to reach a target 50 m away', () {
      final r = DelayedTrackRenderer(_geometry);
      final before = _track([_fix(0, 690), _fix(10, 700)]);
      expect(r.render(before, _t0.add(const Duration(seconds: 22))).progress, closeTo(700, 1e-6));
      // 2 s later render time is at the 1290 fix: a target on the shape,
      // 590 m ahead along it but about 50 m away on the map, inside the 60 m
      // the limiter allows in 2 s.
      final after = _track([_fix(0, 690), _fix(10, 700), _fix(12, 1290), _fix(22, 1350)]);
      final bus = r.render(after, _t0.add(const Duration(seconds: 24)));
      final target = _geometry.poseAt(outAndBackShapeId, 1290)!;
      expect(NearestStopService.haversineDistance(bus.lat, bus.lon, target.lat, target.lon), lessThan(1));
    });
  });
}
