# Harbour Redesign — Phase 2: Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the shell, Stop picker, Board, Alerts and Settings on the Phase 1 component kit, so these screens no longer use any Material/Cupertino widget or Material theme read. Behaviour stays the same, except for the deliberate changes the spec asks for, listed under "Behaviour changes".

**Architecture:** Each screen file imports only `package:flutter/widgets.dart`, `package:flutter/services.dart` (if needed), Riverpod, go_router, `intl`, and `../kit/kit.dart`. State and provider logic is carried over from the legacy files unchanged. Only the widget trees are replaced. The kit first gains the small pieces the screens need (icon button, top bar, loading, empty state, section header, stepper, divider, icon tile, `BBThemeMode`, text-field options, wrapping pills). As each file migrates, it leaves the kit boundary guard's allow-list. When this phase is done, only the three map files (Phase 3) remain on it.

**Tech Stack:** Flutter 3.47.5 / Dart ^3.11, flutter_riverpod 3, go_router 17, intl, http (MockClient in tests), flutter_test goldens.

**Spec:** `docs/superpowers/specs/2026-10-04-harbour-redesign-design.md` (§5, §6.1–§6.5, §9). The Phase 1 handoff, with deferred items and kit gaps, is in `docs/superpowers/notes/2026-10-04-harbour-phase1-ledger.md`.

## Global Constraints

- Work only in `/Users/aham/projects/dev/busboard_nl/.claude/worktrees/unified-ui-map-redesign-fc0a89`. Never use bare `git stash`. Never stage `analysis_options.yaml`, `pubspec.lock`, `tool/capture_raw_gtfsrt.dart`, `ios/Podfile`, `ios/Podfile.lock` or `ios/Runner.xcodeproj/project.pbxproj`. Those are unrelated local changes.
- Screen files (`lib/ui/**` outside `lib/ui/kit/`) must not import `package:flutter/material.dart` or `cupertino.dart`. They must not use `Icons.`, `Theme.of`, `ThemeData`, `ColorScheme`, `Colors.`, or any widget on the guard's list. `test/kit/kit_boundary_test.dart` enforces this. Remove each file from `_legacyAllowList` in the same commit that migrates it.
- No raw colour literals in screens. Use `context.bb.colors` / `RoutePalette`.
- Use `isSemantics(...)` for semantics assertions. Widget tests host screens in `MaterialApp(theme: BBTheme.light(), ...)` or `kitHost`. Kit widgets need `BBTokens` in the theme.
- Copy strings, verbatim:
  - Legal: the `LegalCopy.*` constants (`lib/ui/copy/legal_copy.dart`). Don't change them.
  - Errors: `Please enter a stop ID`, `Stop ID must be 4 digits`, `Schedule data not loaded`, `Failed to load schedule`, `Unable to get location`, `Please enable location services and grant permission.`, `No stops found within 800m.`, `No upcoming departures`, `There are no scheduled departures\nfrom this stop right now.`, `Could not load service alerts`, `No active service alerts.`
- Nav labels: `Board`, `Map`, `Alerts` (spec §6.1).
- Preserve provider calls and navigation exactly. That means:
  - `setSelectedStop` before `context.push('/board/<id>')` from stop entry and near-me
  - `context.push('/settings')`
  - `context.go('/alerts')` from board alert taps
  - `goBranch(i, initialLocation: i == currentIndex)`
  - the board timer lifecycle, re-entrancy guard and `ref.listen` restart
- Every commit ends with your own `Co-Authored-By:` trailer naming your model.
- Before each commit: `flutter analyze lib test` prints "No issues found!", and the full `flutter test` passes.

### Behaviour changes (deliberate, from the spec or a reasonable person's expectation)

1. **Countdown colour:** `soon` colour when ≤ 5 min, otherwise ink. This replaces the old red/orange/green tiers (spec §6.2). The countdown reads `Now` instead of `NOW`.
2. **Status labels in plain words** (spec §6.2):

   | Old label | New label |
   |---|---|
   | PRED | `Live` |
   | SCHEDULE | `Scheduled` |
   | AHEAD | `Early` |
   | BEHIND | `Late` |
   | ON TIME | `On time` |
   | LIVE | `Live` |

   Schedule-only rows now also show `Scheduled`.
3. **Route colours:** route badges use `RoutePalette` everywhere. In alert cards, the route chips become compact `RouteBadge`s.
4. **Settings button reachable sooner:** the Stop picker's settings button now shows during GTFS loading and error too.
5. **Pull to refresh in every state:** the Board can be pulled to refresh in its loading, error and empty states as well.
6. **Stop picker header and route pills:** the title is `Choose a stop` and the field hint is `Stop number on the pole`. Near-me rows show route pills for the routes serving each stop (spec §6.3). The stop-ID error clears as soon as the user edits the field.
7. **Board header:** a stop-number pill, `Change` (back to the picker), settings, and the stop name. The status line reads `Live · updated HH:mm:ss`, or `<issue> · showing schedule` when live data isn't available (spec §6.2). There is no separate back arrow; `Change` and the system back gesture cover it.
8. **Alerts:** the title is `Service alerts`. "Upcoming" no longer lists alerts whose periods have all ended.
9. **Settings:**
   - It gains a Map theme control (Match app / Light / Dark) that writes `setMapThemeMode` (spec §6.5). The map's own sheet stays until Phase 3.
   - The refresh-interval slider becomes a ± stepper (5–60 s, step 5).
   - A failed schedule refresh re-enables the button and shows a `BBToast`. Previously it stayed disabled.

## Review Focus

1. **Text scale 2.0 on a 320 pt phone:** board rows, near-me rows, the stop entry row, settings segmented controls and the stepper must not overflow. Pinned in Tasks 5, 6 and 9.
2. **Screen readers:** each arrival row is one node with a full sentence. Near-me rows and the last-stop card are single labelled buttons. Icon buttons have labels. Pinned in Tasks 2, 5 and 6.
3. **Leaving the Board while its refresh timer runs:** no pending-timer or setState-after-dispose errors. Pinned in Task 7.
4. **GTFS still loading or failed on the Stop picker:** settings is reachable and Retry works. Pinned in Task 5.
5. **Alerts that have fully ended, and stops missing from GTFS:** ended alerts don't appear as "Upcoming". Unknown stops render as `Stop <id>`. Pinned in Task 8.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/ui/kit/bb_theme.dart` (modify) | add `typedef BBThemeMode = ThemeMode;` |
| `lib/ui/kit/bb_icons.dart` (modify) | add the icons the screens need |
| `lib/ui/kit/bb_pill.dart` (modify) | `wrap` option (multi-line labels) |
| `lib/ui/kit/bb_text_field.dart` (modify) | `inputFormatters`, `errorText`, `focusNode`, `textAlign`, `style` |
| `lib/ui/kit/bb_icon_button.dart` | 44 pt labelled icon button |
| `lib/ui/kit/bb_top_bar.dart` | page title bar (title, subtitle, back, actions) |
| `lib/ui/kit/bb_loading.dart` | spinner + label |
| `lib/ui/kit/bb_empty_state.dart` | icon + title + message + action |
| `lib/ui/kit/bb_section_header.dart` | section title + count pill |
| `lib/ui/kit/bb_stepper.dart` | − value + stepper (adjustable semantics) |
| `lib/ui/kit/bb_divider.dart` | hairline divider |
| `lib/ui/kit/bb_icon_tile.dart` | rounded tinted icon square |
| `lib/ui/kit/kit.dart` (modify) | export the new files |
| `lib/data/gtfs/gtfs_repository.dart` (modify) | `routeShortNamesForStop`, `compareRouteNames` |
| `lib/ui/shell/app_shell.dart` | floating `BBNavBar` shell |
| `lib/ui/stop_picker/*.dart` | picker, stop entry, near-me |
| `lib/ui/board/arrival_row_tile.dart`, `arrival_board_screen.dart` | board |
| `lib/ui/alerts/service_alert_card.dart`, `alerts_screen.dart` | alerts |
| `lib/ui/settings/settings_screen.dart` | settings |
| `test/ui/*.dart` | screen tests; `test/ui/goldens/` screen goldens |

---

### Task 1: Kit extensions — BBThemeMode, icons, wrapping pills, text-field options

**Files:**
- Modify: `lib/ui/kit/bb_theme.dart`, `lib/ui/kit/bb_icons.dart`, `lib/ui/kit/bb_pill.dart`, `lib/ui/kit/bb_text_field.dart`
- Test: `test/kit/kit_extensions_test.dart`

**Interfaces:**
- Produces:
  - `typedef BBThemeMode = ThemeMode;` (exported via `bb_theme.dart` → `kit.dart`)
  - New `BBIcons`: `history, update, pin, timer, download, palette, detour, reducedService, stopMoved, accessible, additionalService, checkCircle, locationOff, layers, add, remove`
  - `BBPill({..., bool wrap = false})`
  - `BBTextField({..., List<TextInputFormatter>? inputFormatters, String? errorText, FocusNode? focusNode, TextAlign textAlign = TextAlign.start, TextStyle? style})`

- [ ] **Step 1: Write the failing test** — create `test/kit/kit_extensions_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

void main() {
  test('BBThemeMode aliases ThemeMode so screens need not import Material', () {
    const BBThemeMode mode = BBThemeMode.dark;
    expect(mode, ThemeMode.dark);
  });

  test('new icons exist', () {
    for (final icon in [
      BBIcons.history, BBIcons.update, BBIcons.pin, BBIcons.timer, BBIcons.download, BBIcons.palette,
      BBIcons.detour, BBIcons.reducedService, BBIcons.stopMoved, BBIcons.accessible,
      BBIcons.additionalService, BBIcons.checkCircle, BBIcons.locationOff, BBIcons.layers,
      BBIcons.add, BBIcons.remove,
    ]) {
      expect(icon, isA<IconData>());
    }
  });

  testWidgets('BBPill wrap lets a long label wrap instead of ellipsising', (tester) async {
    const label = 'Freshwater Rd before Anderson Ave · 3080';
    await tester.pumpWidget(kitHost(const SizedBox(width: 160, child: BBPill(label: label, wrap: true)), width: 160));
    final text = tester.widget<Text>(find.text(label));
    expect(text.maxLines, isNull);
    expect(text.softWrap, isTrue);
    expect(text.overflow, TextOverflow.visible);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(kitHost(const SizedBox(width: 160, child: BBPill(label: label)), width: 160));
    expect(tester.widget<Text>(find.text(label)).overflow, TextOverflow.ellipsis);
  });

  testWidgets('BBTextField applies formatters and shows an error', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(kitHost(BBTextField(
      controller: controller,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
      errorText: 'Stop ID must be 4 digits',
      textAlign: TextAlign.center,
    )));
    await tester.enterText(find.byType(TextField), '12a345');
    expect(controller.text, '1234');
    expect(find.text('Stop ID must be 4 digits'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).textAlign, TextAlign.center);
  });

  testWidgets('BBTextField error is announced and the border turns danger', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(const BBTextField(errorText: 'Please enter a stop ID')));
    expect(tester.getSemantics(find.text('Please enter a stop ID')), isSemantics(isLiveRegion: true));
    final box = tester.widget<Container>(find.descendant(of: find.byType(BBTextField), matching: find.byType(Container)).first);
    expect(((box.decoration! as BoxDecoration).border! as Border).top.color, BBColors.light.dangerInk);
    handle.dispose();
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/kit/kit_extensions_test.dart`. Expected: compile errors (`BBThemeMode`, `BBIcons.history`, `wrap`, `inputFormatters` are undefined).

- [ ] **Step 3: Implement**

`lib/ui/kit/bb_theme.dart`: below the imports add:

```dart
/// Theme-mode choice, re-exported so screens never import Material.
typedef BBThemeMode = ThemeMode;
```

`lib/ui/kit/bb_icons.dart`: add inside `BBIcons`:

```dart
  static const IconData history = Icons.history_rounded;
  static const IconData update = Icons.update_rounded;
  static const IconData pin = Icons.pin_drop_rounded;
  static const IconData timer = Icons.timer_rounded;
  static const IconData download = Icons.cloud_download_rounded;
  static const IconData palette = Icons.palette_rounded;
  static const IconData detour = Icons.alt_route_rounded;
  static const IconData reducedService = Icons.remove_circle_outline_rounded;
  static const IconData stopMoved = Icons.wrong_location_rounded;
  static const IconData accessible = Icons.accessible_rounded;
  static const IconData additionalService = Icons.add_road_rounded;
  static const IconData checkCircle = Icons.check_circle_outline_rounded;
  static const IconData locationOff = Icons.location_off_rounded;
  static const IconData layers = Icons.layers_rounded;
  static const IconData add = Icons.add_rounded;
  static const IconData remove = Icons.remove_rounded;
```

`lib/ui/kit/bb_pill.dart`:
- Add the constructor param `this.wrap = false` and the field `final bool wrap;` with the doc comment `/// Let long labels wrap onto several lines instead of ellipsising.`
- In `build`, change the label `Text` to:

```dart
              child: Text(
                label,
                softWrap: wrap,
                maxLines: wrap ? null : 1,
                overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
                style: context.bb.text.caption.copyWith(color: fgColor, fontWeight: FontWeight.w700),
              ),
```

`lib/ui/kit/bb_text_field.dart`:
- Add `import 'package:flutter/services.dart';`.
- Add these constructor params and fields: `this.inputFormatters`, `this.errorText`, `this.focusNode`, `this.textAlign = TextAlign.start`, `this.style`. Their types are `List<TextInputFormatter>?`, `String?`, `FocusNode?`, `TextAlign`, `TextStyle?`.
- In `build`:
  - Compute `final textStyle = bb.text.body.merge(style);` and `final hasError = errorText != null;`.
  - Wrap the existing `Container` in a `Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [...])`.
  - Change the container border to `Border.all(color: hasError ? bb.colors.dangerInk : bb.colors.line, width: hasError ? 1.5 : 1)`.
  - Pass `inputFormatters: inputFormatters, focusNode: focusNode, textAlign: textAlign, style: textStyle,` to the `TextField`, and make the hint style `textStyle.copyWith(color: bb.colors.muted)`.
  - Fix the indentation of `hintMaxLines: 2,`.
  - After the container, add:

```dart
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: BBSpace.xs, left: BBSpace.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(errorText!, style: bb.text.caption.copyWith(color: bb.colors.dangerInk)),
            ),
          ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/kit/kit_extensions_test.dart test/kit` (all kit tests, including goldens, must still pass). If the existing kit goldens change only because of the indentation fix, they shouldn't; if they do change, inspect them and regenerate.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/kit/bb_theme.dart lib/ui/kit/bb_icons.dart lib/ui/kit/bb_pill.dart lib/ui/kit/bb_text_field.dart test/kit/kit_extensions_test.dart
git commit -m "feat(kit): BBThemeMode, screen icons, wrapping pills and text-field options"
```

---

### Task 2: Kit additions — icon button, top bar, loading, empty state, section header, stepper, divider, icon tile

**Files:**
- Create: `lib/ui/kit/bb_icon_button.dart`, `bb_top_bar.dart`, `bb_loading.dart`, `bb_empty_state.dart`, `bb_section_header.dart`, `bb_stepper.dart`, `bb_divider.dart`, `bb_icon_tile.dart`
- Modify: `lib/ui/kit/kit.dart` (export all eight)
- Test: `test/kit/screen_kit_test.dart`

**Interfaces:**
- Consumes: `BBPressable`, `BBPill`, `BBPillTone`, `BBIcons`, tokens.
- Produces:
  - `BBIconButton({required IconData icon, required String semanticLabel, required VoidCallback? onPressed, Color? color, double size = 22})` — 44×44 target
  - `BBTopBar({required String title, String? subtitle, VoidCallback? onBack, List<Widget> actions = const [], bool large = false})`
  - `BBLoading({String? label})`
  - `enum BBEmptyTone { neutral, error }`; `BBEmptyState({required IconData icon, required String title, String? message, Widget? action, BBEmptyTone tone = BBEmptyTone.neutral})`
  - `BBSectionHeader({required String title, int? count, BBPillTone countTone = BBPillTone.brand})`
  - `BBStepper({required int value, required int min, required int max, int step = 1, required ValueChanged<int> onChanged, required String Function(int) format, required String semanticLabel})`
  - `BBDivider({double indent = 0})`
  - `BBIconTile({required IconData icon, BBPillTone tone = BBPillTone.brand, double size = 40})`

- [ ] **Step 1: Write the failing test** — create `test/kit/screen_kit_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

void main() {
  testWidgets('BBIconButton is a 44pt labelled button', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(kitHost(BBIconButton(icon: BBIcons.settings, semanticLabel: 'Settings', onPressed: () => taps++)));
    expect(tester.getSize(find.byType(BBIconButton)), const Size(44, 44));
    expect(tester.getSemantics(find.byType(BBIconButton)), isSemantics(label: 'Settings', isButton: true, hasTapAction: true));
    await tester.tap(find.byType(BBIconButton));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('BBTopBar shows title as a header, back and actions', (tester) async {
    final handle = tester.ensureSemantics();
    var back = 0;
    await tester.pumpWidget(kitHost(BBTopBar(
      title: 'Settings',
      subtitle: 'Stop #1150',
      onBack: () => back++,
      actions: [BBIconButton(icon: BBIcons.settings, semanticLabel: 'More', onPressed: () {})],
    )));
    expect(tester.getSemantics(find.text('Settings')), isSemantics(isHeader: true));
    expect(find.text('Stop #1150'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    expect(back, 1);
    handle.dispose();
  });

  testWidgets('BBEmptyState renders icon, title, message and action', (tester) async {
    await tester.pumpWidget(kitHost(BBEmptyState(
      icon: BBIcons.error,
      tone: BBEmptyTone.error,
      title: 'Failed to load schedule',
      message: 'boom',
      action: BBButton(label: 'Retry', onPressed: () {}),
    )));
    expect(find.text('Failed to load schedule'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.widget<Icon>(find.byType(Icon).first).color, BBColors.light.dangerInk);
  });

  testWidgets('BBLoading announces its label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(const BBLoading(label: 'Finding nearby stops...')));
    expect(find.bySemanticsLabel('Finding nearby stops...'), findsWidgets);
    handle.dispose();
  });

  testWidgets('BBSectionHeader shows a count pill', (tester) async {
    await tester.pumpWidget(kitHost(const BBSectionHeader(title: 'Active now', count: 2, countTone: BBPillTone.danger)));
    expect(find.text('Active now'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('BBStepper steps within bounds and is adjustable for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    var value = 5;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => kitHost(BBStepper(
        value: value,
        min: 5,
        max: 60,
        step: 5,
        format: (v) => '$v seconds',
        semanticLabel: 'Refresh interval',
        onChanged: (v) => setState(() => value = v),
      )),
    ));
    expect(find.text('5 seconds'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Decrease Refresh interval'));
    await tester.pump();
    expect(value, 5); // at min: no change
    await tester.tap(find.bySemanticsLabel('Increase Refresh interval'));
    await tester.pump();
    expect(value, 10);
    final node = tester.getSemantics(find.bySemanticsLabel('Refresh interval'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.increase), isTrue);
    expect(node.value, '10 seconds');
    handle.dispose();
  });

  testWidgets('screen-kit widgets do not overflow at text scale 2.0 on 320pt', (tester) async {
    await tester.pumpWidget(kitHost(
      Column(children: [
        BBTopBar(title: 'Choose a stop', subtitle: "Metrobus · St. John's", large: true,
            actions: [BBIconButton(icon: BBIcons.settings, semanticLabel: 'Settings', onPressed: () {})]),
        BBStepper(value: 30, min: 5, max: 60, step: 5, format: (v) => '$v seconds', semanticLabel: 'Refresh interval', onChanged: (_) {}),
        const BBSectionHeader(title: 'Active now', count: 12),
      ]),
      textScale: 2.0,
      width: 320,
    ));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/kit/screen_kit_test.dart`. Expected: compile errors (the new widgets are undefined).

- [ ] **Step 3: Implement the eight files**

`lib/ui/kit/bb_icon_button.dart`:

```dart
import 'package:flutter/widgets.dart';

import 'bb_pressable.dart';
import 'tokens.dart';

/// Icon-only button with a 44pt target and a required screen-reader label.
class BBIconButton extends StatelessWidget {
  const BBIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.color,
    this.size = 22,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.bb.colors;
    return BBPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Icon(icon, size: size, color: onPressed == null ? c.line : (color ?? c.ink)),
        ),
      ),
    );
  }
}
```

`lib/ui/kit/bb_top_bar.dart`:

```dart
import 'package:flutter/widgets.dart';

import 'bb_icon_button.dart';
import 'bb_icons.dart';
import 'tokens.dart';

/// Page title bar: optional back button, title (+ subtitle) and trailing
/// actions. [large] uses the display style for root screens.
class BBTopBar extends StatelessWidget {
  const BBTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.large = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.xs, BBSpace.s, BBSpace.xs, BBSpace.s),
      child: Row(
        children: [
          if (onBack != null)
            BBIconButton(icon: BBIcons.back, semanticLabel: 'Back', onPressed: onBack)
          else
            const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: large ? bb.text.display : bb.text.title,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: bb.text.caption),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
```

`lib/ui/kit/bb_loading.dart`:

```dart
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Brand spinner with an optional label, announced to screen readers.
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
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3, color: bb.colors.brand),
          ),
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

`lib/ui/kit/bb_empty_state.dart`:

```dart
import 'package:flutter/widgets.dart';

import 'tokens.dart';

enum BBEmptyTone { neutral, error }

/// Centred icon + title + optional message and action, for empty and error
/// states.
class BBEmptyState extends StatelessWidget {
  const BBEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tone = BBEmptyTone.neutral,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final BBEmptyTone tone;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Padding(
      padding: const EdgeInsets.all(BBSpace.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: tone == BBEmptyTone.error ? bb.colors.dangerInk : bb.colors.muted),
          const SizedBox(height: BBSpace.m),
          Text(title, textAlign: TextAlign.center, style: bb.text.headline),
          if (message != null) ...[
            const SizedBox(height: BBSpace.xs),
            Text(message!, textAlign: TextAlign.center, style: bb.text.body.copyWith(color: bb.colors.muted)),
          ],
          if (action != null) ...[
            const SizedBox(height: BBSpace.l),
            action!,
          ],
        ],
      ),
    );
  }
}
```

`lib/ui/kit/bb_section_header.dart`:

```dart
import 'package:flutter/widgets.dart';

import 'bb_pill.dart';
import 'tokens.dart';

class BBSectionHeader extends StatelessWidget {
  const BBSectionHeader({super.key, required this.title, this.count, this.countTone = BBPillTone.brand});

  final String title;
  final int? count;
  final BBPillTone countTone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Semantics(header: true, child: Text(title, style: context.bb.text.title)),
        ),
        if (count != null) ...[
          const SizedBox(width: BBSpace.s),
          BBPill(label: '$count', tone: countTone),
        ],
      ],
    );
  }
}
```

`lib/ui/kit/bb_stepper.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'bb_icon_button.dart';
import 'bb_icons.dart';
import 'tokens.dart';

/// − value + stepper. Screen readers get one adjustable node
/// (swipe up/down to change).
class BBStepper extends StatelessWidget {
  const BBStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    required this.onChanged,
    required this.format,
    required this.semanticLabel,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final String Function(int) format;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final canDec = value > min;
    final canInc = value < max;
    void dec() => onChanged(math.max(min, value - step));
    void inc() => onChanged(math.min(max, value + step));
    return Semantics(
      container: true,
      label: semanticLabel,
      value: format(value),
      increasedValue: canInc ? format(math.min(max, value + step)) : null,
      decreasedValue: canDec ? format(math.max(min, value - step)) : null,
      onIncrease: canInc ? inc : null,
      onDecrease: canDec ? dec : null,
      child: DecoratedBox(
        decoration: BoxDecoration(color: bb.colors.surfaceSunken, borderRadius: BorderRadius.circular(BBRadius.badge)),
        child: Row(
          children: [
            BBIconButton(icon: BBIcons.remove, semanticLabel: 'Decrease $semanticLabel', onPressed: canDec ? dec : null),
            Expanded(
              child: ExcludeSemantics(
                child: Text(format(value), textAlign: TextAlign.center, style: bb.text.headline),
              ),
            ),
            BBIconButton(icon: BBIcons.add, semanticLabel: 'Increase $semanticLabel', onPressed: canInc ? inc : null),
          ],
        ),
      ),
    );
  }
}
```

`lib/ui/kit/bb_divider.dart`:

```dart
import 'package:flutter/widgets.dart';

import 'tokens.dart';

class BBDivider extends StatelessWidget {
  const BBDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: SizedBox(height: 1, width: double.infinity, child: ColoredBox(color: context.bb.colors.line)),
    );
  }
}
```

`lib/ui/kit/bb_icon_tile.dart`:

```dart
import 'package:flutter/widgets.dart';

import 'bb_pill.dart';
import 'tokens.dart';

/// Rounded tinted square holding an icon (list leading visual).
class BBIconTile extends StatelessWidget {
  const BBIconTile({super.key, required this.icon, this.tone = BBPillTone.brand, this.size = 40});

  final IconData icon;
  final BBPillTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.bb.colors;
    final (bg, fg) = switch (tone) {
      BBPillTone.neutral => (c.surfaceSunken, c.muted),
      BBPillTone.brand => (c.brandSoft, c.brandInk),
      BBPillTone.live => (c.liveSoft, c.liveInk),
      BBPillTone.warn => (c.warnBg, c.warnInk),
      BBPillTone.danger => (c.dangerBg, c.dangerInk),
    };
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(BBRadius.badge)),
          child: Icon(icon, size: size * 0.5, color: fg),
        ),
      ),
    );
  }
}
```

`lib/ui/kit/kit.dart`: add (alphabetical with the rest):

```dart
export 'bb_divider.dart';
export 'bb_empty_state.dart';
export 'bb_icon_button.dart';
export 'bb_icon_tile.dart';
export 'bb_loading.dart';
export 'bb_section_header.dart';
export 'bb_stepper.dart';
export 'bb_top_bar.dart';
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/kit/screen_kit_test.dart test/kit`. Expected: PASS. If `find.bySemanticsLabel('Refresh interval')` matches several nodes (container plus children), use `find.bySemanticsLabel(RegExp(r'^Refresh interval$'))`. Keep the assertions.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/kit/bb_icon_button.dart lib/ui/kit/bb_top_bar.dart lib/ui/kit/bb_loading.dart lib/ui/kit/bb_empty_state.dart lib/ui/kit/bb_section_header.dart lib/ui/kit/bb_stepper.dart lib/ui/kit/bb_divider.dart lib/ui/kit/bb_icon_tile.dart lib/ui/kit/kit.dart test/kit/screen_kit_test.dart
git commit -m "feat(kit): icon button, top bar, loading, empty state, section header, stepper, divider, icon tile"
```

---

### Task 3: Routes-serving-a-stop helper

**Files:**
- Modify: `lib/data/gtfs/gtfs_repository.dart`
- Test: `test/gtfs_routes_for_stop_test.dart`

**Interfaces:**
- Produces:
  - `List<String> GtfsRepository.routeShortNamesForStop(String stopId)`: memoised, sorted numerically where possible
  - `static int GtfsRepository.compareRouteNames(String a, String b)`: numeric ids first in numeric order, then the rest alphabetically

- [ ] **Step 1: Write the failing test** — `test/gtfs_routes_for_stop_test.dart`:

```dart
import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:flutter_test/flutter_test.dart';

GtfsRepository _repo() {
  final repo = GtfsRepository();
  for (final (id, short) in [('r10', '10'), ('r2', '2'), ('r15', '15'), ('rX', 'X1')]) {
    repo.routesById[id] = RouteInfo(routeId: id, routeShortName: short, routeLongName: '');
  }
  for (final (trip, route) in [('t1', 'r10'), ('t2', 'r2'), ('t3', 'r10'), ('t4', 'r15'), ('t5', 'rX'), ('t6', 'missing')]) {
    repo.tripsById[trip] = TripInfo(tripId: trip, routeId: route, serviceId: 's', tripHeadsign: '', directionId: 0);
  }
  repo.stopTimesByStopId['1150'] = [
    for (final trip in ['t1', 't2', 't3', 't4', 't5', 't6', 'unknown-trip'])
      StopTimeRow(tripId: trip, arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1),
  ];
  return repo;
}

void main() {
  test('distinct routes serving a stop, numeric order, then alphanumeric', () {
    expect(_repo().routeShortNamesForStop('1150'), ['2', '10', '15', 'X1']);
  });

  test('unknown stop has no routes', () {
    expect(_repo().routeShortNamesForStop('9999'), isEmpty);
  });

  test('result is memoised and unmodifiable', () {
    final repo = _repo();
    final a = repo.routeShortNamesForStop('1150');
    expect(identical(a, repo.routeShortNamesForStop('1150')), isTrue);
    expect(() => a.add('99'), throwsUnsupportedError);
  });

  test('compareRouteNames is a consistent total order', () {
    final names = ['X1', '10', '2', 'A', '15'];
    names.sort(GtfsRepository.compareRouteNames);
    expect(names, ['2', '10', '15', 'A', 'X1']);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/gtfs_routes_for_stop_test.dart`. Expected: compile errors (the methods are undefined).

- [ ] **Step 3: Implement** in `lib/data/gtfs/gtfs_repository.dart`.

Add after the existing index maps:

```dart
  final Map<String, List<String>> _routesForStopCache = {};

  /// Route short names serving [stopId], sorted with [compareRouteNames].
  /// Memoised; cleared whenever data is (re)loaded.
  List<String> routeShortNamesForStop(String stopId) {
    final cached = _routesForStopCache[stopId];
    if (cached != null) return cached;
    final names = <String>{};
    for (final row in stopTimesByStopId[stopId] ?? const <StopTimeRow>[]) {
      final trip = tripsById[row.tripId];
      if (trip == null) continue;
      final route = routesById[trip.routeId];
      if (route == null) continue;
      names.add(route.routeShortName);
    }
    final sorted = names.toList()..sort(compareRouteNames);
    return _routesForStopCache[stopId] = List.unmodifiable(sorted);
  }

  /// Numeric route ids first (numeric order), then the rest alphabetically.
  static int compareRouteNames(String a, String b) {
    final ai = int.tryParse(a);
    final bi = int.tryParse(b);
    if (ai != null && bi != null) return ai.compareTo(bi);
    if (ai != null) return -1;
    if (bi != null) return 1;
    return a.compareTo(b);
  }
```

Then add `_routesForStopCache.clear();` as the first line of `loadFromDirectory`. If `gtfs_models.dart` isn't already imported for `StopTimeRow`, import it.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/gtfs_routes_for_stop_test.dart`, then the full suite.

- [ ] **Step 5: Commit**

```bash
git add lib/data/gtfs/gtfs_repository.dart test/gtfs_routes_for_stop_test.dart
git commit -m "feat(gtfs): routes serving a stop, with a consistent route-name order"
```

---

### Task 4: Shell — floating BBNavBar

**Files:**
- Modify (rewrite): `lib/ui/shell/app_shell.dart`
- Modify: `test/kit/kit_boundary_test.dart` (remove `'lib/ui/shell/app_shell.dart'` from `_legacyAllowList`)
- Test: `test/ui/app_shell_test.dart`

**Interfaces:**
- Consumes: `BBNavBar`, `BBNavItem`, `BBIcons`, `serviceUpdatesProvider`.
- Produces: the unchanged constructor `AppShell({required StatefulNavigationShell navigationShell})`.

- [ ] **Step 1: Write the failing test** — `test/ui/app_shell_test.dart`:

```dart
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _alert = ServiceAlert(
  sourceIds: {'a'},
  header: 'Water Street Detour',
  description: '',
  cause: ServiceAlertCause.construction,
  effect: ServiceAlertEffect.detour,
  severity: ServiceAlertSeverity.warning,
  activePeriods: [],
  targets: [],
);

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/', builder: (_, _) => const Text('PICKER'), routes: [
                GoRoute(path: 'board/:id', builder: (_, s) => Text('BOARD ${s.pathParameters['id']}')),
              ]),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/map', builder: (_, _) => const Text('MAP'))]),
            StatefulShellBranch(routes: [GoRoute(path: '/alerts', builder: (_, _) => const Text('ALERTS'))]),
          ],
        ),
      ],
    );

Future<GoRouter> _pump(WidgetTester tester) async {
  final router = _router();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      serviceUpdatesProvider.overrideWith((ref) => Stream.value(ServiceUpdates(
            alerts: const [_alert],
            serviceStatus: null,
            fetchedAt: DateTime(2026, 10, 4),
            feedTimestamp: null,
          ))),
    ],
    child: MaterialApp.router(theme: BBTheme.light(), routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('shows the floating nav bar with Board / Map / Alerts and the alert count', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(find.byType(BBNavBar), findsOneWidget);
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.bySemanticsLabel('Alerts, 1 active'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tapping a tab switches branch', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.text('MAP'), findsOneWidget);
    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('ALERTS'), findsOneWidget);
  });

  testWidgets('re-tapping the current tab resets the branch to its root', (tester) async {
    final router = await _pump(tester);
    router.push('/board/1150');
    await tester.pumpAndSettle();
    expect(find.text('BOARD 1150'), findsOneWidget);
    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();
    expect(find.text('PICKER'), findsOneWidget);
  });

  testWidgets('map tab content sits above the bar; other tabs run under it', (tester) async {
    await _pump(tester);
    final barTop = tester.getTopLeft(find.byType(BBNavBar)).dy;
    expect(tester.getBottomLeft(find.text('PICKER')).dy, greaterThan(0));
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    final mapPadding = tester.widget<Padding>(
      find.ancestor(of: find.text('MAP'), matching: find.byType(Padding)).first,
    );
    expect((mapPadding.padding as EdgeInsets).bottom, greaterThan(0));
    expect(barTop, greaterThan(0));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/app_shell_test.dart`. Expected: FAIL. The legacy shell uses `NavigationBar` and the label `Bus Board`, so `find.byType(BBNavBar)` finds nothing.

- [ ] **Step 3: Rewrite `lib/ui/shell/app_shell.dart`**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../kit/kit.dart';

/// Tab shell: branch content with the floating Harbour nav bar on top.
/// Board and Alerts scroll under the bar (they reserve
/// [BBNavBar.reservedHeight] at the end of their lists). The legacy map
/// (rebuilt in Phase 3) is laid out above the bar so its controls stay
/// reachable.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _mapBranch = 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAlertCount =
        ref.watch(serviceUpdatesProvider).value?.activeAlertsAt(DateTime.now()).length ?? 0;
    final index = navigationShell.currentIndex;

    return ColoredBox(
      color: context.bb.colors.bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: index == _mapBranch ? BBNavBar.reservedHeight(context) : 0),
              child: navigationShell,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BBNavBar(
              items: [
                const BBNavItem(label: 'Board', icon: BBIcons.board),
                const BBNavItem(label: 'Map', icon: BBIcons.map),
                BBNavItem(label: 'Alerts', icon: BBIcons.alerts, badgeCount: activeAlertCount),
              ],
              currentIndex: index,
              onSelect: (i) => navigationShell.goBranch(i, initialLocation: i == index),
            ),
          ),
        ],
      ),
    );
  }
}
```

Then remove `'lib/ui/shell/app_shell.dart',` from `_legacyAllowList` in `test/kit/kit_boundary_test.dart`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/app_shell_test.dart test/kit/kit_boundary_test.dart test/widget_test.dart`, then the full suite.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/shell/app_shell.dart test/ui/app_shell_test.dart test/kit/kit_boundary_test.dart
git commit -m "feat(ui): floating Harbour nav bar shell"
```

---

### Task 5: Stop picker — screen, stop-number entry, near-me list

**Files:**
- Modify (rewrite): `lib/ui/stop_picker/stop_picker_screen.dart`, `lib/ui/stop_picker/stop_id_entry.dart`, `lib/ui/stop_picker/near_me_list.dart`
- Modify: `test/kit/kit_boundary_test.dart` (remove the three files)
- Test: `test/ui/stop_picker_test.dart`

**Interfaces:**
- Consumes:
  - Providers: `settingsProvider`, `gtfsRepositoryProvider`, `stopInfoProvider`, `nearestStopsProvider`
  - `GtfsRepository.routeShortNamesForStop` (Task 3)
  - Kit (Tasks 1–2)
- Produces: the unchanged constructors `StopPickerScreen()`, `StopIdEntry()` and `NearMeList()`.

- [ ] **Step 1: Write the failing test** — `test/ui/stop_picker_test.dart`:

```dart
import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/stop_picker/stop_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.57, stopLon: -52.73);

GtfsRepository _repo() {
  final repo = GtfsRepository();
  repo.stopsById['1150'] = _mun;
  repo.routesById['r10'] = const RouteInfo(routeId: 'r10', routeShortName: '10', routeLongName: '');
  repo.tripsById['t1'] = const TripInfo(tripId: 't1', routeId: 'r10', serviceId: 's', tripHeadsign: '', directionId: 0);
  repo.stopTimesByStopId['1150'] = const [
    StopTimeRow(tripId: 't1', arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1),
  ];
  return repo;
}

Future<void> _pump(
  WidgetTester tester, {
  required FutureOr<GtfsRepository> Function() gtfs,
  FutureOr<List<NearbyStop>> Function()? nearby,
  Map<String, Object> prefs = const {},
  double textScale = 1.0,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const StopPickerScreen(), routes: [
      GoRoute(path: 'board/:id', builder: (_, s) => Text('BOARD ${s.pathParameters['id']}')),
    ]),
    GoRoute(path: '/settings', builder: (_, _) => const Text('SETTINGS')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gtfsRepositoryProvider.overrideWith((ref) => gtfs()),
      nearestStopsProvider.overrideWith((ref) async => nearby == null ? const <NearbyStop>[] : await nearby()),
    ],
    child: MaterialApp.router(
      theme: BBTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('header, stop entry and near-me rows with route pills', (tester) async {
    await _pump(tester, gtfs: _repo, nearby: () => const [NearbyStop(stop: _mun, distanceMeters: 80)]);
    expect(find.text('Choose a stop'), findsOneWidget);
    expect(find.text('Stop number on the pole'), findsOneWidget);
    expect(find.text('MUN Centre'), findsOneWidget);
    expect(find.text('Stop 1150 · 80m'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Route 10')), findsWidgets);
  });

  testWidgets('stop entry validates and navigates (saving the stop first)', (tester) async {
    await _pump(tester, gtfs: _repo);
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(find.text('Please enter a stop ID'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '115');
    await tester.pump();
    expect(find.text('Please enter a stop ID'), findsNothing); // cleared on edit
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(find.text('Stop ID must be 4 digits'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1150');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.text('BOARD 1150'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('selectedStopId'), '1150');
  });

  testWidgets('tapping a near-me stop saves it and opens its board', (tester) async {
    await _pump(tester, gtfs: _repo, nearby: () => const [NearbyStop(stop: _mun, distanceMeters: 80)]);
    await tester.tap(find.text('MUN Centre'));
    await tester.pumpAndSettle();
    expect(find.text('BOARD 1150'), findsOneWidget);
  });

  testWidgets('last stop card opens the saved stop', (tester) async {
    await _pump(tester, gtfs: _repo, prefs: {'selectedStopId': '1150'});
    expect(find.text('Last stop'), findsOneWidget);
    await tester.tap(find.text('Last stop'));
    await tester.pumpAndSettle();
    expect(find.text('BOARD 1150'), findsOneWidget);
  });

  testWidgets('settings is reachable while GTFS is loading', (tester) async {
    final never = Completer<GtfsRepository>();
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const StopPickerScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const Text('SETTINGS')),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [gtfsRepositoryProvider.overrideWith((ref) => never.future)],
      child: MaterialApp.router(theme: BBTheme.light(), routerConfig: router),
    ));
    await tester.pump();
    expect(find.text('Loading schedule data...'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS'), findsOneWidget);
  });

  testWidgets('GTFS error shows retry', (tester) async {
    await _pump(tester, gtfs: () => Future<GtfsRepository>.error(Exception('offline')));
    expect(find.text('Failed to load schedule'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('near-me empty and error states', (tester) async {
    await _pump(tester, gtfs: _repo, nearby: () => const []);
    expect(find.text('No stops found within 800m.'), findsOneWidget);
    await _pump(tester, gtfs: _repo, nearby: () => Future<List<NearbyStop>>.error(Exception('gps off')));
    expect(find.text('Unable to get location'), findsOneWidget);
    expect(find.text('Please enable location services and grant permission.'), findsOneWidget);
  });

  testWidgets('no overflow at text scale 2.0 on a 320pt phone', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, gtfs: _repo, nearby: () => const [NearbyStop(stop: _mun, distanceMeters: 80)],
        prefs: {'selectedStopId': '1150'}, textScale: 2.0);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/stop_picker_test.dart`. Expected: FAIL (`Choose a stop` isn't found; the legacy title is `BusBoard NL`).

- [ ] **Step 3: Rewrite the three files**

`lib/ui/stop_picker/stop_picker_screen.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../kit/kit.dart';
import 'near_me_list.dart';
import 'stop_id_entry.dart';

class StopPickerScreen extends ConsumerWidget {
  const StopPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final gtfsAsync = ref.watch(gtfsRepositoryProvider);
    final bb = context.bb;

    return BBScaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: BBTopBar(
                title: 'Choose a stop',
                subtitle: "Metrobus · St. John's",
                large: true,
                actions: [
                  BBIconButton(icon: BBIcons.settings, semanticLabel: 'Settings', onPressed: () => context.push('/settings')),
                ],
              ),
            ),
            ...gtfsAsync.when(
              data: (_) => [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: BBSpace.screen),
                  sliver: SliverList.list(children: [
                    if (settings.selectedStopId != null) ...[
                      _LastStopCard(stopId: settings.selectedStopId!),
                      const SizedBox(height: BBSpace.xl),
                    ],
                    const StopIdEntry(),
                    const SizedBox(height: BBSpace.xl),
                    Row(children: [
                      const Expanded(child: BBDivider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: BBSpace.m),
                        child: Text('or', style: bb.text.caption),
                      ),
                      const Expanded(child: BBDivider()),
                    ]),
                    const SizedBox(height: BBSpace.xl),
                    const BBCard(padding: EdgeInsets.all(BBSpace.l), child: NearMeList()),
                  ]),
                ),
              ],
              loading: () => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const BBLoading(label: 'Loading schedule data...'),
                      const SizedBox(height: BBSpace.xs),
                      Text('Downloading GTFS feed from Metrobus', style: bb.text.caption),
                    ]),
                  ),
                ),
              ],
              error: (err, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: BBEmptyState(
                      icon: BBIcons.error,
                      tone: BBEmptyTone.error,
                      title: 'Failed to load schedule',
                      message: err.toString(),
                      action: BBButton(
                        label: 'Retry',
                        icon: BBIcons.refresh,
                        onPressed: () => ref.invalidate(gtfsRepositoryProvider),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(child: SizedBox(height: BBNavBar.reservedHeight(context) + BBSpace.l)),
          ],
        ),
      ),
    );
  }
}

class _LastStopCard extends ConsumerWidget {
  const _LastStopCard({required this.stopId});

  final String stopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final name = ref.watch(stopInfoProvider(stopId))?.stopName ?? 'Stop $stopId';
    return BBCard(
      onTap: () => context.push('/board/$stopId'),
      semanticLabel: 'Last stop, $name, stop $stopId',
      child: Row(children: [
        const BBIconTile(icon: BBIcons.history, tone: BBPillTone.live),
        const SizedBox(width: BBSpace.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Last stop', style: bb.text.caption),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: bb.text.headline),
          ]),
        ),
        Text('#$stopId', style: bb.text.label.copyWith(color: bb.colors.brandInk, fontSize: 15)),
        Icon(BBIcons.chevronRight, color: bb.colors.muted),
      ]),
    );
  }
}
```

`lib/ui/stop_picker/stop_id_entry.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../kit/kit.dart';

class StopIdEntry extends ConsumerStatefulWidget {
  const StopIdEntry({super.key});

  @override
  ConsumerState<StopIdEntry> createState() => _StopIdEntryState();
}

class _StopIdEntryState extends ConsumerState<StopIdEntry> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();

    if (text.isEmpty) {
      setState(() => _errorText = 'Please enter a stop ID');
      return;
    }

    if (text.length != 4 || int.tryParse(text) == null) {
      setState(() => _errorText = 'Stop ID must be 4 digits');
      return;
    }

    setState(() => _errorText = null);

    // Save and navigate
    ref.read(settingsProvider.notifier).setSelectedStop(text);
    context.push('/board/$text');
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Stop number', style: bb.text.label.copyWith(color: bb.colors.muted)),
        const SizedBox(height: BBSpace.s),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BBTextField(
                controller: _controller,
                focusNode: _focusNode,
                hint: 'Stop number on the pole',
                leadingIcon: BBIcons.pin,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.go,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                errorText: _errorText,
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: BBSpace.s),
            BBButton(label: 'Go', icon: BBIcons.search, onPressed: _submit),
          ],
        ),
      ],
    );
  }
}
```

`lib/ui/stop_picker/near_me_list.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/location/nearest_stop_service.dart';
import '../../state/providers.dart';
import '../kit/kit.dart';

class NearMeList extends ConsumerWidget {
  const NearMeList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final nearbyAsync = ref.watch(nearestStopsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Icon(BBIcons.nearMe, size: 20, color: bb.colors.liveInk),
          const SizedBox(width: BBSpace.s),
          Expanded(child: Semantics(header: true, child: Text('Near me', style: bb.text.headline))),
          nearbyAsync.when(
            loading: () => const SizedBox(width: 44, height: 44),
            error: (_, _) => const SizedBox.shrink(),
            data: (_) => BBIconButton(
              icon: BBIcons.refresh,
              semanticLabel: 'Refresh location',
              onPressed: () => ref.invalidate(nearestStopsProvider),
            ),
          ),
        ]),
        nearbyAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BBSpace.xxl),
            child: Center(child: BBLoading(label: 'Finding nearby stops...')),
          ),
          error: (_, _) => BBEmptyState(
            icon: BBIcons.locationOff,
            tone: BBEmptyTone.error,
            title: 'Unable to get location',
            message: 'Please enable location services and grant permission.',
            action: BBButton(
              label: 'Try again',
              icon: BBIcons.refresh,
              kind: BBButtonKind.quiet,
              onPressed: () => ref.invalidate(nearestStopsProvider),
            ),
          ),
          data: (stops) {
            if (stops.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(BBSpace.xxl),
                child: Text(
                  'No stops found within 800m.',
                  textAlign: TextAlign.center,
                  style: bb.text.body.copyWith(color: bb.colors.muted),
                ),
              );
            }
            return Column(children: [
              for (var i = 0; i < stops.length; i++) ...[
                if (i > 0) const BBDivider(indent: 52),
                _NearbyStopTile(nearby: stops[i]),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

class _NearbyStopTile extends ConsumerWidget {
  const _NearbyStopTile({required this.nearby});

  final NearbyStop nearby;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final stop = nearby.stop;
    final routes =
        ref.watch(gtfsRepositoryProvider).asData?.value.routeShortNamesForStop(stop.stopId) ?? const <String>[];
    final routesText = routes.isEmpty ? '' : ', routes ${routes.join(', ')}';
    return BBPressable(
      semanticLabel: '${stop.stopName}, stop ${stop.stopId}, ${nearby.distanceDisplay} away$routesText',
      onTap: () {
        ref.read(settingsProvider.notifier).setSelectedStop(stop.stopId);
        context.push('/board/${stop.stopId}');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BBSpace.m),
        child: Row(children: [
          const BBIconTile(icon: BBIcons.bus),
          const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(stop.stopName, maxLines: 1, overflow: TextOverflow.ellipsis, style: bb.text.headline),
              Text('Stop ${stop.stopId} · ${nearby.distanceDisplay}', style: bb.text.caption),
              if (routes.isNotEmpty) ...[
                const SizedBox(height: BBSpace.xs),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final r in routes.take(6))
                    RouteBadge(routeNumber: int.tryParse(r) ?? 0, label: r, size: RouteBadgeSize.compact),
                ]),
              ],
            ]),
          ),
          Icon(BBIcons.chevronRight, color: bb.colors.muted),
        ]),
      ),
    );
  }
}
```

If `routeShortNamesForStop` is called on a nullable `asData?.value`, keep the `?.` chain so that a GTFS load that hasn't finished yields no pills.

Remove the three stop-picker files from `_legacyAllowList`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/stop_picker_test.dart test/kit/kit_boundary_test.dart`, then the full suite.

If `find.bySemanticsLabel(RegExp('Route 10'))` fails because the tile's `semanticLabel` excludes descendants, assert the tile label instead: `find.bySemanticsLabel(RegExp('MUN Centre, stop 1150, 80m away, routes 10'))`. Separately assert `find.byType(RouteBadge)` `findsOneWidget`. Don't drop the route check.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/stop_picker test/ui/stop_picker_test.dart test/kit/kit_boundary_test.dart
git commit -m "feat(ui): Harbour stop picker with stop-number entry and near-me route pills"
```

---

### Task 6: Board — arrival row

**Files:**
- Modify (rewrite): `lib/ui/board/arrival_row_tile.dart`
- Modify: `test/kit/kit_boundary_test.dart` (remove `'lib/ui/board/arrival_row_tile.dart'`)
- Test: `test/ui/arrival_row_tile_test.dart`

**Interfaces:**
- Consumes: `ArrivalRow`, `LiveStatus`, kit.
- Produces:
  - `ArrivalRowTile({required ArrivalRow arrival})`
  - `static (String, BBPillTone) ArrivalRowTile.statusOf(ArrivalRow)`
  - `static String ArrivalRowTile.semanticsLabel(ArrivalRow)`
  - `static const int ArrivalRowTile.soonThresholdMinutes = 5`

- [ ] **Step 1: Write the failing test** — `test/ui/arrival_row_tile_test.dart`:

```dart
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kit/kit_test_helpers.dart';

ArrivalRow _row({
  int minutes = 4,
  bool isLive = false,
  bool isEnhanced = false,
  LiveStatus? status,
  String? vehicle,
  String? routeRun,
  String? near,
  GtfsTime? predicted,
}) =>
    ArrivalRow(
      routeShortName: '29',
      headsign: 'Signal Hill Rd',
      scheduledTime: GtfsTime.parse('09:52:00'),
      predictedTime: predicted,
      minutesAway: minutes,
      liveStatus: status,
      isLive: isLive,
      tripId: 't',
      vehicleNumber: vehicle,
      isEnhanced: isEnhanced,
      routeRun: routeRun,
      currentLocation: near,
    );

void main() {
  test('status matrix in plain words', () {
    expect(ArrivalRowTile.statusOf(_row(isEnhanced: true, isLive: true)), ('Live', BBPillTone.live));
    expect(ArrivalRowTile.statusOf(_row(isEnhanced: true)), ('Scheduled', BBPillTone.neutral));
    expect(ArrivalRowTile.statusOf(_row(isLive: true, status: LiveStatus.ahead)), ('Early', BBPillTone.live));
    expect(ArrivalRowTile.statusOf(_row(isLive: true, status: LiveStatus.behind)), ('Late', BBPillTone.warn));
    expect(ArrivalRowTile.statusOf(_row(isLive: true, status: LiveStatus.onTime)), ('On time', BBPillTone.live));
    expect(ArrivalRowTile.statusOf(_row(isLive: true)), ('Live', BBPillTone.live));
    expect(ArrivalRowTile.statusOf(_row()), ('Scheduled', BBPillTone.neutral));
  });

  test('screen-reader sentence', () {
    expect(ArrivalRowTile.semanticsLabel(_row(isEnhanced: true, isLive: true, minutes: 4)),
        'Route 29 Signal Hill Rd, live, 4 minutes');
    expect(ArrivalRowTile.semanticsLabel(_row(minutes: 1)), 'Route 29 Signal Hill Rd, scheduled, 1 minute');
    expect(ArrivalRowTile.semanticsLabel(_row(minutes: 0)), 'Route 29 Signal Hill Rd, scheduled, now');
  });

  testWidgets('live row shows run/bus, near, exp and struck-through sched', (tester) async {
    await tester.pumpWidget(kitHost(ArrivalRowTile(
      arrival: _row(isLive: true, status: LiveStatus.behind, vehicle: '2134', routeRun: '29-1', near: 'MUN Centre',
          predicted: GtfsTime.parse('09:55:00')),
    )));
    expect(find.text('Late'), findsOneWidget);
    expect(find.text('29-1 · Bus 2134'), findsOneWidget);
    expect(find.text('Near MUN Centre'), findsOneWidget);
    expect(find.text('exp 09:55'), findsOneWidget);
    final sched = tester.widget<Text>(find.text('sched 09:52'));
    expect(sched.style!.decoration, TextDecoration.lineThrough);
  });

  testWidgets('schedule-only row shows just the scheduled time', (tester) async {
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(vehicle: '2134', near: 'X'))));
    expect(find.text('09:52'), findsOneWidget);
    expect(find.textContaining('Bus'), findsNothing);
    expect(find.textContaining('Near'), findsNothing);
    expect(find.textContaining('exp'), findsNothing);
  });

  testWidgets('minutes: soon colour at <=5, ink above; Now with no unit', (tester) async {
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(minutes: 5))));
    expect(tester.widget<Text>(find.text('5')).style!.color, BBColors.light.soon);
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(minutes: 6))));
    expect(tester.widget<Text>(find.text('6')).style!.color, BBColors.light.ink);
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(minutes: 0))));
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('min'), findsNothing);
  });

  testWidgets('route badge uses the route colour and the row is one semantics node', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(ArrivalRowTile(arrival: _row(isEnhanced: true, isLive: true))));
    expect(find.byType(RouteBadge), findsOneWidget);
    expect(find.bySemanticsLabel('Route 29 Signal Hill Rd, live, 4 minutes'), findsOneWidget);
    expect(find.bySemanticsLabel('Signal Hill Rd'), findsNothing);
    handle.dispose();
  });

  testWidgets('no overflow at text scale 2.0 on 320pt', (tester) async {
    await tester.pumpWidget(kitHost(
      ArrivalRowTile(arrival: _row(isLive: true, status: LiveStatus.onTime, vehicle: '2134', routeRun: '29-1',
          near: 'Elizabeth Ave at Allandale Rd', predicted: GtfsTime.parse('09:55:00'), minutes: 15)),
      textScale: 2.0,
      width: 320,
    ));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/arrival_row_tile_test.dart`. Expected: compile errors (`statusOf` and `semanticsLabel` are undefined).

- [ ] **Step 3: Rewrite `lib/ui/board/arrival_row_tile.dart`**

```dart
import 'package:flutter/widgets.dart';

import '../../domain/arrival/arrival_models.dart';
import '../kit/kit.dart';

/// One departure on the Board: route badge · destination + status · minutes.
class ArrivalRowTile extends StatelessWidget {
  const ArrivalRowTile({super.key, required this.arrival});

  final ArrivalRow arrival;

  /// Minutes at or below which the countdown uses the `soon` colour.
  static const int soonThresholdMinutes = 5;

  /// Plain-words status pill for a row (spec §6.2).
  static (String, BBPillTone) statusOf(ArrivalRow a) {
    if (a.isEnhanced) {
      return a.isLive ? ('Live', BBPillTone.live) : ('Scheduled', BBPillTone.neutral);
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

  /// One sentence for screen readers, e.g. "Route 29 Signal Hill Rd, live, 4 minutes".
  static String semanticsLabel(ArrivalRow a) {
    final (status, _) = statusOf(a);
    final when = a.minutesAway <= 0
        ? 'now'
        : a.minutesAway == 1
            ? '1 minute'
            : '${a.minutesAway} minutes';
    return 'Route ${a.routeShortName} ${a.headsign}, ${status.toLowerCase()}, $when';
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final a = arrival;
    final (status, tone) = statusOf(a);
    final meta = [
      if (a.routeRun != null) a.routeRun!,
      if (a.isLive && a.vehicleNumber != null) 'Bus ${a.vehicleNumber}',
    ].join(' · ');
    final showPredicted = a.isLive && a.predictedTime != null;
    final timeLine = showPredicted ? 'exp ${a.displayTime.toDisplayString()}' : a.scheduledDisplay;
    final showSched = showPredicted && a.scheduledTime != a.predictedTime;
    final soon = a.minutesAway <= soonThresholdMinutes;

    return Semantics(
      label: semanticsLabel(a),
      excludeSemantics: true,
      child: BBCard(
        child: Row(
          children: [
            RouteBadge(routeNumber: int.tryParse(a.routeShortName) ?? 0, label: a.routeShortName),
            const SizedBox(width: BBSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.headsign, maxLines: 1, overflow: TextOverflow.ellipsis, style: bb.text.headline),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      BBPill(label: status, tone: tone, leadingDot: tone == BBPillTone.live),
                      if (meta.isNotEmpty) Text(meta, style: bb.text.caption),
                    ],
                  ),
                  if (a.isLive && (a.currentLocation?.isNotEmpty ?? false))
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Near ${a.currentLocation}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: bb.text.caption,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: BBSpace.m),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  a.minutesAway <= 0 ? 'Now' : '${a.minutesAway}',
                  style: bb.text.minutes.copyWith(color: soon ? bb.colors.soon : bb.colors.ink),
                ),
                if (a.minutesAway > 0) Text('min', style: bb.text.minutesUnit),
                const SizedBox(height: 2),
                Text(timeLine, style: bb.text.caption),
                if (showSched)
                  Text(
                    'sched ${a.scheduledDisplay}',
                    style: bb.text.caption.copyWith(
                      decoration: TextDecoration.lineThrough,
                      decorationColor: bb.colors.muted,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

Remove `'lib/ui/board/arrival_row_tile.dart'` from `_legacyAllowList`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/arrival_row_tile_test.dart test/kit/kit_boundary_test.dart`, then the full suite.

`GtfsTime.toDisplayString()` formats `HH:MM`. If the `exp`/`sched` text the test expects differs from what it renders (for example a 24-hour wrap), assert on whatever `toDisplayString()` produces for those inputs, and note it in the report.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/board/arrival_row_tile.dart test/ui/arrival_row_tile_test.dart test/kit/kit_boundary_test.dart
git commit -m "feat(ui): Harbour arrival row with plain-words status and one-sentence semantics"
```

---

### Task 7: Board — screen

**Files:**
- Modify: `lib/ui/board/arrival_board_screen.dart`. Keep `_refreshData`, `_startTimer`, the lifecycle code and `_relevantAlerts` verbatim. Rewrite `build` and `_buildArrivalsList`. Remove the Material import and the hard-coded colours.
- Modify: `test/kit/kit_boundary_test.dart` (remove `'lib/ui/board/arrival_board_screen.dart'`)
- Test: `test/ui/arrival_board_screen_test.dart`

**Interfaces:**
- Consumes:
  - `ArrivalRowTile` (Task 6) and `ServiceAlertCard` (its current constructor, which Task 8 preserves)
  - kit
  - providers: `gtfsRepositoryProvider`, `timetrackApiProvider`, `metrobusMobileApiProvider`, `serviceUpdatesProvider`, `stopInfoProvider`, `settingsProvider`
- Produces: the unchanged constructor `ArrivalBoardScreen({required String stopId})`.

- [ ] **Step 1: Write the failing test** — `test/ui/arrival_board_screen_test.dart`:

```dart
import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/board/arrival_board_screen.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _failing = MockClient((_) async => http.Response('down', 500));

ServiceAlert _alert(String header) => ServiceAlert(
      sourceIds: {header},
      header: header,
      description: '',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: const [],
      targets: const [ServiceAlertTarget(stopId: '1150')],
    );

GtfsRepository _repo() =>
    GtfsRepository()..stopsById['1150'] = const StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 0, stopLon: 0);

Future<void> _pump(WidgetTester tester, {GtfsRepository? repo, List<ServiceAlert> alerts = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final router = GoRouter(initialLocation: '/board/1150', routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('PICKER'), routes: [
      GoRoute(path: 'board/:id', builder: (_, s) => ArrivalBoardScreen(stopId: s.pathParameters['id']!)),
    ]),
    GoRoute(path: '/settings', builder: (_, _) => const Text('SETTINGS')),
    GoRoute(path: '/alerts', builder: (_, _) => const Text('ALERTS')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async {
        if (repo == null) throw Exception('not loaded');
        return repo;
      }),
      timetrackApiProvider.overrideWithValue(TimeTrackApi(client: _failing)),
      metrobusMobileApiProvider.overrideWithValue(MetrobusMobileApi(client: _failing)),
      serviceUpdatesProvider.overrideWith((ref) => Stream.value(ServiceUpdates(
            alerts: alerts,
            serviceStatus: null,
            fetchedAt: DateTime(2026, 10, 4),
            feedTimestamp: null,
          ))),
    ],
    child: MaterialApp.router(theme: BBTheme.light(), routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  testWidgets('header: stop pill, name, Change, settings, status line', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, repo: _repo());
    expect(find.text('STOP 1150'), findsOneWidget);
    expect(find.text('MUN Centre'), findsOneWidget);
    expect(find.textContaining('Live feed error · showing schedule'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('PICKER'), findsOneWidget);
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('empty board is pull-to-refresh-able', (tester) async {
    await _pump(tester, repo: _repo());
    expect(find.text('No upcoming departures'), findsOneWidget);
    expect(find.text('There are no scheduled departures\nfrom this stop right now.'), findsOneWidget);
    expect(find.byType(BBRefresh), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('schedule not loaded shows the error state', (tester) async {
    await _pump(tester);
    expect(find.text('Schedule data not loaded'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('relevant alerts: compact card + "more" link go to Alerts', (tester) async {
    await _pump(tester, repo: _repo(), alerts: [_alert('Water Street Detour'), _alert('Second')]);
    expect(find.text('Water Street Detour'), findsOneWidget);
    expect(find.text('1 more relevant alert'), findsOneWidget);
    await tester.tap(find.text('1 more relevant alert'));
    await tester.pumpAndSettle();
    expect(find.text('ALERTS'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('leaving the board cancels its refresh timer cleanly', (tester) async {
    await _pump(tester, repo: _repo());
    await _unmount(tester);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/arrival_board_screen_test.dart`. Expected: FAIL (`STOP 1150`, `Change` and the new status text aren't found).

- [ ] **Step 3: Rewrite the UI parts of `lib/ui/board/arrival_board_screen.dart`**

- Replace `import 'package:flutter/material.dart';` with `import 'package:flutter/widgets.dart';`, and add `import '../kit/kit.dart';`. Keep `intl`, Riverpod, go_router and the model/provider/service imports.
- Keep the State class's fields, `initState`, `dispose`, `didChangeAppLifecycleState`, `_startTimer`, `_refreshData` and `_relevantAlerts` **unchanged**.
- Replace `build` and `_buildArrivalsList` with:

```dart
  @override
  Widget build(BuildContext context) {
    ref.listen<int>(settingsProvider.select((s) => s.refreshIntervalSeconds), (prev, next) {
      if (prev != next) _startTimer();
    });

    final bb = context.bb;
    final stopInfo = ref.watch(stopInfoProvider(widget.stopId));
    final stopName = stopInfo?.stopName ?? 'Stop ${widget.stopId}';
    final relevantAlerts = _relevantAlerts(ref.watch(serviceUpdatesProvider).value);
    final updated = DateFormat('HH:mm:ss').format(_lastUpdate);
    final statusText =
        _liveAvailable ? 'Live · updated $updated' : '${_liveIssue ?? 'Live unavailable'} · showing schedule';

    return BBScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.s, BBSpace.xs, 0),
            child: Row(children: [
              BBPill(
                label: 'STOP ${widget.stopId}',
                background: bb.colors.ink,
                foreground: bb.colors.bg,
              ),
              const Spacer(),
              BBButton(label: 'Change', kind: BBButtonKind.quiet, onPressed: () => context.pop()),
              BBIconButton(
                icon: BBIcons.settings,
                semanticLabel: 'Settings',
                onPressed: () => context.push('/settings'),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.xs, BBSpace.screen, 0),
            child: Semantics(
              header: true,
              child: Text(stopName, maxLines: 2, overflow: TextOverflow.ellipsis, style: bb.text.display),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.xs, BBSpace.screen, BBSpace.s),
            child: Semantics(
              liveRegion: true,
              child: Row(children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _liveAvailable ? bb.colors.live : bb.colors.muted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: BBSpace.s),
                Expanded(child: Text(statusText, style: bb.text.caption)),
              ]),
            ),
          ),
          if (relevantAlerts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.xs, BBSpace.screen, BBSpace.xs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ServiceAlertCard(
                  alert: relevantAlerts.first,
                  stopNames: stopInfo == null ? const {} : {widget.stopId: stopInfo.stopName},
                  compact: true,
                  onTap: () => context.go('/alerts'),
                ),
                if (relevantAlerts.length > 1)
                  BBButton(
                    label:
                        '${relevantAlerts.length - 1} more relevant ${relevantAlerts.length == 2 ? "alert" : "alerts"}',
                    kind: BBButtonKind.quiet,
                    onPressed: () => context.go('/alerts'),
                  ),
              ]),
            ),
          Expanded(child: BBRefresh(onRefresh: _refreshData, child: _buildArrivalsList(context))),
        ],
      ),
    );
  }

  Widget _buildArrivalsList(BuildContext context) {
    final bottom = BBNavBar.reservedHeight(context) + BBSpace.l;

    // Every state is a scrollable list so pull-to-refresh always works.
    Widget centered(Widget child) => ListView(
          padding: EdgeInsets.only(bottom: bottom),
          children: [const SizedBox(height: 64), Center(child: child)],
        );

    if (_loading) return centered(const BBLoading(label: 'Loading departures...'));
    if (_error != null) {
      return centered(BBEmptyState(icon: BBIcons.error, tone: BBEmptyTone.error, title: _error!));
    }
    if (_arrivals.isEmpty) {
      return centered(const BBEmptyState(
        icon: BBIcons.schedule,
        title: 'No upcoming departures',
        message: 'There are no scheduled departures\nfrom this stop right now.',
      ));
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(BBSpace.screen, BBSpace.s, BBSpace.screen, bottom),
      itemCount: _arrivals.length,
      separatorBuilder: (_, _) => const SizedBox(height: BBSpace.s),
      itemBuilder: (_, index) => ArrivalRowTile(arrival: _arrivals[index]),
    );
  }
```

`Container(... decoration: BoxDecoration(...))` and `Spacer` are widgets-layer and allowed. Remove the file from `_legacyAllowList`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/arrival_board_screen_test.dart test/kit/kit_boundary_test.dart`, then the full suite.

If a test reports "A Timer is still pending", make sure `_unmount` runs. The board's `Timer.periodic` is cancelled in `dispose`, and the `pump(6 s)` lets the outstanding HTTP futures complete. If `ServiceAlertCard` still fails to build under the guard before Task 8, it is still allow-listed and Material-based, which is fine. It renders under `BBTheme`.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/board/arrival_board_screen.dart test/ui/arrival_board_screen_test.dart test/kit/kit_boundary_test.dart
git commit -m "feat(ui): Harbour board header, status line and always-refreshable list"
```

---

### Task 8: Alerts — card and screen

**Files:**
- Modify (rewrite): `lib/ui/alerts/service_alert_card.dart`, `lib/ui/alerts/alerts_screen.dart`
- Modify: `test/service_alert_card_test.dart`. Host it in `MaterialApp(theme: BBTheme.light(), home: ...)` instead of a bare `MaterialApp` + `Scaffold`, and keep all its assertions.
- Modify: `test/kit/kit_boundary_test.dart` (remove both alerts files)
- Test: `test/ui/alerts_test.dart`

**Interfaces:**
- Consumes: kit, `GtfsRepository.compareRouteNames` (Task 3), `serviceUpdatesProvider`, `gtfsRepositoryProvider`, `LegalCopy`.
- Produces:
  - The **unchanged** constructor `ServiceAlertCard({required ServiceAlert alert, Map<String, String> stopNames = const {}, bool compact = false, VoidCallback? onTap})`. The map sheets and the board rely on it.
  - `static BBPillTone ServiceAlertCard.toneOf(ServiceAlert)`
  - `static IconData ServiceAlertCard.iconOf(ServiceAlert)`
  - `static String? ServiceAlertCard.periodLabel(ServiceAlert, DateTime now)`
  - `AlertsScreen()`

- [ ] **Step 1: Write the failing test** — `test/ui/alerts_test.dart`:

```dart
import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/alerts/service_alert_card.dart';
import 'package:busboard_nl/ui/copy/legal_copy.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceAlert _alert(
  String header, {
  ServiceAlertEffect effect = ServiceAlertEffect.detour,
  ServiceAlertSeverity severity = ServiceAlertSeverity.warning,
  List<ServiceAlertPeriod> periods = const [],
  List<ServiceAlertTarget> targets = const [],
  String description = '',
}) =>
    ServiceAlert(
      sourceIds: {header},
      header: header,
      description: description,
      cause: ServiceAlertCause.construction,
      effect: effect,
      severity: severity,
      activePeriods: periods,
      targets: targets,
    );

final _now = DateTime.now();

Future<void> _pumpScreen(WidgetTester tester, List<ServiceAlert> alerts) async {
  final repo = GtfsRepository()
    ..stopsById['3080'] = const StopInfo(stopId: '3080', stopName: 'Freshwater Rd', stopLat: 0, stopLon: 0);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => repo),
      serviceUpdatesProvider.overrideWith((ref) => Stream.value(ServiceUpdates(
            alerts: alerts,
            serviceStatus: const MetrobusServiceStatus(
              serviceOperating: true, serviceId: '1', day: 'Weekday', message: 'Weekday service operating'),
            fetchedAt: _now,
            feedTimestamp: null,
          ))),
    ],
    child: MaterialApp(theme: BBTheme.light(), home: const AlertsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('tone and icon mapping', () {
    expect(ServiceAlertCard.toneOf(_alert('a', effect: ServiceAlertEffect.noService, severity: ServiceAlertSeverity.info)),
        BBPillTone.danger);
    expect(ServiceAlertCard.toneOf(_alert('a', severity: ServiceAlertSeverity.severe, effect: ServiceAlertEffect.other)),
        BBPillTone.danger);
    expect(ServiceAlertCard.toneOf(_alert('a')), BBPillTone.warn);
    expect(ServiceAlertCard.toneOf(_alert('a', effect: ServiceAlertEffect.other, severity: ServiceAlertSeverity.info)),
        BBPillTone.brand);
    expect(ServiceAlertCard.iconOf(_alert('a')), BBIcons.detour);
    expect(ServiceAlertCard.iconOf(_alert('a', effect: ServiceAlertEffect.unknown)), BBIcons.alerts);
  });

  test('period label: starts / until / active now / none', () {
    final now = DateTime(2026, 10, 4, 12);
    expect(ServiceAlertCard.periodLabel(_alert('a'), now), isNull);
    expect(ServiceAlertCard.periodLabel(_alert('a', periods: [ServiceAlertPeriod(start: DateTime(2026, 10, 5, 7, 10))]), now),
        'Starts Oct 5, 7:10 AM');
    expect(ServiceAlertCard.periodLabel(_alert('a', periods: [ServiceAlertPeriod(end: DateTime(2026, 11, 1, 12, 44))]), now),
        'Until Nov 1, 12:44 PM');
    expect(ServiceAlertCard.periodLabel(_alert('a', periods: [ServiceAlertPeriod(start: DateTime(2026, 1, 1))]), now),
        'Active now');
  });

  testWidgets('screen: status card, active section, routes and stops, footer', (tester) async {
    await _pumpScreen(tester, [
      _alert('Water Street Detour',
          description: 'Routes 3 and 10 use Harbour Drive.',
          targets: const [ServiceAlertTarget(routeId: '10'), ServiceAlertTarget(routeId: '3'), ServiceAlertTarget(stopId: '3080'), ServiceAlertTarget(stopId: '9999')]),
    ]);
    expect(find.text('Service alerts'), findsOneWidget);
    expect(find.text('Weekday service operating'), findsOneWidget);
    expect(find.text('Active now'), findsOneWidget);
    expect(find.text('Water Street Detour'), findsOneWidget);
    expect(find.byType(RouteBadge), findsNWidgets(2));
    expect(find.text('Freshwater Rd · 3080'), findsOneWidget);
    expect(find.text('Stop 9999'), findsOneWidget);
    expect(find.text('Routes 3 and 10 use Harbour Drive.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text(LegalCopy.footer), 200);
    expect(find.text(LegalCopy.footer), findsOneWidget);
  });

  testWidgets('no active alerts card; ended alerts are not "Upcoming"', (tester) async {
    await _pumpScreen(tester, [
      _alert('Old detour', periods: [ServiceAlertPeriod(start: DateTime(2020), end: DateTime(2020, 2))]),
      _alert('Future detour', periods: [ServiceAlertPeriod(start: _now.add(const Duration(days: 2)))]),
    ]);
    expect(find.text('No active service alerts.'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Future detour'), findsOneWidget);
    expect(find.text('Old detour'), findsNothing);
  });

  testWidgets('error state with retry', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
        serviceUpdatesProvider.overrideWith((ref) => Stream<ServiceUpdates>.error(Exception('offline'))),
      ],
      child: MaterialApp(theme: BBTheme.light(), home: const AlertsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Could not load service alerts'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('compact tappable card shows a chevron and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: BBTheme.light(),
      home: Center(child: ServiceAlertCard(alert: _alert('Detour'), compact: true, onTap: () => taps++)),
    ));
    expect(find.byIcon(BBIcons.chevronRight), findsOneWidget);
    await tester.tap(find.text('Detour'));
    expect(taps, 1);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/alerts_test.dart`. Expected: compile errors (`toneOf`, `iconOf` and `periodLabel` are undefined).

- [ ] **Step 3: Rewrite both files**

`lib/ui/alerts/service_alert_card.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../data/gtfs/gtfs_repository.dart';
import '../../data/realtime/service_alert_models.dart';
import '../kit/kit.dart';

/// One service alert. [compact] is the single-line-ish variant used on the
/// board and map sheets; [onTap] adds a chevron.
class ServiceAlertCard extends StatelessWidget {
  const ServiceAlertCard({
    super.key,
    required this.alert,
    this.stopNames = const {},
    this.compact = false,
    this.onTap,
  });

  final ServiceAlert alert;
  final Map<String, String> stopNames;
  final bool compact;
  final VoidCallback? onTap;

  static BBPillTone toneOf(ServiceAlert a) {
    if (a.severity == ServiceAlertSeverity.severe || a.effect == ServiceAlertEffect.noService) {
      return BBPillTone.danger;
    }
    if (a.effect == ServiceAlertEffect.detour ||
        a.effect == ServiceAlertEffect.significantDelays ||
        a.severity == ServiceAlertSeverity.warning) {
      return BBPillTone.warn;
    }
    return BBPillTone.brand;
  }

  static IconData iconOf(ServiceAlert a) => switch (a.effect) {
        ServiceAlertEffect.detour => BBIcons.detour,
        ServiceAlertEffect.noService => BBIcons.noService,
        ServiceAlertEffect.reducedService => BBIcons.reducedService,
        ServiceAlertEffect.significantDelays => BBIcons.schedule,
        ServiceAlertEffect.stopMoved => BBIcons.stopMoved,
        ServiceAlertEffect.accessibilityIssue => BBIcons.accessible,
        ServiceAlertEffect.additionalService => BBIcons.additionalService,
        _ => BBIcons.alerts,
      };

  static String? periodLabel(ServiceAlert a, DateTime now) {
    if (a.activePeriods.isEmpty) return null;
    final starts = a.activePeriods.map((p) => p.start).whereType<DateTime>();
    final ends = a.activePeriods.map((p) => p.end).whereType<DateTime>().toList()..sort();
    final format = DateFormat('MMM d, h:mm a');
    final nextStart = starts.where((s) => s.isAfter(now)).firstOrNull;
    if (nextStart != null) return 'Starts ${format.format(nextStart)}';
    if (ends.isNotEmpty) return 'Until ${format.format(ends.last)}';
    return 'Active now';
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final tone = toneOf(alert);
    final title = alert.header.isNotEmpty ? alert.header : alert.effect.label;
    final routes = alert.routeIds.toList()..sort(GtfsRepository.compareRouteNames);
    final period = compact ? null : periodLabel(alert, DateTime.now());

    return BBCard(
      onTap: onTap,
      padding: EdgeInsets.all(compact ? BBSpace.m : BBSpace.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BBIconTile(icon: iconOf(alert), tone: tone, size: compact ? 34 : 42),
          const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: compact ? 2 : null,
                      overflow: compact ? TextOverflow.ellipsis : TextOverflow.visible,
                      style: compact ? bb.text.label.copyWith(fontSize: 14) : bb.text.headline,
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: BBSpace.s),
                    Icon(BBIcons.chevronRight, size: 20, color: bb.colors.muted),
                  ],
                ]),
                const SizedBox(height: 5),
                Wrap(spacing: 6, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  BBPill(label: alert.effect.label, tone: tone),
                  for (final route in routes)
                    RouteBadge(routeNumber: int.tryParse(route) ?? 0, label: route, size: RouteBadgeSize.compact),
                  for (final stop in alert.stopIds)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 230),
                      child: BBPill(
                        label: stopNames[stop] == null ? 'Stop $stop' : '${stopNames[stop]} · $stop',
                        tone: BBPillTone.brand,
                        wrap: true,
                      ),
                    ),
                ]),
                if (!compact && alert.description.isNotEmpty) ...[
                  const SizedBox(height: BBSpace.m),
                  Text(alert.description, style: bb.text.body.copyWith(color: bb.colors.muted)),
                ],
                if (period != null) ...[
                  const SizedBox(height: BBSpace.m),
                  Row(children: [
                    Icon(BBIcons.schedule, size: 14, color: bb.colors.muted),
                    const SizedBox(width: 6),
                    Text(period, style: bb.text.caption),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

`lib/ui/alerts/alerts_screen.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/realtime/service_alert_models.dart';
import '../../state/providers.dart';
import '../copy/legal_copy.dart';
import '../kit/kit.dart';
import 'service_alert_card.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updatesAsync = ref.watch(serviceUpdatesProvider);
    return BBScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BBTopBar(
            title: 'Service alerts',
            large: true,
            actions: [
              BBIconButton(icon: BBIcons.settings, semanticLabel: 'Settings', onPressed: () => context.push('/settings')),
            ],
          ),
          Expanded(
            child: updatesAsync.when(
              loading: () => const Center(child: BBLoading(label: 'Loading service alerts...')),
              error: (error, _) => Center(
                child: BBEmptyState(
                  icon: BBIcons.offline,
                  tone: BBEmptyTone.error,
                  title: 'Could not load service alerts',
                  message: error.toString(),
                  action: BBButton(
                    label: 'Retry',
                    icon: BBIcons.refresh,
                    onPressed: () => ref.invalidate(serviceUpdatesProvider),
                  ),
                ),
              ),
              data: (updates) => _AlertsContent(updates: updates),
            ),
          ),
        ],
      ),
    );
  }
}

bool _hasEnded(ServiceAlert a, DateTime now) =>
    a.activePeriods.isNotEmpty && a.activePeriods.every((p) => p.hasEndedBefore(now));

class _AlertsContent extends ConsumerWidget {
  const _AlertsContent({required this.updates});

  final ServiceUpdates updates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final now = DateTime.now();
    final active = updates.activeAlertsAt(now);
    final upcoming = updates.alerts.where((a) => !a.isActiveAt(now) && !_hasEnded(a, now)).toList();
    final repo = ref.watch(gtfsRepositoryProvider).asData?.value;
    final stopNames = <String, String>{
      if (repo != null)
        for (final alert in updates.alerts)
          for (final stopId in alert.stopIds)
            if (repo.stopsById[stopId] != null) stopId: repo.stopsById[stopId]!.stopName,
    };

    List<Widget> cards(List<ServiceAlert> alerts) => [
          for (var i = 0; i < alerts.length; i++) ...[
            if (i > 0) const SizedBox(height: BBSpace.m),
            ServiceAlertCard(alert: alerts[i], stopNames: stopNames),
          ],
        ];

    return BBRefresh(
      onRefresh: () async {
        ref.invalidate(serviceUpdatesProvider);
        await ref.read(serviceUpdatesProvider.future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          BBSpace.screen, BBSpace.s, BBSpace.screen, BBNavBar.reservedHeight(context) + BBSpace.l),
        children: [
          _ServiceStatusCard(status: updates.serviceStatus, fetchedAt: updates.feedTimestamp ?? updates.fetchedAt),
          const SizedBox(height: BBSpace.xl),
          BBSectionHeader(
            title: 'Active now',
            count: active.length,
            countTone: active.isEmpty ? BBPillTone.live : BBPillTone.danger,
          ),
          const SizedBox(height: BBSpace.m),
          if (active.isEmpty)
            BBCard(
              padding: const EdgeInsets.all(BBSpace.xl),
              child: Row(children: [
                Icon(BBIcons.checkCircle, color: bb.colors.liveInk),
                const SizedBox(width: BBSpace.m),
                Expanded(child: Text('No active service alerts.', style: bb.text.body)),
              ]),
            )
          else
            ...cards(active),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: BBSpace.xxl),
            BBSectionHeader(title: 'Upcoming', count: upcoming.length),
            const SizedBox(height: BBSpace.m),
            ...cards(upcoming),
          ],
          const SizedBox(height: BBSpace.xl),
          Text(LegalCopy.footer, textAlign: TextAlign.center, style: bb.text.caption),
        ],
      ),
    );
  }
}

class _ServiceStatusCard extends StatelessWidget {
  const _ServiceStatusCard({required this.status, required this.fetchedAt});

  final MetrobusServiceStatus? status;
  final DateTime fetchedAt;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final stopped = status?.serviceOperating == false;
    final title = (status?.message.isNotEmpty ?? false) ? status!.message : 'Metrobus service status';
    return BBCard(
      child: Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: stopped ? bb.colors.dangerInk : bb.colors.live, shape: BoxShape.circle),
        ),
        const SizedBox(width: BBSpace.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: bb.text.headline),
            Text('Updated ${DateFormat('h:mm:ss a').format(fetchedAt)}', style: bb.text.caption),
          ]),
        ),
        if (status?.day.isNotEmpty ?? false)
          BBPill(label: status!.day, tone: stopped ? BBPillTone.danger : BBPillTone.live),
      ]),
    );
  }
}
```

Update `test/service_alert_card_test.dart`:
- Add `import 'package:busboard_nl/ui/kit/kit.dart';`.
- Change `const MaterialApp(home: Scaffold(body: SizedBox(...)))` to `MaterialApp(theme: BBTheme.light(), home: const Center(child: SizedBox(...)))`.
- Keep the stop-label `Text` assertions (maxLines null, softWrap, visible overflow, no exception).

Remove both alerts files from `_legacyAllowList`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/alerts_test.dart test/service_alert_card_test.dart test/bus_bottom_sheet_test.dart test/kit/kit_boundary_test.dart`, then the full suite.

`bus_bottom_sheet_test` builds the legacy map sheet. If that sheet now renders `ServiceAlertCard` without `BBTokens`, wrap that test's `MaterialApp` in `theme: BBTheme.light()`. Don't change the sheet itself; it belongs to Phase 3.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/alerts test/ui/alerts_test.dart test/service_alert_card_test.dart test/bus_bottom_sheet_test.dart test/kit/kit_boundary_test.dart
git commit -m "feat(ui): Harbour service alerts screen and card"
```

---

### Task 9: Settings

**Files:**
- Modify (rewrite): `lib/ui/settings/settings_screen.dart`
- Modify: `test/kit/kit_boundary_test.dart` (remove `'lib/ui/settings/settings_screen.dart'`)
- Test: `test/ui/settings_screen_test.dart`. `test/legal_copy_test.dart` must still pass unchanged.

**Interfaces:**
- Consumes: kit (`BBTopBar`, `BBSegmented`, `BBStepper`, `BBButton`, `BBToast`, `BBThemeMode`, `BBCard`), `settingsProvider` (`setThemeMode`, `setMapThemeMode`, `setRefreshInterval`, `requestForceRefresh`), `gtfsRepositoryProvider`, `LegalCopy`.
- Produces: `SettingsScreen()`.

- [ ] **Step 1: Write the failing test** — `test/ui/settings_screen_test.dart`:

```dart
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester, {Future<GtfsRepository> Function()? gtfs, double textScale = 1}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(overrides: [
    if (gtfs != null) gtfsRepositoryProvider.overrideWith((ref) => gtfs()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: BBTheme.light(),
      home: const SettingsScreen(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('app theme segments write themeMode', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.text('Dark').first);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).themeMode, BBThemeMode.dark);
  });

  testWidgets('map theme: Match app / Light / Dark write mapThemeMode', (tester) async {
    final c = await _pump(tester);
    expect(find.text('Map theme'), findsOneWidget);
    await tester.tap(find.text('Light').last);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).mapThemeMode, BBThemeMode.light);
    await tester.tap(find.text('Match app'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).mapThemeMode, isNull);
  });

  testWidgets('refresh interval stepper steps by 5 within 5–60', (tester) async {
    final c = await _pump(tester);
    expect(find.text('5 seconds'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Increase Refresh interval'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).refreshIntervalSeconds, 10);
  });

  testWidgets('a failed schedule refresh re-enables the button and tells the user', (tester) async {
    // Settings does not watch the repository until Refresh is tapped, so the
    // first (and only) load is the refresh itself — make it fail.
    await _pump(tester, gtfs: () => Future<GtfsRepository>.error(Exception('offline')));
    await tester.scrollUntilVisible(find.text('Refresh schedule now'), 200);
    await tester.tap(find.text('Refresh schedule now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Couldn't refresh schedule data. Try again later."), findsOneWidget);
    expect(find.text('Refresh schedule now'), findsOneWidget); // not stuck on "Downloading..."
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('no overflow at text scale 2.0 on 320pt', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 700 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, textScale: 2.0);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/settings_screen_test.dart`. Expected: FAIL (`Map theme`, `5 seconds` and `Refresh schedule now` aren't found).

- [ ] **Step 3: Rewrite `lib/ui/settings/settings_screen.dart`**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../state/providers.dart';
import '../copy/legal_copy.dart';
import '../kit/kit.dart';

enum _MapThemeChoice { matchApp, light, dark }

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _refreshing = false;

  Future<void> _refreshSchedule() async {
    setState(() => _refreshing = true);
    try {
      ref.read(settingsProvider.notifier).requestForceRefresh();
      ref.invalidate(gtfsRepositoryProvider);
      await ref.read(gtfsRepositoryProvider.future);
    } catch (_) {
      if (mounted) BBToast.show(context, "Couldn't refresh schedule data. Try again later.");
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final mapChoice = switch (settings.mapThemeMode) {
      BBThemeMode.light => _MapThemeChoice.light,
      BBThemeMode.dark => _MapThemeChoice.dark,
      _ => _MapThemeChoice.matchApp,
    };

    Widget section(String title, IconData icon, List<Widget> children) => BBCard(
          padding: const EdgeInsets.all(BBSpace.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, size: 20, color: bb.colors.brandInk),
              const SizedBox(width: BBSpace.s),
              Expanded(child: Semantics(header: true, child: Text(title, style: bb.text.headline))),
            ]),
            const SizedBox(height: BBSpace.m),
            ...children,
          ]),
        );

    return BBScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BBTopBar(title: 'Settings', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  BBSpace.screen, 0, BBSpace.screen, MediaQuery.paddingOf(context).bottom + BBSpace.l),
              children: [
                section('Appearance', BBIcons.palette, [
                  Text('App theme', style: bb.text.label.copyWith(color: bb.colors.muted)),
                  const SizedBox(height: BBSpace.s),
                  BBSegmented<BBThemeMode>(
                    segments: const [
                      BBSegment(value: BBThemeMode.system, label: 'System'),
                      BBSegment(value: BBThemeMode.light, label: 'Light'),
                      BBSegment(value: BBThemeMode.dark, label: 'Dark'),
                    ],
                    selected: settings.themeMode,
                    onChanged: notifier.setThemeMode,
                  ),
                  const SizedBox(height: BBSpace.l),
                  Text('Map theme', style: bb.text.label.copyWith(color: bb.colors.muted)),
                  const SizedBox(height: BBSpace.s),
                  BBSegmented<_MapThemeChoice>(
                    segments: const [
                      BBSegment(value: _MapThemeChoice.matchApp, label: 'Match app'),
                      BBSegment(value: _MapThemeChoice.light, label: 'Light'),
                      BBSegment(value: _MapThemeChoice.dark, label: 'Dark'),
                    ],
                    selected: mapChoice,
                    onChanged: (choice) => notifier.setMapThemeMode(switch (choice) {
                      _MapThemeChoice.matchApp => null,
                      _MapThemeChoice.light => BBThemeMode.light,
                      _MapThemeChoice.dark => BBThemeMode.dark,
                    }),
                  ),
                ]),
                const SizedBox(height: BBSpace.l),
                section('Refresh interval', BBIcons.timer, [
                  Text('How often to check for new live coordinates', style: bb.text.caption),
                  const SizedBox(height: BBSpace.m),
                  BBStepper(
                    value: settings.refreshIntervalSeconds.clamp(5, 60),
                    min: 5,
                    max: 60,
                    step: 5,
                    format: (v) => '$v seconds',
                    semanticLabel: 'Refresh interval',
                    onChanged: notifier.setRefreshInterval,
                  ),
                  const SizedBox(height: BBSpace.s),
                  Text(
                    'Metrobus currently refreshes GPS snapshots about every 10 seconds. '
                    'The map animates smoothly between them.',
                    textAlign: TextAlign.center,
                    style: bb.text.caption,
                  ),
                ]),
                const SizedBox(height: BBSpace.l),
                section('Schedule data (GTFS)', BBIcons.download, [
                  Row(children: [
                    Text('Last updated: ', style: bb.text.caption),
                    Expanded(
                      child: Text(
                        settings.lastGtfsUpdate != null
                            ? DateFormat('MMM d, yyyy HH:mm').format(settings.lastGtfsUpdate!)
                            : 'Never',
                        style: bb.text.label,
                      ),
                    ),
                  ]),
                  const SizedBox(height: BBSpace.xs),
                  Text('Auto-refreshes every 7 days', style: bb.text.caption),
                  const SizedBox(height: BBSpace.m),
                  BBButton(
                    label: _refreshing ? 'Downloading...' : 'Refresh schedule now',
                    icon: BBIcons.refresh,
                    kind: BBButtonKind.quiet,
                    expand: true,
                    onPressed: _refreshing ? null : _refreshSchedule,
                  ),
                ]),
                const SizedBox(height: BBSpace.l),
                section('About', BBIcons.info, [
                  Text('BusBoard NL v1.1.0', style: bb.text.label),
                  const SizedBox(height: BBSpace.xs),
                  Text(
                    'Personalized arrival board for Metrobus\n'
                    "St. John's, Mount Pearl & Paradise, NL",
                    style: bb.text.caption,
                  ),
                  const SizedBox(height: BBSpace.m),
                  Text(LegalCopy.independence, style: bb.text.label),
                  const SizedBox(height: BBSpace.s),
                  Text(LegalCopy.dataCredit, style: bb.text.caption),
                  const SizedBox(height: 2),
                  Text(LegalCopy.mapCredit, style: bb.text.caption),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

`settings.mapThemeMode` is a `ThemeMode?`, and `BBThemeMode` is the same type, so the `switch` patterns type-check. Remove the file from `_legacyAllowList`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/settings_screen_test.dart test/legal_copy_test.dart test/kit/kit_boundary_test.dart`, then the full suite.

If `find.text('Light')` is ambiguous between the two segmented controls, the test uses `.first` for the app theme and `.last` for the map theme. Keep that order (app theme above map theme).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/settings_screen.dart test/ui/settings_screen_test.dart test/kit/kit_boundary_test.dart
git commit -m "feat(ui): Harbour settings with map theme, interval stepper and recoverable refresh"
```

---

### Task 10: Screen goldens, guard check, parity run

**Files:**
- Create: `test/ui/screen_golden_test.dart`, `test/ui/goldens/*.png` (generated)
- Verify: `test/kit/kit_boundary_test.dart` `_legacyAllowList` now holds exactly `lib/ui/map/bus_bottom_sheet.dart`, `lib/ui/map/map_screen.dart` and `lib/ui/map/stop_bottom_sheet.dart`.

**Interfaces:** consumes every screen from Tasks 4–9.

- [ ] **Step 1: Write the golden test** — `test/ui/screen_golden_test.dart`. It renders, with fixtures and in light and dark at text scale 1.0:
  1. a column of four `ArrivalRowTile`s: live early, live late with sched, stop-prediction live, and schedule-only at 0 min
  2. `AlertsScreen` with the two alerts from `test/ui/alerts_test.dart` plus a status
  3. `SettingsScreen`

```dart
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kit/kit_test_helpers.dart';

final _rows = [
  ArrivalRow(routeShortName: '29', headsign: 'Signal Hill Rd', scheduledTime: GtfsTime.parse('09:52:00'),
      predictedTime: GtfsTime.parse('09:51:00'), minutesAway: 4, isLive: true, liveStatus: LiveStatus.ahead,
      tripId: 'a', vehicleNumber: '2134', routeRun: '29-1', currentLocation: 'MUN Centre'),
  ArrivalRow(routeShortName: '23', headsign: 'Stavanger Drive', scheduledTime: GtfsTime.parse('09:52:00'),
      predictedTime: GtfsTime.parse('09:54:00'), minutesAway: 6, isLive: true, liveStatus: LiveStatus.behind,
      tripId: 'b', vehicleNumber: '1207'),
  ArrivalRow(routeShortName: '10', headsign: 'Avalon Mall - MUN Centre - Downtown', scheduledTime: GtfsTime.parse('09:55:00'),
      predictedTime: GtfsTime.parse('09:55:00'), minutesAway: 9, isLive: true, isEnhanced: true, tripId: 'c'),
  ArrivalRow(routeShortName: '16', headsign: 'Avalon Mall', scheduledTime: GtfsTime.parse('09:48:00'),
      minutesAway: 0, tripId: 'd'),
];

Widget _app(Widget home, Brightness b) => ProviderScope(
      overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
        serviceUpdatesProvider.overrideWith((ref) => Stream.value(ServiceUpdates(
              alerts: [
                ServiceAlert(sourceIds: const {'a'}, header: 'Water Street Detour',
                    description: 'Routes 3 and 10 use Harbour Drive between Prescott St and Waldegrave St.',
                    cause: ServiceAlertCause.construction, effect: ServiceAlertEffect.detour,
                    severity: ServiceAlertSeverity.warning,
                    activePeriods: [ServiceAlertPeriod(end: DateTime(2099, 11, 1, 12, 44))],
                    targets: const [ServiceAlertTarget(routeId: '3'), ServiceAlertTarget(routeId: '10')]),
              ],
              serviceStatus: const MetrobusServiceStatus(serviceOperating: true, serviceId: '1', day: 'Weekday',
                  message: 'Weekday service operating'),
              fetchedAt: DateTime(2026, 10, 4, 9, 52, 4),
              feedTimestamp: null,
            ))),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: b == Brightness.dark ? BBTheme.dark() : BBTheme.light(),
        home: home,
      ),
    );

void main() {
  setUpAll(loadAppFonts);

  for (final b in Brightness.values) {
    testWidgets('arrival rows ${b.name}', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 520 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(kitHost(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [for (final r in _rows) Padding(padding: const EdgeInsets.only(bottom: 8), child: ArrivalRowTile(arrival: r))]),
        ),
        brightness: b,
      ));
      await expectLater(find.byType(Column).first, matchesGoldenFile('goldens/arrival_rows_${b.name}.png'));
    });

    testWidgets('alerts screen ${b.name}', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const AlertsScreen(), b));
      await tester.pumpAndSettle();
      await expectLater(find.byType(AlertsScreen), matchesGoldenFile('goldens/alerts_${b.name}.png'));
    });

    testWidgets('settings screen ${b.name}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390 * 3, 1100 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const SettingsScreen(), b));
      await tester.pumpAndSettle();
      await expectLater(find.byType(SettingsScreen), matchesGoldenFile('goldens/settings_${b.name}.png'));
    });
  }
}
```

- [ ] **Step 2: Generate and inspect.** Run `flutter test --update-goldens test/ui/screen_golden_test.dart`. Open every PNG and check against spec §6:
  - cream page / navy in dark
  - jellybean route badges
  - plain-words status pills
  - soon-coloured minutes ≤ 5 and `Now`
  - struck-through `sched` time
  - alert card with detour pill and route badges
  - status card, `Active now` count
  - footer legible
  - Settings segmented controls, stepper, About copy

  Fix components, not tests, if anything is wrong. Then re-run without `--update-goldens`; it should be stable.

- [ ] **Step 3: Verify the guard.** Run `flutter test test/kit/kit_boundary_test.dart`. Confirm `_legacyAllowList` contains only the three `lib/ui/map/` files. If anything else remains, migrate it (or explain why) before finishing.

- [ ] **Step 4: Full suite + analyze.** Run `flutter analyze lib test` and `flutter test`.

- [ ] **Step 5: Parity run (controller).** Build and run on the iOS simulator `BusBoard iPhone 17` and the Android emulator `busboard_pixel`. For Android builds, export `JAVA_HOME=~/.sdkman/candidates/java/21.0.10-tem` and `GRADLE_OPTS=-Dorg.gradle.java.home=$JAVA_HOME`.
  - Walk through picker, board (stop 1150), alerts and settings in light and dark, and once at the largest text size.
  - Check the floating nav bar over the board and alerts lists, with the last item clear of it.
  - Check that the map tab content is laid out above the bar.
  - Check that the board scrolls and pulls to refresh, and that settings' segmented controls and stepper work.
  - Confirm the iOS swipe-back from Settings and the board.
  - Compare the iOS and Android screenshots and report differences, other than the status bar.

- [ ] **Step 6: Commit**

```bash
git add test/ui/screen_golden_test.dart test/ui/goldens
git commit -m "test(ui): Harbour screen goldens in light and dark"
```
