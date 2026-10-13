import 'dart:math' as math;

import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, t) in [('light', BBTokens.light), ('dark', BBTokens.dark)]) {
    final c = t.colors;
    group('WCAG AA ($name, spec §2.1)', () {
      final pairs = <(String, Color, Color, double)>[
        // Body text (4.5:1) on every surface it can sit on.
        for (final (sName, s) in [
          ('bg', c.bg),
          ('surface', c.surface),
          ('surfaceRaised', c.surfaceRaised),
          ('surfaceField', c.surfaceField),
          ('surfaceFloat', c.surfaceFloat),
          ('surfaceSunken', c.surfaceSunken),
        ]) ...[
          ('ink/$sName', c.ink, s, 4.5),
          ('muted/$sName', c.muted, s, 4.5),
        ],
        for (final (sName, s) in [
          ('bg', c.bg),
          ('surface', c.surface),
          ('surfaceRaised', c.surfaceRaised),
          ('surfaceField', c.surfaceField),
          ('brandSoft', c.brandSoft),
        ])
          ('brandInk/$sName', c.brandInk, s, 4.5),
        for (final (sName, s) in [
          ('bg', c.bg),
          ('surface', c.surface),
          ('surfaceRaised', c.surfaceRaised),
          ('liveSoft', c.liveSoft),
        ])
          ('liveInk/$sName', c.liveInk, s, 4.5),
        ('ink/brandSoft (selected row)', c.ink, c.brandSoft, 4.5),
        ('ink/accentSoft', c.ink, c.accentSoft, 4.5),
        ('ink/liveSoft', c.ink, c.liveSoft, 4.5),
        ('warnInk/warnBg', c.warnInk, c.warnBg, 4.5),
        ('dangerInk/dangerBg', c.dangerInk, c.dangerBg, 4.5),
        ('onBrand/brand (buttons, selected chips)', c.onBrand, c.brand, 4.5),
        ('surface on dangerInk (alert count badge)', c.surface, c.dangerInk, 4.5),
        ('bg on ink (toast)', c.bg, c.ink, 4.5),
        // Non-text UI and large text (3:1).
        ('accent/surface (saved-place icons)', c.accent, c.surface, 3.0),
        ('accent/surfaceRaised', c.accent, c.surfaceRaised, 3.0),
        ('accent/surfaceField', c.accent, c.surfaceField, 3.0),
        ('accent/accentSoft', c.accent, c.accentSoft, 3.0),
        ('soon/surface (large minutes)', c.soon, c.surface, 3.0),
        ('soon/surfaceRaised (large minutes)', c.soon, c.surfaceRaised, 3.0),
        ('soon/bg (large minutes)', c.soon, c.bg, 3.0),
        ('muted/surface (off switch outline and thumb)', c.muted, c.surface, 3.0),
        // Focus ring and selected-segment edge (spec §2.2, WCAG 1.4.11).
        for (final (sName, s) in [
          ('surfaceField', c.surfaceField),
          ('surface', c.surface),
          ('surfaceRaised', c.surfaceRaised),
          ('bg', c.bg),
          ('brandSoft', c.brandSoft),
        ])
          ('focus ring (brandEdge)/$sName', t.brandEdge, s, 3.0),
      ];
      for (final (label, fg, bg, min) in pairs) {
        test(label, () {
          expect(contrast(fg, bg), greaterThanOrEqualTo(min),
              reason: '$label is ${contrast(fg, bg).toStringAsFixed(2)}:1, needs $min:1');
        });
      }

      // Placeholders are not text: they only need to stay visible on the card they sit in.
      test('skeleton blocks stay visible on surface and surfaceRaised', () {
        expect(contrast(c.skeleton, c.surface), greaterThanOrEqualTo(1.15));
        expect(contrast(c.skeleton, c.surfaceRaised), greaterThanOrEqualTo(1.15));
      });
    });
  }

  test('bright green fails 3:1 on white, so light focus rings use brandInk (spec §2.2)', () {
    expect(contrast(BBColors.light.brand, BBColors.light.surfaceField), lessThan(3.0));
    expect(BBTokens.light.brandEdge, BBColors.light.brandInk);
    expect(BBTokens.dark.brandEdge, BBColors.dark.brand);
  });

  test('spec §2.1 values', () {
    const l = BBColors.light;
    const d = BBColors.dark;
    expect(l.brand, const Color(0xFF3FAE4F));
    expect(l.onBrand, const Color(0xFF0F2414));
    expect(l.brandInk, const Color(0xFF237A33));
    expect(d.bg, const Color(0xFF0E1220));
    expect(d.surface, const Color(0xFF1D2540));
    expect(d.surfaceRaised, const Color(0xFF252E4C));
    expect(d.surfaceField, const Color(0xFF283152));
    expect(d.surfaceFloat, const Color(0xFF262F4D));
    expect(d.highlight, const Color(0x1AFFFFFF));
    expect(l.highlight, const Color(0x00000000));
    expect(l.accent, const Color(0xFF5B4FD1));
    expect(d.accentSoft, const Color(0xFF26224A));
  });

  test('lerp carries the new tokens', () {
    final mid = BBColors.light.lerp(BBColors.dark, 1);
    expect(mid.surfaceRaised, BBColors.dark.surfaceRaised);
    expect(mid.surfaceField, BBColors.dark.surfaceField);
    expect(mid.surfaceFloat, BBColors.dark.surfaceFloat);
    expect(mid.highlight, BBColors.dark.highlight);
    expect(mid.accent, BBColors.dark.accent);
    expect(mid.accentSoft, BBColors.dark.accentSoft);
  });
}
