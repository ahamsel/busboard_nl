# Harbour Redesign — Phase 1: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Harbour design foundation: design tokens, route colours, Figtree, a platform-neutral component kit, the new theme and behaviour, the new app icon/splash/store art, and the legal wording fixes. Existing screens keep working; they pick up the new colours and font now and are rebuilt on the kit in Phase 2.

**Architecture:** `MaterialApp.router` stays as invisible plumbing. A new `lib/ui/kit/` holds `BBTokens` (a `ThemeExtension`), `RoutePalette`, `BBTheme` (ThemeData with Material visuals neutralised, plus a shared scroll behaviour and page transition), and the kit widgets. Material/Cupertino widgets are allowed only inside `lib/ui/kit/`; a guard test enforces this (legacy screens are allow-listed until Phase 2). Brand assets are generated from SVG masters with ImageMagick.

**Tech Stack:** Flutter 3.47.5 / Dart ^3.11, flutter_riverpod 3, go_router 17, flutter_launcher_icons, flutter_native_splash, ImageMagick 7 (`magick`, already at `/opt/homebrew/bin/magick`), flutter_test goldens.

**Spec:** `docs/superpowers/specs/2026-10-04-harbour-redesign-design.md` (§3, §4, §5, §6.4 footer, §6.5 About, §9). Phases 2 and 3 get their own plans.

## Global Constraints

- Run every command from the worktree root: `/Users/aham/projects/dev/busboard_nl/.claude/worktrees/unified-ui-map-redesign-fc0a89`.
- No raw colour literals (`Color(0x…)`) in new code outside `lib/ui/kit/tokens.dart` and `lib/ui/kit/route_palette.dart`.
- Material/Cupertino widgets only inside `lib/ui/kit/` (plus `MaterialApp.router` in `lib/app.dart`).
- Font family is exactly `Figtree`, bundled in `assets/fonts/` (weights 400/500/600/700/800) and never fetched at runtime.
- Icon/splash brand colour: `#3E7CB1`. In-app `brand` fill token (light): `#3C79AE`, a contrast-corrected shade (see Task 1).
- Never use Metrobus's brand colours (`#4C466F`, `#81B34F`), logo, livery or the word "Official".
- Copy strings, verbatim:
  - Alerts footer: `Data from Metrobus open data · BusBoard is independent`
  - About: `BusBoard NL is an independent app and is not affiliated with Metrobus Transit.`
  - Data credit: `Schedules and live data: Metrobus open data (GTFS, GTFS-Realtime)`
  - Map credit: `Map: OpenFreeMap · © OpenStreetMap contributors`
- Every text/background token pair must meet WCAG AA: 4.5:1 for body text, 3:1 for large text (≥ 18.66 px bold).
- Commit after each task. Every commit message ends with the trailer line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Don't commit the unrelated working-tree changes (`analysis_options.yaml`, `pubspec.lock`, `tool/capture_raw_gtfsrt.dart`) unless a step says so. Stage files by explicit path.

## Review Focus

1. **Large text (text scale 2.0) on narrow phones (320 pt):** the nav bar, route badges and buttons must not overflow or clip. Pinned by the 2.0 goldens (Task 9) and a nav-bar overflow test (Task 6).
2. **A toast shown twice quickly, or the screen closing while a toast is up:** only the newest toast shows, with no "OverlayEntry removed twice" assertion. Pinned in Task 8.
3. **Unknown, new or odd route numbers (0, negative, 99):** a stable colour, no crash. Pinned in Task 2.
4. **"Reduce motion" turned on:** kit animations become instant, and sheet snapping still works (the sheet API rejects a zero duration). Pinned in Tasks 1 and 7.
5. **iOS edge-swipe on the root route, and the swipe on Android:** nothing happens, no exception. A swipe on a pushed iOS route pops it. Pinned in Task 3.

---

## File Structure

| File | Responsibility |
|---|---|
| `assets/fonts/Figtree-{Regular,Medium,SemiBold,Bold,ExtraBold}.ttf`, `assets/fonts/OFL.txt` | Bundled font + licence |
| `lib/ui/kit/tokens.dart` | `BBColors`, `BBText`, `BBSpace`, `BBRadius`, `BBMotion`, `BBTokens`, `context.bb` |
| `lib/ui/kit/route_palette.dart` | `RouteHue`, `RoutePalette` (route → colour) |
| `lib/ui/kit/bb_theme.dart` | `BBTheme`, `BBScrollBehavior`, `BBPageTransitionsBuilder`, `BBEdgeSwipeBack` |
| `lib/ui/kit/bb_icons.dart` | `BBIcons`: semantic icon names → rounded icon glyphs |
| `lib/ui/kit/bb_pressable.dart` | `BBPressable`: press-scale tap target, no ripple |
| `lib/ui/kit/bb_card.dart`, `bb_button.dart`, `bb_pill.dart`, `route_badge.dart` | Basic display/tap components |
| `lib/ui/kit/bb_segmented.dart`, `bb_switch.dart`, `bb_text_field.dart` | Input components |
| `lib/ui/kit/bb_scaffold.dart`, `bb_nav_bar.dart` | Page shell + floating bottom bar |
| `lib/ui/kit/bb_sheet.dart` | Draggable sheet with peek/half/full |
| `lib/ui/kit/bb_toast.dart`, `bb_dialog.dart`, `bb_refresh.dart` | Feedback components |
| `lib/ui/kit/kit.dart` | Barrel export |
| `lib/ui/copy/legal_copy.dart` | Legal/attribution strings |
| `assets/brand/busboard_icon.svg`, `assets/brand/busboard_mark.svg` | Brand masters |
| `tool/brand/render_brand_assets.sh` | Generates every PNG from the masters |
| `test/kit/kit_test_helpers.dart` | `loadAppFonts()`, `kitHost()` |
| `test/kit/*_test.dart` | Kit tests, goldens, guard |

Modified: `pubspec.yaml`, `lib/app.dart`, `lib/ui/alerts/alerts_screen.dart`, `lib/ui/settings/settings_screen.dart`, `test/widget_test.dart`, `docs/superpowers/specs/2026-10-04-harbour-redesign-design.md` (token amendment). Deleted: `lib/ui/theme/app_theme.dart`, `assets/icon/app_icon_nobg.png`, `assets/icon/splash_background.png`.

---

### Task 1: Figtree font + design tokens

**Files:**
- Create: `assets/fonts/*.ttf`, `assets/fonts/OFL.txt`, `lib/ui/kit/tokens.dart`, `test/kit/tokens_test.dart`
- Modify: `pubspec.yaml` (the `flutter:` section at the end of the file), `docs/superpowers/specs/2026-10-04-harbour-redesign-design.md` (§4.1 table)

**Interfaces:**
- Produces:
  - `BBColors` (const `light`/`dark`; fields `bg, surface, surfaceSunken, line, ink, muted, brand, onBrand, brandInk, brandSoft, live, liveInk, liveSoft, soon, warnBg, warnInk, dangerBg, dangerInk`)
  - `BBText` (`family`; fields `display, title, headline, body, label, caption, minutes, minutesUnit`; `BBText.of(BBColors)`)
  - `BBSpace.{xs,s,m,l,xl,xxl,xxxl,screen}`, `BBRadius.{pill,badge,button,card,sheet}`, `BBMotion.{standard,press,sheet,curve}`, `BBMotion.of(BuildContext, Duration) → Duration`
  - `BBTokens extends ThemeExtension<BBTokens>` (`brightness`, `colors`, `text`, `isDark`, `floating({double radius, BorderRadius? borderRadius}) → BoxDecoration`, `card({double radius}) → BoxDecoration`, static `light`/`dark`)
  - `extension BBContext on BuildContext { BBTokens get bb }`

> **Token amendment (contrast-driven).** Computing WCAG ratios for the spec's §4.1 values showed four failures:
> - `brand #3E7CB1` with white text: 4.45:1
> - `muted #6B7785` on cream: 4.09:1
> - `live #2BA36B` as small text: 3.2:1
> - muted on `surfaceSunken`: 4.49:1
>
> This plan uses corrected values: light `brand #3C79AE` (4.6:1, visually identical; the **icon** keeps `#3E7CB1`), light `muted #5A6674`, and new tokens `liveInk` (light `#1B7048` / dark `#4CC38A`) and `liveSoft` (light `#DDF1E6` / dark `#16332A`) for live labels and pills. `live` stays as the dot colour. Step 7 writes this back into the spec.

- [ ] **Step 1: Download Figtree (SIL OFL) into the repo**

```bash
mkdir -p assets/fonts
for w in Regular Medium SemiBold Bold ExtraBold; do
  curl -fsSL -o "assets/fonts/Figtree-$w.ttf" \
    "https://raw.githubusercontent.com/erikdkennedy/figtree/master/fonts/ttf/Figtree-$w.ttf"
done
curl -fsSL -o assets/fonts/OFL.txt https://raw.githubusercontent.com/erikdkennedy/figtree/master/OFL.txt
file assets/fonts/*.ttf
```
Expected: five lines, each containing `TrueType Font data`.

- [ ] **Step 2: Declare the font in `pubspec.yaml`**

Replace the final `flutter:` block (currently just `uses-material-design: true`) with:

```yaml
flutter:
  uses-material-design: true
  fonts:
    - family: Figtree
      fonts:
        - asset: assets/fonts/Figtree-Regular.ttf
          weight: 400
        - asset: assets/fonts/Figtree-Medium.ttf
          weight: 500
        - asset: assets/fonts/Figtree-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Figtree-Bold.ttf
          weight: 700
        - asset: assets/fonts/Figtree-ExtraBold.ttf
          weight: 800
```

Run: `flutter pub get`
Expected: exits 0.

- [ ] **Step 3: Write the failing tokens test**

Create `test/kit/tokens_test.dart`:

```dart
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
        ('soon/surface (large minutes)', c.soon, c.surface, 3.0),
        ('soon/bg (large minutes)', c.soon, c.bg, 3.0),
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
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `flutter test test/kit/tokens_test.dart`
Expected: FAIL to compile with `Target of URI doesn't exist: 'package:busboard_nl/ui/kit/tokens.dart'`.

- [ ] **Step 5: Implement `lib/ui/kit/tokens.dart`**

```dart
import 'package:flutter/material.dart';

/// Colour roles for one brightness (spec §4.1, contrast-amended).
/// Raw colour values live only here and in route_palette.dart.
@immutable
class BBColors {
  const BBColors({
    required this.bg,
    required this.surface,
    required this.surfaceSunken,
    required this.line,
    required this.ink,
    required this.muted,
    required this.brand,
    required this.onBrand,
    required this.brandInk,
    required this.brandSoft,
    required this.live,
    required this.liveInk,
    required this.liveSoft,
    required this.soon,
    required this.warnBg,
    required this.warnInk,
    required this.dangerBg,
    required this.dangerInk,
  });

  final Color bg;
  final Color surface;
  final Color surfaceSunken;
  final Color line;
  final Color ink;
  final Color muted;
  final Color brand;
  final Color onBrand;
  final Color brandInk;
  final Color brandSoft;
  final Color live;
  final Color liveInk;
  final Color liveSoft;
  final Color soon;
  final Color warnBg;
  final Color warnInk;
  final Color dangerBg;
  final Color dangerInk;

  static const light = BBColors(
    bg: Color(0xFFF7F2EA),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEFE7DA),
    line: Color(0xFFECE4D8),
    ink: Color(0xFF1C2A3A),
    muted: Color(0xFF5A6674),
    brand: Color(0xFF3C79AE),
    onBrand: Color(0xFFFFFFFF),
    brandInk: Color(0xFF2C5F8E),
    brandSoft: Color(0xFFDCE8F4),
    live: Color(0xFF2BA36B),
    liveInk: Color(0xFF1B7048),
    liveSoft: Color(0xFFDDF1E6),
    soon: Color(0xFFD9480F),
    warnBg: Color(0xFFFDEBD3),
    warnInk: Color(0xFF8A4B08),
    dangerBg: Color(0xFFFBD9D6),
    dangerInk: Color(0xFF9B1C1C),
  );

  static const dark = BBColors(
    bg: Color(0xFF0F1720),
    surface: Color(0xFF18222E),
    surfaceSunken: Color(0xFF121B25),
    line: Color(0xFF243140),
    ink: Color(0xFFF2EDE4),
    muted: Color(0xFF8E9AA8),
    brand: Color(0xFF6FA6DA),
    onBrand: Color(0xFF0F1720),
    brandInk: Color(0xFF8DBBE6),
    brandSoft: Color(0xFF1D3348),
    live: Color(0xFF4CC38A),
    liveInk: Color(0xFF4CC38A),
    liveSoft: Color(0xFF16332A),
    soon: Color(0xFFFF8A5B),
    warnBg: Color(0xFF3A2A14),
    warnInk: Color(0xFFF5C27A),
    dangerBg: Color(0xFF3A1A1A),
    dangerInk: Color(0xFFF5A3A3),
  );

  BBColors lerp(BBColors other, double t) {
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return BBColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceSunken: l(surfaceSunken, other.surfaceSunken),
      line: l(line, other.line),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      brand: l(brand, other.brand),
      onBrand: l(onBrand, other.onBrand),
      brandInk: l(brandInk, other.brandInk),
      brandSoft: l(brandSoft, other.brandSoft),
      live: l(live, other.live),
      liveInk: l(liveInk, other.liveInk),
      liveSoft: l(liveSoft, other.liveSoft),
      soon: l(soon, other.soon),
      warnBg: l(warnBg, other.warnBg),
      warnInk: l(warnInk, other.warnInk),
      dangerBg: l(dangerBg, other.dangerBg),
      dangerInk: l(dangerInk, other.dangerInk),
    );
  }
}

/// Type scale (spec §4.3). Every style sets `decoration: none` so text never
/// shows Flutter's "missing Material" debug underline.
@immutable
class BBText {
  const BBText({
    required this.display,
    required this.title,
    required this.headline,
    required this.body,
    required this.label,
    required this.caption,
    required this.minutes,
    required this.minutesUnit,
  });

  static const family = 'Figtree';

  final TextStyle display;
  final TextStyle title;
  final TextStyle headline;
  final TextStyle body;
  final TextStyle label;
  final TextStyle caption;

  /// Arrival minutes: tabular figures so digits don't jitter as they change.
  final TextStyle minutes;
  final TextStyle minutesUnit;

  factory BBText.of(BBColors c) {
    TextStyle s(double size, FontWeight weight, {Color? color, double? spacing, double? height}) {
      return TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        color: color ?? c.ink,
        letterSpacing: spacing,
        height: height,
        decoration: TextDecoration.none,
      );
    }

    return BBText(
      display: s(28, FontWeight.w800, spacing: -0.56, height: 1.15),
      title: s(22, FontWeight.w800, spacing: -0.22, height: 1.2),
      headline: s(17, FontWeight.w700, height: 1.25),
      body: s(15, FontWeight.w500, height: 1.4),
      label: s(13, FontWeight.w700, height: 1.25),
      caption: s(12, FontWeight.w500, color: c.muted, height: 1.3),
      minutes: s(26, FontWeight.w800, height: 1.0)
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      minutesUnit: s(11, FontWeight.w600, color: c.muted, height: 1.1),
    );
  }

  BBText lerp(BBText o, double t) {
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return BBText(
      display: l(display, o.display),
      title: l(title, o.title),
      headline: l(headline, o.headline),
      body: l(body, o.body),
      label: l(label, o.label),
      caption: l(caption, o.caption),
      minutes: l(minutes, o.minutes),
      minutesUnit: l(minutesUnit, o.minutesUnit),
    );
  }
}

/// 4-pt spacing scale (spec §4.4).
abstract final class BBSpace {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double screen = 16;
}

abstract final class BBRadius {
  static const double pill = 8;
  static const double badge = 12;
  static const double button = 14;
  static const double card = 16;
  static const double sheet = 24;
}

abstract final class BBMotion {
  static const standard = Duration(milliseconds: 200);
  static const press = Duration(milliseconds: 120);
  static const sheet = Duration(milliseconds: 300);
  static const Curve curve = Curves.easeOutCubic;

  /// [d], or zero when the user has asked the OS to reduce motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

@immutable
class BBTokens extends ThemeExtension<BBTokens> {
  const BBTokens({required this.brightness, required this.colors, required this.text});

  final Brightness brightness;
  final BBColors colors;
  final BBText text;

  static final light = BBTokens(
    brightness: Brightness.light,
    colors: BBColors.light,
    text: BBText.of(BBColors.light),
  );

  static final dark = BBTokens(
    brightness: Brightness.dark,
    colors: BBColors.dark,
    text: BBText.of(BBColors.dark),
  );

  bool get isDark => brightness == Brightness.dark;

  /// Floating elements: nav bar, chips, sheets, dialogs, toasts. The one
  /// shadow in light mode; a hairline border instead in dark mode.
  BoxDecoration floating({double radius = BBRadius.card, BorderRadius? borderRadius}) {
    return BoxDecoration(
      color: colors.surface,
      borderRadius: borderRadius ?? BorderRadius.circular(radius),
      boxShadow: isDark
          ? null
          : const [BoxShadow(color: Color(0x241C2A3A), blurRadius: 16, offset: Offset(0, 4))],
      border: isDark ? Border.all(color: colors.line) : null,
    );
  }

  /// Flat in-page surface (cards in lists).
  BoxDecoration card({double radius = BBRadius.card}) {
    return BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: isDark ? Border.all(color: colors.line) : null,
    );
  }

  @override
  BBTokens copyWith({Brightness? brightness, BBColors? colors, BBText? text}) {
    return BBTokens(
      brightness: brightness ?? this.brightness,
      colors: colors ?? this.colors,
      text: text ?? this.text,
    );
  }

  @override
  BBTokens lerp(covariant BBTokens? other, double t) {
    if (other == null) return this;
    return BBTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      colors: colors.lerp(other.colors, t),
      text: text.lerp(other.text, t),
    );
  }
}

extension BBContext on BuildContext {
  BBTokens get bb => Theme.of(this).extension<BBTokens>()!;
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/kit/tokens_test.dart`
Expected: PASS (all contrast pairs in both modes plus three widget/unit tests).

- [ ] **Step 7: Write the token amendment into the spec**

In `docs/superpowers/specs/2026-10-04-harbour-redesign-design.md` §4.1:
- Change the `muted` light value `#6B7785` → `#5A6674`.
- Change the `brand` light value `#3E7CB1` → `#3C79AE`, and add to its Use cell: "(icon keeps `#3E7CB1`)".
- After the `live` row, add these two rows:

```markdown
| `liveInk` | `#1B7048` | `#4CC38A` | "Live" labels and live pill text (AA on bg/surface/liveSoft) |
| `liveSoft` | `#DDF1E6` | `#16332A` | live pill background |
```

- Change the `live` row's Use cell to "live dot only (not for small text)".

- [ ] **Step 8: Commit**

```bash
git add assets/fonts pubspec.yaml lib/ui/kit/tokens.dart test/kit/tokens_test.dart docs/superpowers/specs/2026-10-04-harbour-redesign-design.md
git commit -m "feat(kit): add Figtree font and Harbour design tokens

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Route palette

**Files:**
- Create: `lib/ui/kit/route_palette.dart`, `test/kit/route_palette_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum RouteHue { red, orange, yellow, lime, green, teal, sky, indigo, lilac, pink }` with `Color fill`, `Color fillDark`, `Color line`, `Color fillFor(Brightness)`; `abstract final class RoutePalette` with `static const Color ink`, `static const Map<int, RouteHue> assigned`, `static RouteHue of(int routeNumber)`.

The assignment table was computed from Metrobus GTFS `routes.txt` + `stop_times.txt` (22 routes) by colouring routes in order of most shared stops, picking the hue with the fewest shared stops among routes already coloured. Only 2 of 699 shared-stop pairs end up the same hue (routes 1/24 and 2/20, one stop each).

- [ ] **Step 1: Write the failing test**

Create `test/kit/route_palette_test.dart`:

```dart
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
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/kit/route_palette_test.dart`
Expected: FAIL to compile (`route_palette.dart` doesn't exist).

- [ ] **Step 3: Implement `lib/ui/kit/route_palette.dart`**

```dart
import 'package:flutter/painting.dart';

/// Ten jellybean route hues (spec §4.2). `fill` is the badge/pill background
/// in light mode, `fillDark` in dark mode, `line` the route shape on the map.
enum RouteHue {
  red(Color(0xFFFFC9C2), Color(0xFFFFB3A8), Color(0xFFD63B3B)),
  orange(Color(0xFFFFD9B8), Color(0xFFFFC28F), Color(0xFFE07A1F)),
  yellow(Color(0xFFFBE7A6), Color(0xFFF5D97A), Color(0xFFC9A219)),
  lime(Color(0xFFE2F0B0), Color(0xFFCFE58A), Color(0xFF7FA31F)),
  green(Color(0xFFCFEEDB), Color(0xFFA6E3BF), Color(0xFF2E9E62)),
  teal(Color(0xFFC4ECE8), Color(0xFF93DDD6), Color(0xFF1F8F86)),
  sky(Color(0xFFCFE3FA), Color(0xFFA9CDF5), Color(0xFF3E7CB1)),
  indigo(Color(0xFFD6DAFA), Color(0xFFB3BAF5), Color(0xFF4A57C9)),
  lilac(Color(0xFFE3D6FA), Color(0xFFCDB6F5), Color(0xFF8656D1)),
  pink(Color(0xFFFAD3E4), Color(0xFFF5B0CD), Color(0xFFC9417E));

  const RouteHue(this.fill, this.fillDark, this.line);

  final Color fill;
  final Color fillDark;
  final Color line;

  Color fillFor(Brightness brightness) =>
      brightness == Brightness.dark ? fillDark : fill;
}

/// The same route always gets the same colour everywhere in the app.
abstract final class RoutePalette {
  /// Text/number colour on every route fill, in both modes.
  static const Color ink = Color(0xFF1C2A3A);

  /// Hand-assigned from GTFS stop overlap so routes sharing stops differ.
  static const Map<int, RouteHue> assigned = {
    1: RouteHue.orange,
    2: RouteHue.red,
    3: RouteHue.yellow,
    6: RouteHue.teal,
    9: RouteHue.teal,
    10: RouteHue.green,
    11: RouteHue.teal,
    12: RouteHue.pink,
    13: RouteHue.indigo,
    14: RouteHue.red,
    15: RouteHue.lilac,
    16: RouteHue.yellow,
    18: RouteHue.lilac,
    19: RouteHue.sky,
    20: RouteHue.red,
    21: RouteHue.lime,
    22: RouteHue.green,
    23: RouteHue.lime,
    24: RouteHue.orange,
    26: RouteHue.pink,
    29: RouteHue.sky,
    30: RouteHue.orange,
  };

  /// Routes not in [assigned] (e.g. a newly added route) get a deterministic
  /// hue from their number.
  static RouteHue of(int routeNumber) =>
      assigned[routeNumber] ??
      RouteHue.values[routeNumber.abs() % RouteHue.values.length];
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/kit/route_palette_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/kit/route_palette.dart test/kit/route_palette_test.dart
git commit -m "feat(kit): add jellybean route palette with GTFS-derived assignments

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: BBTheme, shared scroll behaviour, page transition and iOS edge-swipe; wire into the app

**Files:**
- Create: `lib/ui/kit/bb_theme.dart`, `test/kit/bb_theme_test.dart`
- Modify: `lib/app.dart`, `lib/main.dart`, `test/widget_test.dart`
- Delete: `lib/ui/theme/app_theme.dart`

**Interfaces:**
- Consumes: `BBTokens`, `BBColors`, `BBText`, `BBMotion` (Task 1).
- Produces:
  - `abstract final class BBTheme { static ThemeData light(); static ThemeData dark(); }`
  - `class BBScrollBehavior extends ScrollBehavior` (const ctor)
  - `class BBPageTransitionsBuilder extends PageTransitionsBuilder` (const ctor)
  - `class BBEdgeSwipeBack extends StatefulWidget { const BBEdgeSwipeBack({required bool Function() canPop, required Widget child, double edgeWidth = 20}) }`

- [ ] **Step 1: Write the failing test**

Create `test/kit/bb_theme_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/bb_theme.dart';
import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({required TargetPlatform platform}) {
  return MaterialApp(
    theme: BBTheme.light().copyWith(platform: platform),
    scrollBehavior: const BBScrollBehavior(),
    home: Builder(
      builder: (context) => Scaffold(
        body: ListView(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Center(child: Text('PAGE B')))),
              ),
              child: const Text('open'),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  test('themes carry BBTokens and neutralise Material visuals', () {
    for (final (theme, dark) in [(BBTheme.light(), false), (BBTheme.dark(), true)]) {
      final tokens = theme.extension<BBTokens>()!;
      expect(tokens.isDark, dark);
      expect(theme.scaffoldBackgroundColor, tokens.colors.bg);
      expect(theme.colorScheme.primary, tokens.colors.brand);
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.textTheme.bodyMedium!.fontFamily, BBText.family);
      for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(theme.pageTransitionsTheme.builders[p], isA<BBPageTransitionsBuilder>());
      }
    }
  });

  testWidgets('same bouncing physics on Android and iOS, no glow', (tester) async {
    for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
      await tester.pumpWidget(_app(platform: p));
      final ctx = tester.element(find.byType(ListView));
      final physics = ScrollConfiguration.of(ctx).getScrollPhysics(ctx);
      expect(physics, isA<BouncingScrollPhysics>(), reason: '$p');
      expect(find.byType(GlowingOverscrollIndicator), findsNothing);
      expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    }
  });

  testWidgets('iOS: edge swipe pops a pushed route', (tester) async {
    await tester.pumpWidget(_app(platform: TargetPlatform.iOS));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE B'), findsOneWidget);

    await tester.dragFrom(const Offset(5, 300), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('PAGE B'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('iOS: a short edge swipe springs back and keeps the page', (tester) async {
    await tester.pumpWidget(_app(platform: TargetPlatform.iOS));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('PAGE B'), findsOneWidget);
  });

  testWidgets('iOS: edge swipe on the root route does nothing', (tester) async {
    await tester.pumpWidget(_app(platform: TargetPlatform.iOS));
    await tester.dragFrom(const Offset(5, 300), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('Android: no edge-swipe detector is installed', (tester) async {
    await tester.pumpWidget(_app(platform: TargetPlatform.android));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BBEdgeSwipeBack), findsNothing);
    await tester.dragFrom(const Offset(5, 300), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('PAGE B'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/kit/bb_theme_test.dart`
Expected: FAIL to compile (`bb_theme.dart` doesn't exist).

- [ ] **Step 3: Implement `lib/ui/kit/bb_theme.dart`**

```dart
import 'package:flutter/material.dart';

import 'tokens.dart';

/// App ThemeData built from [BBTokens]. Material stays as plumbing: ripples,
/// tints and platform-specific transitions are switched off. The ColorScheme
/// and TextTheme are mapped from tokens so not-yet-migrated screens pick up
/// the Harbour colours and Figtree until Phase 2 replaces them.
abstract final class BBTheme {
  static ThemeData light() => _build(BBTokens.light);
  static ThemeData dark() => _build(BBTokens.dark);

  static ThemeData _build(BBTokens t) {
    final c = t.colors;
    final base = ThemeData(brightness: t.brightness, useMaterial3: true);
    final scheme = ColorScheme(
      brightness: t.brightness,
      primary: c.brand,
      onPrimary: c.onBrand,
      secondary: c.live,
      onSecondary: c.onBrand,
      error: c.dangerInk,
      onError: c.surface,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.muted,
      surfaceContainerHighest: c.surfaceSunken,
      outline: c.line,
      outlineVariant: c.line,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      fontFamily: BBText.family,
      textTheme: base.textTheme.apply(
        fontFamily: BBText.family,
        bodyColor: c.ink,
        displayColor: c.ink,
      ),
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: BBPageTransitionsBuilder(),
          TargetPlatform.iOS: BBPageTransitionsBuilder(),
        },
      ),
      // Legacy-screen defaults until Phase 2 removes AppBar/Card usage.
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: t.text.headline,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BBRadius.card)),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1),
      extensions: [t],
    );
  }
}

/// One scroll feel on both platforms: bounce, no glow/stretch, no scrollbar.
class BBScrollBehavior extends ScrollBehavior {
  const BBScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

/// One page transition on both platforms: fade + 4% slide-up. On iOS an
/// edge-swipe-back gesture is added; Android's system back already pops.
class BBPageTransitionsBuilder extends PageTransitionsBuilder {
  const BBPageTransitionsBuilder();

  @override
  Duration get transitionDuration => BBMotion.standard;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: BBMotion.curve, reverseCurve: Curves.easeInCubic);
    Widget page = FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      page = BBEdgeSwipeBack(canPop: () => route.popGestureEnabled, child: page);
    }
    return page;
  }
}

/// Drag from the left edge to go back. The page follows the finger. Releasing
/// past a third of the width (or flinging) pops; otherwise it springs back.
class BBEdgeSwipeBack extends StatefulWidget {
  const BBEdgeSwipeBack({super.key, required this.canPop, required this.child, this.edgeWidth = 20});

  final bool Function() canPop;
  final Widget child;
  final double edgeWidth;

  @override
  State<BBEdgeSwipeBack> createState() => _BBEdgeSwipeBackState();
}

class _BBEdgeSwipeBackState extends State<BBEdgeSwipeBack> with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(vsync: this, duration: BBMotion.standard)
    ..addListener(() => setState(() => _dx = _settleFrom * (1 - Curves.easeOut.transform(_settle.value))));
  double _dx = 0;
  double _settleFrom = 0;
  bool _tracking = false;

  void _start(DragStartDetails _) {
    _tracking = widget.canPop();
    if (_tracking) _settle.stop();
  }

  void _update(DragUpdateDetails d) {
    if (!_tracking) return;
    final width = context.size?.width ?? 0;
    setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, width));
  }

  void _end(DragEndDetails d) {
    if (!_tracking) return;
    _tracking = false;
    final width = context.size?.width ?? 1;
    final velocity = d.primaryVelocity ?? 0;
    if (_dx > width / 3 || velocity > 600) {
      Navigator.of(context).maybePop();
    } else {
      _springBack();
    }
  }

  void _springBack() {
    _tracking = false;
    _settleFrom = _dx;
    _settle.forward(from: 0);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: widget.edgeWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _start,
            onHorizontalDragUpdate: _update,
            onHorizontalDragEnd: _end,
            onHorizontalDragCancel: () {
              if (_tracking) _springBack();
            },
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the theme test to verify it passes**

Run: `flutter test test/kit/bb_theme_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Wire it into the app and delete the old theme**

In `lib/app.dart`:
- Replace `import 'ui/theme/app_theme.dart';` with `import 'ui/kit/bb_theme.dart';`.
- In the `MaterialApp.router(...)` call, change the lines to:

```dart
      theme: BBTheme.light(),
      darkTheme: BBTheme.dark(),
      themeMode: settings.themeMode,
      scrollBehavior: const BBScrollBehavior(),
      routerConfig: appRouter,
```

Then run: `git rm lib/ui/theme/app_theme.dart`

Also make Android draw edge-to-edge (spec §5.1). In `lib/main.dart`, add `import 'package:flutter/services.dart';` and, right after `FlutterNativeSplash.preserve(...)`, add:

```dart
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
```

- [ ] **Step 6: Extend the app smoke test**

Replace the body of `test/widget_test.dart` with:

```dart
import 'package:busboard_nl/app.dart';
import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App renders with the Harbour theme', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: BusboardApp()));
    await tester.pump(const Duration(milliseconds: 101));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.extension<BBTokens>(), isNotNull);
    expect(app.darkTheme!.extension<BBTokens>()!.isDark, isTrue);
  });
}
```

- [ ] **Step 7: Run the whole suite and the analyzer**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, and all tests pass (the existing domain/data tests are unaffected).

- [ ] **Step 8: Commit**

```bash
git add lib/ui/kit/bb_theme.dart test/kit/bb_theme_test.dart lib/app.dart lib/main.dart test/widget_test.dart
git commit -m "feat(kit): Harbour theme with shared scroll physics, transitions and iOS edge swipe

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Test helpers + BBIcons, BBPressable, BBCard, BBButton, BBPill, RouteBadge

**Files:**
- Create: `test/kit/kit_test_helpers.dart`, `lib/ui/kit/bb_icons.dart`, `lib/ui/kit/bb_pressable.dart`, `lib/ui/kit/bb_card.dart`, `lib/ui/kit/bb_button.dart`, `lib/ui/kit/bb_pill.dart`, `lib/ui/kit/route_badge.dart`, `test/kit/basic_components_test.dart`

**Interfaces:**
- Consumes: `context.bb`, `BBMotion`, `BBRadius` (Task 1); `RoutePalette` (Task 2); `BBTheme` (Task 3).
- Produces:
  - `Future<void> loadAppFonts()`, `Widget kitHost(Widget child, {Brightness brightness = Brightness.light, double textScale = 1.0, double width = 390})` (test helpers)
  - `abstract final class BBIcons` (static `IconData`s: `board, map, alerts, settings, search, location, nearMe, chevronRight, chevronDown, close, check, refresh, bus, stop, filter, info, warning, noService, schedule, star, starOutline, theme, offline, error, back`)
  - `BBPressable({required Widget child, VoidCallback? onTap, String? semanticLabel, bool haptic = false})`
  - `BBCard({required Widget child, VoidCallback? onTap, EdgeInsetsGeometry padding, String? semanticLabel})`
  - `enum BBButtonKind { primary, quiet }`; `BBButton({required String label, required VoidCallback? onPressed, BBButtonKind kind = BBButtonKind.primary, IconData? icon, bool expand = false})`
  - `enum BBPillTone { neutral, brand, live, warn, danger }`; `BBPill({required String label, BBPillTone tone = BBPillTone.neutral, Color? background, Color? foreground, bool leadingDot = false})`
  - `enum RouteBadgeSize { large, compact }`; `RouteBadge({required int routeNumber, String? label, RouteBadgeSize size = RouteBadgeSize.large})`

- [ ] **Step 1: Create the test helpers**

Create `test/kit/kit_test_helpers.dart`:

```dart
import 'dart:convert';

import 'package:busboard_nl/ui/kit/bb_theme.dart';
import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Loads every font in FontManifest.json (Figtree + MaterialIcons) so goldens
/// render real glyphs instead of test boxes.
Future<void> loadAppFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// Hosts a kit widget in the real Harbour theme on a `bg`-coloured page.
Widget kitHost(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  double width = 390,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.dark ? BBTheme.dark() : BBTheme.light(),
    scrollBehavior: const BBScrollBehavior(),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: app!,
    ),
    home: Builder(
      builder: (context) => Material(
        color: context.bb.colors.bg,
        child: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 2: Write the failing component test**

Create `test/kit/basic_components_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/bb_button.dart';
import 'package:busboard_nl/ui/kit/bb_card.dart';
import 'package:busboard_nl/ui/kit/bb_pill.dart';
import 'package:busboard_nl/ui/kit/bb_pressable.dart';
import 'package:busboard_nl/ui/kit/route_badge.dart';
import 'package:busboard_nl/ui/kit/route_palette.dart';
import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

Color? _boxColor(WidgetTester tester, Finder within) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: within, matching: find.byType(DecoratedBox)).first,
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  testWidgets('BBPressable taps, ignores taps when disabled, has no ink', (tester) async {
    var taps = 0;
    await tester.pumpWidget(kitHost(BBPressable(onTap: () => taps++, child: const Text('tap me'))));
    await tester.tap(find.text('tap me'));
    expect(taps, 1);
    expect(find.byType(InkWell), findsNothing);

    await tester.pumpWidget(kitHost(const BBPressable(onTap: null, child: Text('off'))));
    await tester.tap(find.text('off'));
    expect(taps, 1);
  });

  testWidgets('BBCard is tappable only when onTap is given', (tester) async {
    var taps = 0;
    await tester.pumpWidget(kitHost(BBCard(onTap: () => taps++, child: const Text('card'))));
    await tester.tap(find.text('card'));
    expect(taps, 1);
    expect(_boxColor(tester, find.byType(BBCard)), BBColors.light.surface);
  });

  testWidgets('BBButton primary uses brand fill; disabled does not fire', (tester) async {
    var taps = 0;
    await tester.pumpWidget(kitHost(BBButton(label: 'Use this stop', onPressed: () => taps++)));
    await tester.tap(find.text('Use this stop'));
    expect(taps, 1);
    final container = tester.widget<Container>(
      find.descendant(of: find.byType(BBButton), matching: find.byType(Container)).first,
    );
    expect((container.decoration! as BoxDecoration).color, BBColors.light.brand);

    await tester.pumpWidget(kitHost(const BBButton(label: 'Disabled', onPressed: null)));
    await tester.tap(find.text('Disabled'));
    expect(taps, 1);
  });

  testWidgets('BBPill tones map to token colours', (tester) async {
    await tester.pumpWidget(kitHost(const BBPill(label: 'Detour', tone: BBPillTone.warn)));
    expect(find.text('Detour'), findsOneWidget);
    expect(_boxColor(tester, find.byType(BBPill)), BBColors.light.warnBg);

    await tester.pumpWidget(kitHost(const BBPill(label: 'Live', tone: BBPillTone.live, leadingDot: true)));
    expect(_boxColor(tester, find.byType(BBPill)), BBColors.light.liveSoft);
  });

  testWidgets('RouteBadge uses the route colour and announces the route', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(const RouteBadge(routeNumber: 29)));
    expect(find.text('29'), findsOneWidget);
    expect(_boxColor(tester, find.byType(RouteBadge)), RoutePalette.of(29).fill);
    expect(find.bySemanticsLabel('Route 29'), findsOneWidget);

    await tester.pumpWidget(kitHost(const RouteBadge(routeNumber: 29), brightness: Brightness.dark));
    expect(_boxColor(tester, find.byType(RouteBadge)), RoutePalette.of(29).fillDark);
    handle.dispose();
  });

  testWidgets('large RouteBadge does not overflow at text scale 2.0', (tester) async {
    await tester.pumpWidget(kitHost(const RouteBadge(routeNumber: 26), textScale: 2.0));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/kit/basic_components_test.dart`
Expected: FAIL to compile (kit files don't exist).

- [ ] **Step 4: Implement `lib/ui/kit/bb_icons.dart`**

```dart
import 'package:flutter/widgets.dart';
// Material's icon font is used purely as a glyph source (rounded set), which
// renders identically on iOS and Android.
import 'package:flutter/material.dart' show Icons;

/// The app's single icon vocabulary. Screens use these names, never `Icons.*`.
abstract final class BBIcons {
  static const IconData board = Icons.departure_board_rounded;
  static const IconData map = Icons.map_rounded;
  static const IconData alerts = Icons.campaign_rounded;
  static const IconData settings = Icons.settings_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData location = Icons.my_location_rounded;
  static const IconData nearMe = Icons.near_me_rounded;
  static const IconData chevronRight = Icons.chevron_right_rounded;
  static const IconData chevronDown = Icons.expand_more_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData check = Icons.check_rounded;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData bus = Icons.directions_bus_rounded;
  static const IconData stop = Icons.place_rounded;
  static const IconData filter = Icons.filter_alt_rounded;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData noService = Icons.block_rounded;
  static const IconData schedule = Icons.schedule_rounded;
  static const IconData star = Icons.star_rounded;
  static const IconData starOutline = Icons.star_outline_rounded;
  static const IconData theme = Icons.contrast_rounded;
  static const IconData offline = Icons.cloud_off_rounded;
  static const IconData error = Icons.error_outline_rounded;
  static const IconData back = Icons.arrow_back_rounded;
}
```

- [ ] **Step 5: Implement `lib/ui/kit/bb_pressable.dart`**

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Tap target with a press-scale + dim instead of a ripple (spec §5.1).
class BBPressable extends StatefulWidget {
  const BBPressable({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.haptic = false,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// When set, replaces the child's own semantics.
  final String? semanticLabel;
  final bool haptic;

  @override
  State<BBPressable> createState() => _BBPressableState();
}

class _BBPressableState extends State<BBPressable> {
  bool _down = false;

  void _setDown(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final duration = BBMotion.of(context, BBMotion.press);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setDown(true) : null,
        onTapUp: enabled ? (_) => _setDown(false) : null,
        onTapCancel: enabled ? () => _setDown(false) : null,
        onTap: enabled
            ? () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: duration,
          curve: BBMotion.curve,
          child: AnimatedOpacity(
            opacity: _down ? 0.85 : 1,
            duration: duration,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Implement `lib/ui/kit/bb_card.dart`**

```dart
import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

class BBCard extends StatelessWidget {
  const BBCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: 10),
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final box = DecoratedBox(
      decoration: context.bb.card(),
      child: Padding(padding: padding, child: child),
    );
    if (onTap != null) {
      return BBPressable(onTap: onTap, semanticLabel: semanticLabel, child: box);
    }
    if (semanticLabel != null) {
      return Semantics(label: semanticLabel, excludeSemantics: true, child: box);
    }
    return box;
  }
}
```

- [ ] **Step 7: Implement `lib/ui/kit/bb_button.dart`**

```dart
import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

enum BBButtonKind { primary, quiet }

class BBButton extends StatelessWidget {
  const BBButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = BBButtonKind.primary,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final BBButtonKind kind;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final primary = kind == BBButtonKind.primary;
    final fg = primary ? bb.colors.onBrand : bb.colors.brandInk;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: BBSpace.s),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: bb.text.label.copyWith(color: fg, fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: BBPressable(
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          alignment: expand ? Alignment.center : null,
          decoration: primary
              ? BoxDecoration(color: bb.colors.brand, borderRadius: BorderRadius.circular(BBRadius.button))
              : null,
          child: content,
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Implement `lib/ui/kit/bb_pill.dart`**

```dart
import 'package:flutter/widgets.dart';

import 'tokens.dart';

enum BBPillTone { neutral, brand, live, warn, danger }

class BBPill extends StatelessWidget {
  const BBPill({
    super.key,
    required this.label,
    this.tone = BBPillTone.neutral,
    this.background,
    this.foreground,
    this.leadingDot = false,
  });

  final String label;
  final BBPillTone tone;

  /// Overrides the tone (used for route pills).
  final Color? background;
  final Color? foreground;
  final bool leadingDot;

  @override
  Widget build(BuildContext context) {
    final c = context.bb.colors;
    final (bg, fg) = switch (tone) {
      BBPillTone.neutral => (c.surfaceSunken, c.ink),
      BBPillTone.brand => (c.brandSoft, c.brandInk),
      BBPillTone.live => (c.liveSoft, c.liveInk),
      BBPillTone.warn => (c.warnBg, c.warnInk),
      BBPillTone.danger => (c.dangerBg, c.dangerInk),
    };
    final fgColor = foreground ?? fg;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? bg,
        borderRadius: BorderRadius.circular(BBRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BBSpace.s, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingDot) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: fgColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: context.bb.text.caption.copyWith(color: fgColor, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 9: Implement `lib/ui/kit/route_badge.dart`**

```dart
import 'package:flutter/widgets.dart';

import 'route_palette.dart';
import 'tokens.dart';

enum RouteBadgeSize { large, compact }

class RouteBadge extends StatelessWidget {
  const RouteBadge({
    super.key,
    required this.routeNumber,
    this.label,
    this.size = RouteBadgeSize.large,
  });

  final int routeNumber;

  /// Text shown in the badge; defaults to the route number.
  final String? label;
  final RouteBadgeSize size;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final fill = RoutePalette.of(routeNumber).fillFor(bb.brightness);
    final text = label ?? '$routeNumber';
    final large = size == RouteBadgeSize.large;
    final style = bb.text.label.copyWith(
      color: RoutePalette.ink,
      fontSize: large ? 17 : 12,
      fontWeight: FontWeight.w800,
    );

    final Widget badge = large
        ? SizedBox(
            width: 40,
            height: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(BBRadius.badge)),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(text, style: style, maxLines: 1),
                ),
              ),
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(BBRadius.pill)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 28),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: BBSpace.s, vertical: 3),
                child: Text(text, style: style, maxLines: 1, textAlign: TextAlign.center),
              ),
            ),
          );

    return Semantics(label: 'Route $text', excludeSemantics: true, child: badge);
  }
}
```

- [ ] **Step 10: Run the tests to verify they pass**

Run: `flutter test test/kit/basic_components_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 11: Commit**

```bash
git add test/kit/kit_test_helpers.dart test/kit/basic_components_test.dart lib/ui/kit/bb_icons.dart lib/ui/kit/bb_pressable.dart lib/ui/kit/bb_card.dart lib/ui/kit/bb_button.dart lib/ui/kit/bb_pill.dart lib/ui/kit/route_badge.dart
git commit -m "feat(kit): icons, pressable, card, button, pill and route badge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: BBSegmented, BBSwitch, BBTextField

**Files:**
- Create: `lib/ui/kit/bb_segmented.dart`, `lib/ui/kit/bb_switch.dart`, `lib/ui/kit/bb_text_field.dart`, `test/kit/input_components_test.dart`

**Interfaces:**
- Consumes: `BBPressable` (Task 4), tokens (Task 1), `kitHost` (Task 4).
- Produces:
  - `class BBSegment<T> { const BBSegment({required T value, required String label}) }`; `BBSegmented<T>({required List<BBSegment<T>> segments, required T selected, required ValueChanged<T> onChanged})`
  - `BBSwitch({required bool value, required ValueChanged<bool>? onChanged, String? semanticLabel})`
  - `BBTextField({TextEditingController? controller, String? hint, IconData? leadingIcon, ValueChanged<String>? onChanged, ValueChanged<String>? onSubmitted, TextInputType? keyboardType, TextInputAction? textInputAction, bool autofocus = false})`

- [ ] **Step 1: Write the failing test**

Create `test/kit/input_components_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/bb_segmented.dart';
import 'package:busboard_nl/ui/kit/bb_switch.dart';
import 'package:busboard_nl/ui/kit/bb_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

void main() {
  testWidgets('BBSegmented reports the tapped value, ignores the selected one', (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(kitHost(BBSegmented<String>(
      segments: const [BBSegment(value: 'near', label: 'Near me'), BBSegment(value: 'id', label: 'Stop number')],
      selected: 'near',
      onChanged: changes.add,
    )));
    await tester.tap(find.text('Stop number'));
    await tester.tap(find.text('Near me'));
    expect(changes, ['id']);
  });

  testWidgets('BBSegmented exposes selected state to accessibility', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(BBSegmented<int>(
      segments: const [BBSegment(value: 1, label: 'One'), BBSegment(value: 2, label: 'Two')],
      selected: 2,
      onChanged: (_) {},
    )));
    expect(tester.getSemantics(find.text('Two')), containsSemantics(
      label: 'Two', isSelected: true, isButton: true, hasTapAction: true, isInMutuallyExclusiveGroup: true,
    ));
    handle.dispose();
  });

  testWidgets('BBSwitch toggles and announces state', (tester) async {
    final handle = tester.ensureSemantics();
    bool? got;
    await tester.pumpWidget(kitHost(BBSwitch(value: false, onChanged: (v) => got = v, semanticLabel: 'Haptics')));
    await tester.tap(find.byType(BBSwitch));
    expect(got, isTrue);
    expect(tester.getSemantics(find.byType(BBSwitch)), containsSemantics(
      label: 'Haptics', hasToggledState: true, isToggled: false, hasTapAction: true,
    ));
    handle.dispose();
  });

  testWidgets('BBTextField shows hint and reports typing', (tester) async {
    final typed = <String>[];
    await tester.pumpWidget(kitHost(BBTextField(hint: 'Stop name or number on the pole', onChanged: typed.add)));
    expect(find.text('Stop name or number on the pole'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1150');
    expect(typed.last, '1150');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/kit/input_components_test.dart`
Expected: FAIL to compile.

- [ ] **Step 3: Implement `lib/ui/kit/bb_segmented.dart`**

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

class BBSegment<T> {
  const BBSegment({required this.value, required this.label});
  final T value;
  final String label;
}

class BBSegmented<T> extends StatelessWidget {
  const BBSegmented({super.key, required this.segments, required this.selected, required this.onChanged});

  final List<BBSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final duration = BBMotion.of(context, BBMotion.standard);
    return DecoratedBox(
      decoration: BoxDecoration(color: bb.colors.surfaceSunken, borderRadius: BorderRadius.circular(BBRadius.badge)),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (final s in segments)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: s.value == selected,
                  inMutuallyExclusiveGroup: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (s.value == selected) return;
                      HapticFeedback.selectionClick();
                      onChanged(s.value);
                    },
                    child: AnimatedContainer(
                      duration: duration,
                      curve: BBMotion.curve,
                      padding: const EdgeInsets.symmetric(vertical: BBSpace.s),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.value == selected ? bb.colors.surface : const Color(0x00000000),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: bb.text.label.copyWith(
                          color: s.value == selected ? bb.colors.ink : bb.colors.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

(`Color(0x00000000)` is plain transparent, allowed under the global constraint since it isn't a palette colour. If the guard reviewer objects, use `const Color.fromARGB(0, 0, 0, 0)`.)

- [ ] **Step 4: Implement `lib/ui/kit/bb_switch.dart`**

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

class BBSwitch extends StatelessWidget {
  const BBSwitch({super.key, required this.value, required this.onChanged, this.semanticLabel});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.bb.colors;
    final duration = BBMotion.of(context, BBMotion.standard);
    final enabled = onChanged != null;
    return Semantics(
      label: semanticLabel,
      toggled: value,
      enabled: enabled,
      onTap: enabled ? () => onChanged!(!value) : null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: duration,
            curve: BBMotion.curve,
            width: 46,
            height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? c.brand : c.surfaceSunken,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: value ? c.brand : c.line),
            ),
            child: AnimatedAlign(
              duration: duration,
              curve: BBMotion.curve,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: value ? c.onBrand : c.surface, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Implement `lib/ui/kit/bb_text_field.dart`**

```dart
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Search/input field. Uses Material's TextField internally (kit-only) for
/// selection handles and IME support, with all Material decoration removed.
class BBTextField extends StatelessWidget {
  const BBTextField({
    super.key,
    this.controller,
    this.hint,
    this.leadingIcon,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String? hint;
  final IconData? leadingIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: BBSpace.m),
      decoration: BoxDecoration(
        color: bb.colors.surface,
        borderRadius: BorderRadius.circular(BBRadius.button),
        border: Border.all(color: bb.colors.line),
      ),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 20, color: bb.colors.muted),
            const SizedBox(width: BBSpace.s),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              autofocus: autofocus,
              style: bb.text.body,
              cursorColor: bb.colors.brand,
              decoration: InputDecoration.collapsed(
                hintText: hint,
                hintStyle: bb.text.body.copyWith(color: bb.colors.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/kit/input_components_test.dart`
Expected: PASS (4 tests). If the `matchesSemantics` call for BBSegmented fails only because of an extra flag (e.g. `hasEnabledState`), add the flags the failure message lists. Don't remove `isSelected`/`isInMutuallyExclusiveGroup`.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/kit/bb_segmented.dart lib/ui/kit/bb_switch.dart lib/ui/kit/bb_text_field.dart test/kit/input_components_test.dart
git commit -m "feat(kit): segmented control, switch and text field

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: BBScaffold + BBNavBar

**Files:**
- Create: `lib/ui/kit/bb_scaffold.dart`, `lib/ui/kit/bb_nav_bar.dart`, `test/kit/nav_bar_test.dart`

**Interfaces:**
- Consumes: `BBPressable` (Task 4), tokens.
- Produces:
  - `class BBNavItem { const BBNavItem({required String label, required IconData icon, int badgeCount = 0}) }`
  - `BBNavBar({required List<BBNavItem> items, required int currentIndex, required ValueChanged<int> onSelect})`; `static const double height = 56`; `static const double gap = 16`; `static double reservedHeight(BuildContext)`
  - `BBScaffold({required Widget body, bool safeTop = true})` (provides `bg`, a `Material` ancestor for kit text fields, system-bar icon brightness)

- [ ] **Step 1: Write the failing test**

Create `test/kit/nav_bar_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/bb_icons.dart';
import 'package:busboard_nl/ui/kit/bb_nav_bar.dart';
import 'package:busboard_nl/ui/kit/bb_scaffold.dart';
import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

const _items = [
  BBNavItem(label: 'Board', icon: BBIcons.board),
  BBNavItem(label: 'Map', icon: BBIcons.map),
  BBNavItem(label: 'Alerts', icon: BBIcons.alerts, badgeCount: 2),
];

void main() {
  testWidgets('tapping a tab reports its index', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(kitHost(BBNavBar(items: _items, currentIndex: 0, onSelect: picked.add)));
    await tester.tap(find.text('Map'));
    await tester.tap(find.text('Alerts'));
    expect(picked, [1, 2]);
  });

  testWidgets('badge shows the count and accessibility includes it', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(BBNavBar(items: _items, currentIndex: 0, onSelect: (_) {})));
    expect(find.text('2'), findsOneWidget);
    expect(find.bySemanticsLabel('Alerts, 2 active'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('Board')), containsSemantics(
      label: 'Board', isSelected: true, isButton: true, hasTapAction: true,
    ));
    handle.dispose();
  });

  testWidgets('active tab uses the brand fill', (tester) async {
    await tester.pumpWidget(kitHost(BBNavBar(items: _items, currentIndex: 1, onSelect: (_) {})));
    final active = tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .where((c) => c == BBColors.light.brand);
    expect(active.length, 1);
  });

  testWidgets('no overflow at text scale 2.0 on a 320pt phone', (tester) async {
    await tester.pumpWidget(kitHost(
      BBNavBar(items: _items, currentIndex: 2, onSelect: (_) {}),
      textScale: 2.0,
      width: 320,
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reservedHeight accounts for the bottom safe area', (tester) async {
    late double reserved;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
      child: Builder(builder: (context) {
        reserved = BBNavBar.reservedHeight(context);
        return const SizedBox();
      }),
    ));
    expect(reserved, BBNavBar.height + BBNavBar.gap + 34);
  });

  testWidgets('BBScaffold paints bg and hosts Material for text fields', (tester) async {
    await tester.pumpWidget(kitHost(const SizedBox(height: 200, child: BBScaffold(body: Text('page')))));
    expect(find.text('page'), findsOneWidget);
    final material = tester.widget<Material>(
      find.descendant(of: find.byType(BBScaffold), matching: find.byType(Material)).first,
    );
    expect(material.color, BBColors.light.bg);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/kit/nav_bar_test.dart`
Expected: FAIL to compile.

- [ ] **Step 3: Implement `lib/ui/kit/bb_nav_bar.dart`**

```dart
import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

class BBNavItem {
  const BBNavItem({required this.label, required this.icon, this.badgeCount = 0});
  final String label;
  final IconData icon;
  final int badgeCount;
}

/// White floating pill bar; the active tab is a full Harbour Blue pill.
class BBNavBar extends StatelessWidget {
  const BBNavBar({super.key, required this.items, required this.currentIndex, required this.onSelect});

  final List<BBNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const double height = 56;

  /// Gap between the bar and the bottom safe area.
  static const double gap = 16;

  /// Bottom space a screen must leave free so content isn't hidden by the bar.
  static double reservedHeight(BuildContext context) =>
      height + gap + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, gap + MediaQuery.paddingOf(context).bottom),
      child: Container(
        height: height,
        padding: const EdgeInsets.all(5),
        decoration: bb.floating(radius: BBRadius.sheet),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _Tab(item: items[i], selected: i == currentIndex, onTap: () => onSelect(i)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.selected, required this.onTap});

  final BBNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final fg = selected ? bb.colors.onBrand : bb.colors.muted;
    final label = item.badgeCount > 0 ? '${item.label}, ${item.badgeCount} active' : item.label;
    return Semantics(
      selected: selected,
      child: BBPressable(
        onTap: onTap,
        haptic: true,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: BBMotion.of(context, BBMotion.standard),
          curve: BBMotion.curve,
          decoration: BoxDecoration(
            color: selected ? bb.colors.brand : null,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(item.label, maxLines: 1, style: bb.text.label.copyWith(color: fg)),
                if (item.badgeCount > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: bb.colors.dangerInk, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      '${item.badgeCount}',
                      textAlign: TextAlign.center,
                      style: bb.text.caption.copyWith(
                        color: bb.colors.surface,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement `lib/ui/kit/bb_scaffold.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Page shell: `bg` background, top safe area, system-bar icon brightness
/// matching the theme, and a Material ancestor (kit-internal) so
/// [BBTextField] works.
class BBScaffold extends StatelessWidget {
  const BBScaffold({super.key, required this.body, this.safeTop = true});

  final Widget body;
  final bool safeTop;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final overlay = (bb.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: const Color(0x00000000),
      systemNavigationBarColor: const Color(0x00000000),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Material(
        color: bb.colors.bg,
        child: DefaultTextStyle(
          style: bb.text.body,
          child: SafeArea(top: safeTop, bottom: false, child: body),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/kit/nav_bar_test.dart`
Expected: PASS (6 tests). If the selected-tab `matchesSemantics` fails because the merged node has a different flag set, match the flags the failure output lists, but keep `isSelected: true` and the label.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/kit/bb_nav_bar.dart lib/ui/kit/bb_scaffold.dart test/kit/nav_bar_test.dart
git commit -m "feat(kit): floating nav bar and page scaffold

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: BBSheet

**Files:**
- Create: `lib/ui/kit/bb_sheet.dart`, `test/kit/sheet_test.dart`

**Interfaces:**
- Consumes: tokens.
- Produces: `BBSheet({required List<Widget> slivers, required double peekFraction, double halfFraction = 0.5, double fullFraction = 0.9, double? initialFraction, DraggableScrollableController? controller})`. Fractions are of the sheet's parent height. Asserts `0 < peek < half < full <= 1`.

- [ ] **Step 1: Write the failing test**

Create `test/kit/sheet_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/bb_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

Widget _host(DraggableScrollableController controller, {bool reduceMotion = false}) {
  return kitHost(
    MediaQuery(
      data: MediaQueryData(size: const Size(390, 800), disableAnimations: reduceMotion),
      child: SizedBox(
        height: 800,
        child: Stack(children: [
          BBSheet(
            controller: controller,
            peekFraction: 0.15,
            slivers: [
              SliverList.builder(itemCount: 30, itemBuilder: (_, i) => SizedBox(height: 44, child: Text('row $i'))),
            ],
          ),
        ]),
      ),
    ),
  );
}

void main() {
  testWidgets('starts at peek and snaps up to half when dragged', (tester) async {
    final controller = DraggableScrollableController();
    await tester.pumpWidget(_host(controller));
    expect(controller.size, closeTo(0.15, 0.001));

    await tester.drag(find.text('row 0'), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.5, 0.01));
  });

  testWidgets('still snaps with reduce motion on (no zero-duration assert)', (tester) async {
    final controller = DraggableScrollableController();
    await tester.pumpWidget(_host(controller, reduceMotion: true));
    await tester.drag(find.text('row 0'), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.size, closeTo(0.5, 0.01));
  });

  test('rejects unordered fractions', () {
    expect(() => BBSheet(slivers: const [], peekFraction: 0.6, halfFraction: 0.5), throwsAssertionError);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/kit/sheet_test.dart`
Expected: FAIL to compile.

- [ ] **Step 3: Implement `lib/ui/kit/bb_sheet.dart`**

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Draggable bottom sheet with three detents (peek / half / full) and a
/// haptic tick when it settles on one. Place it in a Stack over the content.
class BBSheet extends StatefulWidget {
  BBSheet({
    super.key,
    required this.slivers,
    required this.peekFraction,
    this.halfFraction = 0.5,
    this.fullFraction = 0.9,
    this.initialFraction,
    this.controller,
  }) : assert(peekFraction > 0 && peekFraction < halfFraction && halfFraction < fullFraction && fullFraction <= 1,
            'BBSheet fractions must satisfy 0 < peek < half < full <= 1');

  final List<Widget> slivers;
  final double peekFraction;
  final double halfFraction;
  final double fullFraction;
  final double? initialFraction;
  final DraggableScrollableController? controller;

  @override
  State<BBSheet> createState() => _BBSheetState();
}

class _BBSheetState extends State<BBSheet> {
  double? _lastDetent;

  bool _onExtent(DraggableScrollableNotification n) {
    for (final detent in [widget.peekFraction, widget.halfFraction, widget.fullFraction]) {
      if ((n.extent - detent).abs() < 0.004) {
        if (_lastDetent != detent) {
          _lastDetent = detent;
          HapticFeedback.selectionClick();
        }
        return false;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final reduce = BBMotion.of(context, BBMotion.sheet) == Duration.zero;
    const radius = BorderRadius.vertical(top: Radius.circular(BBRadius.sheet));
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: _onExtent,
      child: DraggableScrollableSheet(
        controller: widget.controller,
        initialChildSize: widget.initialFraction ?? widget.peekFraction,
        minChildSize: widget.peekFraction,
        maxChildSize: widget.fullFraction,
        snap: true,
        snapSizes: [widget.halfFraction],
        // The sheet API rejects Duration.zero, so "reduce motion" uses 1 ms.
        snapAnimationDuration: reduce ? const Duration(milliseconds: 1) : BBMotion.sheet,
        builder: (context, scrollController) => DecoratedBox(
          decoration: bb.floating(borderRadius: radius).copyWith(color: bb.colors.bg),
          child: ClipRRect(
            borderRadius: radius,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: BBSpace.s, bottom: BBSpace.m),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: bb.colors.line, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
                ...widget.slivers,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/kit/sheet_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/kit/bb_sheet.dart test/kit/sheet_test.dart
git commit -m "feat(kit): draggable sheet with peek/half/full detents

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: BBToast, BBDialog, BBRefresh + kit barrel

**Files:**
- Create: `lib/ui/kit/bb_toast.dart`, `lib/ui/kit/bb_dialog.dart`, `lib/ui/kit/bb_refresh.dart`, `lib/ui/kit/kit.dart`, `test/kit/feedback_components_test.dart`

**Interfaces:**
- Consumes: `BBButton` (Task 4), `BBNavBar.reservedHeight` (Task 6), tokens.
- Produces:
  - `abstract final class BBToast { static void show(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}); }`
  - `class BBDialogAction<T> { const BBDialogAction({required String label, required T value, bool primary = false}) }`; `abstract final class BBDialog { static Future<T?> show<T>(BuildContext context, {required String title, String? message, required List<BBDialogAction<T>> actions}); }`
  - `BBRefresh({required Future<void> Function() onRefresh, required Widget child})`
  - `lib/ui/kit/kit.dart` exporting every kit file.

- [ ] **Step 1: Write the failing test**

Create `test/kit/feedback_components_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

Widget _launcher(void Function(BuildContext) onPressed) {
  return kitHost(Builder(
    builder: (context) => BBButton(label: 'go', onPressed: () => onPressed(context)),
  ));
}

void main() {
  testWidgets('toast appears, announces, then disappears', (tester) async {
    await tester.pumpWidget(_launcher((c) => BBToast.show(c, 'Bus 2134 is no longer reporting')));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Bus 2134 is no longer reporting'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Bus 2134 is no longer reporting'), findsNothing);
  });

  testWidgets('a second toast replaces the first without errors', (tester) async {
    var n = 0;
    await tester.pumpWidget(_launcher((c) => BBToast.show(c, 'toast ${++n}')));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('toast 1'), findsNothing);
    expect(find.text('toast 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('toast survives its launching screen being removed', (tester) async {
    await tester.pumpWidget(_launcher((c) => BBToast.show(c, 'bye')));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(kitHost(const Text('other screen')));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog returns the tapped action value', (tester) async {
    String? result;
    await tester.pumpWidget(_launcher((c) async {
      result = await BBDialog.show<String>(c, title: 'Change stop?', message: 'Your board will switch.', actions: const [
        BBDialogAction(label: 'Cancel', value: 'no'),
        BBDialogAction(label: 'Change', value: 'yes', primary: true),
      ]);
    }));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Change stop?'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(result, 'yes');
    expect(find.text('Change stop?'), findsNothing);
  });

  testWidgets('pull to refresh calls onRefresh', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(kitHost(SizedBox(
      height: 600,
      child: BBRefresh(
        onRefresh: () async => refreshed++,
        child: ListView(children: const [SizedBox(height: 100, child: Text('row'))]),
      ),
    )));
    await tester.fling(find.text('row'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/kit/feedback_components_test.dart`
Expected: FAIL to compile (`kit.dart` doesn't exist).

- [ ] **Step 3: Implement `lib/ui/kit/bb_toast.dart`**

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'bb_nav_bar.dart';
import 'tokens.dart';

/// Floating message above the nav bar (replaces SnackBar). Only one is
/// visible at a time; a new one replaces the current one.
abstract final class BBToast {
  static OverlayEntry? _current;

  static void show(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    _dismissCurrent();
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        duration: duration,
        onDone: () {
          if (identical(_current, entry)) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  static void _dismissCurrent() {
    final current = _current;
    _current = null;
    if (current != null && current.mounted) current.remove();
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({required this.message, required this.duration, required this.onDone});

  final String message;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: BBMotion.standard);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _anim.forward();
    _timer = Timer(widget.duration, () async {
      if (!mounted) return;
      await _anim.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final curved = CurvedAnimation(parent: _anim, curve: BBMotion.curve);
    return Positioned(
      left: BBSpace.l,
      right: BBSpace.l,
      bottom: BBNavBar.reservedHeight(context) + BBSpace.s,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(curved),
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: BBSpace.l, vertical: BBSpace.m),
              decoration: bb.floating(radius: BBRadius.card).copyWith(color: bb.colors.ink),
              child: Text(widget.message, style: bb.text.label.copyWith(color: bb.colors.bg)),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement `lib/ui/kit/bb_dialog.dart`**

```dart
import 'package:flutter/widgets.dart';

import 'bb_button.dart';
import 'tokens.dart';

class BBDialogAction<T> {
  const BBDialogAction({required this.label, required this.value, this.primary = false});
  final String label;
  final T value;
  final bool primary;
}

/// Centred card dialog (replaces AlertDialog).
abstract final class BBDialog {
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? message,
    required List<BBDialogAction<T>> actions,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: const Color(0x661C2A3A),
      transitionDuration: BBMotion.of(context, BBMotion.standard),
      pageBuilder: (dialogContext, _, _) => _DialogCard<T>(title: title, message: message, actions: actions),
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: BBMotion.curve);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
        );
      },
    );
  }
}

class _DialogCard<T> extends StatelessWidget {
  const _DialogCard({required this.title, required this.message, required this.actions});

  final String title;
  final String? message;
  final List<BBDialogAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BBSpace.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DecoratedBox(
            decoration: bb.floating(radius: BBRadius.sheet),
            child: Padding(
              padding: const EdgeInsets.all(BBSpace.xl),
              child: DefaultTextStyle(
                style: bb.text.body,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(header: true, child: Text(title, style: bb.text.headline)),
                    if (message != null) ...[
                      const SizedBox(height: BBSpace.s),
                      Text(message!, style: bb.text.body.copyWith(color: bb.colors.muted)),
                    ],
                    const SizedBox(height: BBSpace.xl),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: BBSpace.s,
                      runSpacing: BBSpace.s,
                      children: [
                        for (final a in actions)
                          BBButton(
                            label: a.label,
                            kind: a.primary ? BBButtonKind.primary : BBButtonKind.quiet,
                            onPressed: () => Navigator.of(context).pop(a.value),
                          ),
                      ],
                    ),
                  ],
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

- [ ] **Step 5: Implement `lib/ui/kit/bb_refresh.dart`**

```dart
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Pull to refresh with a brand-coloured indicator on a flat surface disc.
class BBRefresh extends StatelessWidget {
  const BBRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.bb.colors;
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: c.brand,
      backgroundColor: c.surface,
      elevation: 0,
      displacement: 48,
      child: child,
    );
  }
}
```

- [ ] **Step 6: Create the barrel `lib/ui/kit/kit.dart`**

```dart
/// Harbour component kit. Screens import only this file.
library;

export 'bb_button.dart';
export 'bb_card.dart';
export 'bb_dialog.dart';
export 'bb_icons.dart';
export 'bb_nav_bar.dart';
export 'bb_pill.dart';
export 'bb_pressable.dart';
export 'bb_refresh.dart';
export 'bb_scaffold.dart';
export 'bb_segmented.dart';
export 'bb_sheet.dart';
export 'bb_switch.dart';
export 'bb_text_field.dart';
export 'bb_theme.dart';
export 'bb_toast.dart';
export 'route_badge.dart';
export 'route_palette.dart';
export 'tokens.dart';
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/kit/feedback_components_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 8: Commit**

```bash
git add lib/ui/kit/bb_toast.dart lib/ui/kit/bb_dialog.dart lib/ui/kit/bb_refresh.dart lib/ui/kit/kit.dart test/kit/feedback_components_test.dart
git commit -m "feat(kit): toast, dialog, pull-to-refresh and kit barrel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Kit golden tests (light/dark × text scale 1.0/2.0)

**Files:**
- Create: `test/kit/kit_golden_test.dart`, `test/kit/goldens/*.png` (generated)

**Interfaces:**
- Consumes: everything in `kit.dart`; `loadAppFonts`, `kitHost`.
- Produces: four golden images that lock the kit's look.

- [ ] **Step 1: Write the golden test**

Create `test/kit/kit_golden_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    Widget row(int route, String dest, String status, String mins, {bool soon = false}) => BBCard(
          child: Row(children: [
            RouteBadge(routeNumber: route),
            const SizedBox(width: BBSpace.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(dest, style: bb.text.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(status, style: bb.text.caption),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(mins, style: bb.text.minutes.copyWith(color: soon ? bb.colors.soon : null)),
              Text('min', style: bb.text.minutesUnit),
            ]),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.all(BBSpace.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('MUN Centre', style: bb.text.display),
        const SizedBox(height: BBSpace.s),
        const Wrap(spacing: 6, runSpacing: 6, children: [
          BBPill(label: 'Live', tone: BBPillTone.live, leadingDot: true),
          BBPill(label: 'Detour', tone: BBPillTone.warn),
          BBPill(label: 'No service', tone: BBPillTone.danger),
          BBPill(label: 'Stop 1150', tone: BBPillTone.brand),
          RouteBadge(routeNumber: 10, size: RouteBadgeSize.compact),
          RouteBadge(routeNumber: 14, size: RouteBadgeSize.compact),
        ]),
        const SizedBox(height: BBSpace.s),
        row(29, 'Signal Hill Rd', 'Live · Bus 2134', '4', soon: true),
        const SizedBox(height: BBSpace.s),
        row(23, 'Stavanger Drive', 'Scheduled', '6'),
        const SizedBox(height: BBSpace.m),
        BBSegmented<int>(
          segments: const [BBSegment(value: 0, label: 'Near me'), BBSegment(value: 1, label: 'Stop number')],
          selected: 0,
          onChanged: (_) {},
        ),
        const SizedBox(height: BBSpace.m),
        const BBTextField(hint: 'Stop name or number on the pole', leadingIcon: BBIcons.search),
        const SizedBox(height: BBSpace.m),
        Row(children: [
          BBButton(label: 'Use this stop', onPressed: () {}),
          const SizedBox(width: BBSpace.s),
          BBButton(label: 'Cancel', kind: BBButtonKind.quiet, onPressed: () {}),
          const Spacer(),
          BBSwitch(value: true, onChanged: (_) {}),
        ]),
        const SizedBox(height: BBSpace.m),
        BBNavBar(
          items: const [
            BBNavItem(label: 'Board', icon: BBIcons.board),
            BBNavItem(label: 'Map', icon: BBIcons.map),
            BBNavItem(label: 'Alerts', icon: BBIcons.alerts, badgeCount: 2),
          ],
          currentIndex: 0,
          onSelect: (_) {},
        ),
      ]),
    );
  }
}

void main() {
  setUpAll(loadAppFonts);

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('kit gallery ${brightness.name} x$scale', (tester) async {
        tester.view.physicalSize = Size(390 * 3, (scale == 1.0 ? 900 : 1500) * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(kitHost(
          const SingleChildScrollView(child: _Gallery()),
          brightness: brightness,
          textScale: scale,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(_Gallery),
          matchesGoldenFile('goldens/kit_gallery_${brightness.name}_x${scale.toStringAsFixed(0)}.png'),
        );
      });
    }
  }
}
```

- [ ] **Step 2: Generate the goldens**

Run: `flutter test --update-goldens test/kit/kit_golden_test.dart`
Expected: PASS. Four files are created under `test/kit/goldens/`.

- [ ] **Step 3: Inspect each golden by eye**

Open all four PNGs (Read tool / image viewer) and check against spec §4–§5:
- cream background in light, navy in dark
- Figtree glyphs (not boxes); rounded icons
- coloured route badges with navy numbers
- the orange-red "4"
- the white floating nav bar with the blue active "Board" pill and a red "2" badge
- at x2: no clipped or overlapping text

If anything is wrong, fix the component (not the test), re-run Step 2, and re-inspect.

- [ ] **Step 4: Verify the goldens are stable**

Run: `flutter test test/kit/kit_golden_test.dart`
Expected: PASS (4 tests, no diffs).

- [ ] **Step 5: Commit**

```bash
git add test/kit/kit_golden_test.dart test/kit/goldens
git commit -m "test(kit): light/dark goldens at text scale 1.0 and 2.0

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Kit boundary guard test

**Files:**
- Create: `test/kit/kit_boundary_test.dart`

**Interfaces:**
- Consumes: the file layout of `lib/ui/`.
- Produces: a failing test whenever a non-kit UI file uses Material/Cupertino widgets, except for the legacy allow-list that Phase 2 empties.

- [ ] **Step 1: Write the guard test**

Create `test/kit/kit_boundary_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Material/Cupertino widgets that must not appear in screen code.
final _forbidden = RegExp(
  r'\b(Scaffold|AppBar|NavigationBar|NavigationDestination|BottomNavigationBar|'
  r'FloatingActionButton|ListTile|Card|ElevatedButton|FilledButton|TextButton|'
  r'OutlinedButton|IconButton|SegmentedButton|Switch|SwitchListTile|Chip|FilterChip|'
  r'ChoiceChip|ActionChip|SnackBar|AlertDialog|showModalBottomSheet|showDialog|'
  r'RefreshIndicator|InkWell|Badge|Slider|Cupertino[A-Z]\w*)\b\s*[.(<]'
  r'|\bIcons\.',
);

/// Screens not yet rebuilt on the kit. Phase 2 removes entries as it
/// migrates each file; the list must only ever shrink.
const _legacyAllowList = {
  'lib/ui/alerts/alerts_screen.dart',
  'lib/ui/alerts/service_alert_card.dart',
  'lib/ui/board/arrival_board_screen.dart',
  'lib/ui/board/arrival_row_tile.dart',
  'lib/ui/map/bus_bottom_sheet.dart',
  'lib/ui/map/map_screen.dart',
  'lib/ui/map/stop_bottom_sheet.dart',
  'lib/ui/settings/settings_screen.dart',
  'lib/ui/shell/app_shell.dart',
  'lib/ui/stop_picker/near_me_list.dart',
  'lib/ui/stop_picker/stop_id_entry.dart',
  'lib/ui/stop_picker/stop_picker_screen.dart',
};

void main() {
  final files = Directory('lib/ui')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path.replaceAll(r'\', '/'))
      .where((p) => !p.startsWith('lib/ui/kit/'))
      .toList()
    ..sort();

  List<String> violations(String path) {
    final lines = File(path).readAsLinesSync();
    return [
      for (var i = 0; i < lines.length; i++)
        if (!lines[i].trimLeft().startsWith('//') && _forbidden.hasMatch(lines[i]))
          '$path:${i + 1}: ${lines[i].trim()}',
    ];
  }

  test('screen code uses the kit, not Material/Cupertino widgets', () {
    final bad = [
      for (final f in files)
        if (!_legacyAllowList.contains(f)) ...violations(f),
    ];
    expect(bad, isEmpty, reason: 'Use lib/ui/kit/ instead:\n${bad.join('\n')}');
  });

  test('allow-list only holds files that still need migrating', () {
    final stale = [
      for (final f in _legacyAllowList)
        if (!File(f).existsSync() || violations(f).isEmpty) f,
    ];
    expect(stale, isEmpty, reason: 'Remove these from _legacyAllowList: $stale');
  });

  test('the guard actually detects violations', () {
    expect(_forbidden.hasMatch('return Scaffold('), isTrue);
    expect(_forbidden.hasMatch('Icon(Icons.map)'), isTrue);
    expect(_forbidden.hasMatch('CupertinoButton('), isTrue);
    expect(_forbidden.hasMatch('BBCard('), isFalse);
    expect(_forbidden.hasMatch('final scaffoldKey = 1;'), isFalse);
  });
}
```

- [ ] **Step 2: Run it**

Run: `flutter test test/kit/kit_boundary_test.dart`
Expected: PASS (3 tests). If the "allow-list only holds…" test fails because a legacy file has no violations, remove that file from the allow-list. If the first test fails for a non-allow-listed file outside `lib/ui/kit/`, that file needs migrating or allow-listing: list it and stop to ask.

- [ ] **Step 3: Commit**

```bash
git add test/kit/kit_boundary_test.dart
git commit -m "test(kit): guard screens against direct Material/Cupertino widgets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Legal and attribution copy

**Files:**
- Create: `lib/ui/copy/legal_copy.dart`, `test/legal_copy_test.dart`
- Modify: `lib/ui/alerts/alerts_screen.dart:109` (footer text), `lib/ui/settings/settings_screen.dart:305-346` (About card body)

**Interfaces:**
- Produces: `abstract final class LegalCopy { static const independence, dataCredit, mapCredit, footer; }`

- [ ] **Step 1: Write the failing test**

Create `test/legal_copy_test.dart`:

```dart
import 'dart:io';

import 'package:busboard_nl/ui/copy/legal_copy.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:busboard_nl/ui/kit/bb_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('copy matches the spec verbatim', () {
    expect(LegalCopy.independence,
        'BusBoard NL is an independent app and is not affiliated with Metrobus Transit.');
    expect(LegalCopy.dataCredit, 'Schedules and live data: Metrobus open data (GTFS, GTFS-Realtime)');
    expect(LegalCopy.mapCredit, 'Map: OpenFreeMap · © OpenStreetMap contributors');
    expect(LegalCopy.footer, 'Data from Metrobus open data · BusBoard is independent');
  });

  test('no UI text claims to be official Metrobus', () {
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => File(f.path).readAsStringSync().contains(RegExp(r"'[^']*Official Metrobus")))
        .map((f) => f.path)
        .toList();
    expect(hits, isEmpty);
  });

  testWidgets('Settings shows the independence line and credits', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: BBTheme.light(), home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(LegalCopy.independence), 200);
    expect(find.text(LegalCopy.independence), findsOneWidget);
    expect(find.text(LegalCopy.dataCredit), findsOneWidget);
    expect(find.text(LegalCopy.mapCredit), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/legal_copy_test.dart`
Expected: FAIL to compile (`legal_copy.dart` doesn't exist).

- [ ] **Step 3: Create `lib/ui/copy/legal_copy.dart`**

```dart
/// Legal and attribution strings (spec §6.4, §6.5). Keep verbatim.
abstract final class LegalCopy {
  static const independence =
      'BusBoard NL is an independent app and is not affiliated with Metrobus Transit.';
  static const dataCredit = 'Schedules and live data: Metrobus open data (GTFS, GTFS-Realtime)';
  static const mapCredit = 'Map: OpenFreeMap · © OpenStreetMap contributors';
  static const footer = 'Data from Metrobus open data · BusBoard is independent';
}
```

- [ ] **Step 4: Update the Alerts footer**

In `lib/ui/alerts/alerts_screen.dart`, add `import '../copy/legal_copy.dart';` with the other relative imports, and replace

```dart
            'Pull down to refresh · Official Metrobus GTFS-Realtime',
```

with

```dart
            LegalCopy.footer,
```

- [ ] **Step 5: Update the Settings About card**

In `lib/ui/settings/settings_screen.dart`, add `import '../copy/legal_copy.dart';`. In the About card's `Column` children, replace the final `Text('Data: Metrobus public GTFS, GTFS-Realtime and TimeTrack JSON feeds. No webpage scraping.', …)` widget (the last child) with:

```dart
                    Text(
                      LegalCopy.independence,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      LegalCopy.dataCredit,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      LegalCopy.mapCredit,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
```

(This screen is still legacy Material and is rebuilt on the kit in Phase 2; only the copy changes now.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/legal_copy_test.dart`
Expected: PASS (3 tests). If the Settings test can't find the text because the screen needs additional providers, add the missing provider overrides that the error names to the `ProviderScope`. Don't weaken the assertions.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/copy/legal_copy.dart test/legal_copy_test.dart lib/ui/alerts/alerts_screen.dart lib/ui/settings/settings_screen.dart
git commit -m "fix: state independence from Metrobus and credit data/map sources

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Brand assets: icon, adaptive icon, splash, store art

**Files:**
- Create: `assets/brand/busboard_icon.svg`, `assets/brand/busboard_mark.svg`, `tool/brand/render_brand_assets.sh`
- Generate: `assets/icon/app_icon.png`, `assets/icon/app_icon_foreground.png`, `assets/icon/splash_logo.png`, `assets/icon/splash_logo_android12.png`, `assets/icon/app_icon_gplay.png`, `assets/icon/feature_graph_gplay.png`, plus platform icon/splash resources under `ios/` and `android/`
- Modify: `pubspec.yaml` (`flutter_launcher_icons`, `flutter_native_splash` sections)
- Delete: `assets/icon/app_icon_nobg.png`, `assets/icon/splash_background.png`

**Interfaces:**
- Consumes: Figtree TTFs (Task 1) for the feature-graphic text.
- Produces: the shipped brand assets.

- [ ] **Step 1: Create the full icon master `assets/brand/busboard_icon.svg`**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <!-- BusBoard NL app icon (spec §3.1). Background Harbour Blue. -->
  <rect width="100" height="100" fill="#3E7CB1"/>
  <g id="mark">
    <path d="M12 46 L21 37 L30 46 V70 H12Z" fill="#D63B3B"/>
    <path d="M30 46 L39 37 L48 46 V70 H30Z" fill="#F2C94C"/>
    <path d="M48 46 L57 37 L66 46 V70 H48Z" fill="#C3A6EE"/>
    <path d="M66 46 L75 37 L84 46 V70 H66Z" fill="#6FCF97"/>
    <rect x="18" y="47.5" width="6" height="7" rx="1" fill="#1C2A3A" fill-opacity=".45"/>
    <rect x="36" y="47.5" width="6" height="7" rx="1" fill="#1C2A3A" fill-opacity=".45"/>
    <rect x="54" y="47.5" width="6" height="7" rx="1" fill="#1C2A3A" fill-opacity=".45"/>
    <rect x="72" y="47.5" width="6" height="7" rx="1" fill="#1C2A3A" fill-opacity=".45"/>
    <rect x="14" y="58" width="66" height="22" rx="6" fill="#F7F2EA"/>
    <rect x="19" y="62" width="10" height="8" rx="1.8" fill="#1C2A3A"/>
    <rect x="32" y="62" width="10" height="8" rx="1.8" fill="#1C2A3A"/>
    <rect x="45" y="62" width="10" height="8" rx="1.8" fill="#1C2A3A"/>
    <rect x="58" y="62" width="10" height="8" rx="1.8" fill="#1C2A3A"/>
    <rect x="71" y="62" width="6" height="13" rx="1.8" fill="#1C2A3A"/>
    <circle cx="28" cy="81" r="5" fill="#1C2A3A"/>
    <circle cx="28" cy="81" r="2.2" fill="#F7F2EA"/>
    <circle cx="66" cy="81" r="5" fill="#1C2A3A"/>
    <circle cx="66" cy="81" r="2.2" fill="#F7F2EA"/>
    <path d="M57 9c-6 0-10.5 4.5-10.5 10.5 0 7.5 10.5 17 10.5 17s10.5-9.5 10.5-17C67.5 13.5 63 9 57 9z" fill="#F7F2EA"/>
    <circle cx="57" cy="19.5" r="4" fill="#1C2A3A"/>
  </g>
</svg>
```

- [ ] **Step 2: Create the transparent mark `assets/brand/busboard_mark.svg`**

This is the same `<g id="mark">` content without the background `<rect>`, in a tight viewBox around the artwork (x 12–86, y 9–86):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="10 7 78 81">
  <!-- BusBoard NL mark on transparent (adaptive-icon foreground, splash). -->
  <path d="M12 46 L21 37 L30 46 V70 H12Z" fill="#D63B3B"/>
  <path d="M30 46 L39 37 L48 46 V70 H30Z" fill="#F2C94C"/>
  <path d="M48 46 L57 37 L66 46 V70 H48Z" fill="#C3A6EE"/>
  <path d="M66 46 L75 37 L84 46 V70 H66Z" fill="#6FCF97"/>
  <rect x="18" y="47.5" width="6" height="7" rx="1" fill="#1C2A3A" fill-opacity=".45"/>
  <rect x="36" y="47.5" width="6" height="7" rx="1" fill="#1C2A3A" fill-opacity=".45"/>
  <rect x="54" y="47.5" width="6" height="7" rx="1" fill="#1C2A3A" fill-opacity=".45"/>
  <rect x="72" y="47.5" width="6" height="7" rx="1" fill="#1C2A3A" fill-opacity=".45"/>
  <rect x="14" y="58" width="66" height="22" rx="6" fill="#F7F2EA"/>
  <rect x="19" y="62" width="10" height="8" rx="1.8" fill="#1C2A3A"/>
  <rect x="32" y="62" width="10" height="8" rx="1.8" fill="#1C2A3A"/>
  <rect x="45" y="62" width="10" height="8" rx="1.8" fill="#1C2A3A"/>
  <rect x="58" y="62" width="10" height="8" rx="1.8" fill="#1C2A3A"/>
  <rect x="71" y="62" width="6" height="13" rx="1.8" fill="#1C2A3A"/>
  <circle cx="28" cy="81" r="5" fill="#1C2A3A"/>
  <circle cx="28" cy="81" r="2.2" fill="#F7F2EA"/>
  <circle cx="66" cy="81" r="5" fill="#1C2A3A"/>
  <circle cx="66" cy="81" r="2.2" fill="#F7F2EA"/>
  <path d="M57 9c-6 0-10.5 4.5-10.5 10.5 0 7.5 10.5 17 10.5 17s10.5-9.5 10.5-17C67.5 13.5 63 9 57 9z" fill="#F7F2EA"/>
  <circle cx="57" cy="19.5" r="4" fill="#1C2A3A"/>
</svg>
```

- [ ] **Step 3: Create the render script `tool/brand/render_brand_assets.sh`**

```bash
#!/usr/bin/env bash
# Regenerates every brand PNG from assets/brand/*.svg (spec §3.2).
# Requires ImageMagick 7 (`magick`). Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/../.."

B=assets/brand
I=assets/icon
BLUE='#3E7CB1'
CREAM='#F7F2EA'
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# High density so curves rasterise smoothly before downscaling.
render() { magick -background none -density 1200 "$1" -resize "$2" "$3"; }

# 1. iOS/launcher master: full icon, opaque, 1024.
render "$B/busboard_icon.svg" 1024x1024 "$TMP/icon.png"
magick "$TMP/icon.png" -background "$BLUE" -alpha remove -alpha off "$I/app_icon.png"

# 2. Android adaptive foreground: mark at ~60% of a 1024 transparent canvas
#    (inside the 66% safe zone).
render "$B/busboard_mark.svg" 600x600 "$TMP/mark600.png"
magick -size 1024x1024 xc:none "$TMP/mark600.png" -gravity center -composite "$I/app_icon_foreground.png"

# 3. Splash logo (iOS + pre-12 Android): mark on transparent 768.
render "$B/busboard_mark.svg" 768x768 "$TMP/mark768.png"
magick -size 768x768 xc:none "$TMP/mark768.png" -gravity center -composite "$I/splash_logo.png"

# 4. Android 12 splash: 1152 canvas, content inside the 768 circle.
render "$B/busboard_mark.svg" 560x560 "$TMP/mark560.png"
magick -size 1152x1152 xc:none "$TMP/mark560.png" -gravity center -composite "$I/splash_logo_android12.png"

# 5. Play Store icon 512.
magick "$I/app_icon.png" -resize 512x512 "$I/app_icon_gplay.png"

# 6. Play feature graphic 1024x500: mark left, wordmark right.
render "$B/busboard_mark.svg" 340x340 "$TMP/mark340.png"
magick -size 1024x500 "xc:$BLUE" \
  "$TMP/mark340.png" -gravity west -geometry +80+0 -composite \
  -fill "$CREAM" -gravity west \
  -font assets/fonts/Figtree-ExtraBold.ttf -pointsize 88 -annotate +460-24 'BusBoard NL' \
  -font assets/fonts/Figtree-SemiBold.ttf -pointsize 34 -annotate +464+56 "Live arrivals for St. John's buses" \
  "$I/feature_graph_gplay.png"

magick identify "$I/app_icon.png" "$I/app_icon_foreground.png" "$I/splash_logo.png" \
  "$I/splash_logo_android12.png" "$I/app_icon_gplay.png" "$I/feature_graph_gplay.png"
```

Run:

```bash
chmod +x tool/brand/render_brand_assets.sh
tool/brand/render_brand_assets.sh
```

Expected: six `identify` lines with sizes 1024x1024, 1024x1024, 768x768, 1152x1152, 512x512 and 1024x500.

- [ ] **Step 4: Inspect every PNG by eye**

Open each generated file (Read tool). Check:
- `app_icon.png` matches the approved lilac-house B2 icon, with no transparent corners.
- Both foreground/splash images have a transparent background, and the artwork is centred and uncropped.
- The feature graphic text is Figtree (rounded geometric), cream on blue, and doesn't overlap the mark.

If the pin's curve looks faceted, raise `-density` to 2400 in `render()` and re-run.

- [ ] **Step 5: Point the generators at the new assets in `pubspec.yaml`**

Replace the `flutter_launcher_icons:` and `flutter_native_splash:` sections with:

```yaml
flutter_launcher_icons:
  android: "launcher_icon"
  ios: true
  remove_alpha_ios: true
  image_path: "assets/icon/app_icon.png"
  min_sdk_android: 21
  adaptive_icon_background: "#3E7CB1"
  adaptive_icon_foreground: "assets/icon/app_icon_foreground.png"

flutter_native_splash:
  color: "#3E7CB1"
  image: "assets/icon/splash_logo.png"
  android_12:
    image: "assets/icon/splash_logo_android12.png"
    icon_background_color: "#3E7CB1"
```

- [ ] **Step 6: Regenerate the platform icons and splash; remove the old files**

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
git rm assets/icon/app_icon_nobg.png assets/icon/splash_background.png
grep -rn "splash_background\|app_icon_nobg\|0277BD" ios android pubspec.yaml lib || echo "no stale references"
```

Expected: both generators exit 0; `git status` shows changed files under `ios/Runner/Assets.xcassets/AppIcon.appiconset/`, `ios/Runner/Assets.xcassets/LaunchImage.imageset/`, `android/app/src/main/res/mipmap-*/`, `android/app/src/main/res/drawable*/` and `values*/`; the last command prints `no stale references`. If it lists a stale reference in a generated resource (e.g. an old `background.png` drawable that still uses `splash_background`), re-run `dart run flutter_native_splash:create`, and if it's still there, remove the stale drawable and say so in the commit message.

- [ ] **Step 7: Build both platforms to prove the resources are valid**

```bash
flutter build ios --simulator --debug
flutter build apk --debug
```

Expected: both succeed.

- [ ] **Step 8: Commit**

```bash
git add assets/brand tool/brand assets/icon pubspec.yaml ios/Runner/Assets.xcassets ios/Runner/Base.lproj android/app/src/main/res
git commit -m "feat(brand): new BusBoard icon, adaptive icon, splash and store art

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(If `git status` shows other generated files, e.g. `ios/Runner/Info.plist` from flutter_native_splash, add them by path too.)

---

### Task 13: Phase 1 parity check on the iOS simulator and an Android emulator

**Files:** none (verification only; screenshots go to the scratchpad, not the repo).

**Interfaces:** consumes the whole phase.

- [ ] **Step 1: Run the full suite and the analyzer**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 2: iOS simulator**

Boot a simulator, open the live panel (iOS Simulator `attach`), then:

```bash
xcrun simctl list devices available | grep -m1 "iPhone"
flutter run -d <that simulator id> --debug
```

Check and screenshot:
- the home-screen icon
- the splash (Harbour Blue + mark)
- Board, Map, Alerts and Settings, in light and dark
- a push to Settings and back by edge-swipe
- with the simulator's text size set to the largest accessibility size, Board and Settings

- [ ] **Step 3: Android emulator**

`flutter emulators` lists none on this machine. **Ask the user before downloading** an Android system image (~1–2 GB). With their OK:

```bash
sdkmanager "system-images;android-35;google_apis;arm64-v8a"
avdmanager create avd -n busboard_pixel -k "system-images;android-35;google_apis;arm64-v8a" -d pixel_7
flutter emulators --launch busboard_pixel
flutter run -d emulator-5554 --debug
```

Repeat the Step 2 checks, plus: the adaptive icon on a round mask, and the Android 12 splash. System back pops Settings.

- [ ] **Step 4: Compare and report**

Compare iOS vs Android screenshots for the same screens. Expected Phase 1 result:
- identical colours, font, transitions and scroll bounce on both
- the new icon/splash on both
- screens still use legacy layouts (Material `NavigationBar`, `AppBar`, cards) in the Harbour colours; those are replaced in Phase 2

Report any parity differences other than status bar/safe area to the user, with the screenshot pair. Don't fix screen layouts here; that's Phase 2.
