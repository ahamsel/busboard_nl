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

/// The neutrality rule (spec 2026-10-14 §2.1): a plain grey, with no hue tint, is at most this far from grey in OKLCH.
const neutralChroma = 0.015;

/// Whether [c] counts as a neutral grey. The token test and the old-values test both go through this.
bool isNeutral(Color c) => chroma(c) <= neutralChroma;

void main() {
  for (final (name, c) in [('light', BBColors.light), ('dark', BBColors.dark)]) {
    group('WCAG AA ($name, spec 2026-10-14 §2.1)', () {
      final pairs = <(String, Color, Color, double)>[
        // Body text (4.5:1) on every surface it can sit on.
        for (final (sName, s) in [('bg', c.bg), ('surface', c.surface), ('surfaceSunken', c.surfaceSunken)]) ...[
          ('ink/$sName', c.ink, s, 4.5),
          ('muted/$sName', c.muted, s, 4.5),
          ('brandInk/$sName', c.brandInk, s, 4.5),
          ('liveInk/$sName', c.liveInk, s, 4.5),
        ],
        ('brandInk/brandSoft', c.brandInk, c.brandSoft, 4.5),
        ('liveInk/liveSoft', c.liveInk, c.liveSoft, 4.5),
        ('ink/brandSoft (selected row)', c.ink, c.brandSoft, 4.5),
        ('ink/liveSoft', c.ink, c.liveSoft, 4.5),
        ('warnInk/warnBg', c.warnInk, c.warnBg, 4.5),
        ('dangerInk/dangerBg', c.dangerInk, c.dangerBg, 4.5),
        ('onBrand/brand (primary buttons, selected chips)', c.onBrand, c.brand, 4.5),
        ('surface on dangerInk (nav badge)', c.surface, c.dangerInk, 4.5),
        ('bg on ink (toast)', c.bg, c.ink, 4.5),
        // Non-text UI and large text (3:1).
        ('brand/surface (filled buttons on a sheet)', c.brand, c.surface, 3.0),
        ('brand/surfaceSunken (selected segment border, WCAG 1.4.11)', c.brand, c.surfaceSunken, 3.0),
        ('muted/bg (off switch outline and thumb)', c.muted, c.bg, 3.0),
        ('muted/surface (off switch outline and thumb)', c.muted, c.surface, 3.0),
        ('handle/surface (the grab handle, a control)', c.handle, c.surface, 3.0),
        ('soon/surface (large minutes)', c.soon, c.surface, 3.0),
        ('soon/bg (large minutes)', c.soon, c.bg, 3.0),
      ];
      for (final (label, fg, bg, min) in pairs) {
        test(label, () {
          expect(contrast(fg, bg), greaterThanOrEqualTo(min),
              reason: '$label is ${contrast(fg, bg).toStringAsFixed(2)}:1, needs $min:1');
        });
      }

      // Placeholders are not text: they only need to stay visible on the card they sit in.
      test('skeleton blocks stay visible on surface', () {
        expect(contrast(c.skeleton, c.surface), greaterThanOrEqualTo(name == 'dark' ? 1.3 : 1.2));
      });

      // Neutral greys (spec §2.1): no hue tint. Measured as OKLCH chroma, which stays meaningful near white and
      // black (HSL saturation does not: #F4F5F7 is 16 % "saturated" yet reads as a plain grey).
      test('every neutral token is a plain grey (OKLCH chroma <= 0.015)', () {
        for (final (tName, color) in [
          ('bg', c.bg),
          ('surface', c.surface),
          ('surfaceSunken', c.surfaceSunken),
          ('skeleton', c.skeleton),
          ('line', c.line),
          ('handle', c.handle),
          ('ink', c.ink),
          ('muted', c.muted),
        ]) {
          expect(isNeutral(color), isTrue, reason: '$name $tName is tinted (${chroma(color)})');
        }
      });

      test('dark layers get lighter the higher they sit', () {
        if (name == 'light') return;
        double l(Color x) => x.computeLuminance();
        expect(l(c.surfaceSunken), lessThan(l(c.surface)));
        expect(l(c.bg), lessThan(l(c.surface)));
      });
    });
  }

  test('the old cream, navy and blue-grey tints fail the neutrality check', () {
    // The same predicate the tokens must pass: the 1.4.1 values must not.
    for (final (what, old) in [
      ('light surfaceSunken (cream)', const Color(0xFFEFE7DA)),
      ('light line (cream)', const Color(0xFFECE4D8)),
      ('light ink (navy)', const Color(0xFF1C2A3A)),
      ('light muted (blue-grey)', const Color(0xFF5A6674)),
      ('dark bg (navy)', const Color(0xFF0F1720)),
      ('dark surface (navy)', const Color(0xFF18222E)),
      ('dark muted (blue-grey)', const Color(0xFF8E9AA8)),
    ]) {
      expect(isNeutral(old), isFalse, reason: 'the old $what is tinted (${chroma(old)})');
    }
    // The old light bg and dark ink are only faintly cream (chroma 0.012 and 0.013), inside the 0.015 limit, so the
    // predicate cannot catch them. They are still far more tinted than the greys that replaced them.
    expect(chroma(const Color(0xFFF7F2EA)), greaterThan(3 * chroma(BBColors.light.bg)), reason: 'the old light bg');
    expect(chroma(const Color(0xFFF2EDE4)), greaterThan(3 * chroma(BBColors.dark.ink)), reason: 'the old dark ink');
  });

  test('the neutrality check accepts greys and rejects tints', () {
    for (final grey in [const Color(0xFF000000), const Color(0xFFFFFFFF), const Color(0xFF808080), const Color(0xFFF4F5F7)]) {
      expect(isNeutral(grey), isTrue, reason: '$grey');
    }
    for (final tint in [const Color(0xFFFF0000), const Color(0xFF1272C9), const Color(0xFF45D695)]) {
      expect(isNeutral(tint), isFalse, reason: '$tint');
    }
  });

  test('primary buttons: blue with white text in light, dark text in dark (spec 2026-10-14 §2.2)', () {
    expect(BBColors.light.onBrand, const Color(0xFFFFFFFF));
    expect(BBColors.dark.onBrand.computeLuminance(), lessThan(BBColors.dark.brand.computeLuminance()));
    expect(contrast(BBColors.light.onBrand, BBColors.light.brand), closeTo(4.91, 0.01));
    expect(contrast(BBColors.dark.onBrand, BBColors.dark.brand), closeTo(6.18, 0.01));
  });

  test('spec 2026-10-14 §2.2 values', () {
    const l = BBColors.light;
    const d = BBColors.dark;
    expect(l.bg, const Color(0xFFF4F5F7));
    expect(l.surface, const Color(0xFFFFFFFF));
    expect(l.surfaceSunken, const Color(0xFFEEF0F2));
    expect(l.skeleton, const Color(0xFFE6E8EB));
    expect(l.line, const Color(0xFFE3E5E8));
    expect(l.ink, const Color(0xFF16181C));
    expect(l.muted, const Color(0xFF5F646C));
    expect(l.brand, const Color(0xFF1272C9));
    expect(l.onBrand, const Color(0xFFFFFFFF));
    expect(l.brandInk, const Color(0xFF0D5DA6));
    expect(l.brandSoft, const Color(0xFFE3EEFA));
    expect(d.bg, const Color(0xFF121316));
    expect(d.surface, const Color(0xFF1F2024));
    expect(d.surfaceSunken, const Color(0xFF18191C));
    expect(d.skeleton, const Color(0xFF33353B));
    expect(d.line, const Color(0xFF3A3D44));
    expect(d.ink, const Color(0xFFF2F3F5));
    expect(d.muted, const Color(0xFFA3A7AF));
    expect(d.brand, const Color(0xFF5EA2F0));
    expect(d.onBrand, const Color(0xFF08203A));
    expect(d.brandInk, const Color(0xFF8CC0F7));
    expect(d.brandSoft, const Color(0xFF16304A));
  });

  test('the grab handle grey: 3.09:1 on white, 3.38:1 on the dark sheet', () {
    expect(BBColors.light.handle, const Color(0xFF8E939B));
    expect(BBColors.dark.handle, const Color(0xFF6E727B));
    expect(contrast(BBColors.light.handle, BBColors.light.surface), closeTo(3.09, 0.01));
    expect(contrast(BBColors.dark.handle, BBColors.dark.surface), closeTo(3.38, 0.01));
    expect(BBColors.light.lerp(BBColors.dark, 1).handle, BBColors.dark.handle);
  });

  test('the status colours are unchanged from 1.4.1', () {
    const l = BBColors.light;
    const d = BBColors.dark;
    expect([l.live, l.liveInk, l.liveSoft, l.soon, l.warnBg, l.warnInk, l.dangerBg, l.dangerInk], const [
      Color(0xFF2BA36B), Color(0xFF1B7048), Color(0xFFDDF1E6), Color(0xFFD9480F),
      Color(0xFFFDEBD3), Color(0xFF8A4B08), Color(0xFFFBD9D6), Color(0xFF9B1C1C),
    ]);
    expect([d.live, d.liveInk, d.liveSoft, d.soon, d.warnBg, d.warnInk, d.dangerBg, d.dangerInk], const [
      Color(0xFF4CC38A), Color(0xFF4CC38A), Color(0xFF16332A), Color(0xFFFF8A5B),
      Color(0xFF3A2A14), Color(0xFFF5C27A), Color(0xFF3A1A1A), Color(0xFFF5A3A3),
    ]);
  });

  test('lerp carries every token', () {
    final end = BBColors.light.lerp(BBColors.dark, 1);
    expect(end.bg, BBColors.dark.bg);
    expect(end.line, BBColors.dark.line);
    expect(end.handle, BBColors.dark.handle);
    expect(end.brandSoft, BBColors.dark.brandSoft);
  });

  test('no colour token, scrim or shadow in lib/ keeps the old navy ink tint', () {
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart'))
          for (final (i, line) in f.readAsLinesSync().indexed)
            if (RegExp(r'1C2A3A|F7F2EA|\baccent(Soft)?\b', caseSensitive: false).hasMatch(line)) '${f.path}:${i + 1}: $line',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
