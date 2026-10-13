import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('durations match spec §3.1', () {
    expect(BBMotion.quick, const Duration(milliseconds: 120));
    expect(BBMotion.standard, const Duration(milliseconds: 220));
    expect(BBMotion.emphasis, const Duration(milliseconds: 360));
    expect(BBMotion.stagger, const Duration(milliseconds: 40));
    expect(BBMotion.staggerMax, 8);
    expect(BBMotion.pulse, const Duration(milliseconds: 1600));
    expect(BBMotion.nowPulse, const Duration(milliseconds: 600));
  });

  test('the emphasis spring: damping ≈ 0.78, stiffness ≈ 260', () {
    final s = BBMotion.emphasisSpring;
    expect(s.stiffness, 260);
    expect(s.mass, 1);
    expect(s.damping / (2 * 16.1245), closeTo(0.78, 0.01)); // ratio = c / (2·√(k·m))
  });

  test('the emphasis curve starts at 0, ends exactly at 1 and overshoots only slightly', () {
    final c = BBMotion.emphasisCurve;
    expect(c.transform(0), 0);
    expect(c.transform(1), 1);
    final samples = [for (var i = 0; i <= 200; i++) c.transform(i / 200)];
    final peak = samples.reduce((a, b) => a > b ? a : b);
    expect(peak, greaterThan(1.0), reason: 'a slight overshoot');
    expect(peak, lessThan(1.05));
    expect(c.transform(0.5), greaterThan(0.85), reason: 'it is mostly there by half time');
    // Continuous at the end: no visible jump into 1.
    expect((samples[199] - samples[200]).abs(), lessThan(0.01));
  });

  testWidgets('Reduce Motion: zero durations, a near-instant critically damped spring', (tester) async {
    late Duration normal, reduced;
    late SpringDescription normalSpring, reducedSpring;
    late bool normalFlag, reducedFlag;
    await tester.pumpWidget(Builder(builder: (context) {
      normal = BBMotion.of(context, BBMotion.emphasis);
      normalSpring = BBMotion.spring(context);
      normalFlag = BBMotion.reduced(context);
      return MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(builder: (inner) {
          reduced = BBMotion.of(inner, BBMotion.emphasis);
          reducedSpring = BBMotion.spring(inner);
          reducedFlag = BBMotion.reduced(inner);
          return const SizedBox();
        }),
      );
    }));
    expect(normal, BBMotion.emphasis);
    expect(reduced, Duration.zero);
    expect(normalFlag, isFalse);
    expect(reducedFlag, isTrue);
    expect(normalSpring, same(BBMotion.emphasisSpring));
    expect(reducedSpring, same(BBMotion.reducedSpring));
    // Critically damped (ratio 1) and settled within 100 ms (spec §8).
    final sim = SpringSimulation(reducedSpring, 0, 1, 0);
    expect(reducedSpring.damping, closeTo(2 * 100, 0.001)); // 2·√(10000·1)
    expect(sim.x(0.1), closeTo(1, 0.001));
  });
}
