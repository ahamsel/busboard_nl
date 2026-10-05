import 'dart:math' as math;

import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
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

    test('a backstep of 60-150 m holds, for at most 15 s', () {
      final r = DelayedTrackRenderer(_geometry);
      final track = _track([_fix(0, 300), _fix(10, 500), _fix(20, 380), _fix(70, 380), _fix(80, 400)]);
      // 120 m back: still along the shape, so held, then released after 15 s.
      final frames = sweep(r, track, 10, 40);
      final mark = frames.first.bus.progress!;
      expect(mark, closeTo(500, 1e-6));
      final held = frames.where((f) => (f.bus.progress! - mark).abs() < 1e-6).map((f) => f.at);
      // The hold begins once 60 m are lost (render time 15 s) and lasts 15 s.
      expect(held.last, inInclusiveRange(29.0, 30.2));
      expect(frames.last.bus.progress, lessThan(mark));
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
      final frames = sweep(r, track, 0, 30);
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
      // Median interval 10 s: D = 12 s.
      final steady = _track([_fix(0, 100), _fix(10, 180), _fix(20, 260), _fix(30, 340)]);
      // Median interval 20 s: D = 22 s, clamped to the 20 s maximum.
      final slow = _track([_fix(0, 100), _fix(20, 260), _fix(40, 420), _fix(60, 580)]);
      expect(r.delayFor(steady), const Duration(seconds: 12));
      expect(r.delayFor(slow), const Duration(seconds: 20));
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
      expect(last, closeTo(20, 1e-6)); // reached after 80 s of wall time
      // And back down, at the same pace.
      now = now.add(const Duration(seconds: 10));
      r.render(steady, now);
      expect(r.currentDelayFor('2573')!.inMicroseconds / 1e6, closeTo(19, 1e-6));
    });

    test('two fixes with the same GPS time never divide by zero', () {
      final r = DelayedTrackRenderer(_geometry);
      // The store would drop the duplicate; built directly here.
      final track = _track([_fix(10, 100), _fix(10, 180)]);
      // D = 8 s (median interval 0 + 2 s, clamped up).
      expect(r.render(track, _t0.add(const Duration(seconds: 15))).progress, closeTo(100, 1e-6)); // before
      expect(r.render(track, _t0.add(const Duration(seconds: 18))).progress, closeTo(100, 1e-6)); // at
      final after = r.render(track, _t0.add(const Duration(seconds: 25))).progress!;
      expect(after.isFinite, isTrue);
      expect(after, closeTo(180, 1e-6));
    });
  });
}
