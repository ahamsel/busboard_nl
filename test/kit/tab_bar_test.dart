import 'dart:ui' show SemanticsRole;

import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderDecoratedBox, RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'contrast_test.dart' show contrast;
import 'kit_test_helpers.dart';

const _tabs = [
  BBTab(label: 'Board', icon: BBIcons.board, activeIcon: BBIcons.boardFill, key: ValueKey('t-board')),
  BBTab(label: 'Map', icon: BBIcons.map, activeIcon: BBIcons.mapFill, key: ValueKey('t-map')),
];

/// The bar at the bottom of a phone screen, with [bottomInset] of safe area under it.
Widget _host(int index, ValueChanged<int> onSelect,
        {double bottomInset = 0, Brightness brightness = Brightness.light, double textScale = 1, double width = 390}) =>
    kitHost(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: EdgeInsets.only(bottom: bottomInset)),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: BBTabBar(tabs: _tabs, index: index, onSelect: onSelect),
          ),
        ),
      ),
      brightness: brightness,
      textScale: textScale,
      width: width,
    );

/// The icon a tab shows.
Icon _icon(WidgetTester tester, String key) =>
    tester.widget<Icon>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Icon)));

Text _label(WidgetTester tester, String label) => tester.widget<Text>(find.text(label));

void main() {
  setUpAll(loadAppFonts);

  testWidgets('56 pt tall plus the bottom safe area, on surface with a line hairline on top (spec 2026-10-15 §2.1)',
      (tester) async {
    await tester.pumpWidget(_host(0, (_) {}, bottomInset: 34));
    expect(tester.getSize(find.byType(BBTabBar)).height, BBTabBar.height + 34);
    final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(BBTabBar), matching: find.byType(DecoratedBox)).first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.color, BBColors.light.surface);
    expect((deco.border! as Border).top.color, BBColors.light.line);
  });

  for (final b in Brightness.values) {
    testWidgets('the active tab is brandInk with its filled icon on a brandSoft pill; the other is muted (${b.name})',
        (tester) async {
      final colors = b == Brightness.dark ? BBColors.dark : BBColors.light;
      await tester.pumpWidget(_host(0, (_) {}, brightness: b));
      await tester.pumpAndSettle();
      expect(_icon(tester, 't-board').icon, BBIcons.boardFill);
      expect(_icon(tester, 't-board').color, colors.brandInk);
      expect(_label(tester, 'Board').style!.color, colors.brandInk);
      expect(_icon(tester, 't-map').icon, BBIcons.map);
      expect(_label(tester, 'Map').style!.color, colors.muted);
      final pill = tester.widget<AnimatedContainer>(
          find.descendant(of: find.byKey(const ValueKey('t-board')), matching: find.byType(AnimatedContainer)));
      expect((pill.decoration! as BoxDecoration).color, colors.brandSoft);
      // WCAG AA: labels are text (4.5:1) on the bar, and the active icon sits on its pill.
      expect(contrast(colors.muted, colors.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(colors.brandInk, colors.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(colors.brandInk, colors.brandSoft), greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('a tap anywhere on a tab selects it', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(_host(0, picked.add));
    final map = tester.getRect(find.byKey(const ValueKey('t-map')));
    expect(map.height, greaterThanOrEqualTo(BBTabBar.height), reason: 'the whole height is the target');
    await tester.tapAt(map.topRight + const Offset(-4, 4));
    expect(picked, [1]);
  });

  testWidgets('each tab is a selectable tab button: "Board, tab 1 of 2", selected', (tester) async {
    final handle = tester.ensureSemantics();
    final picked = <int>[];
    await tester.pumpWidget(_host(0, picked.add));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Board, tab 1 of 2')),
      isSemantics(label: 'Board, tab 1 of 2', isButton: true, hasSelectedState: true, isSelected: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Map, tab 2 of 2')),
      isSemantics(label: 'Map, tab 2 of 2', isButton: true, hasSelectedState: true, isSelected: false, hasTapAction: true),
    );
    expect(tester.getSemantics(find.bySemanticsLabel('Map, tab 2 of 2')).role, SemanticsRole.tab);
    tester.semantics.tap(find.semantics.byLabel('Map, tab 2 of 2'));
    expect(picked, [1]);
    handle.dispose();
  });

  testWidgets('under Reduce Motion the pill moves at once', (tester) async {
    Widget host(int i) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _host(i, (_) {}),
        );
    await tester.pumpWidget(host(0));
    await tester.pumpWidget(host(1));
    await tester.pump();
    final pill = tester.renderObject<RenderDecoratedBox>(find.descendant(
        of: find.byKey(const ValueKey('t-map')), matching: find.byType(DecoratedBox)).first);
    expect((pill.decoration as BoxDecoration).color, BBColors.light.brandSoft);
  });

  for (final b in Brightness.values) {
    testWidgets('at 2x text on a 320 pt phone the labels read in full and the bar grows (${b.name})', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(1, (_) {}, textScale: 2, width: 320, brightness: b));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['Board', 'Map']) {
        final p = tester.renderObject<RenderParagraph>(find.text(label));
        expect(p.size.width, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.5),
            reason: '$label is cut short');
      }
      expect(tester.getSize(find.byType(BBTabBar)).height, greaterThan(BBTabBar.height));
    });
  }

  testWidgets('on a wide screen the bar spans it, and its tabs keep to a centred row', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(0, (_) {}, width: 1024));
    expect(tester.getSize(find.byType(BBTabBar)).width, 1024);
    final board = tester.getRect(find.byKey(const ValueKey('t-board')));
    final map = tester.getRect(find.byKey(const ValueKey('t-map')));
    expect(map.right - board.left, BBTabBar.maxRowWidth);
    expect((board.left + map.right) / 2, 512, reason: 'centred');
  });
}
