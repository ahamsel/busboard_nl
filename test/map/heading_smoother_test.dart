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
}
