import 'dart:ui' show SemanticsRole;

import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'contrast_test.dart' show contrast;
import 'kit_test_helpers.dart';

const _tabs = [
  BBTab(label: 'Board', icon: BBIcons.board, activeIcon: BBIcons.boardFill, key: ValueKey('t-board')),
  BBTab(label: 'Map', icon: BBIcons.map, activeIcon: BBIcons.mapFill, key: ValueKey('t-map')),
];

/// The bar at the bottom of a phone screen, with [bottomInset] of safe area under it.
Widget _host(int index, ValueChanged<int> onSelect,
        {double bottomInset = 0,
        Brightness brightness = Brightness.light,
        double textScale = 1,
        double width = 390,
        bool reduceMotion = false}) =>
    kitHost(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(padding: EdgeInsets.only(bottom: bottomInset), disableAnimations: reduceMotion),
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

void _phone(WidgetTester tester, {double width = 390, double height = 844}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The icon a tab shows.
Icon _icon(WidgetTester tester, String key) =>
    tester.widget<Icon>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Icon)));

Text _label(WidgetTester tester, String label) => tester.widget<Text>(find.text(label));

Rect _capsule(WidgetTester tester) => tester.getRect(find.byKey(BBTabBar.capsuleKey));
Rect _thumb(WidgetTester tester) => tester.getRect(
    find.descendant(of: find.byKey(BBTabBar.thumbKey), matching: find.byType(DecoratedBox)));

BoxDecoration _capsuleDecoration(WidgetTester tester) =>
    tester.widget<DecoratedBox>(find.byKey(BBTabBar.capsuleKey)).decoration as BoxDecoration;

void main() {
  setUpAll(loadAppFonts);

  group('the floating capsule (tab bar option B)', () {
    testWidgets('inset 16 pt from each side, 8 pt above the safe area, 52 pt tall, fully rounded, no hairline',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(0, (_) {}, bottomInset: 34));
      final capsule = _capsule(tester);
      expect(capsule.left, BBTabBar.sideInset);
      expect(capsule.right, 390 - BBTabBar.sideInset);
      expect(capsule.bottom, 844 - 34 - BBTabBar.gap, reason: 'floats 8 pt above the home indicator');
      expect(capsule.height, BBTabBar.height);
      // The widget runs from the capsule's top to the screen's bottom edge: its top is the capsule's.
      final bar = tester.getRect(find.byType(BBTabBar));
      expect(bar.top, capsule.top);
      expect(bar.bottom, 844);
      final deco = _capsuleDecoration(tester);
      expect(deco.borderRadius, BorderRadius.circular(999), reason: 'fully rounded ends');
      expect((deco.border! as Border).top.color, BBColors.light.line, reason: 'a 1 px outline all round');
      expect((deco.border! as Border).isUniform, isTrue);
      expect(
        find.descendant(of: find.byType(BBTabBar), matching: find.byWidgetPredicate((w) {
          final d = w is DecoratedBox ? w.decoration : null;
          return d is BoxDecoration && d.border is Border && (d.border! as Border).top != BorderSide.none &&
              !(d.border! as Border).isUniform;
        })),
        findsNothing,
        reason: 'no top hairline',
      );
      // Each half is a 44 pt target.
      expect(tester.getSize(find.byKey(const ValueKey('t-map'))).height, BBTabBar.height - 2 * BBTabBar.padding);
    });

    testWidgets('light: surfaceFloat with the soft float shadow and a line outline', (tester) async {
      await tester.pumpWidget(_host(0, (_) {}));
      final deco = _capsuleDecoration(tester);
      final t = BBTokens.light;
      expect(deco.color, BBColors.light.surfaceFloat);
      expect(deco.boxShadow, t.mapControl().boxShadow);
      expect(deco.border, Border.all(color: BBColors.light.line));
    });

    testWidgets('dark: the map controls\' float (deep shadow, top-edge highlight)', (tester) async {
      await tester.pumpWidget(_host(0, (_) {}, brightness: Brightness.dark));
      final deco = _capsuleDecoration(tester);
      final float = BBTokens.dark.mapControl(radius: 999);
      expect(deco.color, BBColors.dark.surfaceFloat);
      expect(deco.boxShadow, float.boxShadow);
      expect(deco.border, float.border);
      expect((deco.border! as Border).top.color, BBColors.dark.highlight);
    });

    testWidgets('on a wide screen the capsule is centred and at most 360 pt wide', (tester) async {
      _phone(tester, width: 1024, height: 768);
      await tester.pumpWidget(_host(0, (_) {}, width: 1024));
      final capsule = _capsule(tester);
      expect(capsule.width, BBTabBar.maxWidth);
      expect(capsule.center.dx, 512);
    });

    testWidgets('its margins take no taps: they reach what is behind', (tester) async {
      _phone(tester);
      final behind = <String>[];
      await tester.pumpWidget(kitHost(
        BBTabBarLayout(
          body: (context, inset) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => behind.add('map'),
            child: const SizedBox.expand(),
          ),
          bar: BBTabBar(tabs: _tabs, index: 0, onSelect: (_) => behind.add('tab')),
        ),
      ));
      final capsule = _capsule(tester);
      await tester.tapAt(Offset(BBTabBar.sideInset / 2, capsule.center.dy));
      await tester.tapAt(Offset(200, capsule.bottom + BBTabBar.gap / 2));
      await tester.tapAt(capsule.centerRight - const Offset(30, 0));
      expect(behind, ['map', 'map', 'tab']);
    });
  });

  for (final b in Brightness.values) {
    testWidgets('the selected half is a brand thumb, its filled icon and label onBrand; the other is muted (${b.name})',
        (tester) async {
      final colors = b == Brightness.dark ? BBColors.dark : BBColors.light;
      await tester.pumpWidget(_host(0, (_) {}, brightness: b));
      await tester.pumpAndSettle();
      expect(_icon(tester, 't-board').icon, BBIcons.boardFill);
      expect(_icon(tester, 't-board').color, colors.onBrand);
      expect(_label(tester, 'Board').style!.color, colors.onBrand);
      expect(_icon(tester, 't-map').icon, BBIcons.map);
      expect(_icon(tester, 't-map').color, colors.muted);
      expect(_label(tester, 'Map').style!.color, colors.muted);
      final thumb = tester.widget<DecoratedBox>(
          find.descendant(of: find.byKey(BBTabBar.thumbKey), matching: find.byType(DecoratedBox)));
      expect((thumb.decoration as BoxDecoration).color, colors.brand);
      expect(_thumb(tester), tester.getRect(find.byKey(const ValueKey('t-board'))), reason: 'behind the Board half');
      // The icon and label sit side by side, centred in the half.
      final half = tester.getRect(find.byKey(const ValueKey('t-board')));
      final icon = tester.getRect(find.descendant(of: find.byKey(const ValueKey('t-board')), matching: find.byType(Icon)));
      final label = tester.getRect(find.text('Board'));
      expect(label.left, greaterThan(icon.right));
      expect(icon.center.dy, closeTo(label.center.dy, 1));
      expect((icon.left + label.right) / 2, closeTo(half.center.dx, 1));
    });

    test('contrast (WCAG AA), ${b.name}', () {
      final c = b == Brightness.dark ? BBColors.dark : BBColors.light;
      // Text: the selected label on the thumb, and the other on the capsule.
      expect(contrast(c.onBrand, c.brand), greaterThanOrEqualTo(4.5));
      expect(contrast(c.muted, c.surfaceFloat), greaterThanOrEqualTo(4.5));
      // The selection itself (non-text, 3:1): the thumb on the capsule and on the page.
      expect(contrast(c.brand, c.surfaceFloat), greaterThanOrEqualTo(3));
      expect(contrast(c.brand, c.bg), greaterThanOrEqualTo(3));
    });
  }

  test('the pinned contrast values', () {
    double r(Color a, Color b) => double.parse(contrast(a, b).toStringAsFixed(2));
    const l = BBColors.light, d = BBColors.dark;
    expect(r(l.onBrand, l.brand), 4.91);
    expect(r(d.onBrand, d.brand), 6.18);
    expect(r(l.muted, l.surfaceFloat), 5.96);
    expect(r(d.muted, d.surfaceFloat), 5.79);
    // The light capsule's edge on the page: the 1 px line outline alone is 1.16:1 and the white fill 1.09:1, under
    // the 3:1 a non-text boundary asks for. The float shadow carries the edge, as on the floating map controls; the
    // capsule is told apart by its content, and the selection by the brand thumb (4.91:1 on it, 4.5:1 on the page).
    expect(r(l.line, l.bg), 1.16);
    expect(r(l.surfaceFloat, l.bg), 1.09);
    expect(BBTokens.light.mapControl().boxShadow, isNotEmpty);
  });

  testWidgets('a tap anywhere on a half selects it', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(_host(0, picked.add));
    final map = tester.getRect(find.byKey(const ValueKey('t-map')));
    expect(map.height, greaterThanOrEqualTo(44), reason: 'the whole height is the target');
    await tester.tapAt(map.topRight + const Offset(-4, 4));
    expect(picked, [1]);
  });

  testWidgets('each half is a selectable tab button: "Board, tab 1 of 2", selected, in a tab bar', (tester) async {
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
    final bar = tester.getSemantics(find.byKey(BBTabBar.capsuleKey));
    expect(bar.role, SemanticsRole.tabBar);
    tester.semantics.tap(find.semantics.byLabel('Map, tab 2 of 2'));
    expect(picked, [1]);
    handle.dispose();
  });

  testWidgets('the thumb slides to the chosen half over BBMotion.standard', (tester) async {
    await tester.pumpWidget(_host(0, (_) {}));
    final board = tester.getRect(find.byKey(const ValueKey('t-board')));
    final map = tester.getRect(find.byKey(const ValueKey('t-map')));
    expect(_thumb(tester), board);
    final slide = tester.widget<AnimatedAlign>(find.byKey(BBTabBar.thumbKey));
    expect(slide.duration, BBMotion.standard);
    expect(slide.curve, BBMotion.curve);
    await tester.pumpWidget(_host(1, (_) {}));
    await tester.pump(BBMotion.standard ~/ 2);
    final mid = _thumb(tester);
    expect(mid.left, greaterThan(board.left + 1), reason: 'on its way');
    expect(mid.left, lessThan(map.left - 1), reason: 'not there yet');
    expect(mid.size, board.size, reason: 'it slides, it does not stretch');
    await tester.pump(BBMotion.standard ~/ 2);
    expect(_thumb(tester), map);
  });

  testWidgets('under Reduce Motion the thumb switches at once', (tester) async {
    await tester.pumpWidget(_host(0, (_) {}, reduceMotion: true));
    await tester.pumpWidget(_host(1, (_) {}, reduceMotion: true));
    expect(tester.widget<AnimatedAlign>(find.byKey(BBTabBar.thumbKey)).duration, Duration.zero);
    await tester.pump();
    expect(_thumb(tester), tester.getRect(find.byKey(const ValueKey('t-map'))));
    expect(_icon(tester, 't-map').color, BBColors.light.onBrand);
  });

  for (final b in Brightness.values) {
    testWidgets('at 2x text on a 320 pt phone the labels read in full and the capsule grows (${b.name})',
        (tester) async {
      _phone(tester, width: 320, height: 640);
      await tester.pumpWidget(_host(1, (_) {}, textScale: 2, width: 320, brightness: b, bottomInset: 20));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final capsule = _capsule(tester);
      for (final label in ['Board', 'Map']) {
        final p = tester.renderObject<RenderParagraph>(find.text(label));
        expect(p.didExceedMaxLines, isFalse);
        expect(p.size.width, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.5),
            reason: '$label is cut short');
        final r = tester.getRect(find.text(label));
        expect(capsule.contains(r.topLeft) && capsule.contains(r.bottomRight), isTrue, reason: '$label is inside');
      }
      expect(capsule.height, greaterThanOrEqualTo(BBTabBar.height));
      expect(capsule.bottom, 640 - 20 - BBTabBar.gap);
      expect(_thumb(tester), tester.getRect(find.byKey(const ValueKey('t-map'))));
    });

    testWidgets('at 3x text on a 320 pt phone the label goes under the icon, and the capsule grows (${b.name})',
        (tester) async {
      _phone(tester, width: 320, height: 640);
      await tester.pumpWidget(_host(0, (_) {}, textScale: 3.2, width: 320, brightness: b));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final half = tester.getRect(find.byKey(const ValueKey('t-board')));
      final icon = tester.getRect(find.descendant(of: find.byKey(const ValueKey('t-board')), matching: find.byType(Icon)));
      final label = tester.getRect(find.text('Board'));
      final p = tester.renderObject<RenderParagraph>(find.text('Board'));
      expect(p.size.width, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.5));
      expect(label.top, greaterThanOrEqualTo(icon.bottom), reason: 'stacked');
      expect(half.contains(label.bottomRight - const Offset(0.5, 0.5)), isTrue, reason: 'not clipped');
      expect(_capsule(tester).height, greaterThan(BBTabBar.height));
    });
  }

  group('BBTabBarLayout', () {
    Widget list({required double bottomSafe, double textScale = 1}) => kitHost(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(padding: EdgeInsets.only(bottom: bottomSafe)),
              child: BBTabBarLayout(
                body: (context, inset) => ListView(
                  key: const ValueKey('list'),
                  padding: EdgeInsets.only(bottom: inset + BBSpace.xxl),
                  children: [for (var i = 0; i < 30; i++) SizedBox(height: 60, child: Text('Row $i'))],
                ),
                bar: BBTabBar(tabs: _tabs, index: 0, onSelect: (_) {}),
              ),
            ),
          ),
          textScale: textScale,
        );

    for (final scale in [1.0, 2.0]) {
      testWidgets('the body runs to the bottom edge, its inset is the capsule\'s top, and its end scrolls out '
          'from behind the capsule (${scale}x text)', (tester) async {
        _phone(tester);
        await tester.pumpWidget(list(bottomSafe: 34, textScale: scale));
        final capsule = _capsule(tester);
        expect(tester.getRect(find.byKey(const ValueKey('list'))).bottom, 844, reason: 'behind the capsule');
        expect(capsule.bottom, 844 - 34 - BBTabBar.gap);
        await tester.fling(find.byKey(const ValueKey('list')), const Offset(0, -4000), 4000);
        await tester.pumpAndSettle();
        final last = tester.getRect(find.text('Row 29'));
        expect(last.bottom, lessThanOrEqualTo(capsule.top), reason: 'the last row is clear of the capsule');
        expect(find.text('Row 29').hitTestable(), findsOneWidget);
      });
    }
  });
}
