# Harbour Phase 3a — Kit Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the last "made by Flutter / Android" details from the shared kit. That means Phosphor icons and our own glyphs, route-dot pull-to-refresh and loading, skeleton placeholders, a floating-card sheet, a toast that knows where the nav bar is, and the map's chip and control-pill pieces.

**Architecture:** Every change lives in `lib/ui/kit/`, so all screens pick it up at once.
- Screen code changes only where the kit's public API changes:
  - nav items gain an `activeIcon`;
  - Board, Alerts and Near me use the new skeleton;
  - the board and alerts status dots use the new glyph.
- New widgets are built from widgets-layer primitives only. No Material widgets appear, so `RefreshIndicator` and `CircularProgressIndicator` leave the kit.

**Tech Stack:** Flutter 3.47.5 / Dart ^3.11, Riverpod 3, go_router 17, `phosphor_flutter` 2.1.0 (MIT), and flutter_test goldens.

**Spec:** [docs/superpowers/specs/2026-10-04-harbour-phase3-design.md](../specs/2026-10-04-harbour-phase3-design.md) §2 (Phase 3a). Parent spec: [2026-10-04-harbour-redesign-design.md](../specs/2026-10-04-harbour-redesign-design.md).

## Global Constraints

**Kit and design**
- Material/Cupertino widgets may be used only inside `lib/ui/kit/`, as plumbing. Screen code uses kit widgets only, and `test/kit/kit_boundary_test.dart` enforces this.
- After this plan, no file under `lib/ui/kit/` references Material's `Icons.` glyph set.
- Colours come only from `context.bb.colors` (`BBColors`) or `RouteHue`/`RoutePalette`. Never write raw hex in widgets.
- Spacing comes from `BBSpace`, radii from `BBRadius`, and durations from `BBMotion`.
- Every animation goes through `BBMotion.of(context, d)`, which returns zero under Reduce Motion.
- `DraggableScrollableSheet` rejects `Duration.zero`, so use 1 ms instead.
- Tap targets are at least 44 × 44 pt. Every interactive widget has a semantics label.

**Testing**
- Use `isSemantics(...)` for semantics assertions, never `containsSemantics`/`matchesSemantics`.
- Call `tester.ensureSemantics()` and finish with `handle.dispose()` at the end of the test body (not `addTearDown`).
- `kitHost(...)` (in `test/kit/kit_test_helpers.dart`) forces a tight width (390 by default) and has no Material ancestor. Wrap a widget in `Center` when its own size matters.
- Goldens load real fonts with `setUpAll(loadAppFonts)`.
  - Regenerate with `flutter test --update-goldens <files>`.
  - Then open every changed PNG and describe it in the task report.

**Before every commit**
- `flutter analyze lib test` prints "No issues found!".
- The full `flutter test` passes, including goldens.

**Commits**
- Stage only the files your task lists.
- Never stage `analysis_options.yaml`, `ios/Podfile`, `ios/Podfile.lock`, `ios/Runner.xcodeproj/project.pbxproj` or `tool/capture_raw_gtfsrt.dart`; they hold unrelated local changes.
- `pubspec.lock` is staged only by Task 1. It then also carries the SDK-pinned `matcher` 0.12.20 / `meta` 1.19.0 bumps that are already in the working tree. That's deliberate: they come from the installed Flutter SDK.
- End every commit message with the Co-Authored-By trailer of your own model.

**Behaviour changes this plan introduces** (reviewers: these are intended)
1. Every icon glyph changes from Material Rounded to Phosphor. The active nav tab uses Phosphor's fill weight.
2. Pull-to-refresh shows route dots instead of the Material circle. While refreshing, a small floating pill of hopping dots appears at the top of the list.
3. Screen readers get a "Refresh" action on refreshable lists, and hear "Refreshing" then "Updated".
4. The spinner in `BBLoading` becomes hopping route dots.
5. On the Board, Alerts and Near me first loads, placeholder rows replace the spinner and its visible "Loading…" text. The text stays as the screen-reader label.
6. The live and service-status dots on the Board and Alerts become the `liveDot` glyph.
7. `BBSheet` becomes an inset floating card. It has a white surface, radius 24 on every corner, an optional pinned header and screen-reader detent actions.
8. On screens without the nav bar, such as Settings, toasts sit just above the bottom safe area instead of a bar's height above it.

## Review Focus

1. **Screen-reader users can't pull.** The "Refresh" custom action must run `onRefresh` exactly once and announce "Refreshing" then "Updated". (Task 4 test: "screen readers can refresh with the Refresh action".)
2. **`onRefresh` throws, or a second pull arrives mid-refresh.** It must not run twice, the dots must stop, the error is reported once, and the next pull works. (Task 4 tests: "a pull during a refresh does not start another", "a failing refresh ends the indicator and reports once".)
3. **Reduce Motion is on.** The dots stay still with no ticker running, and `animateToDetent` still lands on the detent. (Task 3: "reduce motion shows still, filled dots and runs no animation"; Task 6: "animateToDetent works with reduce motion".)
4. **Text at ×2.0 on a 320 pt screen.** A chip with a long stop name ellipsizes without overflow, and the control pill keeps 44 pt targets. (Task 8: "a long chip label ellipsizes at 2x text on 320 pt", "control pill buttons are 44 pt".)
5. **A hard swipe down on a sheet.** A non-dismissible sheet stays at peek. A dismissible one calls `onDismiss` exactly once. (Task 6: "non-dismissible sheet stays at peek when swiped down", "dismissible sheet closes once when swiped down from peek".)

---

### Task 1: Phosphor icons and fill-weight active tabs

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock` (add `phosphor_flutter: ^2.1.0`)
- Modify: `lib/ui/kit/bb_icons.dart` (whole file)
- Modify: `lib/ui/kit/bb_nav_bar.dart` (`BBNavItem` + `_Tab`)
- Modify: `lib/ui/shell/app_shell.dart` (nav items)
- Create: `test/kit/icons_test.dart`
- Modify: `test/kit/nav_bar_test.dart` (one new test)
- Regenerate: `test/kit/goldens/*.png`, `test/ui/goldens/*.png`

**Interfaces:**
- Produces:
  - `BBIcons.<name>`: every existing name is kept, now with Phosphor glyphs.
  - New fill constants: `BBIcons.boardFill`, `BBIcons.mapFill`, `BBIcons.alertsFill`.
  - `BBNavItem({required String label, required IconData icon, IconData? activeIcon, int badgeCount = 0})`.

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add phosphor_flutter:^2.1.0`
Expected: `pubspec.yaml` gains `phosphor_flutter: ^2.1.0` under `dependencies`, and `flutter pub get` succeeds.

- [ ] **Step 2: Write the failing tests**

Create `test/kit/icons_test.dart`:

```dart
import 'dart:io';

import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _all = <IconData>[
  BBIcons.board, BBIcons.boardFill, BBIcons.map, BBIcons.mapFill, BBIcons.alerts, BBIcons.alertsFill,
  BBIcons.settings, BBIcons.search, BBIcons.location, BBIcons.nearMe, BBIcons.chevronRight,
  BBIcons.chevronDown, BBIcons.close, BBIcons.check, BBIcons.refresh, BBIcons.bus, BBIcons.stop,
  BBIcons.filter, BBIcons.info, BBIcons.warning, BBIcons.noService, BBIcons.schedule, BBIcons.star,
  BBIcons.starOutline, BBIcons.theme, BBIcons.offline, BBIcons.error, BBIcons.back, BBIcons.history,
  BBIcons.update, BBIcons.pin, BBIcons.timer, BBIcons.download, BBIcons.palette, BBIcons.detour,
  BBIcons.reducedService, BBIcons.stopMoved, BBIcons.accessible, BBIcons.additionalService,
  BBIcons.checkCircle, BBIcons.locationOff, BBIcons.layers, BBIcons.add, BBIcons.remove,
];

void main() {
  test('every BBIcons glyph comes from Phosphor', () {
    for (final icon in _all) {
      expect(icon.fontPackage, 'phosphor_flutter', reason: 'codePoint ${icon.codePoint}');
    }
  });

  test('regular weight by default, fill weight for active states', () {
    expect(BBIcons.board.fontFamily, 'PhosphorRegular');
    expect(BBIcons.boardFill.fontFamily, 'PhosphorFill');
    expect(BBIcons.mapFill.fontFamily, 'PhosphorFill');
    expect(BBIcons.alertsFill.fontFamily, 'PhosphorFill');
    expect(BBIcons.star.fontFamily, 'PhosphorFill');
    expect(BBIcons.starOutline.fontFamily, 'PhosphorRegular');
  });

  test('no two BBIcons names share a glyph (except fill/regular pairs)', () {
    final regular = _all.where((i) => i.fontFamily == 'PhosphorRegular').map((i) => i.codePoint).toList();
    expect(regular.toSet().length, regular.length);
  });

  test('the kit no longer uses Material icon glyphs', () {
    final materialIcons = RegExp(r'(?<![A-Za-z_])Icons\.');
    final offenders = <String>[];
    for (final f in Directory('lib/ui/kit').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (materialIcons.hasMatch(src) || src.contains('show Icons')) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });
}
```

(The regular and fill weights share code points by design; the font family is what tells them apart.)

Append to `test/kit/nav_bar_test.dart`, inside `main()`:

```dart
  testWidgets('the active tab shows its fill icon, the others their regular icon', (tester) async {
    await tester.pumpWidget(kitHost(BBNavBar(
      items: const [
        BBNavItem(label: 'Board', icon: BBIcons.board, activeIcon: BBIcons.boardFill),
        BBNavItem(label: 'Map', icon: BBIcons.map, activeIcon: BBIcons.mapFill),
      ],
      currentIndex: 0,
      onSelect: (_) {},
    )));
    expect(find.byIcon(BBIcons.boardFill), findsOneWidget);
    expect(find.byIcon(BBIcons.board), findsNothing);
    expect(find.byIcon(BBIcons.map), findsOneWidget);
    expect(find.byIcon(BBIcons.mapFill), findsNothing);
  });
```

- [ ] **Step 3: Run the tests and watch them fail**

Run: `flutter test test/kit/icons_test.dart test/kit/nav_bar_test.dart`
Expected:
- compile errors for `BBIcons.boardFill` / `activeIcon`;
- after a stub, failures on `fontPackage` (it's null for Material).

- [ ] **Step 4: Replace `lib/ui/kit/bb_icons.dart`**

```dart
import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// The app's single icon vocabulary: Phosphor (MIT), the same on iOS and
/// Android. Screens use these names, never a glyph set directly. Regular
/// weight by default; the `*Fill` names (and [star]) mark active or selected
/// states.
abstract final class BBIcons {
  static const IconData board = PhosphorIconsRegular.clockCountdown;
  static const IconData boardFill = PhosphorIconsFill.clockCountdown;
  static const IconData map = PhosphorIconsRegular.mapTrifold;
  static const IconData mapFill = PhosphorIconsFill.mapTrifold;
  static const IconData alerts = PhosphorIconsRegular.megaphone;
  static const IconData alertsFill = PhosphorIconsFill.megaphone;
  static const IconData settings = PhosphorIconsRegular.gearSix;
  static const IconData search = PhosphorIconsRegular.magnifyingGlass;
  static const IconData location = PhosphorIconsRegular.crosshair;
  static const IconData nearMe = PhosphorIconsRegular.navigationArrow;
  static const IconData chevronRight = PhosphorIconsRegular.caretRight;
  static const IconData chevronDown = PhosphorIconsRegular.caretDown;
  static const IconData close = PhosphorIconsRegular.x;
  static const IconData check = PhosphorIconsRegular.check;
  static const IconData refresh = PhosphorIconsRegular.arrowClockwise;
  static const IconData bus = PhosphorIconsRegular.bus;
  static const IconData stop = PhosphorIconsRegular.mapPin;
  static const IconData filter = PhosphorIconsRegular.funnel;
  static const IconData info = PhosphorIconsRegular.info;
  static const IconData warning = PhosphorIconsRegular.warning;
  static const IconData noService = PhosphorIconsRegular.prohibit;
  static const IconData schedule = PhosphorIconsRegular.clock;
  static const IconData star = PhosphorIconsFill.star;
  static const IconData starOutline = PhosphorIconsRegular.star;
  static const IconData theme = PhosphorIconsRegular.circleHalf;
  static const IconData offline = PhosphorIconsRegular.cloudSlash;
  static const IconData error = PhosphorIconsRegular.warningCircle;
  static const IconData back = PhosphorIconsRegular.arrowLeft;
  static const IconData history = PhosphorIconsRegular.clockCounterClockwise;
  static const IconData update = PhosphorIconsRegular.arrowsClockwise;
  static const IconData pin = PhosphorIconsRegular.mapPinLine;
  static const IconData timer = PhosphorIconsRegular.timer;
  static const IconData download = PhosphorIconsRegular.cloudArrowDown;
  static const IconData palette = PhosphorIconsRegular.palette;
  static const IconData detour = PhosphorIconsRegular.arrowsSplit;
  static const IconData reducedService = PhosphorIconsRegular.minusCircle;
  static const IconData stopMoved = PhosphorIconsRegular.signpost;
  static const IconData accessible = PhosphorIconsRegular.wheelchair;
  static const IconData additionalService = PhosphorIconsRegular.plusCircle;
  static const IconData checkCircle = PhosphorIconsRegular.checkCircle;
  static const IconData locationOff = PhosphorIconsRegular.gpsSlash;
  static const IconData layers = PhosphorIconsRegular.stack;
  static const IconData add = PhosphorIconsRegular.plus;
  static const IconData remove = PhosphorIconsRegular.minus;
}
```

- [ ] **Step 5: Give nav items an active icon**

In `lib/ui/kit/bb_nav_bar.dart`, replace `BBNavItem`:

```dart
class BBNavItem {
  const BBNavItem({required this.label, required this.icon, this.activeIcon, this.badgeCount = 0});
  final String label;
  final IconData icon;

  /// Shown while the tab is selected (the fill weight); defaults to [icon].
  final IconData? activeIcon;
  final int badgeCount;
}
```

In `_Tab.build`, replace `Icon(item.icon, size: 18, color: fg),` with:

```dart
                Icon(selected ? (item.activeIcon ?? item.icon) : item.icon, size: 18, color: fg),
```

In `lib/ui/shell/app_shell.dart`, replace the `items:` list with:

```dart
              items: [
                const BBNavItem(label: 'Board', icon: BBIcons.board, activeIcon: BBIcons.boardFill),
                const BBNavItem(label: 'Map', icon: BBIcons.map, activeIcon: BBIcons.mapFill),
                BBNavItem(
                  label: 'Alerts',
                  icon: BBIcons.alerts,
                  activeIcon: BBIcons.alertsFill,
                  badgeCount: activeAlertCount,
                ),
              ],
```

- [ ] **Step 6: Run the tests and watch them pass**

Run: `flutter test test/kit/icons_test.dart test/kit/nav_bar_test.dart test/kit/kit_extensions_test.dart test/kit/kit_boundary_test.dart`
Expected: PASS.

- [ ] **Step 7: Regenerate and inspect the goldens**

Run: `flutter test --update-goldens test/kit/kit_golden_test.dart test/ui/screen_golden_test.dart`
Then open every PNG under `test/kit/goldens/` and `test/ui/goldens/`. Confirm:
- every icon is a Phosphor glyph (no Material shapes);
- the active Board tab icon is filled;
- nothing is clipped at ×2.0.

Note what you saw in the report.

- [ ] **Step 8: Run analyze and the full suite**

Run: `flutter analyze lib test && flutter test`
Expected: "No issues found!" and "All tests passed!".

- [ ] **Step 9: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/ui/kit/bb_icons.dart lib/ui/kit/bb_nav_bar.dart lib/ui/shell/app_shell.dart test/kit/icons_test.dart test/kit/nav_bar_test.dart test/kit/goldens test/ui/goldens
git commit -m "feat(kit): Phosphor icons, fill weight for the active tab"
```

---

### Task 2: BusBoard glyphs (bus, stop pole, live dot)

**Files:**
- Create: `lib/ui/kit/glyphs/bb_glyph.dart`
- Modify: `lib/ui/kit/kit.dart` (export)
- Modify: `lib/ui/board/arrival_board_screen.dart:240-247` (status dot)
- Modify: `lib/ui/alerts/alerts_screen.dart:148-152` (service-status dot)
- Modify: `test/kit/kit_golden_test.dart` (glyph row)
- Create: `test/kit/glyph_test.dart`
- Regenerate: `test/kit/goldens/*.png`, `test/ui/goldens/*.png`

**Interfaces:**
- Produces:
  - `enum BBGlyphKind { bus, stopPole, liveDot }`
  - `BBGlyph(BBGlyphKind kind, {Key? key, double size = 24, required Color color, String? semanticLabel})`

- [ ] **Step 1: Write the failing test**

Create `test/kit/glyph_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

void main() {
  testWidgets('a glyph renders at the requested size', (tester) async {
    await tester.pumpWidget(kitHost(const Center(
      child: BBGlyph(BBGlyphKind.bus, size: 20, color: Color(0xFF1C2A3A)),
    )));
    expect(tester.getSize(find.byType(BBGlyph)), const Size(20, 20));
  });

  testWidgets('unlabelled glyphs are hidden from screen readers; labelled ones are images', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(const Column(children: [
      BBGlyph(BBGlyphKind.liveDot, color: Color(0xFF2E9E62)),
      BBGlyph(BBGlyphKind.stopPole, color: Color(0xFF1C2A3A), semanticLabel: 'Stop'),
    ])));
    expect(find.semantics.byLabel('Stop'), findsOneWidget);
    expect(tester.getSemantics(find.byType(BBGlyph).last), isSemantics(label: 'Stop', isImage: true));
    expect(
      find.semantics.byPredicate((n) => n.label.isEmpty && n.flagsCollection.isImage),
      findsNothing,
    );
    handle.dispose();
  });

  testWidgets('every kind paints without errors in both themes', (tester) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(kitHost(
        Row(children: [for (final k in BBGlyphKind.values) BBGlyph(k, color: const Color(0xFF3E7CB1))]),
        brightness: b,
      ));
      expect(tester.takeException(), isNull);
    }
  });
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `flutter test test/kit/glyph_test.dart`
Expected: compile error, "BBGlyph isn't defined".

- [ ] **Step 3: Create `lib/ui/kit/glyphs/bb_glyph.dart`**

```dart
import 'package:flutter/widgets.dart';

enum BBGlyphKind { bus, stopPole, liveDot }

/// BusBoard's own glyphs, drawn in the B2 logo's soft style on a 24×24 grid.
/// Used like an icon (a size and a colour); the caller supplies the label,
/// and an unlabelled glyph is decorative.
class BBGlyph extends StatelessWidget {
  const BBGlyph(this.kind, {super.key, this.size = 24, required this.color, this.semanticLabel});

  final BBGlyphKind kind;
  final double size;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final glyph = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GlyphPainter(kind, color)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: glyph);
    return Semantics(label: semanticLabel, image: true, child: glyph);
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind, this.color);

  final BBGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    switch (kind) {
      case BBGlyphKind.bus:
        _bus(canvas, fill);
      case BBGlyphKind.stopPole:
        _stopPole(canvas, fill);
      case BBGlyphKind.liveDot:
        _liveDot(canvas, fill);
    }
  }

  // Front view: rounded body with a windshield cut out (even-odd keeps the
  // glyph one colour on any background), two wheels below.
  void _bus(Canvas canvas, Paint fill) {
    final body = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(RRect.fromLTRBR(4, 3, 20, 18.5, const Radius.circular(3.5)))
      ..addRRect(RRect.fromLTRBR(6, 5.5, 18, 11, const Radius.circular(1.5)));
    canvas.drawPath(body, fill);
    canvas.drawRRect(RRect.fromLTRBR(5.5, 17.5, 8.5, 21, const Radius.circular(1.2)), fill);
    canvas.drawRRect(RRect.fromLTRBR(15.5, 17.5, 18.5, 21, const Radius.circular(1.2)), fill);
  }

  // A stop sign on a pole, as riders see it on the street.
  void _stopPole(Canvas canvas, Paint fill) {
    final sign = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(RRect.fromLTRBR(6, 2, 18, 11, const Radius.circular(2.5)))
      ..addRRect(RRect.fromLTRBR(9, 4.5, 15, 8.5, const Radius.circular(1)));
    canvas.drawPath(sign, fill);
    canvas.drawRRect(RRect.fromLTRBR(11, 11, 13, 21, const Radius.circular(1)), fill);
    canvas.drawRRect(RRect.fromLTRBR(8, 20, 16, 22, const Radius.circular(1)), fill);
  }

  // A solid dot inside a soft ring; never animated.
  void _liveDot(Canvas canvas, Paint fill) {
    canvas.drawCircle(const Offset(12, 12), 10, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(const Offset(12, 12), 5.5, fill);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind || old.color != color;
}
```

Add to `lib/ui/kit/kit.dart`, after `export 'bb_divider.dart';`:

```dart
export 'glyphs/bb_glyph.dart';
```

- [ ] **Step 4: Use the live dot in the Board and Alerts status lines**

In `lib/ui/board/arrival_board_screen.dart`, replace the 7×7 `Container(... shape: BoxShape.circle ...)` in the status row with:

```dart
              BBGlyph(BBGlyphKind.liveDot, size: 12, color: _liveAvailable ? bb.colors.live : bb.colors.muted),
```

In `lib/ui/alerts/alerts_screen.dart`, replace the 10×10 `Container(... shape: BoxShape.circle ...)` in the service-status card with:

```dart
        BBGlyph(BBGlyphKind.liveDot, size: 14, color: stopped ? bb.colors.dangerInk : bb.colors.live),
```

- [ ] **Step 5: Add a glyph row to the kit gallery**

In `test/kit/kit_golden_test.dart`, inside `_Gallery.build`'s column, right after the `BBTextField(...)` line and its following `SizedBox`, insert:

```dart
            Row(
              children: [
                for (final kind in BBGlyphKind.values) ...[
                  BBGlyph(kind, color: bb.colors.ink),
                  const SizedBox(width: BBSpace.m),
                ],
                BBGlyph(BBGlyphKind.liveDot, color: bb.colors.live),
              ],
            ),
            const SizedBox(height: BBSpace.m),
```

If the gallery grows past the view, raise the heights in `tester.view.physicalSize` (`1100` / `1800`) until `tester.getSize(find.byType(_Gallery)).height` fits. Add `expect(tester.getSize(find.byType(_Gallery)).height, lessThanOrEqualTo(scale == 1.0 ? 1100 : 1800));` before the golden assertion so a too-small view fails loudly.

- [ ] **Step 6: Run the tests and watch them pass**

Run: `flutter test test/kit/glyph_test.dart test/ui/arrival_board_screen_test.dart test/ui/alerts_test.dart`
Expected: PASS.

- [ ] **Step 7: Regenerate and inspect the goldens, then analyze and run the full suite**

Run:
- `flutter test --update-goldens test/kit/kit_golden_test.dart test/ui/screen_golden_test.dart`
- then `flutter analyze lib test && flutter test`

Inspect:
- the glyph row (bus, stop pole, live dot) in light and dark;
- the board and alerts status dots, which are now dot-in-ring.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/kit/glyphs/bb_glyph.dart lib/ui/kit/kit.dart lib/ui/board/arrival_board_screen.dart lib/ui/alerts/alerts_screen.dart test/kit/glyph_test.dart test/kit/kit_golden_test.dart test/kit/goldens test/ui/goldens
git commit -m "feat(kit): BusBoard glyphs (bus, stop pole, live dot)"
```

---

### Task 3: Route dots, and `BBLoading` without Material

**Files:**
- Create: `lib/ui/kit/bb_route_dots.dart`
- Modify: `lib/ui/kit/bb_loading.dart` (whole file)
- Modify: `lib/ui/kit/kit.dart` (export)
- Create: `test/kit/route_dots_test.dart`
- Regenerate: goldens if any screen shows `BBLoading` (the stop picker's first-load state)

**Interfaces:**
- Produces:
  - `BBRouteDots({Key? key, double? progress, double dotSize = 10})`. With `progress` null the dots hop. With 0..1 they grow in turn.
  - Each dot is `Transform(key: ValueKey('bb-route-dot-$i'))`.
  - `BBLoading({Key? key, String? label})` keeps its API.

- [ ] **Step 1: Write the failing tests**

Create `test/kit/route_dots_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

Matrix4 _dot(WidgetTester tester, int i) =>
    tester.widget<Transform>(find.byKey(ValueKey('bb-route-dot-$i'))).transform;

double _scale(WidgetTester tester, int i) => _dot(tester, i).getMaxScaleOnAxis();

void main() {
  testWidgets('pull progress grows the dots in turn', (tester) async {
    await tester.pumpWidget(kitHost(const Center(child: BBRouteDots(progress: 0))));
    for (var i = 0; i < 3; i++) {
      expect(_scale(tester, i), closeTo(0.4, 0.001));
    }

    await tester.pumpWidget(kitHost(const Center(child: BBRouteDots(progress: 0.5))));
    expect(_scale(tester, 0), closeTo(1.0, 0.001));
    expect(_scale(tester, 1), closeTo(0.7, 0.001));
    expect(_scale(tester, 2), closeTo(0.4, 0.001));

    await tester.pumpWidget(kitHost(const Center(child: BBRouteDots(progress: 1))));
    for (var i = 0; i < 3; i++) {
      expect(_scale(tester, i), closeTo(1.0, 0.001));
    }
  });

  testWidgets('without progress the dots hop', (tester) async {
    await tester.pumpWidget(kitHost(const Center(child: BBRouteDots())));
    final before = _dot(tester, 0).clone();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_dot(tester, 0), isNot(equals(before)));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('reduce motion shows still, filled dots and runs no animation', (tester) async {
    await tester.pumpWidget(kitHost(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Center(child: BBRouteDots()),
    )));
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 3; i++) {
      expect(_scale(tester, i), closeTo(1.0, 0.001));
      expect(_dot(tester, i).getTranslation().y, 0);
    }
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('BBLoading no longer uses a Material spinner', (tester) async {
    await tester.pumpWidget(kitHost(const BBLoading(label: 'Loading schedule data...')));
    expect(find.byType(BBRouteDots), findsOneWidget);
    expect(find.text('Loading schedule data...'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `flutter test test/kit/route_dots_test.dart`
Expected: compile error, "BBRouteDots isn't defined".

- [ ] **Step 3: Create `lib/ui/kit/bb_route_dots.dart`**

```dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'route_palette.dart';
import 'tokens.dart';

/// BusBoard's progress mark: three dots in route colours. With [progress]
/// (0..1) they grow in turn, as while pulling to refresh; with no progress
/// they hop in sequence. Reduce motion shows them filled and still.
/// Decorative: callers carry the meaning in their own semantics.
class BBRouteDots extends StatefulWidget {
  const BBRouteDots({super.key, this.progress, this.dotSize = 10});

  final double? progress;
  final double dotSize;

  static const List<RouteHue> hues = [RouteHue.red, RouteHue.yellow, RouteHue.green];

  @override
  State<BBRouteDots> createState() => _BBRouteDotsState();
}

class _BBRouteDotsState extends State<BBRouteDots> with SingleTickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = BBMotion.of(context, BBMotion.standard) == Duration.zero;
    _syncTicker();
  }

  @override
  void didUpdateWidget(BBRouteDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final shouldHop = widget.progress == null && !_reduceMotion;
    if (shouldHop && !_hop.isAnimating) {
      _hop.repeat();
    } else if (!shouldHop && _hop.isAnimating) {
      _hop.stop();
    }
  }

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  Matrix4 _transformFor(int i) {
    final progress = widget.progress;
    if (progress != null) {
      final f = (progress.clamp(0.0, 1.0) * 3 - i).clamp(0.0, 1.0);
      final s = 0.4 + 0.6 * f;
      return Matrix4.diagonal3Values(s, s, 1);
    }
    if (_reduceMotion) return Matrix4.identity();
    // Each dot rises during the first 40% of its own phase, 130 ms apart.
    final t = (_hop.value - i * 0.13) % 1.0;
    final rise = t < 0.4 ? math.sin(t / 0.4 * math.pi) : 0.0;
    return Matrix4.translationValues(0, -rise * widget.dotSize * 0.7, 0);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = context.bb.brightness;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _hop,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.dotSize * 0.3),
                child: Transform(
                  key: ValueKey('bb-route-dot-$i'),
                  alignment: Alignment.center,
                  transform: _transformFor(i),
                  child: Opacity(
                    opacity: widget.progress == null
                        ? 1
                        : 0.35 + 0.65 * (widget.progress!.clamp(0.0, 1.0) * 3 - i).clamp(0.0, 1.0),
                    child: Container(
                      width: widget.dotSize,
                      height: widget.dotSize,
                      decoration: BoxDecoration(
                        color: brightness == Brightness.dark ? BBRouteDots.hues[i].fillDark : BBRouteDots.hues[i].line,
                        shape: BoxShape.circle,
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

- [ ] **Step 4: Replace `lib/ui/kit/bb_loading.dart`**

```dart
import 'package:flutter/widgets.dart';

import 'bb_route_dots.dart';
import 'tokens.dart';

/// Hopping route dots with an optional label, announced to screen readers.
/// For short inline waits; first loads of lists use [BBSkeleton].
class BBLoading extends StatelessWidget {
  const BBLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Semantics(
      label: label ?? 'Loading',
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BBRouteDots(),
          if (label != null) ...[
            const SizedBox(height: BBSpace.m),
            ExcludeSemantics(
              child: Text(label!, textAlign: TextAlign.center, style: bb.text.body.copyWith(color: bb.colors.muted)),
            ),
          ],
        ],
      ),
    );
  }
}
```

Add to `lib/ui/kit/kit.dart`, after `export 'bb_refresh.dart';`:

```dart
export 'bb_route_dots.dart';
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `flutter test test/kit/route_dots_test.dart test/kit/screen_kit_test.dart test/ui/stop_picker_test.dart`
Expected: PASS. ("BBLoading announces its label" still passes unchanged.)

- [ ] **Step 6: Regenerate goldens if they changed, then analyze and run the full suite**

Run `flutter analyze lib test && flutter test`. If a golden fails only because a spinner became dots, regenerate that file with `--update-goldens` and inspect it.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/kit/bb_route_dots.dart lib/ui/kit/bb_loading.dart lib/ui/kit/kit.dart test/kit/route_dots_test.dart test/kit/goldens test/ui/goldens
git commit -m "feat(kit): route-dot progress mark; BBLoading without Material"
```

---

### Task 4: `BBRefresh` with route dots (no `RefreshIndicator`)

**Files:**
- Modify: `lib/ui/kit/bb_refresh.dart` (whole file)
- Modify: `test/kit/feedback_components_test.dart` (add tests next to "pull to refresh calls onRefresh")

**Interfaces:**
- Consumes: `BBRouteDots` (Task 3).
- Produces:
  - `BBRefresh({Key? key, required Future<void> Function() onRefresh, required Widget child})`, with an unchanged API;
  - `BBRefresh.triggerDistance` (72);
  - `BBRefresh.refreshAction` (`CustomSemanticsAction(label: 'Refresh')`).

- [ ] **Step 1: Write the failing tests**

Add to `test/kit/feedback_components_test.dart`, after the existing "pull to refresh calls onRefresh" test (add `import 'dart:async';` and `import 'package:flutter/services.dart';` at the top if missing):

```dart
  Widget refreshHost(Future<void> Function() onRefresh) => kitHost(SizedBox(
        height: 600,
        child: BBRefresh(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [SizedBox(height: 100, child: Text('row'))],
          ),
        ),
      ));

  testWidgets('pulling past the trigger ticks once, and a short pull does not refresh', (tester) async {
    var ticks = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') ticks++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    var refreshed = 0;
    await tester.pumpWidget(refreshHost(() async => refreshed++));

    await tester.drag(find.text('row'), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(refreshed, 0);
    expect(ticks, 0);

    await tester.fling(find.text('row'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(refreshed, 1);
    expect(ticks, 1);
  });

  testWidgets('screen readers can refresh with the Refresh action', (tester) async {
    final handle = tester.ensureSemantics();
    final done = Completer<void>();
    var refreshed = 0;
    await tester.pumpWidget(refreshHost(() {
      refreshed++;
      return done.future;
    }));
    final id = CustomSemanticsAction.getIdentifier(BBRefresh.refreshAction);
    tester.semantics.customAction(
      find.semantics.byPredicate((n) => n.getSemanticsData().customSemanticsActionIds?.contains(id) ?? false),
      BBRefresh.refreshAction,
    );
    await tester.pump();
    expect(refreshed, 1);
    expect(find.semantics.byPredicate((n) => n.flagsCollection.isLiveRegion && n.label == 'Refreshing'), findsOneWidget);
    done.complete();
    await tester.pump();
    expect(find.semantics.byPredicate((n) => n.flagsCollection.isLiveRegion && n.label == 'Updated'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    handle.dispose();
  });

  testWidgets('a pull during a refresh does not start another', (tester) async {
    final done = Completer<void>();
    var refreshed = 0;
    await tester.pumpWidget(refreshHost(() {
      refreshed++;
      return done.future;
    }));
    // The hopping dots loop while refreshing, so pump fixed durations here:
    // pumpAndSettle would never settle.
    await tester.fling(find.text('row'), const Offset(0, 300), 1000);
    await tester.pump(const Duration(seconds: 1));
    await tester.fling(find.text('row'), const Offset(0, 300), 1000);
    await tester.pump(const Duration(seconds: 1));
    expect(refreshed, 1);
    expect(find.byType(BBRouteDots), findsOneWidget);
    done.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(BBRouteDots), findsNothing);
  });

  testWidgets('a failing refresh ends the indicator and reports once', (tester) async {
    var calls = 0;
    await tester.pumpWidget(refreshHost(() async {
      calls++;
      throw StateError('offline');
    }));
    await tester.fling(find.text('row'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(find.byType(BBRouteDots), findsNothing);

    await tester.fling(find.text('row'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(calls, 2);
  });
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `flutter test test/kit/feedback_components_test.dart`
Expected: compile errors for `BBRefresh.refreshAction` (and `BBRouteDots` isn't found in the refresh tree).

- [ ] **Step 3: Replace `lib/ui/kit/bb_refresh.dart`**

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'bb_route_dots.dart';
import 'tokens.dart';

/// Pull to refresh with BusBoard's route dots (replaces Material's
/// RefreshIndicator). Pull past [triggerDistance] (one haptic tick) and
/// release: [onRefresh] runs while the dots hop in a small floating pill.
/// Screen readers get a [refreshAction] on the list and hear "Refreshing",
/// then "Updated". The child must overscroll at the top: the app's bouncing
/// scroll behaviour with AlwaysScrollableScrollPhysics.
class BBRefresh extends StatefulWidget {
  const BBRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  static const double triggerDistance = 72;
  static const CustomSemanticsAction refreshAction = CustomSemanticsAction(label: 'Refresh');

  @override
  State<BBRefresh> createState() => _BBRefreshState();
}

class _BBRefreshState extends State<BBRefresh> {
  double _pull = 0;
  bool _armed = false;
  bool _refreshing = false;
  String _announcement = '';
  Timer? _clearAnnouncement;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final overscroll = (n.metrics.minScrollExtent - n.metrics.pixels).clamp(0.0, double.infinity);
    final dragging = (n is ScrollUpdateNotification && n.dragDetails != null) ||
        (n is OverscrollNotification && n.dragDetails != null);
    if (!_refreshing) {
      if (dragging) {
        if (!_armed && overscroll >= BBRefresh.triggerDistance) {
          _armed = true;
          HapticFeedback.selectionClick();
        } else if (_armed && overscroll < BBRefresh.triggerDistance) {
          _armed = false; // Pulled back above the line: cancelled.
        }
      } else if (_armed && (n is ScrollUpdateNotification || n is ScrollEndNotification)) {
        _armed = false; // Released past the line.
        unawaited(_refresh());
      }
    }
    if (overscroll != _pull) setState(() => _pull = overscroll);
    return false;
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _clearAnnouncement?.cancel();
    setState(() {
      _refreshing = true;
      _announcement = 'Refreshing';
    });
    try {
      await widget.onRefresh();
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'BBRefresh'));
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _announcement = 'Updated';
        });
        _clearAnnouncement = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _announcement = '');
        });
      }
    }
  }

  @override
  void dispose() {
    _clearAnnouncement?.cancel();
    super.dispose();
  }

  Widget _indicator(BuildContext context) {
    final bb = context.bb;
    if (_refreshing) {
      return Padding(
        padding: const EdgeInsets.only(top: BBSpace.s),
        child: Center(
          child: DecoratedBox(
            decoration: bb.floating(radius: BBRadius.sheet),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: BBSpace.s),
              child: BBRouteDots(dotSize: 8),
            ),
          ),
        ),
      );
    }
    if (_pull <= 0) return const SizedBox.shrink();
    return SizedBox(
      height: _pull,
      child: Center(child: BBRouteDots(progress: _pull / BBRefresh.triggerDistance, dotSize: 8)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      customSemanticsActions: {BBRefresh.refreshAction: () => unawaited(_refresh())},
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
          Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(child: _indicator(context))),
          Positioned(
            top: 0,
            left: 0,
            // 1×1, not zero-size: zero-area nodes can be dropped from the tree.
            child: Semantics(liveRegion: true, label: _announcement, child: const SizedBox(width: 1, height: 1)),
          ),
        ],
      ),
    );
  }
}
```

If `flutter analyze` flags `package:flutter/semantics.dart` as unnecessary (`CustomSemanticsAction` is also exported by `widgets.dart`), remove that import.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `flutter test test/kit/feedback_components_test.dart test/ui/arrival_board_screen_test.dart test/ui/alerts_test.dart`
Expected: PASS. The existing "pull to refresh calls onRefresh", "loading state is pull-to-refresh-able" and board refresh tests pass unchanged.

- [ ] **Step 5: Run analyze and the full suite (regenerate goldens only if a refresh state is captured)**

Run: `flutter analyze lib test && flutter test`
Expected: "No issues found!" and "All tests passed!". `RefreshIndicator` no longer appears anywhere in `lib/ui/kit/` (check with `grep -rn RefreshIndicator lib`, which should print nothing).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/kit/bb_refresh.dart test/kit/feedback_components_test.dart
git commit -m "feat(kit): route-dot pull to refresh with a screen-reader action"
```

---

### Task 5: `BBSkeleton` placeholder rows for first loads

**Files:**
- Create: `lib/ui/kit/bb_skeleton.dart`
- Modify: `lib/ui/kit/kit.dart` (export)
- Modify: `lib/ui/board/arrival_board_screen.dart:292` (loading state)
- Modify: `lib/ui/alerts/alerts_screen.dart:48` (loading state)
- Modify: `lib/ui/stop_picker/near_me_list.dart:35-38` (loading state)
- Modify: `test/ui/alerts_test.dart:181-182`
- Modify: `test/kit/kit_golden_test.dart` (one skeleton row)
- Create: `test/kit/skeleton_test.dart`
- Regenerate: `test/kit/goldens/*.png` (and any screen golden showing a loading state)

**Interfaces:**
- Produces:
  - `enum BBSkeletonKind { arrivalRow, alertCard, stopCard }`
  - `BBSkeleton({Key? key, required BBSkeletonKind kind, int count = 3, String label = 'Loading'})`

- [ ] **Step 1: Write the failing test**

Create `test/kit/skeleton_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

void main() {
  testWidgets('shows one placeholder per count and announces a single label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(const BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: 4, label: 'Loading departures...')));
    expect(find.byKey(const ValueKey('bb-skeleton-item')), findsNWidgets(4));
    expect(find.semantics.byLabel('Loading departures...'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(BBSkeleton)),
      isSemantics(label: 'Loading departures...', isLiveRegion: true),
    );
    handle.dispose();
  });

  testWidgets('every kind lays out at 2x text on a 320 pt screen without overflow and without animating', (tester) async {
    for (final kind in BBSkeletonKind.values) {
      await tester.pumpWidget(kitHost(BBSkeleton(kind: kind), width: 320, textScale: 2));
      expect(tester.takeException(), isNull, reason: kind.name);
      expect(tester.hasRunningAnimations, isFalse, reason: kind.name);
    }
  });
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `flutter test test/kit/skeleton_test.dart`
Expected: compile error, "BBSkeleton isn't defined".

- [ ] **Step 3: Create `lib/ui/kit/bb_skeleton.dart`**

```dart
import 'package:flutter/widgets.dart';

import 'tokens.dart';

enum BBSkeletonKind { arrivalRow, alertCard, stopCard }

/// Static placeholder rows shaped like the content they stand in for, shown
/// while a list first loads. No shimmer (reduce-motion safe); announced once
/// as [label].
class BBSkeleton extends StatelessWidget {
  const BBSkeleton({super.key, required this.kind, this.count = 3, this.label = 'Loading'});

  final BBSkeletonKind kind;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final block = bb.colors.surfaceSunken;

    Widget box(double w, double h, {double r = 4}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(r)),
        );
    Widget bar(double widthFactor, double h) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: box(double.infinity, h),
        );

    Widget item() => switch (kind) {
          BBSkeletonKind.arrivalRow => Row(children: [
              box(40, 40, r: BBRadius.badge),
              const SizedBox(width: BBSpace.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  bar(0.7, 14),
                  const SizedBox(height: BBSpace.s),
                  bar(0.45, 10),
                ]),
              ),
              const SizedBox(width: BBSpace.m),
              box(28, 24, r: 6),
            ]),
          BBSkeletonKind.alertCard => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              box(40, 40, r: BBRadius.badge),
              const SizedBox(width: BBSpace.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  bar(0.8, 14),
                  const SizedBox(height: BBSpace.s),
                  Row(children: [box(48, 18, r: BBRadius.pill), const SizedBox(width: 6), box(26, 18, r: 6)]),
                  const SizedBox(height: BBSpace.s),
                  bar(1, 10),
                  const SizedBox(height: 6),
                  bar(0.6, 10),
                ]),
              ),
            ]),
          BBSkeletonKind.stopCard => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              bar(0.6, 14),
              const SizedBox(height: 6),
              bar(0.35, 10),
              const SizedBox(height: BBSpace.s),
              Row(children: [
                for (var i = 0; i < 3; i++) ...[box(26, 20, r: 6), const SizedBox(width: 6)],
              ]),
            ]),
        };

    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < count; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: BBSpace.s),
                child: Container(
                  key: const ValueKey('bb-skeleton-item'),
                  padding: const EdgeInsets.all(BBSpace.m),
                  decoration: bb.card(),
                  child: item(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

Add to `lib/ui/kit/kit.dart`, after `export 'bb_sheet.dart';`:

```dart
export 'bb_skeleton.dart';
```

- [ ] **Step 4: Use it on the Board, Alerts and Near me**

`lib/ui/board/arrival_board_screen.dart`: replace `if (_loading) return centered(const BBLoading(label: 'Loading departures...'));` with:

```dart
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottom),
        children: [
          ?alertBlock,
          const Padding(
            padding: EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.s, BBSpace.screen, 0),
            child: BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: 5, label: 'Loading departures...'),
          ),
        ],
      );
    }
```

`lib/ui/alerts/alerts_screen.dart`: replace `loading: () => centered(const BBLoading(label: 'Loading service alerts...')),` with:

```dart
                loading: () => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                      BBSpace.screen, BBSpace.xl, BBSpace.screen, BBNavBar.reservedHeight(context) + BBSpace.l),
                  children: const [
                    BBSkeleton(kind: BBSkeletonKind.alertCard, count: 3, label: 'Loading service alerts...'),
                  ],
                ),
```

`lib/ui/stop_picker/near_me_list.dart`: replace the loading `Padding(... Center(child: BBLoading(label: 'Finding nearby stops...')))` with:

```dart
          loading: () => const Padding(
            padding: EdgeInsets.only(top: BBSpace.s),
            child: BBSkeleton(kind: BBSkeletonKind.stopCard, count: 3, label: 'Finding nearby stops...'),
          ),
```

The stop picker's full-screen "Loading schedule data..." stays `BBLoading`, because it's a short wait with visible text.

- [ ] **Step 5: Update the one test that pinned the old spinner**

In `test/ui/alerts_test.dart` ("loading state is pull-to-refresh-able"), replace `expect(find.byType(BBLoading), findsOneWidget);` with:

```dart
    expect(find.byType(BBSkeleton), findsOneWidget);
    expect(find.bySemanticsLabel('Loading service alerts...'), findsOneWidget);
```

This is behaviour change 5 in the plan header: same pull-to-refresh guarantee, new placeholder.

- [ ] **Step 6: Add a skeleton to the kit gallery**

In `test/kit/kit_golden_test.dart`, after the `row(23, 'Stavanger Drive', 'Scheduled', '6'),` line, insert:

```dart
            const SizedBox(height: BBSpace.s),
            const BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: 1),
```

Raise the view heights if the gallery no longer fits (see Task 2 Step 5).

- [ ] **Step 7: Run the tests, regenerate goldens, then analyze and run the full suite**

Run, in order:
- `flutter test test/kit/skeleton_test.dart test/ui/alerts_test.dart test/ui/arrival_board_screen_test.dart test/ui/stop_picker_test.dart test/ui/screen_overflow_test.dart`
- `flutter test --update-goldens test/kit/kit_golden_test.dart test/ui/screen_golden_test.dart`
- `flutter analyze lib test && flutter test`

Inspect the skeleton row in light and dark. Its blocks should be visible against the card but quiet.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/kit/bb_skeleton.dart lib/ui/kit/kit.dart lib/ui/board/arrival_board_screen.dart lib/ui/alerts/alerts_screen.dart lib/ui/stop_picker/near_me_list.dart test/kit/skeleton_test.dart test/ui/alerts_test.dart test/kit/kit_golden_test.dart test/kit/goldens test/ui/goldens
git commit -m "feat(kit): skeleton placeholders for first loads"
```

---

### Task 6: `BBSheet` becomes a floating card

**Files:**
- Modify: `lib/ui/kit/bb_sheet.dart` (whole file)
- Modify: `test/kit/sheet_test.dart` (`_host` uses `BBSheetController`; new tests)

**Interfaces:**
- Produces:
  - `enum BBSheetDetent { peek, half, full }`
  - `class BBSheetController extends DraggableScrollableController`, with `Future<void> animateToDetent(BBSheetDetent detent)` and `Future<void> collapse()`
  - `BBSheet({Key? key, required List<Widget> slivers, Widget? header, required double peekFraction, double halfFraction = 0.5, double fullFraction = 0.9, double? initialFraction, BBSheetController? controller, double bottomInset = 0, bool dismissible = false, VoidCallback? onDismiss, String semanticLabel = 'Sheet'})`
  - `BBSheet.sideMargin` (8) and `BBSheet.cardKey`
- Note for 3b: the map passes `bottomInset: BBNavBar.reservedHeight(context)` and calls `controller.collapse()` when the map is tapped.

- [ ] **Step 1: Switch the existing tests to `BBSheetController` and write the new ones**

In `test/kit/sheet_test.dart`, change `_host(DraggableScrollableController controller, {bool reduceMotion = false})` to the following. Then replace every `DraggableScrollableController()` in the file with `BBSheetController()`.

```dart
Widget _host(
  BBSheetController controller, {
  bool reduceMotion = false,
  Widget? header,
  double bottomInset = 0,
  bool dismissible = false,
  VoidCallback? onDismiss,
}) {
  return kitHost(
    MediaQuery(
      data: MediaQueryData(size: const Size(390, 800), disableAnimations: reduceMotion),
      child: SizedBox(
        height: 800,
        child: Stack(
          children: [
            BBSheet(
              controller: controller,
              peekFraction: 0.15,
              header: header,
              bottomInset: bottomInset,
              dismissible: dismissible,
              onDismiss: onDismiss,
              slivers: [
                SliverList.builder(itemCount: 30, itemBuilder: (_, i) => SizedBox(height: 44, child: Text('row $i'))),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
```

Add `import 'package:busboard_nl/ui/kit/tokens.dart';` if `BBRadius` isn't already reachable. Then add these tests inside `main()`:

```dart
  testWidgets('floating card: inset 8 on both sides, lifted by bottomInset, rounded on every corner', (tester) async {
    await tester.pumpWidget(_host(BBSheetController(), bottomInset: 100));
    final card = tester.getRect(find.byKey(BBSheet.cardKey));
    expect(card.left, BBSheet.sideMargin);
    expect(card.right, 390 - BBSheet.sideMargin);
    expect(card.bottom, closeTo(800 - 100 - 8, 0.5));
    final box = tester.widget<DecoratedBox>(find.byKey(BBSheet.cardKey)).decoration as BoxDecoration;
    expect(box.borderRadius, BorderRadius.circular(BBRadius.sheet));
  });

  testWidgets('the header stays pinned while the body scrolls', (tester) async {
    final controller = BBSheetController();
    await tester.pumpWidget(_host(controller, header: const SizedBox(height: 48, child: Text('MUN Centre'))));
    await controller.animateToDetent(BBSheetDetent.full);
    await tester.pumpAndSettle();
    final headerBefore = tester.getTopLeft(find.text('MUN Centre')).dy;
    final rowBefore = tester.getTopLeft(find.text('row 8')).dy;
    await tester.drag(find.text('row 8'), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('row 8')).dy, lessThan(rowBefore - 100));
    expect(tester.getTopLeft(find.text('MUN Centre')).dy, headerBefore);
  });

  testWidgets('animateToDetent moves between detents and collapse returns to peek', (tester) async {
    final controller = BBSheetController();
    await tester.pumpWidget(_host(controller));
    await controller.animateToDetent(BBSheetDetent.half);
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.5, 0.01));
    await controller.animateToDetent(BBSheetDetent.full);
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.9, 0.01));
    await controller.collapse();
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.15, 0.01));
  });

  testWidgets('animateToDetent works with reduce motion', (tester) async {
    final controller = BBSheetController();
    await tester.pumpWidget(_host(controller, reduceMotion: true));
    await controller.animateToDetent(BBSheetDetent.half);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.size, closeTo(0.5, 0.01));
  });

  testWidgets('the handle is adjustable with Expand, Collapse and Close actions', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = BBSheetController();
    var dismissed = 0;
    await tester.pumpWidget(_host(controller, dismissible: true, onDismiss: () => dismissed++));
    final sheet = find.semantics.byLabel('Sheet');
    expect(
      tester.getSemantics(find.byKey(BBSheet.handleKey)),
      isSemantics(
        label: 'Sheet',
        value: 'Collapsed',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        customActions: const [CustomSemanticsAction(label: 'Expand'), CustomSemanticsAction(label: 'Close')],
      ),
    );
    tester.semantics.increase(sheet);
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.5, 0.01));
    expect(tester.getSemantics(find.byKey(BBSheet.handleKey)), isSemantics(value: 'Half open'));
    tester.semantics.customAction(sheet, const CustomSemanticsAction(label: 'Collapse'));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.15, 0.01));
    tester.semantics.customAction(sheet, const CustomSemanticsAction(label: 'Close'));
    await tester.pumpAndSettle();
    expect(dismissed, 1);
    handle.dispose();
  });

  testWidgets('non-dismissible sheet stays at peek when swiped down', (tester) async {
    final controller = BBSheetController();
    await tester.pumpWidget(_host(controller));
    await tester.fling(find.text('row 0'), const Offset(0, 400), 2000);
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.15, 0.01));
  });

  testWidgets('dismissible sheet closes once when swiped down from peek', (tester) async {
    final controller = BBSheetController();
    var dismissed = 0;
    await tester.pumpWidget(_host(controller, dismissible: true, onDismiss: () => dismissed++));
    await tester.fling(find.text('row 0'), const Offset(0, 400), 2000);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    expect(dismissed, 1);
  });
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `flutter test test/kit/sheet_test.dart`
Expected: compile errors for `BBSheetController`, `BBSheetDetent`, `BBSheet.cardKey`, `handleKey`, `sideMargin`, `header`, `bottomInset` and `dismissible`.

- [ ] **Step 3: Replace `lib/ui/kit/bb_sheet.dart`**

```dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

enum BBSheetDetent { peek, half, full }

/// Drives a [BBSheet]: its size (it is a [DraggableScrollableController]) and
/// detent moves that honour reduce motion.
class BBSheetController extends DraggableScrollableController {
  _BBSheetState? _sheet;

  /// Animates to [detent] (in 1 ms with reduce motion). No-op when detached.
  Future<void> animateToDetent(BBSheetDetent detent) async {
    final sheet = _sheet;
    if (sheet == null || !isAttached) return;
    await animateTo(sheet._fractionOf(detent), duration: sheet._snapDuration, curve: BBMotion.curve);
  }

  /// Back to peek, e.g. when the map behind the sheet is tapped.
  Future<void> collapse() => animateToDetent(BBSheetDetent.peek);
}

/// Floating card sheet with three detents (peek / half / full): inset by
/// [sideMargin], rounded on every corner, lifted above [bottomInset] (the nav
/// bar on the map), with an optional [header] pinned above the scrolling
/// [slivers]. One haptic tick when it settles on a detent. The grab handle is
/// an adjustable control for screen readers (Expand / Collapse / Close).
/// Place it in a Stack over the content.
class BBSheet extends StatefulWidget {
  const BBSheet({
    super.key,
    required this.slivers,
    this.header,
    required this.peekFraction,
    this.halfFraction = 0.5,
    this.fullFraction = 0.9,
    this.initialFraction,
    this.controller,
    this.bottomInset = 0,
    this.dismissible = false,
    this.onDismiss,
    this.semanticLabel = 'Sheet',
  })  : assert(
          peekFraction > 0 && peekFraction < halfFraction && halfFraction < fullFraction && fullFraction <= 1,
          'BBSheet fractions must satisfy 0 < peek < half < full <= 1',
        ),
        assert(!dismissible || onDismiss != null, 'A dismissible BBSheet needs onDismiss');

  final List<Widget> slivers;
  final Widget? header;
  final double peekFraction;
  final double halfFraction;
  final double fullFraction;
  final double? initialFraction;
  final BBSheetController? controller;
  final double bottomInset;
  final bool dismissible;
  final VoidCallback? onDismiss;
  final String semanticLabel;

  static const double sideMargin = 8;
  static const cardKey = ValueKey('bb-sheet-card');
  static const handleKey = ValueKey('bb-sheet-handle');

  @override
  State<BBSheet> createState() => _BBSheetState();
}

class _BBSheetState extends State<BBSheet> {
  static const _tolerance = 0.004;
  static const _settleDelay = Duration(milliseconds: 80);

  late final BBSheetController _controller = widget.controller ?? BBSheetController();
  late double? _lastDetent = widget.initialFraction ?? widget.peekFraction;
  late double _extent = widget.initialFraction ?? widget.peekFraction;
  Timer? _settleTimer;
  bool _dismissed = false;
  Duration _snapDuration = BBMotion.sheet;

  @override
  void initState() {
    super.initState();
    _controller._sheet = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The sheet API rejects Duration.zero, so "reduce motion" uses 1 ms.
    final d = BBMotion.of(context, BBMotion.sheet);
    _snapDuration = d == Duration.zero ? const Duration(milliseconds: 1) : d;
  }

  double _fractionOf(BBSheetDetent detent) => switch (detent) {
        BBSheetDetent.peek => widget.peekFraction,
        BBSheetDetent.half => widget.halfFraction,
        BBSheetDetent.full => widget.fullFraction,
      };

  BBSheetDetent get _nearest {
    var best = BBSheetDetent.peek;
    for (final d in BBSheetDetent.values) {
      if ((_fractionOf(d) - _extent).abs() < (_fractionOf(best) - _extent).abs()) best = d;
    }
    return best;
  }

  double? _detentNear(double extent) {
    for (final detent in [widget.peekFraction, widget.halfFraction, widget.fullFraction]) {
      if ((extent - detent).abs() < _tolerance) return detent;
    }
    return null;
  }

  // Notifications fire on every size update, so a detent is only "settled"
  // once the extent has stayed on it for a short debounce.
  bool _onExtent(DraggableScrollableNotification n) {
    final nearestBefore = _nearest;
    _extent = n.extent;
    // Rebuild the handle's semantics (value and actions) after the frame:
    // notifications can arrive mid-layout, where setState is not allowed.
    if (_nearest != nearestBefore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    _settleTimer?.cancel();
    if (widget.dismissible && n.extent < _tolerance) {
      _settleTimer = Timer(_settleDelay, _dismiss);
      return false;
    }
    final detent = _detentNear(n.extent);
    if (detent == null) {
      _lastDetent = null;
      return false;
    }
    _settleTimer = Timer(_settleDelay, () {
      if (_detentNear(_extent) == detent && _lastDetent != detent) {
        _lastDetent = detent;
        HapticFeedback.selectionClick();
      }
    });
    return false;
  }

  void _dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    widget.onDismiss?.call();
  }

  void _go(BBSheetDetent detent) => unawaited(_controller.animateToDetent(detent));

  @override
  void dispose() {
    _settleTimer?.cancel();
    if (identical(_controller._sheet, this)) _controller._sheet = null;
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Widget _handle(BuildContext context) {
    final bb = context.bb;
    final at = _nearest;
    final up = switch (at) {
      BBSheetDetent.peek => BBSheetDetent.half,
      _ => BBSheetDetent.full,
    };
    final down = switch (at) {
      BBSheetDetent.full => BBSheetDetent.half,
      _ => BBSheetDetent.peek,
    };
    return Semantics(
      key: BBSheet.handleKey,
      container: true,
      label: widget.semanticLabel,
      value: switch (at) {
        BBSheetDetent.peek => 'Collapsed',
        BBSheetDetent.half => 'Half open',
        BBSheetDetent.full => 'Expanded',
      },
      onIncrease: at == BBSheetDetent.full ? null : () => _go(up),
      onDecrease: at == BBSheetDetent.peek ? (widget.dismissible ? _dismiss : null) : () => _go(down),
      customSemanticsActions: {
        if (at != BBSheetDetent.full) const CustomSemanticsAction(label: 'Expand'): () => _go(up),
        if (at != BBSheetDetent.peek) const CustomSemanticsAction(label: 'Collapse'): () => _go(BBSheetDetent.peek),
        if (widget.dismissible) const CustomSemanticsAction(label: 'Close'): _dismiss,
      },
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

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final top = MediaQuery.paddingOf(context).top;
    final peek = widget.peekFraction;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        BBSheet.sideMargin,
        top + BBSpace.s,
        BBSheet.sideMargin,
        widget.bottomInset + BBSpace.s,
      ),
      child: NotificationListener<DraggableScrollableNotification>(
        onNotification: _onExtent,
        child: DraggableScrollableSheet(
          controller: _controller,
          initialChildSize: widget.initialFraction ?? peek,
          minChildSize: widget.dismissible ? 0 : peek,
          maxChildSize: widget.fullFraction,
          snap: true,
          snapSizes: widget.dismissible ? [peek, widget.halfFraction] : [widget.halfFraction],
          snapAnimationDuration: _snapDuration,
          builder: (context, scrollController) => DecoratedBox(
            key: BBSheet.cardKey,
            decoration: bb.floating(radius: BBRadius.sheet),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BBRadius.sheet),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  PinnedHeaderSliver(
                    child: ColoredBox(
                      color: bb.colors.surface,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_handle(context), ?widget.header],
                      ),
                    ),
                  ),
                  ...widget.slivers,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `flutter test test/kit/sheet_test.dart`
Expected: PASS, including the existing haptics tests.
- If "ticks once when a drag settles on half" fails because the extra `setState` in `_onExtent` changes timing, keep the debounce exactly as written.
- If the haptics test was asserting zero ticks at peek for a dismissible sheet, it isn't affected, because the tests' host defaults to `dismissible: false`.

- [ ] **Step 5: Run analyze and the full suite**

Run: `flutter analyze lib test && flutter test`
Expected: green. `BBSheet` has no screen users yet (the map adopts it in 3b), so no screen golden changes.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/kit/bb_sheet.dart test/kit/sheet_test.dart
git commit -m "feat(kit): BBSheet floating card with pinned header, controller and detent actions"
```

---

### Task 7: The toast reserves the nav bar only where the bar is shown

**Files:**
- Modify: `lib/ui/kit/bb_nav_bar.dart` (add `BBNavBarScope`)
- Modify: `lib/ui/kit/bb_toast.dart` (`show` and `_ToastView`)
- Modify: `lib/ui/shell/app_shell.dart` (wrap the shell in `BBNavBarScope`)
- Modify: `test/kit/feedback_components_test.dart` (two tests)

**Interfaces:**
- Produces: `BBNavBarScope({Key? key, required Widget child})` and `static bool BBNavBarScope.isPresent(BuildContext context)`.

- [ ] **Step 1: Write the failing tests**

Add to `test/kit/feedback_components_test.dart`:

```dart
  testWidgets('outside the tab shell the toast sits just above the bottom safe area', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_launcher((c) => BBToast.show(c, 'no bar here')));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 250));
    final bottom = tester.getRect(find.byKey(BBToast.cardKey)).bottom;
    expect(bottom, closeTo(800 - 34 - BBSpace.l - BBSpace.s, 0.5));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('inside the tab shell the toast clears the nav bar', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late double reserved;
    await tester.pumpWidget(kitHost(BBNavBarScope(
      child: Builder(builder: (c) {
        reserved = BBNavBar.reservedHeight(c);
        return BBButton(label: 'go', onPressed: () => BBToast.show(c, 'above the bar'));
      }),
    )));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 250));
    final bottom = tester.getRect(find.byKey(BBToast.cardKey)).bottom;
    expect(bottom, closeTo(800 - reserved - BBSpace.s, 0.5));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `flutter test test/kit/feedback_components_test.dart`
Expected: compile errors for `BBNavBarScope` / `BBToast.cardKey`.

- [ ] **Step 3: Add `BBNavBarScope`**

Append to `lib/ui/kit/bb_nav_bar.dart`:

```dart
/// Marks the subtree where the floating nav bar is on screen (the tab shell).
/// Overlays such as [BBToast] reserve the bar's height only inside it, so a
/// pushed screen without the bar (Settings) doesn't float its toasts high.
class BBNavBarScope extends InheritedWidget {
  const BBNavBarScope({super.key, required super.child});

  static bool isPresent(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BBNavBarScope>() != null;

  @override
  bool updateShouldNotify(BBNavBarScope oldWidget) => false;
}
```

- [ ] **Step 4: Make the toast use it**

In `lib/ui/kit/bb_toast.dart`:
1. Add `static const cardKey = ValueKey('bb-toast-card');` to `BBToast`.
2. In `show`, compute `final reserveNavBar = BBNavBarScope.isPresent(context);` before building the entry, and pass `reserveNavBar: reserveNavBar` to `_ToastView`.
3. Give `_ToastView` a `final bool reserveNavBar;` field (`required this.reserveNavBar` in its constructor).
4. In `_ToastViewState.build`, replace the `bottom:` expression and add the key to the `Container`:

```dart
      // Above the nav bar where it is shown (else just above the safe area),
      // or above the keyboard when that is taller.
      bottom: math.max(
            widget.reserveNavBar
                ? BBNavBar.reservedHeight(context)
                : MediaQuery.paddingOf(context).bottom + BBSpace.l,
            MediaQuery.viewInsetsOf(context).bottom,
          ) +
          BBSpace.s,
```

```dart
            child: Container(
              key: BBToast.cardKey,
              padding: const EdgeInsets.symmetric(horizontal: BBSpace.l, vertical: BBSpace.m),
```

- [ ] **Step 5: Provide the scope in the tab shell**

In `lib/ui/shell/app_shell.dart`, wrap the returned `ColoredBox` in the scope (no other change):

```dart
    return BBNavBarScope(
      child: ColoredBox(
        color: context.bb.colors.bg,
        child: Stack(
          // ... unchanged children ...
        ),
      ),
    );
```

- [ ] **Step 6: Run the tests and watch them pass, then analyze and run the full suite**

Run:
- `flutter test test/kit/feedback_components_test.dart test/ui/settings_screen_test.dart test/ui/app_shell_test.dart`
- then `flutter analyze lib test && flutter test`

Expected: PASS. The keyboard test still passes, because the keyboard is taller than the safe-area offset.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/kit/bb_nav_bar.dart lib/ui/kit/bb_toast.dart lib/ui/shell/app_shell.dart test/kit/feedback_components_test.dart
git commit -m "fix(kit): toasts reserve the nav bar only where it is shown"
```

---

### Task 8: `BBChip` and `BBControlPill` (map controls)

**Files:**
- Create: `lib/ui/kit/bb_chip.dart`
- Create: `lib/ui/kit/bb_control_pill.dart`
- Modify: `lib/ui/kit/kit.dart` (exports)
- Modify: `test/kit/kit_golden_test.dart` (chips and pill row)
- Create: `test/kit/map_controls_test.dart`
- Regenerate: `test/kit/goldens/*.png`

**Interfaces:**
- Consumes: `BBPressable`, `BBIconButton`, `BBIcons` (Task 1).
- Produces:
  - `BBChip({Key? key, required String label, IconData? icon, Widget? leading, bool chevron = false, bool selected = false, VoidCallback? onTap, String? semanticLabel})`
  - `BBControlPillItem({required IconData icon, required String semanticLabel, required VoidCallback? onPressed, bool selected = false})`
  - `BBControlPill({Key? key, required List<BBControlPillItem> items})`

- [ ] **Step 1: Write the failing tests**

Create `test/kit/map_controls_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

void main() {
  testWidgets('a chip is a labelled 44 pt button that taps', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(kitHost(Center(
      child: BBChip(label: 'MUN Centre · 1150', icon: BBIcons.star, chevron: true, onTap: () => taps++),
    )));
    expect(tester.getSize(find.byType(BBChip)).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(find.byType(BBChip)),
      isSemantics(label: 'MUN Centre · 1150', isButton: true, hasTapAction: true),
    );
    await tester.tap(find.byType(BBChip));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a selected chip uses the brand fill and says so', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(Center(child: BBChip(label: 'Route 10', selected: true, onTap: () {}))));
    final box = tester.widget<Container>(find.byKey(BBChip.surfaceKey)).decoration as BoxDecoration;
    expect(box.color, BBColors.light.brand);
    expect(tester.getSemantics(find.byType(BBChip)), isSemantics(label: 'Route 10', isSelected: true));
    handle.dispose();
  });

  testWidgets('a long chip label ellipsizes at 2x text on 320 pt', (tester) async {
    await tester.pumpWidget(kitHost(
      BBChip(label: 'Freshwater Rd before Anderson Ave · 3080', icon: BBIcons.star, chevron: true, onTap: () {}),
      width: 320,
      textScale: 2,
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(BBChip)).width, lessThanOrEqualTo(320));
  });

  testWidgets('control pill buttons are 44 pt, labelled, and dim when disabled', (tester) async {
    final handle = tester.ensureSemantics();
    var located = 0;
    await tester.pumpWidget(kitHost(Center(
      child: BBControlPill(items: [
        BBControlPillItem(icon: BBIcons.location, semanticLabel: 'My location', onPressed: () => located++),
        const BBControlPillItem(icon: BBIcons.layers, semanticLabel: 'Layers', onPressed: null),
      ]),
    )));
    for (final button in tester.widgetList(find.byType(BBIconButton))) {
      expect(tester.getSize(find.byWidget(button)), const Size(44, 44));
    }
    expect(find.semantics.byLabel('My location'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('My location'));
    expect(located, 1);
    expect(tester.widget<Opacity>(find.descendant(of: find.byType(BBControlPill), matching: find.byType(Opacity)).last).opacity, 0.45);
    handle.dispose();
  });
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `flutter test test/kit/map_controls_test.dart`
Expected: compile errors, "BBChip/BBControlPill isn't defined".

- [ ] **Step 3: Create `lib/ui/kit/bb_chip.dart`**

```dart
import 'package:flutter/widgets.dart';

import 'bb_icons.dart';
import 'bb_pressable.dart';
import 'tokens.dart';

/// Floating map chip (your stop, route filter, "Back to bus"): a 44 pt pill on
/// the floating surface. [selected] uses the brand fill. The label ellipsizes
/// to fit; [leading] (e.g. a [BBGlyph]) replaces [icon].
class BBChip extends StatelessWidget {
  const BBChip({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.chevron = false,
    this.selected = false,
    this.onTap,
    this.semanticLabel,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final bool chevron;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const surfaceKey = ValueKey('bb-chip-surface');

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final fg = selected ? bb.colors.onBrand : bb.colors.ink;
    final lead = leading ?? (icon == null ? null : Icon(icon, size: 18, color: selected ? fg : bb.colors.brand));
    return Semantics(
      selected: selected,
      child: BBPressable(
        onTap: onTap,
        semanticLabel: semanticLabel ?? label,
        child: Container(
          key: surfaceKey,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: BBSpace.l, vertical: BBSpace.s),
          decoration: bb.floating(radius: 22).copyWith(color: selected ? bb.colors.brand : bb.colors.surface),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (lead != null) ...[lead, const SizedBox(width: BBSpace.s)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bb.text.label.copyWith(color: fg),
                ),
              ),
              if (chevron) ...[
                const SizedBox(width: BBSpace.xs),
                Icon(BBIcons.chevronDown, size: 16, color: selected ? fg : bb.colors.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Create `lib/ui/kit/bb_control_pill.dart`**

```dart
import 'package:flutter/widgets.dart';

import 'bb_icon_button.dart';
import 'tokens.dart';

class BBControlPillItem {
  const BBControlPillItem({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool selected;
}

/// Vertical stack of 44 pt map controls on one floating pill (e.g. "my
/// location"), separated by hairlines. A selected item uses the brand colour.
class BBControlPill extends StatelessWidget {
  const BBControlPill({super.key, required this.items});

  final List<BBControlPillItem> items;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return DecoratedBox(
      decoration: bb.floating(radius: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Container(width: 28, height: 1, color: bb.colors.line),
            Semantics(
              selected: items[i].selected,
              child: BBIconButton(
                icon: items[i].icon,
                semanticLabel: items[i].semanticLabel,
                onPressed: items[i].onPressed,
                color: items[i].selected ? bb.colors.brand : bb.colors.ink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

Add to `lib/ui/kit/kit.dart`, in alphabetical position:

```dart
export 'bb_chip.dart';
export 'bb_control_pill.dart';
```

- [ ] **Step 5: Add the controls to the kit gallery**

In `test/kit/kit_golden_test.dart`, just before the `BBNavBar(` entry, insert:

```dart
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      BBChip(label: 'MUN Centre · 1150', icon: BBIcons.star, chevron: true, onTap: () {}),
                      BBChip(label: 'All routes', chevron: true, onTap: () {}),
                      BBChip(label: 'Route 10', selected: true, onTap: () {}),
                    ],
                  ),
                ),
                const SizedBox(width: BBSpace.m),
                BBControlPill(items: [
                  BBControlPillItem(icon: BBIcons.location, semanticLabel: 'My location', onPressed: () {}),
                ]),
              ],
            ),
            const SizedBox(height: BBSpace.m),
```

Raise the view heights if needed (see Task 2 Step 5).

- [ ] **Step 6: Run the tests, regenerate goldens, then analyze and run the full suite**

Run:
- `flutter test test/kit/map_controls_test.dart`
- `flutter test --update-goldens test/kit/kit_golden_test.dart`
- `flutter analyze lib test && flutter test`

Inspect the chips and the pill:
- light mode uses the shadow, dark mode a hairline;
- the selected chip is brand blue with white text;
- at ×2.0 the chips wrap and no label overflows.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/kit/bb_chip.dart lib/ui/kit/bb_control_pill.dart lib/ui/kit/kit.dart test/kit/map_controls_test.dart test/kit/kit_golden_test.dart test/kit/goldens
git commit -m "feat(kit): BBChip and BBControlPill for the map"
```

---

## After the last task (controller)

- Run on the iOS simulator and the Android emulator with live data, in light and dark, at large text:
  - the Board, Alerts, picker and Settings: icons, refresh and skeletons;
  - a Settings toast, which now sits low.
- Record the result in the ledger.
- The Phase 3b plan (the map) is written next. It adopts `BBSheet`, `BBChip`, `BBControlPill`, `BBGlyph` and the floating-card language, and moves the map branch's bottom padding out of `AppShell`.
