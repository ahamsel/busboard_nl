# Neutral Greys, Harbour Blue, Slim Home Sheet and Follow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give BusBoard NL 1.5.0 neutral grey surfaces with a brighter Harbour blue brand, a slim home bar that leaves the map most of the screen, and a Follow button you can find on live departures.

**Architecture:** Colour still flows from `lib/ui/kit/tokens.dart` (`BBColors`), the route palette (`lib/ui/kit/route_palette.dart`), the map palette (`tool/src/harbour_style.dart`, generated into `assets/map/*.json`) and the brand SVGs (rendered by `tool/brand/render_brand_assets.sh`). The home sheet keeps its one `BBSheet`: on a phone its header becomes the bar (Where to? plus a new `HomeStopLine`), and today's home header moves under it into the body, so the existing header-measuring code (`_scheduleHeaderMeasure` → `peekPx`) makes the bar's height follow its content and the text size. `BBSheet` gains an opt-in button handle and a `nudge`; the home screen's existing map `Listener` gains the tuck-away; `ArrivalRowTile` gains a Follow pill and an explain tap.

**Tech Stack:** Flutter 3.47 / Dart 3.9, flutter_riverpod 3, go_router, maplibre_gl, shared_preferences (`SharedPreferencesAsync`), flutter_test goldens, ImageMagick 7 (`magick`), flutter_launcher_icons, flutter_native_splash.

**Spec:** `docs/superpowers/specs/2026-10-14-neutral-blue-slim-sheet-design.md` (binding). Read it before starting any task.

**Branch:** `claude/visual-refresh-spec` in `/Users/aham/projects/dev/busboard_nl/.claude/worktrees/unified-ui-map-redesign-fc0a89` (HEAD `e404122` when this plan was written). Run every command from that directory.

**Dry run:** every task's code and tests below were applied, in order, to a scratch copy of the repo at `e404122`. After each task `flutter analyze` was clean and the non-golden suite passed; after Task 8 the whole suite passed (1,436 tests, goldens regenerated). Expect only small drift (an extra test that names an old value), not design surprises.

## Global Constraints

- **Accessibility:** WCAG AA everywhere: 4.5:1 for body text; 3:1 for large text (18.66 px bold or 24 px regular and up) and for non-text UI (icons, outlines, focus rings). Every control has a screen-reader label; the screen-reader strings in spec §3.2 and §4 are used exactly as this plan pins them. Nothing overflows at 2× text; light and dark both work.
- **Reduce Motion** (`MediaQuery.disableAnimations`, read through `BBMotion.reduced` / `BBMotion.of`) is respected: the bar hint never plays under it, sheet moves are near-instant (the sheet's 1 ms snap), and loops don't run.
- **No new dependencies.** Everything here uses packages already in `pubspec.yaml`.
- **No Material or Cupertino widgets in screen code.** `test/kit/kit_boundary_test.dart` enforces this for `lib/ui/**` outside `lib/ui/kit/`: import `package:flutter/widgets.dart` and `../kit/kit.dart`, never `material.dart` or `cupertino.dart`.
- **Only real colours carry colour** (spec §2.1): the brand (`#1272C9` light, `#5EA2F0` dark) is a fill with `onBrand` on it; blue text or icons on a surface use `brandInk`; `accent`/`accentSoft` no longer exist; every other surface, line, text, shadow and scrim is a neutral grey or black.
- **Staging:** stage explicit paths only (never `git add -A`, `git add .` or `git commit -a`). Never stage `analysis_options.yaml`, `tool/capture_raw_gtfsrt.dart`, `test/fixtures/timetrack/`, `build/`, `store/marketing/` or `.superpowers/`: they are the developer's local, uncommitted files. Check `git status --short` before every commit.
- **Never use bare `git stash`** (the stash is shared with other worktrees and sessions). To set work aside, make a WIP commit.
- **Commit trailer:** every commit message ends with exactly this line:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- **Devices:** only the iOS simulator **"BusBoard iPhone 17"** (`0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54`). Never run on or install to the developer's iPhone (`00008140-000C49E61482801C`), the Android emulator `emulator-5554` or the Android phone `RFCRA1CK68W`.
- **Goldens fail by design until Task 8.** Tasks 1–7 change pixels, so `test/kit/kit_golden_test.dart` and `test/ui/screen_golden_test.dart` fail until Task 8 regenerates them. Don't update goldens before Task 8. At the end of Tasks 1–7 run:
  `flutter analyze` (expected: `No issues found!`) and
  `flutter test $(find test -name '*_test.dart' ! -name '*golden_test.dart' | sort)` (expected: `All tests passed!`).
- **Known flake:** `test/ui/stop_sheet_test.dart` "once the alert has fired, home stops polling its stop (F4)" failed once under full-suite load in the dry run and passed on every rerun. If it is the only failure, rerun that file alone before suspecting your change.

## Review Focus

Conditions the spec implies but its own test list doesn't name, most likely to bite a rider first. Each has a test in the task named.

1. **Huge text on the narrowest phone** (iOS accessibility sizes go past 3×): the stop line must never overflow; the minutes shrink before they would truncate, and the name gives way first. → Task 4, "at 3x text on 320 pt the line still fits".
2. **A refresh that fails after a good load** (Riverpod keeps the old rows on an error): the stop line must say Offline, not keep showing old minutes as if live. → Task 4, "a refresh that fails after a good load says Offline".
3. **A card that opens at launch (a notification) while the hint's flag is being read:** the card must never be nudged, and the hint must still play once the bar shows. → Task 5, "a card that opens while the flag is read is never lifted".
4. **The tuck-away fighting the sheet's own gestures:** a drag that starts on the sheet is the sheet's, never a map pan; and a two-finger pinch tucks once, not once per finger. → Task 6, "a drag that starts on the sheet is the sheet's own" and "a two-finger pinch lowers the sheet once".
5. **A live row with no usable vehicle number** (live, but `vehicleNumber` null or empty): no Follow pill, and the tap explains instead of following nothing. → Task 7, "scheduled-only and vehicle-less rows follow nothing".

## Spec gaps and ambiguities resolved here

- **Neutrality check (§2.1, §5):** the spec's own neutral values fail "HSL saturation ≤ 8 %" (light `bg` `#F4F5F7` is 15.8 %, `ink` `#16181C` 12 %, `surfaceSunken` 13.3 %, `line` 9.8 %; dark `bg` 10 %, `surfaceRaised` 8.2 %, `ink` 13 %), because HSL saturation blows up near white and black. The spec's colour table wins; the test measures neutrality as **OKLCH chroma ≤ 0.015** instead (the new greys are 0–0.014; the old tinted ones 0.029–0.052).
- **Dark scrim lift:** with the same 60 % black (spec: "same strengths"), a dialog over the new darker neutral sheet is lifted 1.197:1, under the old test's 1.2. The test floor becomes 1.15; the dialog's highlight and shadow carry the edge as before.
- **Map label and building colours** aren't in spec §2.4's table but must go neutral too: light label `#737880`, building `#E4E6E9`; dark label `#80848C`, building `#1E1F23` (labels stay at least 3:1 on the land).
- **Route hues:** the enum value `ocean` is renamed back to `green` with a new line `#0FA23F` (fills unchanged from the old green). Route 22 shared route 10's hue, so it turns green too. `sky` (line `#60B4C9`) and `indigo` (light line `#3C3F90`; dark line unchanged `#5673F0`) failed against the new blue and move just far enough. All other hues are unchanged.
- **Stop line screen-reader strings:** spec §3.2's fragments are completed as: "Your stop, MUN Centre. Route 10 arriving now, live. Open board" (capital R after the full stop); "same words" rows read "Your stop, MUN Centre. No buses for a while. Open board", "… First bus 6:28 AM. Open board", "… Offline, updated 9:42 AM. Open board" (a comma for the visible "·"); loading is exactly "Your stop, MUN Centre. Loading"; an alert inserts "Detour affects this stop." (the alert's effect label) after the stop name.
- **"No buses for a while" vs "First bus":** both mean nothing within the arrivals' three hours. It is "First bus …" when the next departure is the first of its service day at that stop (night, or before service); otherwise "No buses for a while".
- **"Now" in the soon colour:** `soon` on white is 4.30:1, under 4.5 for normal text, so the line's minutes use the 22 pt `title` style (large text, 3:1).
- **What else sits in the bar:** the bar is Where to? and the stop line. Two transient things stay with it: the existing one-time home tip (above Where to?, until dismissed) and an armed arrival alert's strip (F4: it must stay in sight and cancellable with the stop's sheet closed). Saved places, alerts for you, Your stop with Open board and its next buses move under the bar.
- **Tablet panel (§3.7 unchanged):** it keeps today's full header and body; only the phone gets the bar.
- **Handle button:** a full-width 24 pt strip (WCAG 2.2 target size 2.5.8), "Show more" at the bar and "Show less" above it. One stop per tap: bar → half, half → bar, full → half. Expand and Collapse stay as screen-reader actions so full height is reachable without a drag. Cards keep today's adjustable "Map sheet" handle.
- **Tuck-away and follow mode:** never while any bus is followed (including a card opened over the follow card).
- **Follow tip "once the rider follows a bus":** any follow, from anywhere, stores the flag (the home screen marks it when a follow starts).
- **Toast "announced to screen readers":** a live region alone isn't read out by VoiceOver, so `BBToast.show` gains `announce: true`, which also sends a `SemanticsService` announcement.
- **Goldens:** the home's resting golden is renamed `home_peek_*` → `home_bar_*` (its rest is now the bar); there is no separate peek state left to keep.

## File Structure

| File | Responsibility |
|---|---|
| `lib/ui/kit/tokens.dart` (modify) | Neutral `BBColors` and the brighter blue; no `accent`; black scrims and shadows |
| `lib/ui/kit/route_palette.dart`, `bb_route_dots.dart` (modify) | `RouteHue.green` (was `ocean`), retuned `sky` and `indigo`, neutral badge ink |
| `lib/ui/kit/bb_chip.dart`, `bb_sheet.dart`, `bb_segmented.dart`, `bb_switch.dart` (modify) | `brandInk` for chip icons; neutral header shadow; comments; `BBSheet.handleButton`, `handleExtent`, `BBSheetController.nudge` |
| `lib/ui/kit/bb_toast.dart` (modify) | `announce:` for toasts that answer a tap |
| `tool/src/harbour_style.dart`, `assets/map/harbour_{light,dark}.json` (modify, regenerated) | Neutral map palettes |
| `assets/brand/*.svg`, `tool/brand/render_brand_assets.sh`, `pubspec.yaml`, generated `assets/icon/*`, `android/…/res`, `ios/…/Assets.xcassets` (modify) | Blue icon and splash, green and purple houses, centred mark |
| `lib/domain/arrival/first_bus.dart` (create) | `firstBusAfter`: the next departure when it is the first of its service day |
| `lib/state/seen_flags.dart` (create) | `SeenFlagNotifier`, `barHintSeenProvider`, `followTipSeenProvider` (one-time flags in `SharedPreferencesAsync`) |
| `lib/ui/home/home_stop_line.dart` (create) | `StopLineKind`, `StopLineInfo`, `HomeStopLine`: the bar's second row in every state |
| `lib/ui/home/home_sheet.dart`, `sheet_content.dart` (modify) | `HomeSheetContent.bar` / `barBody` for the phone; `header` / `body` stay for the tablet |
| `lib/ui/home/home_screen.dart` (modify) | Phone/tablet header choice, bar handle, the one-time lift, the tuck-away, follow-tip marking |
| `lib/ui/board/arrival_row_tile.dart` (modify) | Follow pill, `onExplain`, the pill's own semantics node |
| `lib/ui/home/follow_tip.dart` (create), `stop_sheet.dart`, `lib/ui/map/stop_card.dart` (modify) | The one-time follow tip; scheduled rows explain themselves |
| `test/…` | One test file per behaviour, named in each task |

---

### Task 1: Neutral colour tokens, the brighter blue, and the route hues that must move with it

The route palette is in this task because `test/kit/route_palette_test.dart` checks every route line against the brand: changing the brand without moving `ocean`, `sky` and `indigo` would leave the suite red.

**Files:**
- Modify: `lib/ui/kit/tokens.dart`
- Modify: `lib/ui/kit/bb_sheet.dart:308` (pinned header shadow)
- Modify: `lib/ui/kit/bb_chip.dart:40`
- Modify: `lib/ui/kit/bb_segmented.dart:54-56`, `lib/ui/kit/bb_switch.dart:55` (comments only)
- Modify: `lib/ui/kit/route_palette.dart`, `lib/ui/kit/bb_route_dots.dart:18`
- Rewrite: `test/kit/contrast_test.dart`
- Modify: `test/kit/scrim_test.dart`, `test/kit/elevation_test.dart`, `test/kit/route_palette_test.dart`, `test/tool/harbour_style_test.dart`
- Modify (rename only): `test/map/marker_images_test.dart`, `test/map/map_layers_test.dart`, `test/map/map_hit_test_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `BBColors` without `accent`/`accentSoft` (constructor, fields and `lerp`). Values per spec §2.2: light `bg #F4F5F7`, `surfaceSunken #EEF0F2`, `skeleton #E6E8EB`, `line #E3E5E8`, `ink #16181C`, `muted #5F646C`, `brand #1272C9`, `onBrand #FFFFFF`, `brandInk #0D5DA6`, `brandSoft #E3EEFA`; dark `bg #121316`, `surface #1F2024`, `surfaceRaised #27292E`, `surfaceField #2B2D32`, `surfaceFloat #2A2C31`, `surfaceSunken #18191C`, `skeleton #33353B`, `line #3A3D44`, `highlight #14FFFFFF`, `ink #F2F3F5`, `muted #A3A7AF`, `brand #5EA2F0`, `onBrand #08203A`, `brandInk #8CC0F7`, `brandSoft #16304A`. Status colours unchanged.
  - `BBScrim.soft = Color(0x33000000)`, `BBScrim.strong = Color(0x66000000)`; light float shadow `0x23000000`, light card shadow `0x15000000`, sheet header shadow `0x1A000000`.
  - `BBTokens.brandEdge`: unchanged (`brandInk` light, `brand` dark).
  - `RouteHue.green` (index 4, was `ocean`): fill `#CFEEDB`, fillDark `#A6E3BF`, line `#0FA23F`. `RouteHue.sky.line == #60B4C9`. `RouteHue.indigo.line == #3C3F90`, `lineDark == #5673F0`. `RoutePalette.ink == Color(0xFF16181C)`. `RoutePalette.assigned[10] == RoutePalette.assigned[22] == RouteHue.green`.
  - `chroma(Color)` in `test/kit/contrast_test.dart` (OKLCH chroma), next to the existing `contrast`.

- [ ] **Step 1: Write the failing tests**

Replace the whole of `test/kit/contrast_test.dart` with:

```dart
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
```

In `test/kit/scrim_test.dart`, replace:

```dart
  test('light keeps the ink-green scrims; dark uses black, heavier', () {
    expect(BBScrim.soft, const Color(0x3313261A));
    expect(BBScrim.strong, const Color(0x6613261A));
```

with:

```dart
  test('scrims are neutral black: light at 20 % and 40 %, dark heavier (spec 2026-10-14 §2.1)', () {
    expect(BBScrim.soft, const Color(0x33000000));
    expect(BBScrim.strong, const Color(0x66000000));
```

and replace:

```dart
  test('dark: a dialog on surface is lifted off the sheet it covers (>= 1.2:1; its top highlight and shadow add the rest)', () {
    final c = BBColors.dark;
    final covered = _over(BBScrim.strongDark, c.surface);
    expect(contrast(c.surface, covered), greaterThanOrEqualTo(1.2));
```

with:

```dart
  test('dark: a dialog on surface is lifted off the sheet it covers (>= 1.15:1; its top highlight and shadow add the rest)', () {
    // The neutral dark surface (#1F2024) is darker than the old navy, so the same 60 % black dims it a little less
    // in ratio (1.197:1); the dialog's 8 % white top highlight and its shadow carry the edge.
    final c = BBColors.dark;
    final covered = _over(BBScrim.strongDark, c.surface);
    expect(contrast(c.surface, covered), greaterThanOrEqualTo(1.15));
```

In `test/kit/elevation_test.dart`, replace:

```dart
    test('light floating layers: white, no border, a soft green-tinted shadow (8–14%)', () {
      final d = BBTokens.light.floating();
      expect(d.color, BBColors.light.surface);
      expect(d.border, isNull);
      final shadow = d.boxShadow!.single;
      expect(shadow.color.withValues(alpha: 1), BBColors.light.ink);
```

with:

```dart
    test('light floating layers: white, no border, a soft neutral black shadow (8–14%)', () {
      final d = BBTokens.light.floating();
      expect(d.color, BBColors.light.surface);
      expect(d.border, isNull);
      final shadow = d.boxShadow!.single;
      expect(shadow.color.withValues(alpha: 1), const Color(0xFF000000));
```

then replace:

```dart
      expect(BBTokens.light.card().boxShadow!.single.color.a, inInclusiveRange(0.08, 0.14));
```

with:

```dart
      expect(BBTokens.light.card().boxShadow!.single.color.a, inInclusiveRange(0.08, 0.14));
      expect(BBTokens.light.card().boxShadow!.single.color.withValues(alpha: 1), const Color(0xFF000000));
```

and replace:

```dart
  test('bright green is a fill only: no icon, text or cursor uses colors.brand (spec §2.1)', () {
```

with:

```dart
  test('the brand is a fill only: no icon, text or cursor uses colors.brand (spec 2026-10-14 §2.1)', () {
```

In `test/kit/route_palette_test.dart`:

1. Replace the test name `'no route line sits within ΔE 0.08 of brand, live, accent or warn (or their inks), in either mode (spec §2.3)'` with `'no route line sits within ΔE 0.08 of brand, live or warn (or their inks), in either mode (spec §2.3)'`, and delete the line `        ('accent', c.accent),` from its list.
2. Replace:

```dart
  test('route 10 and route 23 moved off the UI greens', () {
    expect(RoutePalette.of(10), RouteHue.ocean);
```

with:

```dart
  test('route 10 is green again; route 23 stays olive (spec 2026-10-14 §2.3)', () {
    expect(RoutePalette.of(10), RouteHue.green);
```

3. Replace:

```dart
    // Hand-assigned from GTFS stop overlap (spec §4.2 of the Harbour redesign). Only the hue
    // names green → ocean and lime → olive changed.
```

with:

```dart
    // Hand-assigned from GTFS stop overlap (spec §4.2 of the Harbour redesign). Only the hue
    // names changed over time (lime → olive; green → ocean → green).
```

4. In that same test's map, replace `10: RouteHue.ocean, 11:` with `10: RouteHue.green, 11:` and `22: RouteHue.ocean, 23:` with `22: RouteHue.green, 23:`.
5. Replace `['red', 'orange', 'yellow', 'olive', 'ocean', 'teal', 'sky', 'indigo', 'lilac', 'pink']` with `['red', 'orange', 'yellow', 'olive', 'green', 'teal', 'sky', 'indigo', 'lilac', 'pink']`.
6. Replace:

```dart
  test('badge ink is the app ink', () {
    expect(RoutePalette.ink, BBColors.light.ink);
  });
```

with:

```dart
  test('badge ink is the app ink', () {
    expect(RoutePalette.ink, BBColors.light.ink);
  });

  test('the retuned lines (spec 2026-10-14 §2.3)', () {
    expect(RouteHue.green.line, const Color(0xFF0FA23F));
    expect(RouteHue.sky.line, const Color(0xFF60B4C9));
    expect(RouteHue.indigo.line, const Color(0xFF3C3F90));
    expect(RouteHue.indigo.lineFor(Brightness.dark), const Color(0xFF5673F0));
  });
```

Rename the hue in the map tests (the file contents otherwise stay):

```bash
sed -i '' -e 's/RouteHue\.ocean/RouteHue.green/g' -e "s/'bb-notch-ocean'/'bb-notch-green'/g" \
  test/map/marker_images_test.dart test/map/map_layers_test.dart test/map/map_hit_test_test.dart
grep -rn "RouteHue.ocean\|bb-notch-ocean" test lib
```

Expected: the `grep` prints nothing from `test/`; it still shows `lib/ui/kit/bb_route_dots.dart` (fixed in Step 3).

In `test/tool/harbour_style_test.dart`, the last test checks the old navy's "blue shift", which no neutral grey has. Replace the whole test that starts with `  test('the dark map is a greyer, darker navy than the sheet floating on it (spec §2.4)', () {` (through its closing `  });`, just before the file's final `}`) with:

```dart
  test('the dark map sits a step below the sheet floating on it (spec 2026-10-14 §2.4)', () {
    Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));
    final land = hex(HarbourPalette.dark.land);
    expect(land.computeLuminance(), lessThan(BBColors.dark.surface.computeLuminance()));
  });
```

(Task 2 adds the map's own neutrality test.)

- [ ] **Step 2: Run the tests to see them fail**

Run: `flutter test test/kit/contrast_test.dart test/kit/scrim_test.dart test/kit/elevation_test.dart test/kit/route_palette_test.dart test/map/marker_images_test.dart`
Expected: FAIL. `route_palette_test.dart` and the map tests don't compile (`RouteHue.green` isn't defined); `contrast_test.dart` fails "spec 2026-10-14 §2.2 values", the neutrality check and the `13261A|accent` scan; `scrim_test.dart` and `elevation_test.dart` fail on the ink-green colours.

- [ ] **Step 3: Implement the tokens**

In `lib/ui/kit/tokens.dart`:

1. Replace the class comment:

```dart
/// Colour roles for one brightness (visual refresh spec §2.1: Metrobus green,
/// "Night Bus" dark). Raw colour values live only here and in route_palette.dart.
```

with:

```dart
/// Colour roles for one brightness (spec 2026-10-14 §2: neutral greys and the brightened Harbour blue).
/// Only the brand, routes, live and status states carry colour; everything else is a neutral grey.
/// Raw colour values live only here and in route_palette.dart.
```

2. In the constructor, delete the two lines `    required this.accent,` and `    required this.accentSoft,`.
3. Replace:

```dart
  /// Green text on surfaces.
  final Color brandInk;
  final Color brandSoft;

  /// Secondary accent (indigo): saved-place icons, a few highlights.
  final Color accent;
  final Color accentSoft;
```

with:

```dart
  /// Blue text and icons on surfaces (saved-place icons, quick-pick chips).
  final Color brandInk;
  final Color brandSoft;
```

4. Replace the two constants, from `  static const light = BBColors(` through the `);` that closes `static const dark = BBColors(` (lines 85–139), with:

```dart
  static const light = BBColors(
    bg: Color(0xFFF4F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceField: Color(0xFFFFFFFF),
    surfaceFloat: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEEF0F2),
    skeleton: Color(0xFFE6E8EB),
    line: Color(0xFFE3E5E8),
    highlight: Color(0x00000000),
    ink: Color(0xFF16181C),
    muted: Color(0xFF5F646C),
    brand: Color(0xFF1272C9),
    onBrand: Color(0xFFFFFFFF),
    brandInk: Color(0xFF0D5DA6),
    brandSoft: Color(0xFFE3EEFA),
    live: Color(0xFF2FB67C),
    liveInk: Color(0xFF1E7A4E),
    liveSoft: Color(0xFFDFF4EA),
    soon: Color(0xFFD9480F),
    warnBg: Color(0xFFFCEFD2),
    warnInk: Color(0xFF7A5200),
    dangerBg: Color(0xFFFBD9D6),
    dangerInk: Color(0xFF9B1C1C),
  );

  static const dark = BBColors(
    bg: Color(0xFF121316),
    surface: Color(0xFF1F2024),
    surfaceRaised: Color(0xFF27292E),
    surfaceField: Color(0xFF2B2D32),
    surfaceFloat: Color(0xFF2A2C31),
    surfaceSunken: Color(0xFF18191C),
    skeleton: Color(0xFF33353B),
    line: Color(0xFF3A3D44),
    highlight: Color(0x14FFFFFF),
    ink: Color(0xFFF2F3F5),
    muted: Color(0xFFA3A7AF),
    brand: Color(0xFF5EA2F0),
    onBrand: Color(0xFF08203A),
    brandInk: Color(0xFF8CC0F7),
    brandSoft: Color(0xFF16304A),
    live: Color(0xFF45D695),
    liveInk: Color(0xFF45D695),
    liveSoft: Color(0xFF123227),
    soon: Color(0xFFFF8A5B),
    warnBg: Color(0xFF3A2E12),
    warnInk: Color(0xFFF9D58A),
    dangerBg: Color(0xFF3A1A1A),
    dangerInk: Color(0xFFF5A3A3),
  );
```

5. In `lerp`, delete the two lines `      accent: l(accent, other.accent),` and `      accentSoft: l(accentSoft, other.accentSoft),`.
6. Replace:

```dart
/// Dimmed backdrops behind dialogs and floating cards. Light: ink-tinted. Dark: black, heavier, since dark
/// surfaces are already deep and a faint tint would not lift a card off the sheet under it. Every modal card
/// (dialogs, the picker, the small cards that open over the map) uses [strongOf], so they all dim alike.
abstract final class BBScrim {
  static const Color soft = Color(0x3313261A);
  static const Color strong = Color(0x6613261A);
```

with:

```dart
/// Dimmed backdrops behind dialogs and floating cards: neutral black (spec 2026-10-14 §2.1). Dark is heavier, since
/// dark surfaces are already deep and a faint dim would not lift a card off the sheet under it. Every modal card
/// (dialogs, the picker, the small cards that open over the map) uses [strongOf], so they all dim alike.
abstract final class BBScrim {
  static const Color soft = Color(0x33000000); // black, 20 %
  static const Color strong = Color(0x66000000); // black, 40 %
```

7. Replace:

```dart
  /// Focus rings and selection edges: `brand` in dark; `brandInk` in light, where
  /// bright green on white is under 3:1 (spec §2.2, WCAG 1.4.11).
```

with:

```dart
  /// Focus rings and selection edges: `brand` in dark; the deeper `brandInk` in light, which keeps
  /// every edge well over 3:1 on white and on `brandSoft` (WCAG 1.4.11).
```

8. Replace:

```dart
  /// Dark floating layers: a deep black shadow (spec §2.1, 45–55%). Light: a soft green-tinted one (8–14%).
  List<BoxShadow> get _floatShadow => isDark
      ? const [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8))]
      : const [BoxShadow(color: Color(0x2313261A), blurRadius: 16, offset: Offset(0, 4))];
```

with:

```dart
  /// Dark floating layers: a deep black shadow (45–55%). Light: a soft black one (8–14%). Neutral in both.
  List<BoxShadow> get _floatShadow => isDark
      ? const [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8))]
      : const [BoxShadow(color: Color(0x23000000), blurRadius: 16, offset: Offset(0, 4))];
```

9. Replace:

```dart
  /// A card: `surface` on a page, `surfaceRaised` on a sheet or panel ([raised]). Light: white with
  /// a faint green-tinted shadow. Dark: the top-edge highlight, depth from lightness alone.
```

with:

```dart
  /// A card: `surface` on a page, `surfaceRaised` on a sheet or panel ([raised]). Light: white with
  /// a faint black shadow. Dark: the top-edge highlight, depth from lightness alone.
```

10. In `card(...)`, replace `Color(0x1513261A)` with `Color(0x15000000)`.

In `lib/ui/kit/bb_sheet.dart`, replace `const Color(0x1A13261A)` with `const Color(0x1A000000)`.

In `lib/ui/kit/bb_chip.dart`, replace:

```dart
    final lead = leading ?? (icon == null ? null : Icon(icon, size: 18, color: selected ? fg : bb.colors.accent));
```

with:

```dart
    final lead = leading ?? (icon == null ? null : Icon(icon, size: 18, color: selected ? fg : bb.colors.brandInk));
```

In `lib/ui/kit/bb_segmented.dart`, replace:

```dart
                    // the track, so the edge carries the state (WCAG 1.4.11). brandEdge is brandInk in
                    // light, where bright green on white is under 3:1.
```

with:

```dart
                    // the track, so the edge carries the state (WCAG 1.4.11). brandEdge is brandInk in
                    // light and brand in dark.
```

In `lib/ui/kit/bb_switch.dart`, replace:

```dart
                // On: the brandEdge border, since the bright green fill alone is ~2.85:1 on white.
```

with:

```dart
                // On: the brandEdge border as well, so the edge stays at 3:1 or more in both themes.
```

- [ ] **Step 4: Implement the route hues**

In `lib/ui/kit/route_palette.dart`, replace:

```dart
  // Was green: blended into the brand and live greens (spec §2.3).
  ocean(Color(0xFFB9DDF0), Color(0xFF8FC6E6), Color(0xFF2D7BB2)),
  teal(Color(0xFFC4ECE8), Color(0xFF93DDD6), Color(0xFF1F8F86)),
  sky(Color(0xFFCFE3FA), Color(0xFFA9CDF5), Color(0xFF65ADE0)),
  // Lines moved away from the indigo accent. The dark-map line is lighter (#2E4E99 is 2.2:1 on the dark land) and
  // pushed a little toward violet so it stays clear of ocean.
  indigo(Color(0xFFD6DAFA), Color(0xFFB3BAF5), Color(0xFF2E4E99), Color(0xFF5673F0)),
```

with:

```dart
  // Green again (spec 2026-10-14 §2.3): the brand is blue now, and the old ocean line sat next to it. A purer,
  // yellower green than the live green, so it stays clear of live, liveInk, olive and teal.
  green(Color(0xFFCFEEDB), Color(0xFFA6E3BF), Color(0xFF0FA23F)),
  teal(Color(0xFFC4ECE8), Color(0xFF93DDD6), Color(0xFF1F8F86)),
  // Moved toward cyan, off the dark brand blue (#5EA2F0) and its ink.
  sky(Color(0xFFCFE3FA), Color(0xFFA9CDF5), Color(0xFF60B4C9)),
  // The light line moved toward violet, off the light brandInk (#0D5DA6). The dark-map line stays lighter
  // (#3C3F90 is under 3:1 on the dark land).
  indigo(Color(0xFFD6DAFA), Color(0xFFB3BAF5), Color(0xFF3C3F90), Color(0xFF5673F0)),
```

then replace:

```dart
  /// Text/number colour on every route fill, in both modes.
  static const Color ink = Color(0xFF13261A);
```

with:

```dart
  /// Text/number colour on every route fill, in both modes: the app's light ink.
  static const Color ink = Color(0xFF16181C);
```

and in `assigned`, replace `    10: RouteHue.ocean,` with `    10: RouteHue.green,` and `    22: RouteHue.ocean,` with `    22: RouteHue.green,`.

In `lib/ui/kit/bb_route_dots.dart`, replace `RouteHue.ocean]` with `RouteHue.green]`.

These values were checked with the test's own OKLab ΔE: every line is at least 0.08 from light and dark `brand`, `brandInk`, `live`, `liveInk` and `warnInk` (closest: `indigo`'s dark line to light `brand`, 0.081; `green` to light `live`, 0.085), every pair of lines at least 0.09 apart in both map modes, and each line keeps its contrast on the old and the new map land and roads.

- [ ] **Step 5: Run the tests to see them pass**

Run: `flutter test test/kit/contrast_test.dart test/kit/scrim_test.dart test/kit/elevation_test.dart test/kit/route_palette_test.dart test/tool/harbour_style_test.dart test/map/marker_images_test.dart test/map/map_layers_test.dart test/map/map_hit_test_test.dart`
Expected: PASS.

Run: `grep -rn "13261A\|accent" lib`
Expected: nothing.

- [ ] **Step 6: The whole suite**

Run `flutter analyze` (expected: `No issues found!`) and the non-golden suite (see Global Constraints; expected: `All tests passed!`).

- [ ] **Step 7: Commit**

```bash
git add lib/ui/kit/tokens.dart lib/ui/kit/bb_sheet.dart lib/ui/kit/bb_chip.dart lib/ui/kit/bb_segmented.dart \
  lib/ui/kit/bb_switch.dart lib/ui/kit/route_palette.dart lib/ui/kit/bb_route_dots.dart \
  test/kit/contrast_test.dart test/kit/scrim_test.dart test/kit/elevation_test.dart test/kit/route_palette_test.dart \
  test/tool/harbour_style_test.dart test/map/marker_images_test.dart test/map/map_layers_test.dart \
  test/map/map_hit_test_test.dart
git commit -m "feat(kit): neutral greys and the brighter Harbour blue; route 10 is green again

The green and purple tints are gone: surfaces, lines, text, shadows and
scrims are neutral, and accent is retired for brandInk. Sky and indigo
move just far enough to stay clear of the new blue.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 2: Neutral map styles

**Files:**
- Modify: `tool/src/harbour_style.dart:29-51` (`HarbourPalette.light` and `.dark`)
- Modify (regenerated): `assets/map/harbour_light.json`, `assets/map/harbour_dark.json`
- Modify: `test/tool/harbour_style_test.dart`
- Modify: `test/helpers/planner_app.dart:92` (the stub map's default land colour)

**Interfaces:**
- Consumes: `BBColors.dark.surface == #1F2024` (Task 1); `oklab` from `test/kit/route_palette_test.dart`.
- Produces: `HarbourPalette.light` = land `#EEF0F2`, water `#C9D9E4`, park `#DCE8DD`, road `#FFFFFF`, roadCasing `#D9DCE0`, label `#737880`, building `#E4E6E9`; `HarbourPalette.dark` = land `#17181B`, water `#0F1820`, park `#172019`, road `#26282C`, roadCasing `#2F3237`, label `#80848C`, building `#1E1F23`. The screen goldens (`test/ui/screen_golden_test.dart`'s `_land`) and `StubMap()` read these.

- [ ] **Step 1: Write the failing tests**

In `test/tool/harbour_style_test.dart`:

1. Add `import 'dart:math' as math;` after `import 'dart:io';`, and `import '../kit/route_palette_test.dart' show oklab;` after `import '../../tool/src/harbour_style.dart';`.
2. Change the expected colours (each value appears only in these expectations):

```bash
sed -i '' -e "s/'#EEF3EF'/'#EEF0F2'/g" -e "s/'#C2DCE6'/'#C9D9E4'/g" -e "s/'#D5EAD7'/'#DCE8DD'/g" \
  -e "s/'#151A26'/'#17181B'/g" -e "s/'#0D1A2E'/'#0F1820'/g" -e "s/'#15231F'/'#172019'/g" \
  -e "s/'#D4DED7'/'#D9DCE0'/g" -e "s/'#232A3A'/'#26282C'/g" -e "s/'#2C3447'/'#2F3237'/g" \
  -e "s/'#738579'/'#737880'/g" -e "s/'#7C869B'/'#80848C'/g" test/tool/harbour_style_test.dart
```

3. After the test `'the dark map sits a step below the sheet floating on it (spec 2026-10-14 §2.4)'` (the last one, from Task 1), before the file's final `}`, add:

```dart

  test('both maps are neutral: only water and parks carry colour (spec 2026-10-14 §2.4)', () {
    Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));
    double chroma(String h) {
      final lab = oklab(hex(h));
      return math.sqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    }

    for (final p in [HarbourPalette.light, HarbourPalette.dark]) {
      for (final (name, value) in [
        ('land', p.land),
        ('road', p.road),
        ('roadCasing', p.roadCasing),
        ('label', p.label),
        ('building', p.building),
      ]) {
        expect(chroma(value), lessThanOrEqualTo(0.015), reason: '${p.name} $name $value is tinted');
      }
      expect(chroma(p.water), greaterThan(0.015), reason: '${p.name} water is still blue-grey');
      expect(chroma(p.park), greaterThan(0.015), reason: '${p.name} parks are still green');
    }
  });

  test('map labels stay readable on the land (3:1 or more)', () {
    Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));
    double ratio(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final p in [HarbourPalette.light, HarbourPalette.dark]) {
      expect(ratio(hex(p.label), hex(p.land)), greaterThanOrEqualTo(3.0), reason: p.name);
    }
  });
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `flutter test test/tool/harbour_style_test.dart`
Expected: FAIL: the palette expectations, the committed-styles land checks and "both maps are neutral".

- [ ] **Step 3: Implement the palettes**

In `tool/src/harbour_style.dart`, replace both constants, from `  static const light = HarbourPalette(` through the `);` that closes `static const dark = HarbourPalette(` (keep the class's closing `}` after them), with:

```dart
  /// Neutral greys (spec 2026-10-14 §2.4): water stays blue-grey and parks a muted green, the only coloured land.
  static const light = HarbourPalette(
    name: 'Harbour light',
    land: '#EEF0F2',
    water: '#C9D9E4',
    park: '#DCE8DD',
    road: '#FFFFFF',
    roadCasing: '#D9DCE0',
    label: '#737880',
    building: '#E4E6E9',
  );

  /// A neutral dark grey a step below the app's dark `surface` (#1F2024), so sheets, cards and map buttons stand
  /// clear of the map; their shadow and top highlight do the rest.
  static const dark = HarbourPalette(
    name: 'Harbour dark',
    land: '#17181B',
    water: '#0F1820',
    park: '#172019',
    road: '#26282C',
    roadCasing: '#2F3237',
    label: '#80848C',
    building: '#1E1F23',
  );
```

(This also replaces the old doc comment above `dark`, "A greyer, cooler navy …".)

- [ ] **Step 4: Regenerate the committed styles**

Run: `dart run tool/build_map_styles.dart --recolour`
Expected: `recoloured assets/map/harbour_light.json` and `recoloured assets/map/harbour_dark.json`.

Check: `grep -c "EEF3EF\|151A26\|738579\|7C869B" assets/map/harbour_light.json assets/map/harbour_dark.json` prints `0` for both files, and `git diff --stat assets/map` shows only those two files (about 116 changed lines each way).

In `test/helpers/planner_app.dart`, replace:

```dart
  StubMap({this.color = const Color(0xFFEEF3EF)});
```

with:

```dart
  StubMap({this.color = const Color(0xFFEEF0F2)});
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `flutter test test/tool/harbour_style_test.dart test/kit/route_palette_test.dart`
Expected: PASS (the route lines still read on the new dark land and roads: 3:1 or more; on the light land, 2:1 or more).

- [ ] **Step 6: The whole suite**

`flutter analyze` and the non-golden suite, as in Global Constraints. Expected: clean, all pass.

- [ ] **Step 7: Commit**

```bash
git add tool/src/harbour_style.dart assets/map/harbour_light.json assets/map/harbour_dark.json \
  test/tool/harbour_style_test.dart test/helpers/planner_app.dart
git commit -m "feat(map): neutral grey map styles; water and parks keep the only colour

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 3: The blue icon and splash

**Files:**
- Rewrite: `assets/brand/busboard_icon.svg`, `assets/brand/busboard_mark.svg`
- Modify: `tool/brand/render_brand_assets.sh:2,9-10,19,39,41`
- Modify: `pubspec.yaml:48,52,56`
- Modify (regenerated): `assets/icon/app_icon.png`, `app_icon_foreground.png`, `app_icon_gplay.png`, `splash_logo.png`, `splash_logo_android12.png`; files under `android/app/src/main/res/` and `ios/Runner/Assets.xcassets/`
- Rewrite: `test/brand_assets_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (the colours come from spec §2.5).
- Produces: the icon on `#1272C9`; houses coral `#EF5B5B`, gold `#F2B53A`, green `#3FAE4F`, electric purple `#B65CFF`; windows, wheels and pin dot `#16181C`; bus body and pin white; the mark moved by `translate(2 2.5)` (its bounding box, x 12–84 and y 9–86 in 100-unit space, is then centred on 50, 50). `assets/icon/feature_graph_gplay.png` deliberately stays as it is (spec §2.5: redone at release).

`tool/brand/render_brand_assets.sh` needs ImageMagick 7 (`magick -version`); it is installed at `/opt/homebrew/bin/magick`.

- [ ] **Step 1: Write the failing test**

Replace the whole of `test/brand_assets_test.dart` with:

```dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// The pixel at ([x], [y]) of the PNG at [path].
Future<ui.Color> _pixel(String path, int x, int y) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * image.width + x) * 4;
  return ui.Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

/// Within 2 of [expected] on every channel (resizing may round).
Matcher _near(ui.Color expected) => predicate<ui.Color>(
      (c) => [(c.r, expected.r), (c.g, expected.g), (c.b, expected.b), (c.a, expected.a)]
          .every((p) => ((p.$1 - p.$2) * 255).abs() <= 2),
      'within 2/255 of $expected',
    );

const _blue = ui.Color(0xFF1272C9);

void main() {
  test('pubspec: the adaptive icon and both splashes use the Harbour blue (spec 2026-10-14 §2.5)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('adaptive_icon_background: "#1272C9"'));
    expect(RegExp(r'flutter_native_splash:\s*\n\s*color: "#1272C9"').hasMatch(pubspec), isTrue);
    expect(pubspec, contains('icon_background_color: "#1272C9"'));
    expect(pubspec, isNot(contains('#3FAE4F')), reason: 'the old green background is gone');
  });

  for (final svg in ['assets/brand/busboard_icon.svg', 'assets/brand/busboard_mark.svg']) {
    test('$svg: coral, gold, green and electric purple houses; ink #16181C; white bus and pin; centred', () {
      final text = File(svg).readAsStringSync().toUpperCase();
      for (final c in ['#EF5B5B', '#F2B53A', '#3FAE4F', '#B65CFF', '#16181C', '#FFFFFF']) {
        expect(text, contains(c));
      }
      // The blue house would vanish on the blue; the old violet and ink go with it.
      for (final old in ['#2F6FE4', '#8C5CF6', '#13261A']) {
        expect(text, isNot(contains(old)), reason: 'old colour $old');
      }
      expect(File(svg).readAsStringSync(), contains('transform="translate(2 2.5)"'), reason: 'the mark is centred');
    });
  }

  test('the icon master sits on the Harbour blue, not the old green', () {
    final icon = File('assets/brand/busboard_icon.svg').readAsStringSync();
    expect(icon, contains('<rect width="100" height="100" fill="#1272C9"/>'));
    expect(icon, isNot(contains('<rect width="100" height="100" fill="#3FAE4F"/>')));
  });

  test("the mark's view box is centred on the moved mark (its middle is 50, 50)", () {
    final box = RegExp(r'viewBox="([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+)"')
        .firstMatch(File('assets/brand/busboard_mark.svg').readAsStringSync())!;
    final v = [for (var i = 1; i <= 4; i++) double.parse(box.group(i)!)];
    expect(v[0] + v[2] / 2, 50);
    expect(v[1] + v[3] / 2, 50);
  });

  testWidgets('the rendered icons and the iOS launch background are blue', (tester) async {
    await tester.runAsync(() async {
      expect(await _pixel('assets/icon/app_icon.png', 4, 4), _near(_blue));
      expect(await _pixel('assets/icon/app_icon_gplay.png', 2, 2), _near(_blue));
      expect(await _pixel('ios/Runner/Assets.xcassets/LaunchBackground.imageset/background.png', 0, 0), _near(_blue));
      expect(await _pixel('ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png', 4, 4), _near(_blue));
    });
  });

  test('the generated Android resources carry the blue, and no green background is left', () {
    final colors = File('android/app/src/main/res/values/colors.xml').readAsStringSync().toUpperCase();
    expect(colors, contains('#1272C9'));
    expect(colors, isNot(contains('#3FAE4F')));
    for (final f in ['android/app/src/main/res/values-v31/styles.xml', 'android/app/src/main/res/values-night-v31/styles.xml']) {
      final xml = File(f).readAsStringSync().toUpperCase();
      expect(xml, contains('#1272C9'), reason: f);
      expect(xml, isNot(contains('#3FAE4F')), reason: f);
    }
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/brand_assets_test.dart`
Expected: FAIL in every test (the green background, the blue and violet houses, the old ink, no transform).

- [ ] **Step 3: Rewrite the SVG masters**

Replace the whole of `assets/brand/busboard_icon.svg` with:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <!-- BusBoard NL app icon (spec 2026-10-14 §2.5). Background brightened Harbour blue; the mark centred. -->
  <rect width="100" height="100" fill="#1272C9"/>
  <g id="mark" transform="translate(2 2.5)">
    <path d="M12 46 L21 37 L30 46 V70 H12Z" fill="#EF5B5B"/>
    <path d="M30 46 L39 37 L48 46 V70 H30Z" fill="#F2B53A"/>
    <path d="M48 46 L57 37 L66 46 V70 H48Z" fill="#3FAE4F"/>
    <path d="M66 46 L75 37 L84 46 V70 H66Z" fill="#B65CFF"/>
    <rect x="18" y="47.5" width="6" height="7" rx="1" fill="#16181C" fill-opacity=".45"/>
    <rect x="36" y="47.5" width="6" height="7" rx="1" fill="#16181C" fill-opacity=".45"/>
    <rect x="54" y="47.5" width="6" height="7" rx="1" fill="#16181C" fill-opacity=".45"/>
    <rect x="72" y="47.5" width="6" height="7" rx="1" fill="#16181C" fill-opacity=".45"/>
    <rect x="14" y="58" width="66" height="22" rx="6" fill="#FFFFFF"/>
    <rect x="19" y="62" width="10" height="8" rx="1.8" fill="#16181C"/>
    <rect x="32" y="62" width="10" height="8" rx="1.8" fill="#16181C"/>
    <rect x="45" y="62" width="10" height="8" rx="1.8" fill="#16181C"/>
    <rect x="58" y="62" width="10" height="8" rx="1.8" fill="#16181C"/>
    <rect x="71" y="62" width="6" height="13" rx="1.8" fill="#16181C"/>
    <circle cx="28" cy="81" r="5" fill="#16181C"/>
    <circle cx="28" cy="81" r="2.2" fill="#FFFFFF"/>
    <circle cx="66" cy="81" r="5" fill="#16181C"/>
    <circle cx="66" cy="81" r="2.2" fill="#FFFFFF"/>
    <path d="M57 9c-6 0-10.5 4.5-10.5 10.5 0 7.5 10.5 17 10.5 17s10.5-9.5 10.5-17C67.5 13.5 63 9 57 9z" fill="#FFFFFF"/>
    <circle cx="57" cy="19.5" r="4" fill="#16181C"/>
  </g>
</svg>
```

Replace the whole of `assets/brand/busboard_mark.svg` with:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="11 9.5 78 81">
  <!-- BusBoard NL mark on transparent (adaptive-icon foreground, splash), centred like the icon's. -->
  <g transform="translate(2 2.5)">
    <path d="M12 46 L21 37 L30 46 V70 H12Z" fill="#EF5B5B"/>
    <path d="M30 46 L39 37 L48 46 V70 H30Z" fill="#F2B53A"/>
    <path d="M48 46 L57 37 L66 46 V70 H48Z" fill="#3FAE4F"/>
    <path d="M66 46 L75 37 L84 46 V70 H66Z" fill="#B65CFF"/>
    <rect x="18" y="47.5" width="6" height="7" rx="1" fill="#16181C" fill-opacity=".45"/>
    <rect x="36" y="47.5" width="6" height="7" rx="1" fill="#16181C" fill-opacity=".45"/>
    <rect x="54" y="47.5" width="6" height="7" rx="1" fill="#16181C" fill-opacity=".45"/>
    <rect x="72" y="47.5" width="6" height="7" rx="1" fill="#16181C" fill-opacity=".45"/>
    <rect x="14" y="58" width="66" height="22" rx="6" fill="#FFFFFF"/>
    <rect x="19" y="62" width="10" height="8" rx="1.8" fill="#16181C"/>
    <rect x="32" y="62" width="10" height="8" rx="1.8" fill="#16181C"/>
    <rect x="45" y="62" width="10" height="8" rx="1.8" fill="#16181C"/>
    <rect x="58" y="62" width="10" height="8" rx="1.8" fill="#16181C"/>
    <rect x="71" y="62" width="6" height="13" rx="1.8" fill="#16181C"/>
    <circle cx="28" cy="81" r="5" fill="#16181C"/>
    <circle cx="28" cy="81" r="2.2" fill="#FFFFFF"/>
    <circle cx="66" cy="81" r="5" fill="#16181C"/>
    <circle cx="66" cy="81" r="2.2" fill="#FFFFFF"/>
    <path d="M57 9c-6 0-10.5 4.5-10.5 10.5 0 7.5 10.5 17 10.5 17s10.5-9.5 10.5-17C67.5 13.5 63 9 57 9z" fill="#FFFFFF"/>
    <circle cx="57" cy="19.5" r="4" fill="#16181C"/>
  </g>
</svg>
```

Only colours, the comments, the `transform` and the mark's `viewBox` change: every shape keeps its coordinates. The mark's view box moves by the same (2, 2.5), so it stays the same size and is centred on (50, 50). The house windows keep `fill-opacity=".45"`.

- [ ] **Step 4: Point the render script and pubspec at the blue**

In `tool/brand/render_brand_assets.sh`:
- replace the first comment line `# Regenerates every brand PNG from assets/brand/*.svg (visual refresh spec §6.2).` with `# Regenerates every brand PNG from assets/brand/*.svg (spec 2026-10-14 §2.5).`;
- replace `GREEN='#3FAE4F'` with `BLUE='#1272C9'` and `INK='#0F2414'` with `WHITE='#FFFFFF'` (white text on the blue feature graphic);
- replace `"$GREEN"` with `"$BLUE"` (line 19), `"xc:$GREEN"` with `"xc:$BLUE"` (line 39) and `-fill "$INK"` with `-fill "$WHITE"` (line 41).

Check: `grep -n 'GREEN\|INK' tool/brand/render_brand_assets.sh` prints nothing.

Then:

```bash
sed -i '' 's/"#3FAE4F"/"#1272C9"/g' pubspec.yaml
grep -n '1272C9' pubspec.yaml
```

Expected: three lines: `adaptive_icon_background`, `color` (under `flutter_native_splash`) and `icon_background_color`.

- [ ] **Step 5: Render the PNGs and the platform assets**

```bash
bash tool/brand/render_brand_assets.sh
git checkout -- assets/icon/feature_graph_gplay.png   # redone at release (spec §2.5)
dart run flutter_launcher_icons
dart run flutter_native_splash:create
git status --short android ios assets
```

Expected `git status` (dry run): `android/app/src/main/res/values/colors.xml`, `values-v31/styles.xml`, `values-night-v31/styles.xml`; the `mipmap-*`/`drawable*` launcher, foreground, splash and background PNGs; `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`, `LaunchImage.imageset/*.png` and `LaunchBackground.imageset/background.png`; `assets/brand/*.svg` and the five `assets/icon/*.png`. If either tool touched anything else (for example `Info.plist`, `AndroidManifest.xml`, `LaunchScreen.storyboard` or `launch_background.xml`), look at `git diff <file>`; if the change isn't a colour or a splash image reference, restore it with `git checkout -- <file>` and say so in your report.

Look at the result: open `assets/icon/app_icon.png` and `assets/icon/app_icon_foreground.png` with the Read tool. Expected: a blue square; coral, gold, green and purple houses; a white bus with dark windows and wheels; a white pin; the whole mark centred left to right and top to bottom.

- [ ] **Step 6: Run the test to see it pass**

Run: `flutter test test/brand_assets_test.dart`
Expected: PASS. Then `flutter analyze` and the non-golden suite (expected: clean, all pass).

- [ ] **Step 7: Commit**

```bash
git add assets/brand/busboard_icon.svg assets/brand/busboard_mark.svg tool/brand/render_brand_assets.sh pubspec.yaml \
  assets/icon/app_icon.png assets/icon/app_icon_foreground.png assets/icon/app_icon_gplay.png \
  assets/icon/splash_logo.png assets/icon/splash_logo_android12.png \
  android/app/src/main/res ios/Runner/Assets.xcassets test/brand_assets_test.dart
git status --short
git commit -m "feat(brand): blue icon and splash, a green and an electric purple house, the mark centred

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(`git status --short` after `git add` must show nothing staged outside these paths; `analysis_options.yaml` and the other local files stay unstaged.)

---
### Task 4: The slim bar and the stop line

On a phone the home sheet's header becomes the bar: Where to? and the new stop line (plus the one-time tip and an armed alert's strip while they show). Today's header content moves under it. The bar's height needs no new mechanism: `home_screen.dart` already measures the sheet header (`_measuredHeader` → `_scheduleHeaderMeasure` → `_headerHeight`) and sets the peek to `measured + handle + 8` (`peekPx`, line 1168). A slimmer header gives a slimmer peek, and it grows with the text size because the header does.

**Files:**
- Create: `lib/domain/arrival/first_bus.dart`, `test/domain/first_bus_test.dart`
- Create: `lib/ui/home/home_stop_line.dart`, `test/ui/home_stop_line_test.dart`
- Modify: `lib/ui/home/home_sheet.dart`, `lib/ui/home/sheet_content.dart`
- Modify: `lib/ui/home/home_screen.dart:1171,1214,1217`
- Modify: `test/ui/home_sheet_test.dart`, `test/ui/home_screen_test.dart`, `test/ui/screen_overflow_test.dart`, `test/ui/reduce_motion_test.dart`, `test/ui/board_button_test.dart`

**Interfaces:**
- Consumes: `BBColors` (Task 1). Existing: `stopArrivalsProvider(stopId)` (`AsyncValue<List<ArrivalRow>>`, rows within 3 h), `stopArrivalsUpdatedAtProvider` (`Map<String, DateTime>`), `serviceUpdatesProvider`, `gtfsRepositoryProvider`, `plannerClockProvider` (`DateTime Function()`, the tests' clock), `HomeSheetNotifier.openBoard(String stopId)`, `nearestStopsProvider`.
- Produces:
  - `DateTime? firstBusAfter(GtfsRepository repo, String stopId, DateTime now)` in `lib/domain/arrival/first_bus.dart`.
  - `enum StopLineKind { next, none, firstBus, loading, offline }`.
  - `class StopLineInfo` with `const StopLineInfo({required String stopName, required StopLineKind kind, String? route, int? minutes, bool live = false, DateTime? firstBus, DateTime? updatedAt, String? alertEffect})`, `factory StopLineInfo.resolve({required String stopName, required AsyncValue<List<ArrivalRow>> arrivals, required DateTime? Function() firstBus, DateTime? updatedAt, String? alertEffect})`, `bool get now`, `String? note({required bool use24h})`, `String semantics({required bool use24h})`.
  - `class HomeStopLine extends ConsumerWidget` with `const HomeStopLine({Key? key, VoidCallback? onChooseStop})`, `static const lineKey = ValueKey('home-stop-line')`, `static const double minHeight = 48`. Its alert mark is `ValueKey('home-stop-line-alert')`.
  - `HomeSheetContent.bar({VoidCallback? onChooseStop})` (phone header) and `HomeSheetContent.barBody()` (phone body); `HomeSheetContent.header` / `body` are unchanged (tablet).
  - `selectionHeader(HomeSheet, {VoidCallback? onChooseStop, bool wide = false})`, `selectionSlivers(HomeSheet, {bool wide = false})`.

- [ ] **Step 1: Write the failing tests for the first bus**

Create `test/domain/first_bus_test.dart`:

```dart
import 'package:busboard_nl/domain/arrival/first_bus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../trip_planner/test_network.dart';

DateTime _at(int h, int m, {int day = 0}) => DateTime(testDay.year, testDay.month, testDay.day + day, h, m);

void main() {
  // TestNetwork: stop A's buses leave 08:00 to 08:50; service runs every day of 2026.
  test('before the morning service: the first bus today', () {
    expect(firstBusAfter(TestNetwork().repo, 'A', _at(5, 0)), _at(8, 0));
  });

  test('after the last bus: the first bus tomorrow', () {
    expect(firstBusAfter(TestNetwork().repo, 'A', _at(13, 0)), _at(8, 0, day: 1));
  });

  test('a gap in the middle of the day is not a first bus', () {
    final net = TestNetwork()..addTrip('A-late', '1', ['A', 'B'], 14 * 3600, 300);
    expect(firstBusAfter(net.repo, 'A', _at(9, 30)), isNull);
  });

  test('a trip past midnight counts on its own service day', () {
    // Route 9 reaches Y at 24:20, its only stop time there: the first (and only) bus of the day at Y.
    expect(firstBusAfter(TestNetwork().repo, 'Y', _at(23, 55)), _at(0, 20, day: 1));
  });

  test('a stop with no stop times, or an unknown one, has no first bus', () {
    expect(firstBusAfter(TestNetwork().repo, 'H', _at(5, 0)), isNull);
    expect(firstBusAfter(TestNetwork().repo, 'nowhere', _at(5, 0)), isNull);
  });
}
```

Run: `flutter test test/domain/first_bus_test.dart`
Expected: FAIL to compile (`first_bus.dart` doesn't exist).

- [ ] **Step 2: Implement `firstBusAfter`**

Create `lib/domain/arrival/first_bus.dart`:

```dart
import '../../data/gtfs/gtfs_repository.dart';
import '../../data/gtfs/gtfs_time.dart';

/// The next departure from [stopId] after [now], when it is the first of its service day there: the morning's
/// first bus, or the first of a day that has none until later (spec 2026-10-14 §3.2, "First bus 6:28 AM"). Null when
/// the next departure is a later one of its day (a gap in the middle of the day: "No buses for a while"), or when
/// nothing leaves the stop from yesterday's service through tomorrow's.
DateTime? firstBusAfter(GtfsRepository repo, String stopId, DateTime now) {
  final times = repo.stopTimesByStopId[stopId];
  if (times == null || times.isEmpty) return null;
  final today = DateTime(now.year, now.month, now.day);
  DateTime? next;
  var nextIsFirst = false;
  // Yesterday's service still runs after midnight (24:15 is today's 00:15).
  for (var offset = -1; offset <= 1; offset++) {
    final day = DateTime(today.year, today.month, today.day + offset);
    final services = repo.activeServiceIds(day);
    if (services.isEmpty) continue;
    int? earliest;
    int? soonest;
    for (final st in times) {
      final trip = repo.tripsById[st.tripId];
      if (trip == null || !services.contains(trip.serviceId)) continue;
      final GtfsTime t;
      try {
        t = GtfsTime.parse(st.departureTime);
      } on FormatException {
        continue;
      }
      final s = t.totalSeconds;
      if (earliest == null || s < earliest) earliest = s;
      if (t.toDateTime(day).isAfter(now) && (soonest == null || s < soonest)) soonest = s;
    }
    if (soonest == null) continue;
    final at = GtfsTime.fromSeconds(soonest).toDateTime(day);
    if (next == null || at.isBefore(next)) {
      next = at;
      nextIsFirst = soonest == earliest;
    }
  }
  return nextIsFirst ? next : null;
}
```

Run: `flutter test test/domain/first_bus_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 3: Write the failing tests for the stop line**

Create `test/ui/home_stop_line_test.dart`:

```dart
import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_stop_line.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/test_network.dart';

DateTime _at(int h, int m) => DateTime(testDay.year, testDay.month, testDay.day, h, m);

class _Settings extends SettingsNotifier {
  _Settings(this.stopId);
  final String? stopId;
  @override
  AppSettings build() => AppSettings(selectedStopId: stopId);
}

ArrivalRow _row(int minutes, {bool live = false}) => ArrivalRow(
      routeShortName: '1',
      headsign: 'Downtown',
      scheduledTime: GtfsTime.parse('13:05:00'),
      minutesAway: minutes,
      isLive: live,
      tripId: 't$minutes',
      vehicleNumber: live ? '2134' : null,
    );

final _line = find.byKey(HomeStopLine.lineKey);
Finder _inLine(Finder f) => find.descendant(of: _line, matching: f);

/// The real home on the test network, your stop C (or [stop]), at [now], its departures from [arrivals].
Future<void> _pump(
  WidgetTester tester, {
  FutureOr<List<ArrivalRow>> Function()? arrivals,
  DateTime? now,
  TestNetwork? net,
  List<ServiceAlert> alerts = const [],
  String? stop = 'C',
  double textScale = 1,
}) =>
    pumpPlannerApp(
      tester,
      net: net ?? TestNetwork(),
      now: now ?? _at(13, 0),
      alerts: alerts,
      textScale: textScale,
      use24h: false,
      overrides: [
        settingsProvider.overrideWith(() => _Settings(stop)),
        stopArrivalsProvider.overrideWith((ref, id) async => arrivals == null ? const <ArrivalRow>[] : await arrivals()),
      ],
    );

void main() {
  setUpAll(loadAppFonts);

  group('what a screen reader hears (spec 2026-10-14 §3.2)', () {
    StopLineInfo next(int minutes, {bool live = true, String? alert}) => StopLineInfo(
          stopName: 'MUN Centre',
          kind: StopLineKind.next,
          route: '10',
          minutes: minutes,
          live: live,
          alertEffect: alert,
        );

    test('live, scheduled, one minute and now', () {
      expect(next(4).semantics(use24h: false), 'Your stop, MUN Centre. Route 10 in 4 minutes, live. Open board');
      expect(next(4, live: false).semantics(use24h: false),
          'Your stop, MUN Centre. Route 10 in 4 minutes, scheduled. Open board');
      expect(next(1).semantics(use24h: false), 'Your stop, MUN Centre. Route 10 in 1 minute, live. Open board');
      expect(next(0).semantics(use24h: false), 'Your stop, MUN Centre. Route 10 arriving now, live. Open board');
    });

    test('no buses, first bus, loading and offline', () {
      const none = StopLineInfo(stopName: 'MUN Centre', kind: StopLineKind.none);
      expect(none.semantics(use24h: false), 'Your stop, MUN Centre. No buses for a while. Open board');
      final first = StopLineInfo(stopName: 'MUN Centre', kind: StopLineKind.firstBus, firstBus: _at(6, 28));
      expect(first.semantics(use24h: false), 'Your stop, MUN Centre. First bus 6:28 AM. Open board');
      const loading = StopLineInfo(stopName: 'MUN Centre', kind: StopLineKind.loading);
      expect(loading.semantics(use24h: false), 'Your stop, MUN Centre. Loading');
      final offline = StopLineInfo(stopName: 'MUN Centre', kind: StopLineKind.offline, updatedAt: _at(9, 42));
      expect(offline.semantics(use24h: false), 'Your stop, MUN Centre. Offline, updated 9:42 AM. Open board');
      expect(offline.note(use24h: false), 'Offline · updated 9:42 AM');
    });

    test('an alert on the stop is said right after its name', () {
      expect(next(4, alert: 'Detour').semantics(use24h: false),
          'Your stop, MUN Centre. Detour affects this stop. Route 10 in 4 minutes, live. Open board');
    });

    test('resolve picks the state from the departures', () {
      StopLineInfo resolve(AsyncValue<List<ArrivalRow>> a, {DateTime? first}) =>
          StopLineInfo.resolve(stopName: 'MUN Centre', arrivals: a, firstBus: () => first);
      expect(resolve(const AsyncLoading()).kind, StopLineKind.loading);
      expect(resolve(AsyncError(Exception('down'), StackTrace.empty)).kind, StopLineKind.offline);
      expect(resolve(const AsyncData([])).kind, StopLineKind.none);
      expect(resolve(const AsyncData([]), first: _at(6, 28)).kind, StopLineKind.firstBus);
      final live = resolve(AsyncData([_row(4, live: true), _row(9)]));
      expect((live.kind, live.route, live.minutes, live.live), (StopLineKind.next, '1', 4, true));
    });
  });

  testWidgets('live next bus: route, rolling minutes and the breathing dot', (tester) async {
    await _pump(tester, arrivals: () => [_row(4, live: true)]);
    expect(find.bySemanticsLabel('Your stop, Stop C. Route 1 in 4 minutes, live. Open board'), findsOneWidget);
    expect(_inLine(find.text('Stop C')), findsOneWidget);
    expect(_inLine(find.byType(RouteBadge)), findsOneWidget);
    expect(_inLine(find.byType(BBRollingText)), findsOneWidget);
    expect(_inLine(find.text('4')), findsOneWidget);
    expect(_inLine(find.byType(BBLiveDot)), findsOneWidget);
  });

  testWidgets('scheduled next bus: no dot', (tester) async {
    await _pump(tester, arrivals: () => [_row(4)]);
    expect(find.bySemanticsLabel('Your stop, Stop C. Route 1 in 4 minutes, scheduled. Open board'), findsOneWidget);
    expect(_inLine(find.byType(BBLiveDot)), findsNothing);
  });

  testWidgets('"Now" in the soon colour, with no minute unit', (tester) async {
    await _pump(tester, arrivals: () => [_row(0, live: true)]);
    expect(find.bySemanticsLabel('Your stop, Stop C. Route 1 arriving now, live. Open board'), findsOneWidget);
    expect(tester.widget<Text>(_inLine(find.text('Now'))).style!.color, BBColors.light.soon);
    expect(_inLine(find.text(' min')), findsNothing);
  });

  testWidgets('no bus within three hours, and not a first bus: "No buses for a while"', (tester) async {
    // Stop C's morning buses are gone by 09:30 and the next leaves at 14:00: a gap, not a first bus.
    final net = TestNetwork()..addTrip('2-late', '2', ['C', 'D'], 14 * 3600, 240);
    await _pump(tester, net: net, now: _at(9, 30));
    expect(_inLine(find.text(' · No buses for a while')), findsOneWidget);
    expect(find.bySemanticsLabel('Your stop, Stop C. No buses for a while. Open board'), findsOneWidget);
  });

  testWidgets("at night: tomorrow's first bus", (tester) async {
    await _pump(tester, now: _at(22, 0));
    expect(_inLine(find.text(' · First bus 8:05 AM')), findsOneWidget);
    expect(find.bySemanticsLabel('Your stop, Stop C. First bus 8:05 AM. Open board'), findsOneWidget);
  });

  testWidgets('loading: the name and a shimmer where the time goes', (tester) async {
    await _pump(tester, arrivals: () => Completer<List<ArrivalRow>>().future);
    expect(_inLine(find.byType(BBSkeleton)), findsOneWidget);
    expect(find.bySemanticsLabel('Your stop, Stop C. Loading'), findsOneWidget);
  });

  testWidgets('offline: when the departures last loaded', (tester) async {
    await _pump(tester, arrivals: () => throw Exception('offline'));
    // Riverpod retries a failed provider with backoff before surfacing the error.
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(_inLine(find.text(' · Offline')), findsOneWidget);
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
        .read(stopArrivalsUpdatedAtProvider.notifier)
        .stamp('C', _at(9, 42));
    await tester.pumpAndSettle();
    expect(_inLine(find.text(' · Offline · updated 9:42 AM')), findsOneWidget);
    expect(find.bySemanticsLabel('Your stop, Stop C. Offline, updated 9:42 AM. Open board'), findsOneWidget);
  });

  testWidgets('a refresh that fails after a good load says Offline, not the old minutes', (tester) async {
    var calls = 0;
    await _pump(tester, arrivals: () {
      if (calls++ == 0) return [_row(4, live: true)];
      throw Exception('offline');
    });
    expect(_inLine(find.text('4')), findsOneWidget);
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen))).invalidate(stopArrivalsProvider('C'));
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(_inLine(find.textContaining('Offline')), findsOneWidget);
    expect(_inLine(find.text('4')), findsNothing);
  });

  testWidgets('at 3x text on 320 pt the line still fits: the time shrinks rather than truncate', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, arrivals: () => [_row(12, live: true)], textScale: 3);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(_line).right, lessThanOrEqualTo(320));
    expect(tester.renderObject<RenderParagraph>(_inLine(find.text('12'))).didExceedMaxLines, isFalse);
  });

  testWidgets('an alert affecting the stop: a gold mark after its name', (tester) async {
    await _pump(
      tester,
      arrivals: () => [_row(4, live: true)],
      alerts: [
        ServiceAlert(
          sourceIds: const {'d'},
          header: 'Stop C moved',
          description: '',
          cause: ServiceAlertCause.construction,
          effect: ServiceAlertEffect.detour,
          severity: ServiceAlertSeverity.warning,
          activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
          targets: const [ServiceAlertTarget(stopId: 'C')],
        ),
      ],
    );
    final mark = _inLine(find.byKey(const ValueKey('home-stop-line-alert')));
    expect(mark, findsOneWidget);
    expect(tester.widget<Icon>(mark).color, BBColors.light.warnInk);
    expect(
      find.bySemanticsLabel('Your stop, Stop C. Detour affects this stop. Route 1 in 4 minutes, live. Open board'),
      findsOneWidget,
    );
  });

  testWidgets('no stop chosen: "Choose your stop"', (tester) async {
    await _pump(tester, stop: null);
    expect(_inLine(find.text('Choose your stop')), findsOneWidget);
    expect(find.bySemanticsLabel('Choose your stop'), findsOneWidget);
  });

  for (final (what, arrivals, now) in [
    ('the next bus', () => [_row(12, live: true)], _at(13, 0)),
    ('the first bus', () => const <ArrivalRow>[], _at(22, 0)),
  ]) {
    testWidgets('at 2x text on 320 pt the long name truncates first, never $what', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final net = TestNetwork();
      net.repo.stopsById['C'] =
          const StopInfo(stopId: 'C', stopName: 'Memorial University Centre Bus Terminal', stopLat: 47.57, stopLon: -52.75);
      await _pump(tester, net: net, now: now, arrivals: arrivals, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(_line).right, lessThanOrEqualTo(320));
      final name = tester.renderObject<RenderParagraph>(_inLine(find.text('Memorial University Centre Bus Terminal')));
      expect(name.didExceedMaxLines, isTrue, reason: 'the name gives way');
      final time = _inLine(find.text(what == 'the next bus' ? '12' : ' · First bus 8:05 AM'));
      expect(time, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(time).didExceedMaxLines, isFalse, reason: 'the time reads in full');
    });
  }
}
```

Notes for this file: the TestNetwork's stop C has its first departure at 08:05 (route 2), so "First bus 8:05 AM" at 22:00; `pumpPlannerApp(use24h: false)` gives 12-hour times; `loadAppFonts` makes the 2× and 3× tests measure the real Figtree.

Run: `flutter test test/ui/home_stop_line_test.dart`
Expected: FAIL to compile (`home_stop_line.dart` doesn't exist).

- [ ] **Step 4: Implement the stop line**

Create `lib/ui/home/home_stop_line.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival/first_bus.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../kit/kit.dart';

/// What the stop line shows (spec 2026-10-14 §3.2).
enum StopLineKind {
  /// The next bus: its route and minutes ("Now" at 0 or less), live or scheduled.
  next,

  /// No bus within the three hours the arrivals cover, and the next one is not a day's first.
  none,

  /// Night, or before the day's service: the first bus's time.
  firstBus,

  /// The first load is still running.
  loading,

  /// The departures could not be loaded (offline, or a feed error).
  offline,
}

/// The stop line's content for one moment: everything [HomeStopLine] draws and says.
@immutable
class StopLineInfo {
  const StopLineInfo({
    required this.stopName,
    required this.kind,
    this.route,
    this.minutes,
    this.live = false,
    this.firstBus,
    this.updatedAt,
    this.alertEffect,
  });

  /// [arrivals] is the stop's departures as loaded; [firstBus] is asked only when none are due.
  factory StopLineInfo.resolve({
    required String stopName,
    required AsyncValue<List<ArrivalRow>> arrivals,
    required DateTime? Function() firstBus,
    DateTime? updatedAt,
    String? alertEffect,
  }) {
    StopLineInfo of(StopLineKind kind, {ArrivalRow? next, DateTime? first}) => StopLineInfo(
      stopName: stopName,
      kind: kind,
      route: next?.routeShortName,
      minutes: next?.minutesAway,
      live: next?.isLive ?? false,
      firstBus: first,
      updatedAt: updatedAt,
      alertEffect: alertEffect,
    );
    if (arrivals.hasError) return of(StopLineKind.offline);
    final rows = arrivals.value;
    if (rows == null) return of(StopLineKind.loading);
    if (rows.isNotEmpty) return of(StopLineKind.next, next: rows.first);
    final first = firstBus();
    return first == null ? of(StopLineKind.none) : of(StopLineKind.firstBus, first: first);
  }

  final String stopName;
  final StopLineKind kind;
  final String? route;
  final int? minutes;
  final bool live;
  final DateTime? firstBus;

  /// When the departures last loaded, for the offline note.
  final DateTime? updatedAt;

  /// The label of an active alert's effect on the stop or its routes ("Detour"), or null.
  final String? alertEffect;

  bool get now => kind == StopLineKind.next && (minutes ?? 0) <= 0;

  /// The words after the stop name for the kinds without a route: "No buses for a while", "First bus 6:28 AM",
  /// "Offline · updated 9:42 AM". Null for [StopLineKind.next] and [StopLineKind.loading].
  String? note({required bool use24h}) => switch (kind) {
    StopLineKind.none => 'No buses for a while',
    StopLineKind.firstBus => 'First bus ${BBTime.of(firstBus!, use24h: use24h)}',
    StopLineKind.offline =>
      updatedAt == null ? 'Offline' : 'Offline · updated ${BBTime.of(updatedAt!, use24h: use24h)}',
    StopLineKind.next || StopLineKind.loading => null,
  };

  /// What a screen reader says (spec 2026-10-14 §3.2).
  String semantics({required bool use24h}) {
    final head = 'Your stop, $stopName.${alertEffect == null ? '' : ' $alertEffect affects this stop.'}';
    final status = live ? 'live' : 'scheduled';
    return switch (kind) {
      StopLineKind.loading => '$head Loading',
      StopLineKind.next when now => '$head Route $route arriving now, $status. Open board',
      StopLineKind.next =>
        '$head Route $route in ${minutes == 1 ? '1 minute' : '$minutes minutes'}, $status. Open board',
      StopLineKind.offline =>
        '$head ${updatedAt == null ? 'Offline' : 'Offline, updated ${BBTime.of(updatedAt!, use24h: use24h)}'}. Open board',
      _ => '$head ${note(use24h: use24h)}. Open board',
    };
  }
}

/// The bar's second row (spec 2026-10-14 §3.1, §3.2): your stop and its next bus, one tap from its Board. With no
/// stop chosen it is "Choose your stop", which pulls the sheet up to the nearby stops ([onChooseStop]) or, with none
/// to show, opens a stop search.
class HomeStopLine extends ConsumerWidget {
  const HomeStopLine({super.key, this.onChooseStop});

  final VoidCallback? onChooseStop;

  static const lineKey = ValueKey('home-stop-line');

  /// At least this tall at any text size (spec §3.1).
  static const double minHeight = 48;

  /// The most of the line a note may take; the stop name gets the rest and truncates first.
  static const double _maxNoteShare = 0.6;

  /// What the stop name keeps however large the text: its first letters and an ellipsis.
  static const double _minName = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final stopId = ref.watch(settingsProvider.select((s) => s.selectedStopId));
    final stop = stopId == null ? null : ref.watch(stopInfoProvider(stopId));
    if (stop == null) {
      return BBPressable(
        key: lineKey,
        semanticLabel: 'Choose your stop',
        onTap: () {
          // Nearby stops to pick from: pull up to them. None (location off or refused, or nothing near): a search for
          // the stop number on the pole (spec 2026-10-12 §4.4).
          final nearby = ref.read(nearestStopsProvider);
          final none = nearby.hasError || (nearby.hasValue && nearby.value!.isEmpty);
          if (none) {
            context.push('/search?pickStop=1');
          } else {
            onChooseStop?.call();
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: Row(
            children: [
              Icon(BBIcons.nearMe, size: 18, color: bb.brandEdge),
              const SizedBox(width: BBSpace.s),
              Flexible(
                child: Text('Choose your stop', style: bb.text.headline.copyWith(color: bb.colors.brandInk)),
              ),
              const SizedBox(width: BBSpace.xs),
              Icon(BBIcons.chevronRight, size: 18, color: bb.colors.brandInk),
            ],
          ),
        ),
      );
    }

    final use24h = BBTime.use24h(context);
    final arrivals = ref.watch(stopArrivalsProvider(stop.stopId));
    final updatedAt = ref.watch(stopArrivalsUpdatedAtProvider.select((m) => m[stop.stopId]));
    final repo = ref.watch(gtfsRepositoryProvider).value;
    final updates = ref.watch(serviceUpdatesProvider).value;
    final routes = repo?.routeShortNamesForStop(stop.stopId).toSet() ?? const <String>{};
    final alert = updates
        ?.activeAlertsAt(DateTime.now())
        .where((a) => a.appliesTo(routeIds: routes, stopId: stop.stopId))
        .firstOrNull;
    final info = StopLineInfo.resolve(
      stopName: stop.stopName,
      arrivals: arrivals,
      updatedAt: updatedAt,
      alertEffect: alert?.effect.label,
      firstBus: () => repo == null ? null : firstBusAfter(repo, stop.stopId, ref.read(plannerClockProvider)()),
    );

    final muted = bb.text.body.copyWith(color: bb.colors.muted);
    return BBPressable(
      key: lineKey,
      semanticLabel: info.semantics(use24h: use24h),
      onTap: () => ref.read(homeSheetProvider.notifier).openBoard(stop.stopId),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: LayoutBuilder(
          builder: (context, box) {
            // The star, its gap and the alert mark are fixed; the name keeps [_minName]; the rest may go to the time.
            final tailMax = math.max(0.0, box.maxWidth - 26 - (info.alertEffect == null ? 0 : 22) - _minName);
            return Row(
              children: [
                Icon(BBIcons.star, size: 18, color: bb.brandEdge),
                const SizedBox(width: BBSpace.s),
                // The name gives way first: the time after it never truncates (spec §3.2).
                Flexible(
                  child: Text(stop.stopName, style: bb.text.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (info.alertEffect != null) ...[
                  const SizedBox(width: BBSpace.xs),
                  Icon(
                    BBIcons.warning,
                    key: const ValueKey('home-stop-line-alert'),
                    size: 18,
                    color: bb.colors.warnInk,
                  ),
                ],
                switch (info.kind) {
                  // Shrinks (never truncates) only when even a 40 pt name would not leave it room: huge text on a
                  // narrow phone.
                  StopLineKind.next => ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: tailMax),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(' · ', style: muted),
                          RouteBadge.name(info.route!, size: RouteBadgeSize.compact),
                          const SizedBox(width: BBSpace.s),
                          // Rolling minutes (visual refresh §3.2), at title size: large text, so "Now" in `soon`
                          // meets 3:1.
                          BBRollingText(
                            info.now ? 'Now' : '${info.minutes}',
                            style: bb.text.title.copyWith(
                              color: info.now ? bb.colors.soon : bb.colors.ink,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (!info.now) Text(' min', style: bb.text.headline),
                          if (info.live) ...[
                            const SizedBox(width: BBSpace.s),
                            BBLiveDot(color: bb.colors.live, size: 10),
                          ],
                        ],
                      ),
                    ),
                  ),
                  StopLineKind.loading => const Padding(
                    padding: EdgeInsets.only(left: BBSpace.s),
                    child: SizedBox(width: 64, child: BBSkeleton(kind: BBSkeletonKind.line, count: 1)),
                  ),
                  // A note wraps onto a second line rather than lose its end (the bar grows with it).
                  _ => ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: math.min(tailMax, box.maxWidth * _maxNoteShare)),
                    child: Text(' · ${info.note(use24h: use24h)}', style: muted),
                  ),
                },
              ],
            );
          },
        ),
      ),
    );
  }
}
```

Why it is built this way:
- The name is `Flexible` with one line and an ellipsis, so it gives way first. The time is laid out at its natural width, capped at what the name leaves (`tailMax`, always keeping 40 pt of name) and shrunk with `FittedBox(scaleDown)` only if even that is too narrow (huge text on a narrow phone). It is never cut.
- The minutes use `title` (22 pt, weight 800): "Now" in `soon` is then large text, which needs 3:1 (`soon` on white is 4.3:1, short of the 4.5:1 normal text would need).
- Notes ("No buses for a while", "First bus …", "Offline · …") may wrap onto a second line instead of losing their end; the bar grows with them.
- `BBPressable(semanticLabel: …)` replaces the row's own semantics with the one sentence from `StopLineInfo.semantics`, so the route badge, the skeleton and the live dot don't add their own words.

- [ ] **Step 5: Put the bar in the home sheet**

In `lib/ui/home/home_sheet.dart`:

1. Add `import 'home_stop_line.dart';` before `import 'home_tip.dart';`.
2. Replace:

```dart
/// The home sheet (spec 2026-10-12 §3.1). The header is what peeks: Where to, saved places, alerts for you,
/// your stop's next buses. The body: saved trips, then nearby stops.
abstract final class HomeSheetContent {
  static const whereToKey = ValueKey('where-to');
  static const openBoardKey = ValueKey('home-open-board');

  /// [onChooseStop] pulls the sheet up to the nearby stops (home_screen.dart passes its sheet's full detent). With no
  /// nearby stops to show (no location, or none near) "Choose your stop" opens a stop search instead (spec §4.4).
  static Widget header({VoidCallback? onChooseStop}) => _Header(onChooseStop: onChooseStop);
  static Widget body() => const _Body();
}
```

with:

```dart
/// The home sheet (spec 2026-10-12 §3.1, 2026-10-14 §3). On a phone its header is the slim bar that rests over the
/// map: Where to? and your stop's line ([bar]); pulled up, [barBody] shows saved places, alerts for you, your stop's
/// next buses with Open board, saved trips and nearby stops. The tablet panel keeps the full [header] and [body].
abstract final class HomeSheetContent {
  static const whereToKey = ValueKey('where-to');
  static const openBoardKey = ValueKey('home-open-board');

  /// [onChooseStop] pulls the sheet up to the nearby stops (home_screen.dart passes its sheet's full detent). With no
  /// nearby stops to show (no location, or none near) "Choose your stop" opens a stop search instead (spec §4.4).
  static Widget bar({VoidCallback? onChooseStop}) => _Bar(onChooseStop: onChooseStop);

  /// Under the bar: everything the bar leaves out, then saved trips and nearby stops.
  static Widget barBody() => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_Header(belowBar: true), _Body()],
      );

  /// The tablet panel's header, as before the bar (spec 2026-10-14 §3.7).
  static Widget header({VoidCallback? onChooseStop}) => _Header(onChooseStop: onChooseStop);
  static Widget body() => const _Body();
}

/// The phone's bar (spec 2026-10-14 §3.1): Where to? and the stop line, each at least 48 pt tall, under the one-time
/// tip while it shows. An armed arrival alert's strip joins them, so it stays in sight and can be cancelled with the
/// stop's sheet closed (F4). Its height is its content's, so it grows with the text size.
class _Bar extends ConsumerWidget {
  const _Bar({this.onChooseStop});

  final VoidCallback? onChooseStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAlert = ref.watch(arrivalAlertProvider.select((a) => a.value != null));
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeTip(),
          const _WhereTo(),
          const SizedBox(height: BBSpace.s),
          HomeStopLine(onChooseStop: onChooseStop),
          if (hasAlert) ...[const SizedBox(height: BBSpace.s), const AlertStrip()],
        ],
      ),
    );
  }
}

/// "Where to?": the search field, at least 48 pt tall.
class _WhereTo extends StatelessWidget {
  const _WhereTo();

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return BBPressable(
      key: HomeSheetContent.whereToKey,
      semanticLabel: 'Where to? Search for a place or a stop',
      onTap: () => context.push('/search'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: DecoratedBox(
          decoration: bb.field(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: BBSpace.s),
            child: Row(
              children: [
                Icon(BBIcons.search, size: 20, color: bb.colors.muted),
                const SizedBox(width: BBSpace.s),
                Expanded(
                  child: Text('Where to?', style: bb.text.title.copyWith(color: bb.colors.muted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

3. Replace:

```dart
class _Header extends ConsumerWidget {
  const _Header({this.onChooseStop});

  final VoidCallback? onChooseStop;
```

with:

```dart
class _Header extends ConsumerWidget {
  const _Header({this.onChooseStop, this.belowBar = false});

  final VoidCallback? onChooseStop;

  /// Under the phone's bar, which already has the tip, Where to?, "Choose your stop" and an armed alert's strip.
  final bool belowBar;
```

4. In `_Header.build`, replace:

```dart
        children: [
          const HomeTip(),
          BBPressable(
            key: HomeSheetContent.whereToKey,
            semanticLabel: 'Where to? Search for a place or a stop',
            onTap: () => context.push('/search'),
            child: DecoratedBox(
              decoration: bb.field(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: BBSpace.s),
                child: Row(
                  children: [
                    Icon(BBIcons.search, size: 20, color: bb.colors.muted),
                    const SizedBox(width: BBSpace.s),
                    Expanded(
                      child: Text('Where to?', style: bb.text.title.copyWith(color: bb.colors.muted)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: BBSpace.s),
          Wrap(
```

with:

```dart
        children: [
          if (!belowBar) ...[const HomeTip(), const _WhereTo()],
          const SizedBox(height: BBSpace.s),
          Wrap(
```

5. Replace:

```dart
          if (hasAlert) ...[const SizedBox(height: BBSpace.s), const AlertStrip()],
          const SizedBox(height: BBSpace.m),
          if (stop == null)
            BBButton(
```

with:

```dart
          if (hasAlert && !belowBar) ...[const SizedBox(height: BBSpace.s), const AlertStrip()],
          const SizedBox(height: BBSpace.m),
          if (stop == null && belowBar)
            const SizedBox.shrink()
          else if (stop == null)
            BBButton(
```

In `lib/ui/home/sheet_content.dart`, replace:

```dart
/// The sheet's header for what it shows. [onChooseStop] is the home sheet's "Choose your stop".
Widget selectionHeader(HomeSheet sheet, {VoidCallback? onChooseStop}) => switch (sheet) {
      HomeSheetHome() => HomeSheetContent.header(onChooseStop: onChooseStop),
```

with:

```dart
/// The sheet's header for what it shows. [onChooseStop] is the home sheet's "Choose your stop". On a phone ([wide]
/// false) the home sheet's header is its slim bar; the tablet panel keeps the full header.
Widget selectionHeader(HomeSheet sheet, {VoidCallback? onChooseStop, bool wide = false}) => switch (sheet) {
      HomeSheetHome() =>
        wide ? HomeSheetContent.header(onChooseStop: onChooseStop) : HomeSheetContent.bar(onChooseStop: onChooseStop),
```

and replace:

```dart
/// The sheet's slivers under [selectionHeader].
List<Widget> selectionSlivers(HomeSheet sheet) => switch (sheet) {
      HomeSheetHome() => [SliverToBoxAdapter(child: HomeSheetContent.body())],
```

with:

```dart
/// The sheet's slivers under [selectionHeader] (the same [wide]).
List<Widget> selectionSlivers(HomeSheet sheet, {bool wide = false}) => switch (sheet) {
      HomeSheetHome() => [SliverToBoxAdapter(child: wide ? HomeSheetContent.body() : HomeSheetContent.barBody())],
```

In `lib/ui/home/home_screen.dart`, replace:

```dart
          : selectionHeader(sheet, onChooseStop: () => _showMore(wide: wide)));
      final panelSlivers = followShowing
          ? [SliverToBoxAdapter(child: FollowCardBody(snapshot: follow.snapshot))]
          : selectionSlivers(sheet);
```

with:

```dart
          : selectionHeader(sheet, onChooseStop: () => _showMore(wide: wide), wide: wide));
      final panelSlivers = followShowing
          ? [SliverToBoxAdapter(child: FollowCardBody(snapshot: follow.snapshot))]
          : selectionSlivers(sheet, wide: wide);
```

and replace the comment line:

```dart
      // The home sheet peeks taller (Where to?, places, alerts and your stop): spec §3.1.
```

with:

```dart
      // The home sheet's bar is slim (spec 2026-10-14 §3.1); the cap only matters while the one-time tip sits in it.
```

(`_maxHomePeek` stays 0.55: with the one-time tip in the bar at 360x640, "Got it" must stay inside the resting sheet; see `screen_overflow_test.dart`'s tip tests.)

Run: `flutter test test/ui/home_stop_line_test.dart test/domain/first_bus_test.dart`
Expected: PASS (17 + 5 tests).

- [ ] **Step 6: Update the home tests that assumed the tall peek**

The saved places, alerts for you, Your stop and its buses now sit one pull up, and the stop line also starts with "Your stop, …", so several tests change.

`test/ui/home_sheet_test.dart`:

1. Add `import 'package:busboard_nl/ui/home/home_stop_line.dart';` after the `home_sheet.dart` import, and delete `import 'package:busboard_nl/ui/map/stop_card.dart';` (no longer used).
2. Before `/// Pulls the sheet to its full height, where saved trips and nearby stops are.` add:

```dart
/// Pulls the sheet from its bar up to half, where saved places, alerts for you and your stop's buses are.
Future<void> _toHalf(WidgetTester tester) async {
  await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
  await tester.pumpAndSettle();
}

```

3. Replace the whole test `testWidgets('at peek: Where to, saved places, alerts for you and your stop, with no taps', …` (through its closing `  });`) with:

```dart
  testWidgets('at rest the sheet is the slim bar: Where to? and the stop line, whole, the rest one pull up (spec 2026-10-14 §3.1)',
      (tester) async {
    await _pumpHome(
      tester,
      places: [_home],
      alerts: [_alertOnRoute1()],
      arrivals: [_arrival(4), _arrival(12)],
    );
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    var card = tester.getRect(find.byKey(BBSheet.cardKey));
    for (final (name, f) in [
      ('Where to?', find.byKey(HomeSheetContent.whereToKey)),
      ('the stop line', find.byKey(HomeStopLine.lineKey)),
    ]) {
      final r = tester.getRect(f);
      expect(r.top, greaterThanOrEqualTo(card.top), reason: name);
      expect(r.bottom, lessThanOrEqualTo(card.bottom), reason: '$name is whole inside the bar');
      expect(r.height, greaterThanOrEqualTo(48), reason: '$name is at least 48 pt tall');
    }
    expect(card.height, lessThan(0.2 * screen.height), reason: 'the bar leaves the map most of the screen');
    for (final (name, f) in [
      ('the saved place', find.text('Home')),
      ('the alert for you', find.textContaining('Detour on 1')),
      ('the next bus', find.byType(ArrivalRowTile).first),
    ]) {
      expect(f.hitTestable(), findsNothing, reason: '$name waits under the bar');
    }

    // Pulled up to half: today's home content (spec §3.3).
    await _toHalf(tester);
    card = tester.getRect(find.byKey(BBSheet.cardKey));
    for (final (name, f) in [
      ('the saved place', find.text('Home')),
      ('the alert for you', find.textContaining('Detour on 1')),
      ('your stop', find.bySemanticsLabel('Your stop, Stop C. Open its buses')),
      ('Open board', find.bySemanticsLabel('Open board, Stop C')),
      ('the next bus', find.byType(ArrivalRowTile).first),
    ]) {
      final r = tester.getRect(f);
      expect(r.top, greaterThanOrEqualTo(card.top), reason: name);
      expect(r.bottom, lessThanOrEqualTo(card.bottom), reason: '$name is whole inside the sheet at half');
    }
  });
```

4. Add `    await _toHalf(tester);` as the line right after `await _pumpHome(tester, places: [_home]);` in these tests: "a saved place opens trip options to it", "a saved place starts a fresh trip: an old start, mode and time are dropped (F3, Ruling 14)" and "a long-press on a saved place offers Remove, and Cancel keeps it"; right after the closing `);` of `pumpPlannerApp(…)` in "a saved place starts from My location when the phone knows where it is (F3)"; and right after `await _pumpHome(tester, alerts: [_alertOnRoute1()]);` in "an alert for you is one line, and opens Alerts".
5. In "Plan a trip from here starts from that stop, leaving now, and the search's pick keeps it (F3)", replace `    await tester.tap(find.bySemanticsLabel(RegExp(r'^Your stop, Stop C')));` with `    await tester.tap(find.byKey(HomeStopLine.lineKey));` (the stop line opens the stop's Board, whose header has "Plan a trip from here").
6. Replace the test:

```dart
  testWidgets('your stop opens its sheet', (tester) async {
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Your stop, Stop C')));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
  });
```

with:

```dart
  testWidgets("the stop line opens your stop's Board, at full height (spec 2026-10-14 §3.2)", (tester) async {
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    await tester.tap(find.byKey(HomeStopLine.lineKey));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.fullFraction * (844 - 2 * BBSpace.s), 1));
  });

  testWidgets('pulled up, Your stop opens its sheet', (tester) async {
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    await _toHalf(tester);
    await tester.tap(find.bySemanticsLabel('Your stop, Stop C. Open its buses'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
  });
```

(The two "Choose your stop" tests keep working unchanged: with no stop, the stop line reads "Choose your stop" and behaves like the old button, which the phone body no longer repeats.)

`test/ui/home_screen_test.dart`:

1. Add `import 'package:busboard_nl/ui/home/home_stop_line.dart';` after `import 'package:busboard_nl/ui/home/home_sheet.dart';`.
2. Replace the whole test `testWidgets("the peek shows Where to?, your stop and its next two buses in full", …` (through its closing `  });`) with:

```dart
  testWidgets("the bar shows Where to? and your stop's line in full; pulled up, your stop and its next two buses",
      (tester) async {
    ArrivalRow arrival(int minutes) => ArrivalRow(
          routeShortName: '10',
          headsign: 'Downtown',
          scheduledTime: GtfsTime.parse('09:52:00'),
          predictedTime: GtfsTime.parse('09:55:00'),
          minutesAway: minutes,
          liveStatus: LiveStatus.behind,
          isLive: true,
          tripId: 't$minutes',
          vehicleNumber: '2134',
          isEnhanced: false,
          routeRun: '10-1',
        );
    final handle = tester.ensureSemantics();
    await _pump(tester, size: const Size(390, 844), prefs: {'selectedStopId': '1150'}, arrivals: [arrival(3), arrival(9), arrival(15)],
        overrides: [homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen())]);
    var card = tester.getRect(find.byKey(BBSheet.cardKey));
    // The bar: Where to? and the stop line, whole inside the resting sheet (spec 2026-10-14 §3.1).
    for (final f in [find.byKey(HomeSheetContent.whereToKey), find.byKey(HomeStopLine.lineKey)]) {
      expect(tester.getRect(f).top, greaterThanOrEqualTo(card.top));
      expect(tester.getRect(f).bottom, lessThanOrEqualTo(card.bottom));
    }
    expect(find.byType(ArrivalRowTile).hitTestable(), findsNothing, reason: 'the buses wait under the bar');
    // Pulled up to half: your stop's header row, then its next two buses (spec §3.3).
    await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    card = tester.getRect(find.byKey(BBSheet.cardKey));
    final tiles = find.byType(ArrivalRowTile);
    final yourStop = tester.getRect(find.bySemanticsLabel('Your stop, MUN Centre. Open its buses'));
    final first = tester.getRect(tiles.at(0));
    expect(yourStop.top, greaterThanOrEqualTo(card.top));
    expect(yourStop.bottom, lessThanOrEqualTo(first.top), reason: 'your stop is above its first bus');
    expect(first.bottom, lessThanOrEqualTo(card.bottom), reason: 'the next bus fits inside the sheet at half');
    expect(tester.getRect(tiles.at(1)).bottom, lessThanOrEqualTo(card.bottom), reason: 'the second bus too');
    handle.dispose();
  });
```

`test/ui/screen_overflow_test.dart`:

1. Add `import 'package:busboard_nl/ui/home/home_stop_line.dart';` after `import 'package:busboard_nl/ui/home/home_sheet.dart';`.
2. Replace the comment above `pumpHomeAtPeek`:

```dart
  // The home at its peek: the real screen, so the peek is the sheet's own. Where to?, the first saved place and the
  // top of Your stop must be visible (on screen, inside the peeking sheet) however large the text, with two saved
  // places and an alert for you (spec §3.1).
```

with:

```dart
  // The home at rest: the real screen, so the bar is the sheet's own. Where to? and the stop line must be visible (on
  // screen, inside the bar) however large the text, with two saved places and an alert for you (spec 2026-10-14 §3.1).
```

3. Replace `    testWidgets('home at peek, 360x640, 2.0x text, ${dark ? 'dark' : 'light'}', (tester) async {` with `    testWidgets('home at the bar, 360x640, 2.0x text, ${dark ? 'dark' : 'light'}', (tester) async {`, and in that test replace:

```dart
      expectVisibleAtPeek(tester, find.text('Home'), 'the first saved place', size);
      expectVisibleAtPeek(tester, find.bySemanticsLabel(RegExp('^Your stop')), 'the top of Your stop', size);
```

with:

```dart
      expectVisibleAtPeek(tester, find.byKey(HomeStopLine.lineKey), 'the stop line', size);
```

4. Replace:

```dart
  testWidgets('home at peek, 390x844, 1.0x text: Your stop and the next bus are whole above the bottom', (tester) async {
    final handle = tester.ensureSemantics();
    const size = Size(390, 844);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHomeAtPeek(tester, size: size, textScale: 1.0, dark: false);
    final card = tester.getRect(find.byKey(BBSheet.cardKey));
    final yourStop = tester.getRect(find.bySemanticsLabel(RegExp('^Your stop')));
    final firstBus = tester.getRect(find.byType(ArrivalRowTile).first);
    for (final (name, r) in [('Your stop', yourStop), ('the first bus', firstBus)]) {
      expect(r.top, greaterThanOrEqualTo(card.top), reason: name);
      expect(r.bottom, lessThanOrEqualTo(card.bottom), reason: '$name is whole inside the peeking sheet');
```

with:

```dart
  testWidgets('home at 390x844, 1.0x text: the stop line is whole in the bar; at half, Your stop and the next bus',
      (tester) async {
    final handle = tester.ensureSemantics();
    const size = Size(390, 844);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHomeAtPeek(tester, size: size, textScale: 1.0, dark: false);
    final bar = tester.getRect(find.byKey(BBSheet.cardKey));
    final line = tester.getRect(find.byKey(HomeStopLine.lineKey));
    expect(line.top, greaterThanOrEqualTo(bar.top));
    expect(line.bottom, lessThanOrEqualTo(bar.bottom), reason: 'the stop line is whole inside the bar');
    await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byKey(BBSheet.cardKey));
    final yourStop = tester.getRect(find.bySemanticsLabel(RegExp(r'^Your stop, .*\. Open its buses$')));
    final firstBus = tester.getRect(find.byType(ArrivalRowTile).first);
    for (final (name, r) in [('Your stop', yourStop), ('the first bus', firstBus)]) {
      expect(r.top, greaterThanOrEqualTo(card.top), reason: name);
      expect(r.bottom, lessThanOrEqualTo(card.bottom), reason: '$name is whole inside the sheet at half');
```

(The tip tests in that file stay as they are: the tip is still above Where to?, in the bar.)

`test/ui/reduce_motion_test.dart`: add `import 'package:busboard_nl/ui/home/home_stop_line.dart';` after the `home_screen.dart` import, and replace:

```dart
    // A stop sheet, from Your stop.
    await tester.tap(find.bySemanticsLabel(RegExp('^Your stop')));
```

with:

```dart
    // A stop's Board, from the bar's stop line.
    await tester.tap(find.byKey(HomeStopLine.lineKey));
```

`test/ui/board_button_test.dart`:

1. After `import 'package:busboard_nl/ui/home/home_screen.dart';` add:

```dart
import 'package:busboard_nl/ui/home/home_sheet.dart' show HomeSheetContent;
import 'package:busboard_nl/ui/home/home_stop_line.dart';
```

2. Replace the comment:

```dart
/// "Open board" (riders used to the old Board tab): on home's Your stop and in every stop sheet's header, it opens
/// the stop's sheet at full height, its Board; on the tablet panel it scrolls to the departures.
```

with:

```dart
/// "Open board" (riders used to the old Board tab): on home's Your stop, on the bar's stop line and in every stop
/// sheet's header, it opens the stop's sheet at full height, its Board; on the tablet panel it scrolls to the departures.
```

3. Replace:

```dart
  testWidgets("home's Your stop has Open board, which opens the stop's sheet at full height", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    expect(_openBoard, findsOneWidget);
    await tester.tap(_openBoard);
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    _expectAtFull(tester);
  });
```

with:

```dart
  testWidgets("the bar's stop line opens the stop's sheet at full height (spec 2026-10-14 §3.2)", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await tester.tap(find.byKey(HomeStopLine.lineKey));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    _expectAtFull(tester);
  });

  testWidgets("pulled up, home's Your stop has Open board, which opens the stop's sheet at full height", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_openBoard.hitTestable(), findsOneWidget);
    await tester.tap(_openBoard);
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    _expectAtFull(tester);
  });
```

4. In "at 2x text on a 320 wide phone, Open board and Show map read in full, light and dark", replace:

```dart
      expect(tester.takeException(), isNull);
      expect(find.text('Open board'), findsOneWidget);
      await tester.tap(_openBoard);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Show map'), findsOneWidget, reason: 'its other face reads in full too');
      _expectAtFull(tester);
```

with:

```dart
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(HomeStopLine.lineKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Show map'), findsOneWidget, reason: 'the Board open, its button reads Show map in full');
      _expectAtFull(tester);
      await tester.tap(find.bySemanticsLabel('Show the map, Stop C'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Open board'), findsOneWidget, reason: 'and Open board reads in full too');
```

(The tablet tests in that file are unchanged: the panel keeps the full header with its own Open board.)

- [ ] **Step 7: Run the changed tests**

Run: `flutter test test/ui/home_sheet_test.dart test/ui/home_screen_test.dart test/ui/screen_overflow_test.dart test/ui/reduce_motion_test.dart test/ui/board_button_test.dart test/ui/stop_sheet_test.dart test/ui/home_tablet_test.dart test/ui/board_reopen_test.dart`
Expected: PASS. (`board_reopen_test.dart`'s "a cold start with a remembered Board opens home with that stop's sheet at full height" is the spec §3.5 restore check; `stop_sheet_test.dart`'s F4 test checks the armed alert's strip is still on the home sheet.)

- [ ] **Step 8: The whole suite**

`flutter analyze` and the non-golden suite. Expected: clean, all pass.

- [ ] **Step 9: Commit**

```bash
git add lib/domain/arrival/first_bus.dart lib/ui/home/home_stop_line.dart lib/ui/home/home_sheet.dart \
  lib/ui/home/sheet_content.dart lib/ui/home/home_screen.dart test/domain/first_bus_test.dart \
  test/ui/home_stop_line_test.dart test/ui/home_sheet_test.dart test/ui/home_screen_test.dart \
  test/ui/screen_overflow_test.dart test/ui/reduce_motion_test.dart test/ui/board_button_test.dart
git commit -m "feat(home): the sheet rests as a slim bar: Where to? and your stop's line

The stop line shows the next bus (live, scheduled or Now), no buses for
a while, the first bus, loading, offline and an alert mark, and opens
the stop's Board. Saved places, alerts and your stop's buses are one
pull up. The tablet panel is unchanged.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 5: The handle as a button, and the one-time lift

**Files:**
- Modify: `lib/ui/kit/bb_sheet.dart` (`handleButton`, `handleExtent`, `handleButtonExtent`, `BBSheetController.nudge`)
- Create: `lib/state/seen_flags.dart`, `test/state/seen_flags_test.dart`
- Modify: `lib/ui/home/home_screen.dart` (handle extent in the peek, `handleButton:`, `_hintBar`)
- Modify: `test/helpers/planner_app.dart` (`barHintSeen`), `test/kit/sheet_test.dart`, `test/ui/home_screen_test.dart`, `test/ui/home_sheet_test.dart`, `test/ui/saved_trips_test.dart:59`

**Interfaces:**
- Consumes: the bar (Task 4); `BBMotion.reduced`, `BBMotion.standard`, `BBMotion.emphasis`, `BBMotion.curve`.
- Produces:
  - `BBSheet({…, bool handleButton = false})`; `static const double BBSheet.handleExtent = 20`, `BBSheet.handleButtonExtent = 24`. With `handleButton`, the handle (`BBSheet.handleKey`) is a button labelled `'Show more'` at peek and `'Show less'` above it, with custom actions `'Expand'` (to full) and `'Collapse'` (to peek).
  - `Future<void> BBSheetController.nudge(double lift)`: up by `lift` logical pixels and back, no haptic tick, nothing under reduce motion.
  - `lib/state/seen_flags.dart`: `const barHintSeenKey = 'home_bar_hint_seen.v1'`; `class SeenFlagNotifier extends AsyncNotifier<bool>` with `SeenFlagNotifier(String key)`, `factory SeenFlagNotifier.seen(String key)` (already seen, for tests), `Future<void> markSeen()`; `final barHintSeenProvider = AsyncNotifierProvider<SeenFlagNotifier, bool>(…)`. Task 7 adds `followTipSeenKey` and `followTipSeenProvider` to this file.
  - `pumpPlannerApp(…, bool barHintSeen = true)`; `home_screen_test.dart`'s `_pump(…, bool barHintSeen = true)`.

- [ ] **Step 1: Write the failing sheet tests**

In `test/kit/sheet_test.dart`:

1. Add `import 'dart:math' as math;` after `import 'dart:async';`.
2. In `_host`, add a parameter `bool handleButton = false,` after `Brightness brightness = Brightness.light,`, and pass `handleButton: handleButton,` to `BBSheet(…)` after `onDismiss: onDismiss,`.
3. Before `  testWidgets('non-dismissible sheet stays at peek when swiped down', (tester) async {` add:

```dart
  testWidgets('a handle button reads Show more at peek and Show less above it; each tap moves one stop', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = BBSheetController();
    await tester.pumpWidget(_host(controller, handleButton: true));
    expect(
      tester.getSemantics(find.byKey(BBSheet.handleKey)),
      isSemantics(label: 'Show more', isButton: true, hasTapAction: true),
    );
    expect(tester.getSize(find.byKey(BBSheet.handleKey)).height, BBSheet.handleButtonExtent);
    await tester.tap(find.byKey(BBSheet.handleKey));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.5, 0.01), reason: 'peek to half');
    expect(tester.getSemantics(find.byKey(BBSheet.handleKey)), isSemantics(label: 'Show less', isButton: true));
    tester.semantics.tap(find.semantics.byLabel('Show less'));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.15, 0.01), reason: 'half to peek, by a screen reader');
    unawaited(controller.animateToDetent(BBSheetDetent.full));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BBSheet.handleKey));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.5, 0.01), reason: 'full to half');
    handle.dispose();
  });

  testWidgets('a handle button keeps Expand and Collapse for screen readers, and still drags', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = BBSheetController();
    await tester.pumpWidget(_host(controller, handleButton: true));
    tester.semantics.customAction(find.semantics.byLabel('Show more'), const CustomSemanticsAction(label: 'Expand'));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.9, 0.01), reason: 'Expand reaches full');
    tester.semantics.customAction(find.semantics.byLabel('Show less'), const CustomSemanticsAction(label: 'Collapse'));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.15, 0.01));
    await tester.drag(find.byKey(BBSheet.handleKey), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.5, 0.01), reason: 'a drag on the handle still moves the sheet');
    handle.dispose();
  });

  testWidgets('nudge does nothing under reduce motion', (tester) async {
    final controller = BBSheetController();
    await tester.pumpWidget(_host(controller, reduceMotion: true));
    final rest = tester.getRect(find.byKey(BBSheet.cardKey)).top;
    unawaited(controller.nudge(24));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, rest);
    }
  });

```

4. In the `haptics` group, before `    testWidgets('programmatic animation to full ticks once, not when crossing half', (tester) async {` add:

```dart
    testWidgets('nudge lifts the sheet 24 pt and settles it back where it was, with no tick', (tester) async {
      mockHaptics(tester);
      final controller = BBSheetController();
      await tester.pumpWidget(_host(controller));
      await settle(tester);
      final rest = tester.getRect(find.byKey(BBSheet.cardKey)).top;
      unawaited(controller.nudge(24));
      var highest = rest;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        highest = math.min(highest, tester.getRect(find.byKey(BBSheet.cardKey)).top);
      }
      await settle(tester);
      expect(highest, closeTo(rest - 24, 1), reason: 'it rises about 24 pt');
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, closeTo(rest, 0.5), reason: 'and settles back');
      expect(ticks, 0, reason: 'a hint, not a settle on a new detent');
    });

```

Run: `flutter test test/kit/sheet_test.dart`
Expected: FAIL to compile (`handleButton`, `handleButtonExtent` and `nudge` don't exist).

- [ ] **Step 2: Implement the button handle and `nudge`**

In `lib/ui/kit/bb_sheet.dart`:

1. Add `import 'dart:math' as math;` after `import 'dart:async';`.
2. After `  Future<void> collapse() => animateToDetent(BBSheetDetent.peek);` (inside `BBSheetController`) add:

```dart

  /// "There is more above": lifts the sheet [lift] logical pixels and settles it back where it was, with no haptic
  /// tick (spec 2026-10-14 §3.6). Does nothing under reduce motion, or when detached.
  ///
  /// Same caveat as [animateToDetent]: don't await it from tests; use `unawaited(...)`.
  Future<void> nudge(double lift) async {
    final sheet = _sheet;
    if (sheet == null || !isAttached || sheet._reduced) return;
    final rest = size;
    final up = math.min(rest + pixelsToSize(lift), sheet.widget.fullFraction);
    sheet._quiet = true;
    try {
      await animateTo(up, duration: BBMotion.standard, curve: BBMotion.curve);
      if (!isAttached) return;
      await animateTo(rest, duration: BBMotion.emphasis, curve: BBMotion.curve);
    } finally {
      sheet._quiet = false;
    }
  }
```

3. Replace the class comment's line `/// an adjustable control for screen readers (Expand / Collapse / Close).` with:

```dart
/// an adjustable control for screen readers (Expand / Collapse / Close), or,
/// with [handleButton], a button that moves one stop ("Show more" / "Show less").
```

4. In the constructor, after `    this.fadeUnderHeader = false,` add `    this.handleButton = false,`.
5. Replace:

```dart
  /// Home: the top of the list fades under the pinned header once it scrolls (spec §5).
  final bool fadeUnderHeader;

  static const double sideMargin = 8;
```

with:

```dart
  /// Home: the top of the list fades under the pinned header once it scrolls (spec §5).
  final bool fadeUnderHeader;

  /// Home (spec 2026-10-14 §3.6): the grab handle is a button, "Show more" at peek and "Show less" above it, and a
  /// tap moves one stop: peek to half, half to peek, full to half. It is [handleButtonExtent] tall, a 24 pt target.
  final bool handleButton;

  static const double sideMargin = 8;

  /// The grab handle's height above the header: 8 + 4 + 8, or [handleButtonExtent] when it is a button.
  static const double handleExtent = 20;
  static const double handleButtonExtent = 24;
```

6. In `_BBSheetState`, replace:

```dart
  bool _moreBelow = false;
  Duration _snapDuration = BBMotion.emphasis;
```

with:

```dart
  bool _moreBelow = false;
  Duration _snapDuration = BBMotion.emphasis;
  bool _reduced = false;

  /// While [BBSheetController.nudge] runs: leaving and coming back to a detent is not a new settle (no tick).
  bool _quiet = false;
```

7. In `didChangeDependencies`, after `    _snapDuration = d == Duration.zero ? const Duration(milliseconds: 1) : d;` add `    _reduced = BBMotion.reduced(context);`.
8. In `_onExtent`, replace:

```dart
    if (detent == null) {
      _lastDetent = null;
      return false;
    }
```

with:

```dart
    if (detent == null) {
      if (!_quiet) _lastDetent = null;
      return false;
    }
```

9. In `_handle`, replace:

```dart
    final bb = context.bb;
    final at = _nearest;
    final up = switch (at) {
```

with:

```dart
    final bb = context.bb;
    final at = _nearest;
    final bar = Container(
      width: 34,
      height: 4,
      decoration: BoxDecoration(color: bb.colors.line, borderRadius: BorderRadius.circular(2)),
    );
    if (widget.handleButton) return _handleButton(at, bar);
    final up = switch (at) {
```

and replace the end of `_handle`:

```dart
      child: Center(
        child: Container(
          margin: const EdgeInsets.only(top: BBSpace.s, bottom: BBSpace.s),
          width: 34,
          height: 4,
          decoration: BoxDecoration(color: bb.colors.line, borderRadius: BorderRadius.circular(2)),
        ),
      ),
    );
  }
```

with:

```dart
      child: Center(
        child: Padding(padding: const EdgeInsets.symmetric(vertical: BBSpace.s), child: bar),
      ),
    );
  }

  /// The home sheet's handle (spec 2026-10-14 §3.6): a full-width button, one stop per tap. Expand and Collapse stay
  /// as screen-reader actions, so full height is reachable without a drag.
  Widget _handleButton(BBSheetDetent at, Widget bar) {
    final atPeek = at == BBSheetDetent.peek;
    final target = switch (at) {
      BBSheetDetent.peek => BBSheetDetent.half,
      BBSheetDetent.half => BBSheetDetent.peek,
      BBSheetDetent.full => BBSheetDetent.half,
    };
    void go() => _go(target);
    return Semantics(
      key: BBSheet.handleKey,
      container: true,
      button: true,
      label: atPeek ? 'Show more' : 'Show less',
      onTap: go,
      customSemanticsActions: {
        if (at != BBSheetDetent.full) const CustomSemanticsAction(label: 'Expand'): () => _go(BBSheetDetent.full),
        if (at != BBSheetDetent.peek) const CustomSemanticsAction(label: 'Collapse'): () => _go(BBSheetDetent.peek),
      },
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: go,
        child: SizedBox(height: BBSheet.handleButtonExtent, child: Center(child: bar)),
      ),
    );
  }
```

(The tap recognizer only wins taps: a drag that starts on the handle still goes to the sheet's scrollable, so the sheet still drags by its handle.)

Run: `flutter test test/kit/sheet_test.dart`
Expected: PASS.

- [ ] **Step 3: Write the failing flag tests and create the flags**

Create `test/state/seen_flags_test.dart`:

```dart
import 'package:busboard_nl/state/seen_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_alerts.dart';

void main() {
  setUp(useInMemoryAlertStore);

  test('a flag reads false until marked, then true, and stays true on the next start', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(barHintSeenProvider.future), isFalse);
    await c.read(barHintSeenProvider.notifier).markSeen();
    expect(c.read(barHintSeenProvider).value, isTrue);
    expect(await SharedPreferencesAsync().getBool(barHintSeenKey), isTrue);
    final next = ProviderContainer();
    addTearDown(next.dispose);
    expect(await next.read(barHintSeenProvider.future), isTrue);
  });

  test('marking while the stored value is still being read keeps it marked', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(barHintSeenProvider.notifier).markSeen();
    expect(c.read(barHintSeenProvider).value, isTrue);
    expect(await c.read(barHintSeenProvider.future), isTrue);
  });

  test('the seen double is seen without reading the phone', () async {
    final c = ProviderContainer(overrides: [
      barHintSeenProvider.overrideWith(() => SeenFlagNotifier.seen(barHintSeenKey)),
    ]);
    addTearDown(c.dispose);
    expect(await c.read(barHintSeenProvider.future), isTrue);
    expect(await SharedPreferencesAsync().getBool(barHintSeenKey), isNull);
  });
}
```

Run it: FAIL to compile (`seen_flags.dart` doesn't exist). Then create `lib/state/seen_flags.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The SharedPreferences key of the bar's one-time lift (spec 2026-10-14 §3.6).
const barHintSeenKey = 'home_bar_hint_seen.v1';

/// A one-time hint that, once seen, never shows again: a flag kept on the phone under [key].
class SeenFlagNotifier extends AsyncNotifier<bool> {
  SeenFlagNotifier(this.key);

  /// Already seen, for tests.
  factory SeenFlagNotifier.seen(String key) = _AlreadySeen;

  final String key;

  @override
  Future<bool> build() async => await SharedPreferencesAsync().getBool(key) ?? false;

  /// Stores the flag. Waits for the stored value first, so a read still in flight can't bring the hint back.
  Future<void> markSeen() async {
    try {
      if (await future) return;
    } catch (_) {
      // Unreadable: store it anyway.
    }
    state = const AsyncData(true);
    await SharedPreferencesAsync().setBool(key, true);
  }
}

class _AlreadySeen extends SeenFlagNotifier {
  _AlreadySeen(super.key);

  @override
  Future<bool> build() async => true;
}

/// Whether the bar's one-time lift has played.
final barHintSeenProvider = AsyncNotifierProvider<SeenFlagNotifier, bool>(() => SeenFlagNotifier(barHintSeenKey));
```

(`markSeen` awaits `future` first: if it set the state while the first read was still in flight, that read would finish afterwards and set it back to `false`.)

Run: `flutter test test/state/seen_flags_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 4: Keep the hint out of every existing screen test**

The hint moves the sheet, so screen tests start with it seen, as they already do for the home tip.

In `test/helpers/planner_app.dart`:
1. Add `import 'package:busboard_nl/state/seen_flags.dart';` after `import 'package:busboard_nl/state/providers.dart';`.
2. Replace the doc line `/// The one-time home tip is already seen unless [homeTipSeen] is false (it sits above "Where to?" and moves the peek).` with:

```dart
/// The one-time home tip is already seen unless [homeTipSeen] is false (it sits above "Where to?" and moves the peek),
/// and so is the bar's one-time lift unless [barHintSeen] is false.
```

3. After the parameter `  bool homeTipSeen = true,` add `  bool barHintSeen = true,`.
4. After `        if (homeTipSeen) homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen()),` add:

```dart
        if (barHintSeen) barHintSeenProvider.overrideWith(() => SeenFlagNotifier.seen(barHintSeenKey)),
```

In `test/ui/home_screen_test.dart` (its own `_pump`, whose stub map calls `onReady`, where the hint starts):
1. Add `import 'package:busboard_nl/state/seen_flags.dart';` after `import 'package:busboard_nl/state/providers.dart';`.
2. In `_pump`'s parameters, after `  bool disableAnimations = false,` add `  bool barHintSeen = true,`.
3. Replace:

```dart
      busTrackingStreamProvider.overrideWith((ref) => busStream ?? Stream.value(buses)),
      ...fakeAlertOverrides,
      ...overrides,
```

with:

```dart
      busTrackingStreamProvider.overrideWith((ref) => busStream ?? Stream.value(buses)),
      // The bar's one-time lift moves the sheet: off unless a test asks for it.
      if (barHintSeen) barHintSeenProvider.overrideWith(() => SeenFlagNotifier.seen(barHintSeenKey)),
      ...fakeAlertOverrides,
      ...overrides,
```

In `test/ui/saved_trips_test.dart`, the home handle is no longer labelled "Map sheet": replace `  await tester.drag(find.bySemanticsLabel('Map sheet'), const Offset(0, -600));` with `  await tester.drag(find.byKey(BBSheet.handleKey), const Offset(0, -600));`.

- [ ] **Step 5: Write the failing home tests**

In `test/ui/home_screen_test.dart`, before `void main() {` add:

```dart
/// The bar hint's flag, held until [gate] completes, so a test can watch the lift from its start.
class _HeldFlag extends SeenFlagNotifier {
  _HeldFlag(this.gate) : super(barHintSeenKey);
  final Completer<bool> gate;
  @override
  Future<bool> build() => gate.future;
}

```

and before `  testWidgets('no overflow at 320 pt and text x2.0', (tester) async {` (the one right after the stop-line test from Task 4) add:

```dart
  group('the bar hint (spec 2026-10-14 §3.6)', () {
    /// Pumps home with the hint not yet seen, lets the flag answer, and records the sheet's top every frame for 1.3 s.
    Future<List<double>> watchHint(WidgetTester tester, {bool reduceMotion = false}) async {
      final gate = Completer<bool>();
      await _pump(tester, prefs: {'selectedStopId': '1150'}, barHintSeen: false, disableAnimations: reduceMotion,
          overrides: [
            barHintSeenProvider.overrideWith(() => _HeldFlag(gate)),
            homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen()),
          ]);
      final tops = [tester.getRect(find.byKey(BBSheet.cardKey)).top];
      gate.complete(false);
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        tops.add(tester.getRect(find.byKey(BBSheet.cardKey)).top);
      }
      return tops;
    }

    testWidgets('the first time the bar shows, the sheet lifts about 24 pt and settles back, and that is stored',
        (tester) async {
      final tops = await watchHint(tester);
      expect(tops.reduce(math.min), lessThanOrEqualTo(tops.first - 20), reason: 'it lifts');
      expect(tops.last, closeTo(tops.first, 0.5), reason: 'and settles back at the bar');
      expect(await SharedPreferencesAsync().getBool(barHintSeenKey), isTrue);
    });

    testWidgets('it plays once: back at the bar after a card, the sheet stays put', (tester) async {
      await watchHint(tester);
      final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      c.read(homeSheetProvider.notifier).open(const StopSheet('1150'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      c.read(homeSheetProvider.notifier).home();
      // A new home sheet measures its bar on its first frames.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final rest = tester.getRect(find.byKey(BBSheet.cardKey)).top;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, closeTo(rest, 0.5));
      }
    });

    testWidgets('a card that opens while the flag is read is never lifted; the hint waits for the bar', (tester) async {
      final gate = Completer<bool>();
      await _pump(tester, prefs: {'selectedStopId': '1150'}, barHintSeen: false, overrides: [
        barHintSeenProvider.overrideWith(() => _HeldFlag(gate)),
        homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen()),
      ]);
      final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      // A notification's stop card arrives first.
      c.read(homeSheetProvider.notifier).open(const StopSheet('1150'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final half = tester.getRect(find.byKey(BBSheet.cardKey)).top;
      gate.complete(false);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, half, reason: 'the card is not nudged');
      }
      expect(await SharedPreferencesAsync().getBool(barHintSeenKey), isNull, reason: 'not shown yet');
      // Back at the bar, it plays.
      c.read(homeSheetProvider.notifier).home();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final tops = <double>[];
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        tops.add(tester.getRect(find.byKey(BBSheet.cardKey)).top);
      }
      expect(await SharedPreferencesAsync().getBool(barHintSeenKey), isTrue);
      expect(tops.last, closeTo(tops.reduce(math.max), 0.5), reason: 'it settles back at the bar');
    });

    testWidgets('never under Reduce Motion, and nothing is stored', (tester) async {
      final tops = await watchHint(tester, reduceMotion: true);
      expect(tops.reduce(math.max) - tops.reduce(math.min), lessThan(0.5));
      expect(await SharedPreferencesAsync().getBool(barHintSeenKey), isNull);
    });
  });

```

In `test/ui/home_sheet_test.dart`, before `  testWidgets('an alert that is not on your stop or its routes stays out of the header', (tester) async {` add:

```dart
  testWidgets('the handle is a button: Show more at the bar, Show less pulled up, one stop per tap (spec 2026-10-14 §3.6)',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    expect(
      tester.getSemantics(find.byKey(BBSheet.handleKey)),
      isSemantics(label: 'Show more', isButton: true, hasTapAction: true),
    );
    final bar = tester.getRect(find.byKey(BBSheet.cardKey)).height;
    await tester.tap(find.byKey(BBSheet.handleKey));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * (844 - 2 * BBSpace.s), 1));
    expect(tester.getSemantics(find.byKey(BBSheet.handleKey)), isSemantics(label: 'Show less', isButton: true));
    tester.semantics.tap(find.semantics.byLabel('Show less'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(bar, 1), reason: 'back down to the bar');
    // A card's handle stays the adjustable "Map sheet" control.
    _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.byKey(BBSheet.handleKey)), isSemantics(label: 'Map sheet', isButton: false));
    handle.dispose();
  });

```

Run: `flutter test test/ui/home_sheet_test.dart test/ui/home_screen_test.dart --plain-name "the handle is a button"` and `flutter test test/ui/home_screen_test.dart --plain-name "the bar hint"`
Expected: FAIL: the home handle is still "Map sheet", and nothing lifts (no flag is written).

- [ ] **Step 6: Wire the home screen**

In `lib/ui/home/home_screen.dart`:

1. Add `import '../../state/seen_flags.dart';` after `import '../../state/providers.dart';`.
2. Replace:

```dart
  static const _panPauseDistance = 18.0;
```

with:

```dart
  static const _panPauseDistance = 18.0;

  /// How far the bar's one-time hint lifts the sheet (spec 2026-10-14 §3.6).
  static const _barHintLift = 24.0;
```

3. Replace:

```dart
  /// The card [_onSheetOpened] last handled: the first build's check and the listener may both see one card open.
  HomeSheet _opened = const HomeSheetHome();
```

with:

```dart
  /// The card [_onSheetOpened] last handled: the first build's check and the listener may both see one card open.
  HomeSheet _opened = const HomeSheetHome();

  /// The bar's one-time lift has been tried this run (it plays at most once, and only if never seen before).
  bool _barHintTried = false;
```

4. In `_onReady`, replace:

```dart
    _surface = surface;
    _camera = camera;
    _fitJourneyIfDue();
```

with:

```dart
    _surface = surface;
    _camera = camera;
    unawaited(_hintBar());
    _fitJourneyIfDue();
```

5. Replace:

```dart
  /// The pull-up sheet is above its peek: it covers the bottom of the map, where "Back to bus" sits.
  bool _sheetAbovePeek = false;
```

with:

```dart
  /// The pull-up sheet is above its peek: it covers the bottom of the map, where "Back to bus" sits.
  bool _sheetAbovePeek = false;

  /// The first time the bar shows with the map ready, the sheet lifts [_barHintLift] and settles back, once ever
  /// (spec 2026-10-14 §3.6). Not under Reduce Motion (nothing is stored then, so it can play once motion is back), on
  /// the tablet panel, while following or choosing on the map, or with a card open.
  Future<void> _hintBar() async {
    if (_barHintTried || !mounted || _camera == null || BBMotion.reduced(context)) return;
    if (_wide || _follow != null || ref.read(mapPickProvider) != null) return;
    if (ref.read(homeSheetProvider) is! HomeSheetHome) return;
    final sheet = _sheet;
    if (!sheet.isAttached) return;
    _barHintTried = true;
    final bool seen;
    try {
      seen = await ref.read(barHintSeenProvider.future);
    } catch (e) {
      _log('Bar hint flag not read: $e');
      return;
    }
    if (seen || !mounted) return;
    // Something took the bar's place while the flag was read (a card, a follow, a map pick): try again once it is back.
    if (!identical(sheet, _sheet) || !sheet.isAttached || _follow != null || ref.read(mapPickProvider) != null) {
      _barHintTried = false;
      return;
    }
    unawaited(ref.read(barHintSeenProvider.notifier).markSeen().catchError((Object e) => _log('Bar hint not saved: $e')));
    await sheet.nudge(_barHintLift);
  }
```

6. In `build`, replace:

```dart
      _forgetBoard();
      _onSheetOpened(next);
    });
```

with:

```dart
      _forgetBoard();
      _onSheetOpened(next);
      // Back at the bar (a card opened at launch has closed): the one-time lift, if it has not played yet.
      if (next is HomeSheetHome) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_hintBar()));
    });
```

7. Replace:

```dart
      // The peek shows the whole header: handle (8 + 4 + 8) and a little air
      // under it. Until the header has been measured, an estimate.
      final measured = _headerHeight;
      final peekPx = measured == null ? (168 * media.textScaler.scale(1)).clamp(140.0, 320.0) : measured + 20 + BBSpace.s;
```

with:

```dart
      // The peek shows the whole header: the handle (the bar's is a 24 pt button) and a little air
      // under it. Until the header has been measured, an estimate.
      final measured = _headerHeight;
      final handle = homeShowing && !followShowing ? BBSheet.handleButtonExtent : BBSheet.handleExtent;
      final peekPx =
          measured == null ? (168 * media.textScaler.scale(1)).clamp(140.0, 320.0) : measured + handle + BBSpace.s;
```

8. Replace:

```dart
                  fadeUnderHeader: homeShowing && !followShowing,
```

with:

```dart
                  fadeUnderHeader: homeShowing && !followShowing,
                  // The bar's handle is a button: "Show more" / "Show less" (spec 2026-10-14 §3.6).
                  handleButton: homeShowing && !followShowing,
```

- [ ] **Step 7: Run the tests to see them pass**

Run: `flutter test test/kit/sheet_test.dart test/state/seen_flags_test.dart test/ui/home_sheet_test.dart test/ui/home_screen_test.dart test/ui/saved_trips_test.dart`
Expected: PASS.

- [ ] **Step 8: The whole suite**

`flutter analyze` and the non-golden suite. Expected: clean, all pass.

- [ ] **Step 9: Commit**

```bash
git add lib/ui/kit/bb_sheet.dart lib/state/seen_flags.dart lib/ui/home/home_screen.dart \
  test/kit/sheet_test.dart test/state/seen_flags_test.dart test/helpers/planner_app.dart \
  test/ui/home_screen_test.dart test/ui/home_sheet_test.dart test/ui/saved_trips_test.dart
git commit -m "feat(home): the bar's handle is a Show more / Show less button, and the bar lifts once to show it moves

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 6: The sheet tucks away on map gestures

The trigger lives in the map's own `Listener` (`home_screen.dart`, the `Positioned.fill` around `buildMap`), which already measures pans and pinches against `_panPauseDistance` to pause the follow camera. That `Listener` only sees pointers that went down on the map: the sheet sits above it in the `Stack` and wins the hit test for every touch that starts on the card. So the sheet's own drags and scrolls never reach the tuck-away, and the two can't fight.

**Files:**
- Modify: `lib/ui/home/home_screen.dart` (`_tucked`, `_sheetExtent`, `_peekFraction`, `_onPointerDown`, `_onPointerMove`, `_tuckSheet`, `_onSheetExtent`, `_sheetFor`, the peek in `build`, the map `Listener`)
- Modify: `test/ui/home_screen_test.dart`

**Interfaces:**
- Consumes: `BBSheetController.collapse()` (existing: animates to peek on the emphasis spring, 1 ms under reduce motion); `_panPauseDistance` (18); `mapPickProvider`; `_wide`; `_follow`.
- Produces: no public API. Behaviour: one deliberate map gesture (any pointer past 18 pt) collapses the pull-up sheet to its peek once, unless following, on the tablet panel, or choosing on the map.

- [ ] **Step 1: Write the failing tests**

In `test/ui/home_screen_test.dart`, before `  testWidgets('no overflow at 320 pt and text x2.0', (tester) async {` add:

```dart
  group('the sheet tucks away on map gestures (spec 2026-10-14 §3.4)', () {
    double top(WidgetTester tester) => tester.getRect(find.byKey(BBSheet.cardKey)).top;
    ProviderContainer container(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));

    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Home with your stop, the tip seen, and the home sheet pulled from its bar up to half. Returns the bar's top.
    Future<double> homeAtHalf(WidgetTester tester, {bool reduceMotion = false}) async {
      await _pump(tester, prefs: {'selectedStopId': '1150'}, disableAnimations: reduceMotion,
          overrides: [homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen())]);
      final bar = top(tester);
      await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
      await frames(tester);
      expect(top(tester), lessThan(bar - 200), reason: 'the home sheet is up at half');
      return bar;
    }

    /// A pan on bare map: left of the map buttons, between the chips and the sheet at half.
    Future<void> panMap(WidgetTester tester) async {
      await tester.dragFrom(const Offset(60, 170), const Offset(0, 40));
      await frames(tester);
    }

    testWidgets('a pan lowers the home sheet to its bar', (tester) async {
      final bar = await homeAtHalf(tester);
      await panMap(tester);
      expect(top(tester), closeTo(bar, 1));
    });

    testWidgets('a pan lowers a stop card to its own lowest position, and the card stays', (tester) async {
      await _pump(tester, prefs: {'selectedStopId': '1150'});
      container(tester).read(homeSheetProvider.notifier).open(const StopSheet('1150'));
      await frames(tester);
      final card = tester.widget<BBSheet>(find.byType(BBSheet));
      final area = 844 - 2 * BBSpace.s;
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(card.halfFraction * area, 1));
      await panMap(tester);
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(card.peekFraction * area, 1));
      expect(container(tester).read(homeSheetProvider), const StopSheet('1150'));
    });

    testWidgets('a tap, or a move shorter than a pan, leaves the sheet where it is', (tester) async {
      await _pump(tester, prefs: {'selectedStopId': '1150'});
      container(tester).read(homeSheetProvider.notifier).open(const StopSheet('1150'));
      await frames(tester);
      final half = top(tester);
      final gesture = await tester.startGesture(const Offset(60, 170));
      await gesture.moveBy(const Offset(0, 10));
      await frames(tester);
      expect(top(tester), half);
      await gesture.cancel();
    });

    testWidgets('not while choosing on the map', (tester) async {
      await homeAtHalf(tester);
      container(tester).read(mapPickProvider.notifier).start(MapPick.to);
      await frames(tester);
      final half = top(tester);
      await panMap(tester);
      expect(top(tester), half);
    });

    testWidgets('not on the tablet side panel, which has no detents', (tester) async {
      await _pump(tester, size: const Size(1024, 768), prefs: {'selectedStopId': '1150'});
      final panel = tester.getRect(find.byKey(const ValueKey('home-side-panel')));
      await tester.dragFrom(const Offset(800, 400), const Offset(0, 40));
      await frames(tester);
      expect(find.byType(BBSheet), findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('home-side-panel'))), panel);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a drag that starts on the sheet is the sheet's own: pulled up to full, it stays", (tester) async {
      await homeAtHalf(tester);
      await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -400));
      await frames(tester);
      final full = top(tester);
      final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.fullFraction * (844 - 2 * BBSpace.s), 1));
      await frames(tester);
      expect(top(tester), full);
    });

    testWidgets('a two-finger pinch lowers the sheet once, to its bar', (tester) async {
      final bar = await homeAtHalf(tester);
      final a = await tester.startGesture(const Offset(60, 150), pointer: 1);
      final b = await tester.startGesture(const Offset(60, 190), pointer: 2);
      for (var i = 0; i < 4; i++) {
        await a.moveBy(const Offset(0, -8));
        await b.moveBy(const Offset(0, 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await frames(tester);
      expect(top(tester), closeTo(bar, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('with Reduce Motion the sheet jumps down', (tester) async {
      final bar = await homeAtHalf(tester, reduceMotion: true);
      await tester.dragFrom(const Offset(60, 170), const Offset(0, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(top(tester), closeTo(bar, 1));
    });
  });

```

In the `follow mode` group of the same file, before `    testWidgets('a plain tap on the map does not pause', (tester) async {` add:

```dart
    testWidgets('a pan never moves the follow card: it keeps its place (spec 2026-10-14 §3.4)', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      await tester.drag(find.byType(FollowCardHeader), const Offset(0, -300));
      await _frames(tester, 30);
      final pulledUp = tester.getRect(find.byKey(BBSheet.cardKey)).top;
      await tester.dragFrom(const Offset(60, 170), const Offset(0, 40));
      await _frames(tester, 6);
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, pulledUp);
    });

```

The pan point (60, 170) is bare map on a 390x844 phone: below the route chip row, left of the Alerts/Settings/My location column, and above a sheet or card at half.

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/ui/home_screen_test.dart --plain-name "tucks away"`
Expected: FAIL in "a pan lowers the home sheet to its bar", "a pan lowers a stop card to its own lowest position, and the card stays", "a two-finger pinch lowers the sheet once, to its bar" and "with Reduce Motion the sheet jumps down" (the sheet doesn't move). The other cases already pass and guard the exceptions.

- [ ] **Step 3: Implement the tuck-away**

In `lib/ui/home/home_screen.dart`:

1. Replace:

```dart
  _Follow? _follow;
  final _pointerStarts = <int, Offset>{};
```

with:

```dart
  _Follow? _follow;
  final _pointerStarts = <int, Offset>{};

  /// The map gesture under way has already tucked the sheet away (or been found not to): once per gesture.
  bool _tucked = false;

  /// The pull-up sheet's latest extent, and its peek as last laid out: the tuck-away moves only a sheet above its peek.
  double _sheetExtent = 0;
  double _peekFraction = 0;
```

2. Replace the whole `_onPointerMove` method:

```dart
  void _onPointerMove(PointerMoveEvent e) {
    final f = _follow;
    final start = _pointerStarts[e.pointer];
    if (start == null || (e.position - start).distance <= _panPauseDistance) return;
    // A pan or a pinch moves the camera: the follow camera pauses and the location ping is dropped.
    if (_pinging || (f != null && !f.paused)) {
      setState(() {
        _pinging = false;
        f?.paused = true;
      });
    }
  }
```

with:

```dart
  void _onPointerDown(PointerDownEvent e) {
    // The first finger of a new gesture: it may tuck the sheet away once.
    if (_pointerStarts.isEmpty) _tucked = false;
    _pointerStarts[e.pointer] = e.position;
  }

  void _onPointerMove(PointerMoveEvent e) {
    final f = _follow;
    final start = _pointerStarts[e.pointer];
    if (start == null || (e.position - start).distance <= _panPauseDistance) return;
    // A pan or a pinch moves the camera: the follow camera pauses and the location ping is dropped.
    if (_pinging || (f != null && !f.paused)) {
      setState(() {
        _pinging = false;
        f?.paused = true;
      });
    }
    _tuckSheet();
  }

  /// A deliberate pan or pinch on the map (past [_panPauseDistance], so never a tap) lowers the pull-up sheet to its
  /// lowest stop, once per gesture (spec 2026-10-14 §3.4): the home sheet to its bar, a stop, bus, options or trip card
  /// to its own peek. Only the map's Listener calls it, so the sheet's own drags and scrolls never do. Not while
  /// following (the follow card keeps its place), on the tablet panel, or while choosing on the map. Under Reduce Motion
  /// the sheet's 1 ms snap makes it a jump.
  void _tuckSheet() {
    if (_tucked) return;
    _tucked = true;
    if (_wide || _follow != null || ref.read(mapPickProvider) != null) return;
    if (!_sheet.isAttached || _sheetExtent <= _peekFraction + 0.005) return;
    unawaited(_sheet.collapse());
  }
```

3. In `_onSheetExtent`, replace:

```dart
  bool _onSheetExtent(DraggableScrollableNotification n) {
    final wasAtFull = _sheetAtFull;
```

with:

```dart
  bool _onSheetExtent(DraggableScrollableNotification n) {
    _sheetExtent = n.extent;
    final wasAtFull = _sheetAtFull;
```

4. In `_sheetFor`, replace:

```dart
      _sheetKey = key;
      _sheetAtFull = false;
```

with:

```dart
      _sheetKey = key;
      _sheetAtFull = false;
      _sheetExtent = 0;
```

5. In `build`, replace:

```dart
      final peek = math.max((peekPx / sheetArea).clamp(0.12, maxPeek), math.min(actionsPx / sheetArea, _maxActionsPeek));
```

with:

```dart
      final peek = math.max((peekPx / sheetArea).clamp(0.12, maxPeek), math.min(actionsPx / sheetArea, _maxActionsPeek));
      _peekFraction = peek;
```

6. Replace:

```dart
              // Translucent: the map still gets every touch. Moving a pointer
              // far enough (a pan or a pinch) pauses the follow camera.
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) => _pointerStarts[e.pointer] = e.position,
```

with:

```dart
              // Translucent: the map still gets every touch. Moving a pointer
              // far enough (a pan or a pinch) pauses the follow camera and tucks the sheet away.
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `flutter test test/ui/home_screen_test.dart`
Expected: PASS (the new group, the new follow-mode case, and every existing follow/pan/ping test: "panning pauses the camera", "a plain tap on the map does not pause", "a 10 px jitter does not pause", "a two-finger pinch pauses").

- [ ] **Step 5: The whole suite**

`flutter analyze` and the non-golden suite. Expected: clean, all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/home/home_screen.dart test/ui/home_screen_test.dart
git commit -m "feat(home): a deliberate pan or pinch on the map lowers the sheet out of the way

The home sheet drops to its bar and a card to its own lowest position.
Never while following, on the tablet panel or while choosing on the map.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 7: Follow you can find: the pill, the explaining tap, the one-time tip

**Files:**
- Rewrite: `lib/ui/board/arrival_row_tile.dart`
- Modify: `lib/ui/kit/bb_toast.dart` (`announce:`)
- Create: `lib/ui/home/follow_tip.dart`
- Modify: `lib/state/seen_flags.dart` (`followTipSeenKey`, `followTipSeenProvider`)
- Modify: `lib/ui/home/stop_sheet.dart`, `lib/ui/map/stop_card.dart`, `lib/ui/home/home_screen.dart` (the follow listener)
- Modify: `test/helpers/planner_app.dart` (`followTipSeen`), `test/ui/arrival_row_tile_test.dart`, `test/kit/feedback_components_test.dart`, `test/ui/stop_sheet_test.dart`

**Interfaces:**
- Consumes: `SeenFlagNotifier`, `seen_flags.dart` (Task 5); `FollowableArrival.followableVehicle` (existing extension in `lib/state/follow_providers.dart`: the vehicle when `isLive` and the number is non-empty).
- Produces:
  - `ArrivalRowTile({Key? key, required ArrivalRow arrival, VoidCallback? onTap, VoidCallback? onExplain, Widget? action})`. `onTap` still means "follow this row's bus"; a live row with `onTap` and a non-empty vehicle shows the Follow pill (`ArrivalRowTile.followKey`) in place of "Bus 2134". `onExplain` is the tap for a row with no bus to follow.
  - `static const ArrivalRowTile.followKey = ValueKey('arrival-follow')`, `static const String ArrivalRowTile.notLiveYet = "No bus on this trip yet. You can follow it once it's live."`, `static String ArrivalRowTile.followLabel(String vehicle)` → `'Follow bus $vehicle on the map'`.
  - `BBToast.show(BuildContext, String, {Duration duration = 3 s, bool announce = false})`.
  - `const followTipSeenKey = 'follow_tip_seen.v1'`, `followTipSeenProvider` (same shape as `barHintSeenProvider`).
  - `class FollowTip extends ConsumerWidget` with `static const text = 'Tap a live bus to follow it on the map'` and `static const closeKey = ValueKey('follow-tip-close')`; its close button is labelled "Hide this tip".
  - `pumpPlannerApp(…, bool followTipSeen = true)`.

- [ ] **Step 1: Write the failing tests**

In `test/ui/arrival_row_tile_test.dart`, before `  testWidgets('a row without onTap has no tap action', (tester) async {` add:

```dart
  group('the Follow pill (spec 2026-10-14 §4.1)', () {
    testWidgets('a followable live row shows "Follow 2134" in place of "Bus 2134", in brandSoft and brandInk',
        (tester) async {
      await tester.pumpWidget(kitHost(ArrivalRowTile(
        arrival: _row(isLive: true, status: LiveStatus.onTime, vehicle: '2134', routeRun: '29-1'),
        onTap: () {},
      )));
      expect(find.textContaining('Follow 2134'), findsOneWidget);
      expect(find.text('29-1'), findsOneWidget);
      expect(find.textContaining('Bus 2134'), findsNothing);
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byKey(ArrivalRowTile.followKey), matching: find.byType(DecoratedBox)).first,
      );
      expect((box.decoration as BoxDecoration).color, BBColors.light.brandSoft);
      final text = tester.widget<Text>(find.textContaining('Follow 2134'));
      expect(text.style!.color, BBColors.light.brandInk);
    });

    testWidgets('its target is at least 44 x 44, it is its own button, and a tap follows', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(kitHost(ArrivalRowTile(
        arrival: _row(isLive: true, status: LiveStatus.onTime, vehicle: '2134'),
        onTap: () => taps++,
      )));
      final pill = find.byKey(ArrivalRowTile.followKey);
      final size = tester.getSize(pill);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(pill),
        isSemantics(label: 'Follow bus 2134 on the map', isButton: true, hasTapAction: true),
      );
      await tester.tap(pill);
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('no pill without a follow, or on a scheduled row', (tester) async {
      await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(isLive: true, vehicle: '2134', routeRun: '29-1'))));
      expect(find.byKey(ArrivalRowTile.followKey), findsNothing);
      expect(find.text('29-1 · Bus 2134'), findsOneWidget, reason: 'the Board keeps the plain bus number');
      await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(), onExplain: () {})));
      expect(find.byKey(ArrivalRowTile.followKey), findsNothing);
    });

    testWidgets('at 2x text on 320 pt the pill reads in full', (tester) async {
      await tester.pumpWidget(kitHost(
        ArrivalRowTile(
          arrival: _row(isLive: true, status: LiveStatus.onTime, vehicle: '2134', routeRun: '29-1', minutes: 15),
          onTap: () {},
        ),
        textScale: 2.0,
        width: 320,
      ));
      expect(tester.takeException(), isNull);
      final pill = tester.renderObject<RenderParagraph>(find.textContaining('Follow 2134'));
      expect(pill.didExceedMaxLines, isFalse);
    });
  });

  testWidgets('a row with onExplain is a button that explains, with no follow hint (spec 2026-10-14 §4.2)',
      (tester) async {
    final handle = tester.ensureSemantics();
    var explained = 0;
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(), onExplain: () => explained++)));
    expect(
      find.semantics.byLabel('Route 29 Signal Hill Rd, scheduled, 4 minutes'),
      isSemantics(label: 'Route 29 Signal Hill Rd, scheduled, 4 minutes', isButton: true, hasTapAction: true),
    );
    await tester.tap(find.text('Signal Hill Rd'));
    expect(explained, 1);
    handle.dispose();
  });

```

In `test/kit/feedback_components_test.dart`, before `  testWidgets('toast stays above the on-screen keyboard', (tester) async {` add:

```dart
  testWidgets('a toast with announce tells screen readers at once; a plain one leaves it to its live region',
      (tester) async {
    final said = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (m) async {
      final event = m as Map<Object?, Object?>;
      if (event['type'] == 'announce') said.add((event['data']! as Map<Object?, Object?>)['message']! as String);
      return null;
    });
    addTearDown(() =>
        tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
    await tester.pumpWidget(_launcher((c) => BBToast.show(c, 'plain')));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(said, isEmpty);
    await tester.pumpWidget(_launcher((c) => BBToast.show(c, 'No bus on this trip yet.', announce: true)));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(said, ['No bus on this trip yet.']);
    expect(find.text('No bus on this trip yet.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

```

In `test/helpers/planner_app.dart`:
1. Replace the doc lines added in Task 5:

```dart
/// The one-time home tip is already seen unless [homeTipSeen] is false (it sits above "Where to?" and moves the peek),
/// and so is the bar's one-time lift unless [barHintSeen] is false.
```

with:

```dart
/// The one-time home tip is already seen unless [homeTipSeen] is false (it sits above "Where to?" and moves the peek),
/// and so are the bar's one-time lift unless [barHintSeen] is false and the stop sheet's follow tip unless
/// [followTipSeen] is false.
```

2. After `  bool barHintSeen = true,` add `  bool followTipSeen = true,`.
3. After `        if (barHintSeen) barHintSeenProvider.overrideWith(() => SeenFlagNotifier.seen(barHintSeenKey)),` add:

```dart
        if (followTipSeen) followTipSeenProvider.overrideWith(() => SeenFlagNotifier.seen(followTipSeenKey)),
```

In `test/ui/stop_sheet_test.dart`:

1. Imports: add `import 'package:busboard_nl/state/seen_flags.dart';` after the `providers.dart` import; `import 'package:busboard_nl/ui/home/follow_tip.dart';` before the `home_screen.dart` import; `import 'package:flutter/services.dart' show SystemChannels;` after `import 'package:flutter/rendering.dart' show RenderParagraph;`; `import 'package:shared_preferences/shared_preferences.dart';` after `import 'package:http/testing.dart';`.
2. In `_pump`, add the parameter `  bool followTipSeen = true,` after `  bool use24h = true,`, and pass `    followTipSeen: followTipSeen,` to `pumpPlannerApp` after `    use24h: use24h,`.
3. Before `Future<void> _unmount(WidgetTester tester) async {` add:

```dart
/// Records what the app announces to screen readers.
List<String> _announcements(WidgetTester tester) {
  final said = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (m) async {
    final event = m as Map<Object?, Object?>;
    if (event['type'] == 'announce') said.add((event['data']! as Map<Object?, Object?>)['message']! as String);
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null),
  );
  return said;
}

```

4. Replace the whole test `testWidgets('a scheduled-only row is not tappable', …` (through its closing `  });`) with:

```dart
  testWidgets('a scheduled row explains itself: a toast, announced, and the row stays (spec 2026-10-14 §4.2)',
      (tester) async {
    final said = _announcements(tester);
    await _pump(tester, repo: _repoWithDepartures(), timeTrackClient: _liveFeed2573);
    expect(find.text('Schedule Terminal'), findsOneWidget);
    final before = tester.getRect(find.text('Schedule Terminal'));
    await tester.tap(find.text('Schedule Terminal'));
    await tester.pumpAndSettle();
    expect(find.text(ArrivalRowTile.notLiveYet), findsOneWidget);
    expect(said, [ArrivalRowTile.notLiveYet]);
    expect(tester.getRect(find.text('Schedule Terminal')), before, reason: 'the row stays where it is');
    expect(_c(tester).read(homeSheetProvider), const StopSheet('1150'));
    expect(_c(tester).read(followProvider), isNull);
    await _unmount(tester);
  });

  testWidgets("a live row's Follow pill follows its bus (spec 2026-10-14 §4.1)", (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, repo: _repoWithDepartures(), timeTrackClient: _liveFeed2573);
    final pill = find.byKey(ArrivalRowTile.followKey);
    expect(pill, findsOneWidget, reason: 'only the live row has one');
    expect(find.textContaining('Follow 2573'), findsOneWidget);
    expect(
      tester.getSemantics(pill),
      isSemantics(label: 'Follow bus 2573 on the map', isButton: true, hasTapAction: true),
    );
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(_c(tester).read(followProvider), const FollowTarget('2573'));
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
    handle.dispose();
    await _unmount(tester);
  });

  group('the one-time follow tip (spec 2026-10-14 §4.3)', () {
    testWidgets('shows under live departures; closing it stores that', (tester) async {
      await _pump(tester, repo: _repoWithDepartures(), timeTrackClient: _liveFeed2573, followTipSeen: false);
      expect(find.text(FollowTip.text), findsOneWidget);
      await tester.ensureVisible(find.byKey(FollowTip.closeKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FollowTip.closeKey));
      await tester.pumpAndSettle();
      expect(find.text(FollowTip.text), findsNothing);
      expect(await SharedPreferencesAsync().getBool(followTipSeenKey), isTrue);
      await _unmount(tester);
    });

    testWidgets('a followed bus puts it away for good', (tester) async {
      await _pump(tester, repo: _repoWithDepartures(), timeTrackClient: _liveFeed2573, followTipSeen: false);
      expect(find.text(FollowTip.text), findsOneWidget);
      await tester.tap(find.text('Live Terminal'));
      await tester.pumpAndSettle();
      expect(await SharedPreferencesAsync().getBool(followTipSeenKey), isTrue);
      _c(tester).read(followProvider.notifier).stop();
      _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('1150'));
      await tester.pumpAndSettle();
      expect(find.text(FollowTip.text), findsNothing);
      await _unmount(tester);
    });

    testWidgets('not without a live departure', (tester) async {
      await _pump(tester, repo: _repoWithDepartures(), followTipSeen: false);
      expect(find.text('Schedule Terminal'), findsOneWidget);
      expect(find.text(FollowTip.text), findsNothing);
      await _unmount(tester);
    });
  });
```

5. Rename `testWidgets('scheduled-only and vehicle-less rows are inert', (tester) async {` to `testWidgets('scheduled-only and vehicle-less rows follow nothing', (tester) async {`, and in it replace:

```dart
    for (final route in ['5', '6', '7']) {
      await tester.tap(find.bySemanticsLabel(RegExp('^Route $route ')));
      await tester.pumpAndSettle();
    }
```

with:

```dart
    expect(find.byKey(ArrivalRowTile.followKey), findsNothing, reason: 'no bus to follow, no Follow pill');
    for (final route in ['5', '6', '7']) {
      await tester.tap(find.bySemanticsLabel(RegExp('^Route $route ')));
      await tester.pumpAndSettle();
    }
    expect(find.text(ArrivalRowTile.notLiveYet), findsOneWidget, reason: 'each says why instead');
```

6. In "only live rows announce the follow hint", replace:

```dart
    expect(
      find.semantics.byLabel('Route 5 Downtown, scheduled, 4 minutes'),
      isSemantics(label: 'Route 5 Downtown, scheduled, 4 minutes', isButton: false, hasTapAction: false),
    );
```

with:

```dart
    // A scheduled row is a button too, but it explains itself rather than follow (spec 2026-10-14 §4.2).
    expect(
      find.semantics.byLabel('Route 5 Downtown, scheduled, 4 minutes'),
      isSemantics(label: 'Route 5 Downtown, scheduled, 4 minutes', isButton: true, hasTapAction: true),
    );
```

Run: `flutter test test/ui/arrival_row_tile_test.dart test/kit/feedback_components_test.dart test/ui/stop_sheet_test.dart`
Expected: FAIL to compile (`onExplain`, `followKey`, `notLiveYet`, `announce`, `follow_tip.dart`, `followTipSeenKey` don't exist).

- [ ] **Step 2: The toast's announcement and the tip's flag**

In `lib/ui/kit/bb_toast.dart`:
1. Add `import 'package:flutter/semantics.dart';` before `import 'package:flutter/widgets.dart';`.
2. Replace:

```dart
  static void show(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    _dismissCurrent();
```

with:

```dart
  /// [announce] also tells screen readers now, for a message that answers a tap (a live region alone is not read
  /// out by VoiceOver).
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    bool announce = false,
  }) {
    _dismissCurrent();
    if (announce) {
      unawaited(SemanticsService.sendAnnouncement(View.of(context), message, Directionality.of(context)));
    }
```

In `lib/state/seen_flags.dart`, replace:

```dart
/// The SharedPreferences key of the bar's one-time lift (spec 2026-10-14 §3.6).
const barHintSeenKey = 'home_bar_hint_seen.v1';
```

with:

```dart
/// The SharedPreferences key of the bar's one-time lift (spec 2026-10-14 §3.6).
const barHintSeenKey = 'home_bar_hint_seen.v1';

/// The SharedPreferences key of the stop sheet's one-time follow tip (spec 2026-10-14 §4.3).
const followTipSeenKey = 'follow_tip_seen.v1';
```

and append at the end of the file:

```dart

/// Whether the stop sheet's one-time follow tip has been closed, or a bus followed.
final followTipSeenProvider = AsyncNotifierProvider<SeenFlagNotifier, bool>(() => SeenFlagNotifier(followTipSeenKey));
```

- [ ] **Step 3: The Follow pill and the explaining tap**

Replace the whole of `lib/ui/board/arrival_row_tile.dart` with:

```dart
import 'package:flutter/widgets.dart';

import '../../data/gtfs/gtfs_time.dart';
import '../../domain/arrival/arrival_models.dart';
import '../kit/kit.dart';

/// One departure on the Board: route badge · destination + status · minutes. A live row that can be followed shows a
/// Follow pill in its status line (spec 2026-10-14 §4.1).
class ArrivalRowTile extends StatelessWidget {
  const ArrivalRowTile({
    super.key,
    required this.arrival,
    this.onTap,
    this.onExplain,
    this.action,
  });

  final ArrivalRow arrival;

  /// Starts following this row's bus: the row and its Follow pill both call it. Null for a row with no bus to follow.
  final VoidCallback? onTap;

  /// A tap on a row with no bus to follow ([onTap] null): the caller says why (spec 2026-10-14 §4.2). Null leaves
  /// such a row inert.
  final VoidCallback? onExplain;

  /// A trailing control with its own semantics (the alert bell).
  final Widget? action;

  /// The Follow pill's tap target.
  static const followKey = ValueKey('arrival-follow');

  /// What a scheduled row's tap says (spec 2026-10-14 §4.2).
  static const notLiveYet = "No bus on this trip yet. You can follow it once it's live.";

  /// The Follow pill's screen-reader label.
  static String followLabel(String vehicle) => 'Follow bus $vehicle on the map';

  /// Minutes at or below which the countdown uses the `soon` colour.
  static const int soonThresholdMinutes = 5;

  /// Largest share of the row the minutes column may take, so large text scales
  /// make its lines wrap instead of pushing the row past the card edge.
  static const double _maxTrailingShare = 0.45;

  /// Plain-words status pill for a row (spec §6.2).
  static (String, BBPillTone) statusOf(ArrivalRow a) {
    if (a.isEnhanced) {
      return a.isLive
          ? ('Live', BBPillTone.live)
          : ('Scheduled', BBPillTone.neutral);
    }
    if (a.isLive) {
      return switch (a.liveStatus) {
        LiveStatus.ahead => ('Early', BBPillTone.live),
        LiveStatus.behind => ('Late', BBPillTone.warn),
        LiveStatus.onTime => ('On time', BBPillTone.live),
        null => ('Live', BBPillTone.live),
      };
    }
    return ('Scheduled', BBPillTone.neutral);
  }

  /// One sentence for screen readers, e.g. "Route 29 Signal Hill Rd, live, 4 minutes,
  /// expected 09:55" (the expected time is spoken only for live rows with a prediction).
  static String semanticsLabel(ArrivalRow a, {required bool use24h}) {
    final (status, _) = statusOf(a);
    final when = a.minutesAway <= 0
        ? 'now'
        : a.minutesAway == 1
        ? '1 minute'
        : '${a.minutesAway} minutes';
    final expected = a.isLive && a.predictedTime != null
        ? ', expected ${BBTime.clock(a.displayTime.totalSeconds, use24h: use24h)}'
        : '';
    return 'Route ${a.routeShortName} ${a.headsign}, ${status.toLowerCase()}, $when$expected';
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final a = arrival;
    final use24h = BBTime.use24h(context);
    String clock(GtfsTime t) => BBTime.clock(t.totalSeconds, use24h: use24h);
    final (status, tone) = statusOf(a);
    final vehicle = a.vehicleNumber;
    // The pill names the bus, so the plain "Bus 2134" goes (spec §4.1).
    final followable = onTap != null && a.isLive && vehicle != null && vehicle.isNotEmpty;
    final meta = [
      if (a.routeRun != null) a.routeRun!,
      if (a.isLive && vehicle != null && !followable) 'Bus $vehicle',
    ].join(' · ');
    final showPredicted = a.isLive && a.predictedTime != null;
    final timeLine = showPredicted
        ? 'exp ${clock(a.displayTime)}'
        : clock(a.scheduledTime);
    final showSched = showPredicted && a.scheduledTime != a.predictedTime;
    final soon = a.minutesAway <= soonThresholdMinutes;
    final tap = onTap ?? onExplain;

    // The row's own sentence stands for everything in it but the Follow pill, which keeps its own node.
    final content = LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          ExcludeSemantics(child: RouteBadge.name(a.routeShortName)),
          const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Text(
                    a.headsign,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: bb.text.headline,
                  ),
                ),
                const SizedBox(height: 3),
                // At large text the pill wraps under the status rather than truncate.
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ExcludeSemantics(
                      child: BBPill(
                        label: status,
                        tone: tone,
                        leadingDot: tone == BBPillTone.live,
                      ),
                    ),
                    if (meta.isNotEmpty) ExcludeSemantics(child: Text(meta, style: bb.text.caption)),
                    if (followable) _FollowPill(vehicle: vehicle, onTap: onTap!),
                  ],
                ),
                if (a.isLive && (a.currentLocation?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: ExcludeSemantics(
                      child: Text(
                        'Near ${a.currentLocation}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: bb.text.caption,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: BBSpace.m),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: box.maxWidth * _maxTrailingShare,
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // The number rolls as it counts down (spec §3.2).
                  BBRollingText(
                    a.minutesAway <= 0 ? 'Now' : '${a.minutesAway}',
                    style: bb.text.minutes.copyWith(
                      color: soon ? bb.colors.soon : bb.colors.ink,
                    ),
                  ),
                  if (a.minutesAway > 0) Text('min', style: bb.text.minutesUnit),
                  const SizedBox(height: 2),
                  Text(timeLine, style: bb.text.caption),
                  if (showSched)
                    Text(
                      'sched ${clock(a.scheduledTime)}',
                      style: bb.text.caption.copyWith(
                        decoration: TextDecoration.lineThrough,
                        decorationColor: bb.colors.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    // A row becoming "Now" swells once and its card edge glows brand (spec §3.2).
    return BBNowPulse(
      active: a.minutesAway <= 0,
      child: BBCard(
        onTap: tap,
        // The content below carries the tap and label; the card adds no second node.
        exposeSemantics: false,
        child: Row(
          children: [
            Expanded(
              // The content's own semantics replace the card's, so the tap is
              // restated here; the action stays outside so it keeps its own.
              child: Semantics(
                container: true,
                label: semanticsLabel(a, use24h: use24h),
                button: tap != null ? true : null,
                onTap: tap,
                onTapHint: onTap == null ? null : 'follow bus ${a.vehicleNumber} on the map',
                child: content,
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// "Follow 2134" (spec 2026-10-14 §4.1): `brandSoft` with `brandInk` text, in a 44 pt target. It follows the bus, as
/// the row does.
class _FollowPill extends StatelessWidget {
  const _FollowPill({required this.vehicle, required this.onTap});

  final String vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final ink = bb.colors.brandInk;
    return Semantics(
      container: true,
      child: BBPressable(
        key: ArrivalRowTile.followKey,
        semanticLabel: ArrivalRowTile.followLabel(vehicle),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: bb.colors.brandSoft, borderRadius: BorderRadius.circular(BBRadius.pill)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: BBSpace.s, vertical: 3),
                // One paragraph, icon and words, so on a narrow row it wraps instead of overflowing.
                child: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(BBIcons.bus, size: 14, color: ink),
                      ),
                      TextSpan(text: ' Follow $vehicle'),
                    ],
                  ),
                  style: bb.text.caption.copyWith(color: ink, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

What changed from the old file: the constructor's `onExplain`, `followKey`, `notLiveYet` and `followLabel`; `followable` drops "Bus 2134" from the meta line and adds `_FollowPill` to the status `Wrap`; the row's `Semantics` is now a `container` that excludes each text piece one by one (instead of `excludeSemantics: true` over everything), so the pill keeps its own node; the row's tap is `onTap ?? onExplain`, with the follow hint only for `onTap`. The pill's icon and words are one `Text.rich` paragraph, so on a narrow row at large text it wraps instead of overflowing; the `Wrap` puts it under the status when it doesn't fit beside it.

- [ ] **Step 4: The tip, and wiring the stop sheet**

Create `lib/ui/home/follow_tip.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/seen_flags.dart';
import '../kit/kit.dart';

/// The one-time tip under a stop's departures while one of them is live (spec 2026-10-14 §4.3). It goes for good once
/// the rider closes it or follows a bus (the home screen marks it then).
class FollowTip extends ConsumerWidget {
  const FollowTip({super.key});

  static const text = 'Tap a live bus to follow it on the map';
  static const closeKey = ValueKey('follow-tip-close');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(followTipSeenProvider).value != false) return const SizedBox.shrink();
    final bb = context.bb;
    return Row(
      children: [
        Icon(BBIcons.info, size: 18, color: bb.colors.muted),
        const SizedBox(width: BBSpace.s),
        Expanded(child: Text(text, style: bb.text.caption)),
        BBIconButton(
          key: closeKey,
          icon: BBIcons.close,
          size: 18,
          color: bb.colors.muted,
          semanticLabel: 'Hide this tip',
          onPressed: () => ref.read(followTipSeenProvider.notifier).markSeen(),
        ),
      ],
    );
  }
}
```

In `lib/ui/home/stop_sheet.dart`:
1. Add `import 'follow_tip.dart';` after `import '../kit/kit.dart';`.
2. In `_StopBody.build`, after the `follow` function (ending `    }` just before the comment `// Rows are keyed by trip and scheduled time …`), add:

```dart

    // A row with no bus to follow says why, and stays where it is (spec 2026-10-14 §4.2).
    void explain() => BBToast.show(context, ArrivalRowTile.notLiveYet, announce: true);
```

3. Replace:

```dart
                          onTap: follow(a),
                          action: AlertBell(arrival: a, stopId: stopId, stopName: name),
```

with:

```dart
                          onTap: follow(a),
                          onExplain: explain,
                          action: AlertBell(arrival: a, stopId: stopId, stopName: name),
```

4. Replace the end of the body's column:

```dart
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

with:

```dart
                ],
              ),
            ),
          // While a departure is live: the one-time "tap to follow" tip (spec 2026-10-14 §4.3).
          if (rows != null && rows.any((r) => r.followableVehicle != null)) const FollowTip(),
        ],
      ),
    );
  }
}
```

In `lib/ui/map/stop_card.dart` (the home's "your stop" preview), replace:

```dart
        children: [for (final a in rows) ArrivalRowTile(arrival: a, onTap: _followable(ref, a))],
```

with:

```dart
        children: [
          for (final a in rows)
            ArrivalRowTile(
              arrival: a,
              onTap: _followable(ref, a),
              // A row with no bus to follow says why (spec 2026-10-14 §4.2).
              onExplain: () => BBToast.show(context, ArrivalRowTile.notLiveYet, announce: true),
            ),
        ],
```

In `lib/ui/home/home_screen.dart`, replace:

```dart
    ref.listen<FollowTarget?>(followProvider, (prev, next) {
      if (prev != next) _onFollowChanged(next);
```

with:

```dart
    ref.listen<FollowTarget?>(followProvider, (prev, next) {
      if (prev != next) _onFollowChanged(next);
      // A bus followed, from anywhere: the stop sheet's "tap to follow" tip has done its job (spec 2026-10-14 §4.3).
      if (next != null && prev == null) {
        unawaited(ref.read(followTipSeenProvider.notifier).markSeen().catchError((Object e) => _log('Tip not saved: $e')));
      }
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `flutter test test/ui/arrival_row_tile_test.dart test/kit/feedback_components_test.dart test/ui/stop_sheet_test.dart test/ui/screen_overflow_test.dart`
Expected: PASS (`screen_overflow_test.dart`'s "the stop sheet at 320x640, 2.0x text … live" cases are the large-text check for the pill on a real sheet).

- [ ] **Step 6: The whole suite**

`flutter analyze` and the non-golden suite. Expected: clean, all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/board/arrival_row_tile.dart lib/ui/kit/bb_toast.dart lib/ui/home/follow_tip.dart lib/state/seen_flags.dart \
  lib/ui/home/stop_sheet.dart lib/ui/map/stop_card.dart lib/ui/home/home_screen.dart test/helpers/planner_app.dart \
  test/ui/arrival_row_tile_test.dart test/kit/feedback_components_test.dart test/ui/stop_sheet_test.dart
git commit -m "feat(stop): live departures show a Follow pill; scheduled ones say when they can be followed

A one-time tip under live departures points at it, until the rider
closes it or follows a bus.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 8: Goldens, the 2× pass, the simulator check and the accessibility review

**Files:**
- Modify: `test/ui/screen_golden_test.dart` (the home golden is the bar; the half drag)
- Delete: `test/ui/goldens/home_peek_light.png`, `test/ui/goldens/home_peek_dark.png`
- Create (generated): `test/ui/goldens/home_bar_light.png`, `test/ui/goldens/home_bar_dark.png`
- Modify (regenerated): every other PNG under `test/ui/goldens/` and `test/kit/goldens/`

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces: goldens for the new look, reviewed by eye; a simulator report; an accessibility review.

- [ ] **Step 1: Point the screen goldens at the bar**

In `test/ui/screen_golden_test.dart`, replace:

```dart
    testWidgets('home peek ${b.name}', (tester) async {
      await _pumpApp(tester, b);
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/home_peek_${b.name}.png'));
    });
```

with:

```dart
    // The home at rest: the slim bar over the map (spec 2026-10-14 §3.1).
    testWidgets('home bar ${b.name}', (tester) async {
      await _pumpApp(tester, b);
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/home_bar_${b.name}.png'));
    });
```

and in "home at half dark" replace `    await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -250));` with `    await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));` (from the slim bar, a 250 pt drag no longer settles at half, and the test's own check, "the sheet is up at half", would fail).

```bash
git rm test/ui/goldens/home_peek_light.png test/ui/goldens/home_peek_dark.png
```

- [ ] **Step 2: Regenerate every golden**

Run: `flutter test --update-goldens test/ui/screen_golden_test.dart test/kit/kit_golden_test.dart`
Expected: `All tests passed!`; `git status --short test` shows the two new `home_bar_*.png`, the two deleted `home_peek_*.png`, and every other PNG in `test/ui/goldens/` and `test/kit/goldens/` modified.

- [ ] **Step 3: Look at every golden**

Open each PNG in `test/ui/goldens/` and `test/kit/goldens/` with the Read tool. Check:
- **Light:** neutral grey background `#F4F5F7` and map `#EEF0F2`, white sheets and cards, near-black text; no green or purple tint anywhere. Filled buttons (Open board, Show map, selected chips) are the blue `#1272C9` with white text; blue text and icons (Plan a trip from here, saved-place and chip icons) are `#0D5DA6`.
- **Dark:** neutral greys getting lighter the higher they sit (map `#17181B`, sheet `#1F2024`, cards `#27292E`), no navy or purple; filled buttons `#5EA2F0` with dark text.
- **Home bar (`home_bar_light/dark`):** the sheet is a slim bar at the bottom (about a sixth of the screen): Where to?, then "★ MUN Centre ⚠ · [29] 4 min ●". The map, chips and buttons have the rest.
- **Home at half (`home_half_dark`):** saved place chips, the alert row, MUN Centre with the blue Open board, then the departures, each live one with a "Follow 2134"-style pill.
- **Stop sheet (`stop_sheet_*`):** live rows show the Follow pill in `brandSoft`/`brandInk`; "Now" in orange; route 10's badge is green.
- **Kit gallery:** chips with blue icons, no purple.

If anything is off, fix the code (not the golden) and regenerate. Then run `flutter test` (the whole suite, goldens included). Expected: all pass.

- [ ] **Step 4: The 2× pass**

The large-text checks this plan added or kept, run together:

Run: `flutter test test/ui/home_stop_line_test.dart test/ui/screen_overflow_test.dart test/ui/arrival_row_tile_test.dart test/ui/board_button_test.dart test/ui/home_screen_test.dart`
Expected: PASS. Together they cover the stop line at 2× and 3× on 320 pt, the home bar at 2× on 360x640 (light and dark), the stop sheet with live rows at 2× on 320x640, the Follow pill at 2× on 320 pt, Open board/Show map at 2× on 320x640, and the home at 2× on 320x640 with and without a follow.

- [ ] **Step 5: Commit the goldens**

```bash
git add test/ui/screen_golden_test.dart test/ui/goldens test/kit/goldens
git status --short
git commit -m "test: regenerate goldens for the neutral greys, the Harbour blue and the slim bar

home_peek_* becomes home_bar_*: the home now rests as the bar. Every
golden was looked at by eye.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(`git status --short` after `git add` must show only those paths staged, plus the two deletions from Step 1.)

- [ ] **Step 6: The simulator check (BusBoard iPhone 17 only)**

Use only the simulator **"BusBoard iPhone 17"** (`0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54`). Never the developer's iPhone (`00008140-000C49E61482801C`), `emulator-5554` or `RFCRA1CK68W`; if you run `flutter devices`, ignore those three.

```bash
xcrun simctl boot 0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54 || true   # "already booted" is fine
open -a Simulator
xcrun simctl ui 0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54 appearance light
xcrun simctl ui 0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54 content_size large
flutter run -d 0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54
```

(With the iOS simulator tool available, call its `attach` action first so the developer can watch.) To see the one-time lift again, erase the app's data first: `xcrun simctl uninstall 0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54 com.ahamsel.busboardNl` before `flutter run`. Check each item and take a screenshot of each (`xcrun simctl io 0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54 screenshot /tmp/nb-<name>.png`, or the simulator tool's `screenshot`):

1. **Icon and splash.** On the home screen (Device → Home, or the tool's `HOME` button) the icon is blue with coral, gold, green and purple houses, the mark centred. Relaunch: the splash is blue with the mark.
2. **The bar (light).** The app opens at the bar: Where to? and your stop's line, about a sixth of the screen. The first time, after the map shows, the bar lifts a little and settles back once; it doesn't do it again on the next launch. Tap the handle: "Show more" takes it to half; tap again to come back down. Tap the stop line: the stop's Board opens at full height.
3. **Pan to collapse.** Pull the sheet up to half, then pan the map: the sheet drops to the bar. Open a stop from the map (at half), pan: the card drops to its lowest position and stays open.
4. **Follow.** On a stop with a live bus, the live row shows "Follow ####"; tap it: the map follows the bus. On a scheduled row, a tap shows "No bus on this trip yet. You can follow it once it's live." The first time, the stop sheet shows "Tap a live bus to follow it on the map" under the departures.
5. **Dark.** `xcrun simctl ui 0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54 appearance dark`. Check the bar, a stop sheet at full and the trip options: neutral greys, no navy or purple, the sheet clear of the map.
6. **Large text.** `xcrun simctl ui 0B7616E4-5ABB-4FD3-8ED6-9D309DC91F54 content_size accessibility-extra-extra-extra-large`. The bar's stop line keeps its minutes whole (the name gives way); the Follow pill wraps under the status rather than cut. Reset with `content_size large`.
7. **Reduce Motion.** In the simulator's Settings → Accessibility → Motion, turn on Reduce Motion. Uninstall and reinstall as above: the bar doesn't lift; panning the map makes the sheet jump down rather than glide.

Report each item as pass or fail, with the screenshot paths. Send the bar (light and dark), the Follow pill and the icon screenshots to the developer with SendUserFile, if that tool is available.

- [ ] **Step 7: The accessibility review**

Spec §6 asks for an accessibility review of this spec's screens with the design plugin's accessibility skill. Invoke the `design:accessibility-review` skill (Skill tool) on the Step 6 screenshots of: the bar (light and dark), the home at half, a stop sheet with a Follow pill and the follow tip, and the scheduled-row toast. Give it the screen-reader strings from spec §3.2 and §4 as pinned in this plan's "Spec gaps and ambiguities resolved here". Report its findings; fix any WCAG AA failure it finds in a follow-up commit (with tests), and list anything it rates below AA as open for the developer.

The developer's own iPhone check (spec §6) is theirs to do. Say so in the final report.

---
## Spec coverage (self-review)

| Spec | Task |
|---|---|
| §2.1 neutral surfaces, brand rules, accent retired, dark layering, neutral shadows and scrims, AA | 1 (contrast, neutrality, scrim and elevation tests) |
| §2.2 token table | 1 ("spec 2026-10-14 §2.2 values") |
| §2.3 route palette against the new brand; route 10 green; ΔE 0.09 between hues | 1 (`route_palette_test.dart`) |
| §2.4 map styles, regenerated with `--recolour` | 2 |
| §2.5 icon, splash, house colours, centring, regeneration | 3 (`brand_assets_test.dart`) |
| §3.1 the bar: two rows ≥ 48 pt, height from content | 4 (bar test in `home_sheet_test.dart`, 2× and 3× in `home_stop_line_test.dart` and `screen_overflow_test.dart`) |
| §3.2 every stop-line state, screen-reader strings, tap opens the Board, rolling minutes, 2× truncates the name first | 4 (`home_stop_line_test.dart`, `home_sheet_test.dart`, `board_button_test.dart`) |
| §3.3 detents bar/half/full, flicks, not dismissible, one gesture all the way up | 4 (unchanged `BBSheet` snapping; "the home sheet itself never swipes away"), 5 |
| §3.4 tuck-away: home to bar, cards to their lowest, past the pause distance, never in follow/tablet/pick, Reduce Motion | 6 |
| §3.5 opens at the bar; Board left open reopens at full; links as today | 4 (bar test), existing `board_reopen_test.dart` and `home_routes_test.dart` |
| §3.6 one-time lift (stored, never under Reduce Motion); handle button Show more / Show less; Board one tap away | 5; 4 (stop line) |
| §3.7 tablet panel, follow card, card content, Open board / Show map unchanged | 4 (tablet keeps `header`/`body`), existing `home_tablet_test.dart`, `follow_card_test.dart`, `board_button_test.dart` |
| §4.1 Follow pill: brandSoft/brandInk, 44×44, label, follows, wraps at 2× | 7 |
| §4.2 scheduled rows: toast, announced, row stays | 7 |
| §4.3 one-time tip, gone after a follow or a close | 7 |
| §4.4 unchanged follow paths | existing `map_cards_test.dart`, `journey_detail_test.dart`, `follow_card_test.dart` |
| §5 tests, goldens (`home_bar_light`/`dark`), simulator check | 1–7, 8 |
| §6 done when: tests, analyze, goldens reviewed, accessibility review | 8 (the developer's iPhone approval is theirs) |
