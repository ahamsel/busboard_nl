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
