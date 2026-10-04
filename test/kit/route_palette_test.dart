import 'dart:math' as math;

import 'package:busboard_nl/ui/kit/route_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const metrobusRoutes = [1, 2, 3, 6, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 20, 21, 22, 23, 24, 26, 29, 30];

  test('every current Metrobus route has a hand-assigned hue', () {
    for (final r in metrobusRoutes) {
      expect(RoutePalette.assigned.containsKey(r), isTrue, reason: 'route $r');
    }
  });

  test('assignments match the spec table', () {
    expect(RoutePalette.of(29), RouteHue.sky);
    expect(RoutePalette.of(10), RouteHue.green);
    expect(RoutePalette.of(16), RouteHue.yellow);
    expect(RoutePalette.of(23), RouteHue.lime);
  });

  test('unknown, zero and negative route numbers are stable and do not throw', () {
    for (final r in [0, -5, 99, 1000]) {
      expect(RoutePalette.of(r), RoutePalette.of(r));
      expect(RouteHue.values, contains(RoutePalette.of(r)));
    }
    expect(RoutePalette.of(99), RouteHue.values[99 % RouteHue.values.length]);
  });

  test('route number text is readable on every fill in both modes', () {
    for (final hue in RouteHue.values) {
      for (final b in Brightness.values) {
        expect(contrast(RoutePalette.ink, hue.fillFor(b)), greaterThanOrEqualTo(4.5),
            reason: '${hue.name} $b');
      }
    }
  });

  test('fillFor picks the dark variant in dark mode', () {
    expect(RouteHue.red.fillFor(Brightness.light), RouteHue.red.fill);
    expect(RouteHue.red.fillFor(Brightness.dark), RouteHue.red.fillDark);
  });

  test('ofName: numeric names use the number, others hash stably', () {
    expect(RoutePalette.ofName('29'), RoutePalette.of(29));
    expect(RoutePalette.ofName('10'), RoutePalette.of(10));
    expect(RoutePalette.ofName('10A'), RoutePalette.ofName('10A'));
    expect(RouteHue.values, contains(RoutePalette.ofName('10A')));
    // Letter-suffixed or lettered routes no longer all collapse to hue 0.
    final names = ['10A', '10B', '12A', 'X1', 'N2', 'Express', 'A', 'B', 'C'];
    final hues = {for (final n in names) RoutePalette.ofName(n)};
    expect(hues.length, greaterThan(1));
    expect(RoutePalette.ofName('10A'), isNot(RoutePalette.ofName('10')));
  });

  test('ofName: empty and odd names do not throw', () {
    expect(RouteHue.values, contains(RoutePalette.ofName('')));
    expect(RoutePalette.ofName(''), RoutePalette.ofName(''));
    expect(RouteHue.values, contains(RoutePalette.ofName('  ')));
    expect(RouteHue.values, contains(RoutePalette.ofName('-5')));
  });
}
