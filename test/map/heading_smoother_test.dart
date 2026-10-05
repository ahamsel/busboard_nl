import 'package:busboard_nl/domain/map/heading_smoother.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 5, 12);
DateTime _at(int ms) => _t0.add(Duration(milliseconds: ms));

void main() {
  test('shortestDelta takes the short way round', () {
    expect(HeadingSmoother.shortestDelta(350, 10), 20);
    expect(HeadingSmoother.shortestDelta(10, 350), -20);
    expect(HeadingSmoother.shortestDelta(0, 180), 180);
    expect(HeadingSmoother.shortestDelta(90, 90), 0);
  });

  test('the first frame takes the target', () {
    expect(HeadingSmoother().smooth('a', 270, _t0), 270);
  });

  test('350° → 10° turns through north, never through south', () {
    final s = HeadingSmoother()..smooth('a', 350, _t0);
    for (var ms = 16; ms <= 400; ms += 16) {
      final h = s.smooth('a', 10, _at(ms));
      expect(h < 30 || h > 330, isTrue, reason: 'heading $h at $ms ms');
    }
    expect(s.smooth('a', 10, _at(416)), 10);
  });

  test('turns at most 180° per second', () {
    final s = HeadingSmoother()..smooth('a', 0, _t0);
    expect(s.smooth('a', 90, _at(250)), closeTo(45, 1e-9));
    expect(s.smooth('a', 90, _at(500)), closeTo(90, 1e-9));
  });

  test('snaps after a gap of more than 2 s, and holds at the same time', () {
    final s = HeadingSmoother()..smooth('a', 0, _t0);
    expect(s.smooth('a', 180, _at(2500)), 180);
    expect(s.smooth('a', 0, _at(2500)), 180);
  });

  test('normalises targets and prunes vehicles that are gone', () {
    final s = HeadingSmoother();
    expect(s.smooth('a', -90, _t0), 270);
    expect(s.smooth('b', 450, _t0), 90);
    s.prune({'b'});
    expect(s.smooth('a', 10, _at(16)), 10, reason: 'a was pruned, so this is a first frame');
  });

  // Fix item 1: NaN or infinite target
  test('NaN or infinite targets return previous heading without storing state', () {
    final s = HeadingSmoother();
    s.smooth('a', 90, _t0);

    // Multiple NaN calls return previous heading
    expect(s.smooth('a', double.nan, _at(16)), closeTo(90, 1e-9));
    expect(s.smooth('a', double.nan, _at(32)), closeTo(90, 1e-9));
    expect(s.smooth('a', double.infinity, _at(48)), closeTo(90, 1e-9));

    // After NaN/infinity, next valid target rate-limits (state was preserved)
    // From 90 to 180 at 180°/s, in 64ms: 180 * 0.064 = 11.52° movement
    final h = s.smooth('a', 180, _at(64));
    expect(h, closeTo(90 + 11.52, 1e-6), reason: 'rate-limits from state at t0');

    // double.negativeInfinity also returns previous heading
    expect(s.smooth('a', double.negativeInfinity, _at(80)), closeTo(h, 1e-9));
  });

  test('NaN on first frame returns 0, next valid target snaps', () {
    final s = HeadingSmoother();
    expect(s.smooth('a', double.nan, _t0), 0);
    expect(s.smooth('a', 180, _at(16)), 180, reason: 'snaps as first frame');
  });

  // Fix item 2: Counter-clockwise path
  test('10° → 350° turns counter-clockwise through north', () {
    final s = HeadingSmoother()..smooth('a', 10, _t0);
    for (var ms = 16; ms <= 240; ms += 16) {
      final h = s.smooth('a', 350, _at(ms));
      expect(h < 30 || h > 330, isTrue, reason: 'heading $h at $ms ms');
    }
    expect(s.smooth('a', 350, _at(256)), 350);
  });

  test('0° → 180° maintains consistent direction and reaches target', () {
    final s = HeadingSmoother()..smooth('a', 0, _t0);
    double? prevDelta;
    for (var ms = 16; ms <= 960; ms += 16) {
      final h = s.smooth('a', 180, _at(ms));
      final delta = HeadingSmoother.shortestDelta(0, h);
      if (prevDelta != null) {
        expect(delta.sign, equals(prevDelta.sign), reason: 'direction consistent at $ms ms');
      }
      prevDelta = delta;
    }
    expect(s.smooth('a', 180, _at(1000)), closeTo(180, 1e-9));
  });

  // Fix item 3: Never return 360.0
  test('smooth never returns 360.0', () {
    final s = HeadingSmoother();
    expect(s.smooth('a', -1e-20, _t0), 0.0);
  });

  // Fix item 4: Backward clock
  test('backward time jump snaps to target', () {
    final s = HeadingSmoother()..smooth('a', 0, _t0);
    final backwardTime = _t0.subtract(Duration(hours: 1));
    expect(s.smooth('a', 180, backwardTime), 180);
    expect(s.smooth('a', 90, _at(16)), 90, reason: 'normal rate-limiting resumes');
  });

  // Fix item 5: Coverage
  test('snap after gap exceeds 2 seconds', () {
    final s = HeadingSmoother()..smooth('a', 0, _t0);
    // After 2.1s gap, snap to new target
    expect(s.smooth('a', 180, _t0.add(Duration(seconds: 2, milliseconds: 100))), closeTo(180, 1e-9));
  });

  test('snap-gap boundary at exactly 2 seconds vs 2s+1µs', () {
    // At 10°/s, in 2s we can only move 20°, so we can observe rate-limiting vs snapping
    final s1 = HeadingSmoother(maxDegreesPerSecond: 10)..smooth('a', 0, _t0);
    // At exactly 2s, dt == 2s, don't snap yet (dt !> snapGap)
    // From 0 to 90, delta = 90, step = 10 * 2 = 20, so output = 0 + 20 = 20
    expect(s1.smooth('a', 90, _t0.add(Duration(seconds: 2))), closeTo(20, 1e-9), reason: 'rate-limits at exactly 2s');

    // With a fresh instance, at 2s + 1µs, dt > 2s, snap to target
    final s2 = HeadingSmoother(maxDegreesPerSecond: 10)..smooth('a', 0, _t0);
    expect(s2.smooth('a', 90, _t0.add(Duration(seconds: 2, microseconds: 1))), closeTo(90, 1e-9), reason: 'snaps after 2s + 1µs');
  });

  test('prune keeps other vehicles\' state; kept vehicle rate-limits normally', () {
    final s = HeadingSmoother()
      ..smooth('a', 0, _t0)
      ..smooth('b', 0, _t0);
    s.prune({'b'});
    // After prune, 'a' is gone; 'b' is still tracked
    expect(s.smooth('b', 90, _at(250)), closeTo(45, 1e-9), reason: 'b still rate-limited');
    // 'a' is treated as new vehicle
    expect(s.smooth('a', 180, _at(250)), 180, reason: 'a is first frame after prune');
  });
}
