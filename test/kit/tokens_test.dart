import 'dart:math' as math;

import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, c) in [('light', BBColors.light), ('dark', BBColors.dark)]) {
    group('WCAG AA contrast ($name)', () {
      final pairs = <(String, Color, Color, double)>[
        ('ink/bg', c.ink, c.bg, 4.5),
        ('ink/surface', c.ink, c.surface, 4.5),
        ('ink/surfaceSunken', c.ink, c.surfaceSunken, 4.5),
        ('muted/bg', c.muted, c.bg, 4.5),
        ('muted/surface', c.muted, c.surface, 4.5),
        ('muted/surfaceSunken', c.muted, c.surfaceSunken, 4.5),
        ('brandInk/bg', c.brandInk, c.bg, 4.5),
        ('brandInk/surface', c.brandInk, c.surface, 4.5),
        ('brandInk/brandSoft', c.brandInk, c.brandSoft, 4.5),
        ('onBrand/brand', c.onBrand, c.brand, 4.5),
        ('liveInk/bg', c.liveInk, c.bg, 4.5),
        ('liveInk/surface', c.liveInk, c.surface, 4.5),
        ('liveInk/liveSoft', c.liveInk, c.liveSoft, 4.5),
        ('warnInk/warnBg', c.warnInk, c.warnBg, 4.5),
        ('dangerInk/dangerBg', c.dangerInk, c.dangerBg, 4.5),
        ('surface on dangerInk (nav badge)', c.surface, c.dangerInk, 4.5),
        ('brand/surfaceSunken (selected segment border, WCAG 1.4.11)', c.brand, c.surfaceSunken, 3.0),
        ('muted/bg (off switch outline and thumb)', c.muted, c.bg, 3.0),
        ('muted/surface (off switch outline and thumb)', c.muted, c.surface, 3.0),
        ('soon/surface (large minutes)', c.soon, c.surface, 3.0),
        ('soon/bg (large minutes)', c.soon, c.bg, 3.0),
        ('skeleton/surface (placeholder blocks stay visible)', c.skeleton, c.surface, name == 'dark' ? 1.35 : 1.2),
      ];
      for (final (label, fg, bg, min) in pairs) {
        test(label, () {
          expect(contrast(fg, bg), greaterThanOrEqualTo(min),
              reason: '$label is ${contrast(fg, bg).toStringAsFixed(2)}:1');
        });
      }
    });
  }

  test('text styles use Figtree, no decoration, tabular minutes', () {
    final t = BBText.of(BBColors.light);
    for (final s in [t.display, t.title, t.headline, t.body, t.label, t.caption, t.minutes, t.minutesUnit]) {
      expect(s.fontFamily, BBText.family);
      expect(s.decoration, TextDecoration.none);
    }
    expect(t.minutes.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(t.minutes.fontSize, 26);
    expect(t.minutes.fontWeight, FontWeight.w800);
  });

  testWidgets('BBMotion.of returns zero when animations are disabled', (tester) async {
    late Duration normal;
    late Duration reduced;
    await tester.pumpWidget(Builder(builder: (context) {
      normal = BBMotion.of(context, BBMotion.standard);
      return MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(builder: (inner) {
          reduced = BBMotion.of(inner, BBMotion.standard);
          return const SizedBox();
        }),
      );
    }));
    expect(normal, BBMotion.standard);
    expect(reduced, Duration.zero);
  });

  testWidgets('context.bb resolves the theme extension', (tester) async {
    late BBTokens tokens;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [BBTokens.dark]),
      home: Builder(builder: (context) {
        tokens = context.bb;
        return const SizedBox();
      }),
    ));
    expect(tokens.isDark, isTrue);
    expect(tokens.colors.bg, BBColors.dark.bg);
  });
}
