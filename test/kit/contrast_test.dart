import 'dart:io';
import 'dart:math' as math;

import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'route_palette_test.dart' show oklab;

/// WCAG 2.x contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// OKLCH chroma: how far [c] is from a pure grey of its lightness (0 for a grey).
double chroma(Color c) {
  final lab = oklab(c);
  return math.sqrt(lab[1] * lab[1] + lab[2] * lab[2]);
}

void main() {
  for (final (name, t) in [('light', BBTokens.light), ('dark', BBTokens.dark)]) {
    final c = t.colors;
    group('WCAG AA ($name, spec 2026-10-14 §2.1)', () {
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
          ('surfaceFloat', c.surfaceFloat),
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
        ('ink/liveSoft', c.ink, c.liveSoft, 4.5),
        ('warnInk/warnBg', c.warnInk, c.warnBg, 4.5),
        ('dangerInk/dangerBg', c.dangerInk, c.dangerBg, 4.5),
        ('onBrand/brand (buttons, selected chips)', c.onBrand, c.brand, 4.5),
        ('surface on dangerInk (alert count badge)', c.surface, c.dangerInk, 4.5),
        ('bg on ink (toast)', c.bg, c.ink, 4.5),
        // Non-text UI and large text (3:1).
        ('brandInk/surface (saved-place icons)', c.brandInk, c.surface, 3.0),
        ('brandInk/surfaceField (quick-pick chip icons)', c.brandInk, c.surfaceField, 3.0),
        ('brandInk/surfaceFloat (chips on the map)', c.brandInk, c.surfaceFloat, 3.0),
        ('brand/surface (filled buttons on a sheet)', c.brand, c.surface, 3.0),
        ('brand/surfaceRaised', c.brand, c.surfaceRaised, 3.0),
        ('warnInk/surface (the alert mark on the stop line)', c.warnInk, c.surface, 3.0),
        ('soon/surface (large minutes)', c.soon, c.surface, 3.0),
        ('soon/surfaceRaised (large minutes)', c.soon, c.surfaceRaised, 3.0),
        ('soon/bg (large minutes)', c.soon, c.bg, 3.0),
        ('muted/surface (off switch outline and thumb)', c.muted, c.surface, 3.0),
        // Focus ring and selected-segment edge (WCAG 1.4.11).
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

      // Neutral greys (spec §2.1): no hue tint. Measured as OKLCH chroma, which stays meaningful near white and
      // black (HSL saturation does not: #F4F5F7 is 16 % "saturated" yet reads as a plain grey).
      test('every neutral token is a plain grey (OKLCH chroma <= 0.015)', () {
        for (final (tName, color) in [
          ('bg', c.bg),
          ('surface', c.surface),
          ('surfaceRaised', c.surfaceRaised),
          ('surfaceField', c.surfaceField),
          ('surfaceFloat', c.surfaceFloat),
          ('surfaceSunken', c.surfaceSunken),
          ('skeleton', c.skeleton),
          ('line', c.line),
          ('ink', c.ink),
          ('muted', c.muted),
          ('highlight', c.highlight.withValues(alpha: 1)),
        ]) {
          expect(chroma(color), lessThanOrEqualTo(0.015), reason: '$name $tName is tinted (${chroma(color)})');
        }
      });

      test('dark layers get lighter the higher they sit', () {
        if (name == 'light') return;
        double l(Color x) => x.computeLuminance();
        expect(l(c.bg), lessThan(l(c.surface)));
        expect(l(c.surface), lessThan(l(c.surfaceRaised)));
        expect(l(c.surfaceRaised), lessThan(l(c.surfaceField)));
        expect(l(c.surface), lessThan(l(c.surfaceFloat)));
      });
    });
  }

  test('the old green and purple tints are gone (they failed the neutrality check)', () {
    expect(chroma(const Color(0xFFF6FAF6)), greaterThan(0.005), reason: 'the old light bg is tinted');
    expect(chroma(const Color(0xFF1D2540)), greaterThan(0.015), reason: 'the old dark surface is tinted');
    expect(chroma(const Color(0xFF5F7366)), greaterThan(0.015), reason: 'the old light muted is tinted');
  });

  test('light focus rings use the deeper brandInk; dark ones the brand', () {
    expect(BBTokens.light.brandEdge, BBColors.light.brandInk);
    expect(BBTokens.dark.brandEdge, BBColors.dark.brand);
  });

  test('spec 2026-10-14 §2.2 values', () {
    const l = BBColors.light;
    const d = BBColors.dark;
    expect(l.bg, const Color(0xFFF4F5F7));
    expect(l.surfaceSunken, const Color(0xFFEEF0F2));
    expect(l.skeleton, const Color(0xFFE6E8EB));
    expect(l.line, const Color(0xFFE3E5E8));
    expect(l.ink, const Color(0xFF16181C));
    expect(l.muted, const Color(0xFF5F646C));
    expect(l.brand, const Color(0xFF1272C9));
    expect(l.onBrand, const Color(0xFFFFFFFF));
    expect(l.brandInk, const Color(0xFF0D5DA6));
    expect(l.brandSoft, const Color(0xFFE3EEFA));
    expect(l.highlight, const Color(0x00000000));
    expect(d.bg, const Color(0xFF121316));
    expect(d.surface, const Color(0xFF1F2024));
    expect(d.surfaceRaised, const Color(0xFF27292E));
    expect(d.surfaceField, const Color(0xFF2B2D32));
    expect(d.surfaceFloat, const Color(0xFF2A2C31));
    expect(d.surfaceSunken, const Color(0xFF18191C));
    expect(d.skeleton, const Color(0xFF33353B));
    expect(d.line, const Color(0xFF3A3D44));
    expect(d.highlight, const Color(0x14FFFFFF));
    expect(d.ink, const Color(0xFFF2F3F5));
    expect(d.muted, const Color(0xFFA3A7AF));
    expect(d.brand, const Color(0xFF5EA2F0));
    expect(d.onBrand, const Color(0xFF08203A));
    expect(d.brandInk, const Color(0xFF8CC0F7));
    expect(d.brandSoft, const Color(0xFF16304A));
  });

  test('the status colours are unchanged', () {
    const l = BBColors.light;
    const d = BBColors.dark;
    expect([l.live, l.liveInk, l.liveSoft, l.soon, l.warnBg, l.warnInk, l.dangerBg, l.dangerInk], const [
      Color(0xFF2FB67C), Color(0xFF1E7A4E), Color(0xFFDFF4EA), Color(0xFFD9480F),
      Color(0xFFFCEFD2), Color(0xFF7A5200), Color(0xFFFBD9D6), Color(0xFF9B1C1C),
    ]);
    expect([d.live, d.liveInk, d.liveSoft, d.soon, d.warnBg, d.warnInk, d.dangerBg, d.dangerInk], const [
      Color(0xFF45D695), Color(0xFF45D695), Color(0xFF123227), Color(0xFFFF8A5B),
      Color(0xFF3A2E12), Color(0xFFF9D58A), Color(0xFF3A1A1A), Color(0xFFF5A3A3),
    ]);
  });

  test('lerp carries every token', () {
    final mid = BBColors.light.lerp(BBColors.dark, 1);
    expect(mid.surfaceRaised, BBColors.dark.surfaceRaised);
    expect(mid.surfaceField, BBColors.dark.surfaceField);
    expect(mid.surfaceFloat, BBColors.dark.surfaceFloat);
    expect(mid.highlight, BBColors.dark.highlight);
    expect(mid.brandSoft, BBColors.dark.brandSoft);
  });

  test('no colour token, scrim or shadow in lib/ keeps the old ink-green tint or the purple accent', () {
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart'))
          for (final (i, line) in f.readAsLinesSync().indexed)
            if (RegExp(r'13261A|\baccent(Soft)?\b', caseSensitive: false).hasMatch(line)) '${f.path}:${i + 1}: $line',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
