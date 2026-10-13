import 'dart:math' as math;

import 'package:busboard_nl/ui/kit/route_palette.dart';
import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// OKLab (Björn Ottosson, 2020) of an sRGB colour.
List<double> oklab(Color c) {
  double lin(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r), g = lin(c.g), b = lin(c.b);
  double cbrt(double x) => math.pow(x, 1 / 3).toDouble();
  final l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  ];
}

/// Euclidean distance in OKLab.
double deltaE(Color a, Color b) {
  final x = oklab(a), y = oklab(b);
  return math.sqrt(math.pow(x[0] - y[0], 2) + math.pow(x[1] - y[1], 2) + math.pow(x[2] - y[2], 2));
}

void main() {
  const metrobusRoutes = [1, 2, 3, 6, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 20, 21, 22, 23, 24, 26, 29, 30];

  test('the OKLab helper matches known values', () {
    expect(deltaE(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)), 0);
    expect(oklab(const Color(0xFFFFFFFF))[0], closeTo(1.0, 0.001));
    expect(deltaE(const Color(0xFF000000), const Color(0xFFFFFFFF)), closeTo(1.0, 0.001));
  });

  test('no route line sits within ΔE 0.08 of brand, live, accent or warn, in either mode (spec §2.3)', () {
    for (final c in [BBColors.light, BBColors.dark]) {
      for (final (uiName, ui) in [('brand', c.brand), ('live', c.live), ('accent', c.accent), ('warn', c.warnInk)]) {
        for (final hue in RouteHue.values) {
          expect(deltaE(hue.line, ui), greaterThanOrEqualTo(0.08),
              reason: '${hue.name} line is ${deltaE(hue.line, ui).toStringAsFixed(3)} from $uiName');
        }
      }
    }
  });

  test('route lines stay apart from each other (ΔE ≥ 0.09)', () {
    for (var i = 0; i < RouteHue.values.length; i++) {
      for (var j = i + 1; j < RouteHue.values.length; j++) {
        final a = RouteHue.values[i], b = RouteHue.values[j];
        expect(deltaE(a.line, b.line), greaterThanOrEqualTo(0.09), reason: '${a.name} vs ${b.name}');
      }
    }
  });

  test('route number text is readable (4.5:1) on every fill in both modes', () {
    for (final hue in RouteHue.values) {
      for (final b in Brightness.values) {
        expect(contrast(RoutePalette.ink, hue.fillFor(b)), greaterThanOrEqualTo(4.5), reason: '${hue.name} $b');
      }
    }
  });

  test('badge ink is the app ink', () {
    expect(RoutePalette.ink, BBColors.light.ink);
  });

  test('every current Metrobus route has a hand-assigned hue', () {
    for (final r in metrobusRoutes) {
      expect(RoutePalette.assigned.containsKey(r), isTrue, reason: 'route $r');
    }
  });

  test('route 10 and route 23 moved off the UI greens', () {
    expect(RoutePalette.of(10), RouteHue.ocean);
    expect(RoutePalette.of(23), RouteHue.olive);
    expect(RoutePalette.of(29), RouteHue.sky);
    expect(RoutePalette.of(16), RouteHue.yellow);
  });

  test('routes that share stops keep different hues: the assignment table is unchanged', () {
    // Hand-assigned from GTFS stop overlap (spec §4.2 of the Harbour redesign). Only the hue
    // names green → ocean and lime → olive changed.
    expect(RoutePalette.assigned, const {
      1: RouteHue.orange, 2: RouteHue.red, 3: RouteHue.yellow, 6: RouteHue.teal, 9: RouteHue.teal,
      10: RouteHue.ocean, 11: RouteHue.teal, 12: RouteHue.pink, 13: RouteHue.indigo, 14: RouteHue.red,
      15: RouteHue.lilac, 16: RouteHue.yellow, 18: RouteHue.lilac, 19: RouteHue.sky, 20: RouteHue.red,
      21: RouteHue.olive, 22: RouteHue.ocean, 23: RouteHue.olive, 24: RouteHue.orange, 26: RouteHue.pink,
      29: RouteHue.sky, 30: RouteHue.orange,
    });
  });

  test('hue positions are unchanged, so fallback hues for new routes do not move', () {
    expect(RouteHue.values.map((h) => h.name).toList(),
        ['red', 'orange', 'yellow', 'olive', 'ocean', 'teal', 'sky', 'indigo', 'lilac', 'pink']);
  });

  test('unknown, zero and negative route numbers are stable and do not throw', () {
    for (final r in [0, -5, 99, 1000]) {
      expect(RoutePalette.of(r), RoutePalette.of(r));
      expect(RouteHue.values, contains(RoutePalette.of(r)));
    }
    expect(RoutePalette.of(99), RouteHue.values[99 % RouteHue.values.length]);
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
