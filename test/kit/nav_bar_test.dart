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
];

void main() {
  // Real Figtree metrics (the test font is far wider) so the fit is truthful.
  setUpAll(loadAppFonts);

  testWidgets('tapping a tab reports its index', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(kitHost(BBNavBar(items: _items, currentIndex: 0, onSelect: picked.add)));
    await tester.tap(find.text('Map'));
    await tester.tap(find.text('Board'));
    expect(picked, [1, 0]);
  });

  testWidgets('each tab is a button named for it, and the current one says so', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(BBNavBar(items: _items, currentIndex: 0, onSelect: (_) {})));
    expect(find.bySemanticsLabel('Map'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('Board')), isSemantics(
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
      BBNavBar(items: _items, currentIndex: 1, onSelect: (_) {}),
      textScale: 2.0,
      width: 320,
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at text scale 2.0 all tab labels render at the same size and each tab is a 44pt target', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(kitHost(
        BBNavBar(items: _items, currentIndex: 0, onSelect: (_) {}),
        brightness: brightness,
        textScale: 2.0,
        width: 375,
      ));
      expect(tester.takeException(), isNull);
      // Rendered height (includes any FittedBox scaling, unlike getSize).
      double rendered(String label) {
        final f = find.text(label);
        return (tester.getBottomLeft(f) - tester.getTopLeft(f)).dy;
      }

      expect(rendered('Map'), closeTo(rendered('Board'), 0.5), reason: '${brightness.name}: Map vs Board');
      for (final label in ['Board', 'Map']) {
        final tab = find.ancestor(of: find.text(label), matching: find.byType(AnimatedContainer));
        expect(tester.getSize(tab).height, greaterThanOrEqualTo(44), reason: '${brightness.name}: $label tab');
      }
    }
  });

  testWidgets('heightFor and reservedHeight grow with text scale (clamped to 1.3x)', (tester) async {
    for (final (scale, expected) in [(1.0, 56.0), (1.3, 56.0 * 1.3), (2.0, 56.0 * 1.3), (0.8, 56.0)]) {
      late double h;
      late double reserved;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(padding: const EdgeInsets.only(bottom: 34), textScaler: TextScaler.linear(scale)),
        child: Builder(builder: (context) {
          h = BBNavBar.heightFor(context);
          reserved = BBNavBar.reservedHeight(context);
          return const SizedBox();
        }),
      ));
      expect(h, closeTo(expected, 0.001), reason: 'scale $scale');
      expect(reserved, closeTo(h + BBNavBar.gap + 34, 0.001), reason: 'scale $scale');
    }
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
}
