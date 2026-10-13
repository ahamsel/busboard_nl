import 'dart:io';

import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

BoxDecoration _firstBox(WidgetTester tester, Finder within) => tester
    .widget<DecoratedBox>(find.descendant(of: within, matching: find.byType(DecoratedBox)).first)
    .decoration as BoxDecoration;

Widget _sheetWith(Widget child) => MediaQuery(
      data: const MediaQueryData(size: Size(390, 800)),
      child: SizedBox(
        height: 800,
        child: Stack(children: [
          BBSheet(
            peekFraction: 0.5,
            halfFraction: 0.6,
            initialFraction: 0.6,
            slivers: [SliverToBoxAdapter(child: child)],
          ),
        ]),
      ),
    );

void main() {
  group('decorations (spec §2.1)', () {
    test('dark floating layers: surface, a 1 px top highlight and a deep black shadow', () {
      final d = BBTokens.dark.floating();
      expect(d.color, BBColors.dark.surface);
      final border = d.border! as Border;
      expect(border.top.color, BBColors.dark.highlight);
      expect(border.top.width, 1);
      expect(border.bottom, BorderSide.none);
      final shadow = d.boxShadow!.single;
      expect(shadow.color.withValues(alpha: 1), const Color(0xFF000000));
      expect(shadow.color.a, inInclusiveRange(0.45, 0.55));
    });

    test('light floating layers: white, no border, a soft green-tinted shadow (8–14%)', () {
      final d = BBTokens.light.floating();
      expect(d.color, BBColors.light.surface);
      expect(d.border, isNull);
      final shadow = d.boxShadow!.single;
      expect(shadow.color.withValues(alpha: 1), BBColors.light.ink);
      expect(shadow.color.a, inInclusiveRange(0.08, 0.14));
    });

    test('dark: the higher a layer floats, the lighter it is', () {
      const c = BBColors.dark;
      double l(Color x) => x.computeLuminance();
      expect(l(c.bg), lessThan(l(c.surface)));
      expect(l(c.surface), lessThan(l(c.surfaceRaised)));
      expect(l(c.surfaceRaised), lessThan(l(c.surfaceField)));
      expect(l(c.surface), lessThan(l(c.surfaceFloat)));
    });

    test('map controls float on surfaceFloat; selected ones are a brand fill', () {
      for (final t in [BBTokens.light, BBTokens.dark]) {
        expect(t.mapControl().color, t.colors.surfaceFloat);
        expect(t.mapControl(selected: true).color, t.colors.brand);
        expect(t.mapControl().boxShadow, isNotEmpty);
      }
    });

    test('cards: surface on a page, surfaceRaised on a sheet; dark cards carry the top highlight', () {
      expect(BBTokens.dark.card().color, BBColors.dark.surface);
      expect(BBTokens.dark.card(raised: true).color, BBColors.dark.surfaceRaised);
      expect((BBTokens.dark.card().border! as Border).top.color, BBColors.dark.highlight);
      expect(BBTokens.light.card().border, isNull);
      expect(BBTokens.light.card().boxShadow!.single.color.a, inInclusiveRange(0.08, 0.14));
    });

    test('fields: surfaceField with a 1.5 px line outline; focused, a 2 px brandEdge ring; error, dangerInk', () {
      for (final t in [BBTokens.light, BBTokens.dark]) {
        final rest = t.field();
        expect(rest.color, t.colors.surfaceField);
        expect((rest.border! as Border).top.color, t.colors.line);
        expect((rest.border! as Border).top.width, 1.5);
        final focused = t.field(focused: true).border! as Border;
        expect(focused.top.color, t.brandEdge);
        expect(focused.top.width, 2);
        expect((t.field(error: true).border! as Border).top.color, t.colors.dangerInk);
        expect(rest.color, isNot(t.colors.surfaceSunken));
      }
    });
  });

  testWidgets('a BBCard inside a BBSheet rises to surfaceRaised; on a page it stays surface', (tester) async {
    await tester.pumpWidget(kitHost(_sheetWith(const BBCard(child: Text('in sheet'))), brightness: Brightness.dark));
    expect(_firstBox(tester, find.byType(BBCard)).color, BBColors.dark.surfaceRaised);

    await tester.pumpWidget(kitHost(const BBCard(child: Text('on page')), brightness: Brightness.dark));
    expect(_firstBox(tester, find.byType(BBCard)).color, BBColors.dark.surface);
  });

  testWidgets('a BBChip floats on surfaceFloat on the map, and sits on surfaceField on a sheet', (tester) async {
    BoxDecoration chip() =>
        tester.widget<AnimatedContainer>(find.byKey(BBChip.surfaceKey)).decoration! as BoxDecoration;
    await tester.pumpWidget(kitHost(Center(child: BBChip(label: 'All routes', onTap: () {})), brightness: Brightness.dark));
    expect(chip().color, BBColors.dark.surfaceFloat);
    expect(chip().boxShadow, isNotEmpty);

    await tester.pumpWidget(kitHost(_sheetWith(Center(child: BBChip(label: 'Home', onTap: () {}))), brightness: Brightness.dark));
    expect(chip().color, BBColors.dark.surfaceField);
    expect((chip().border! as Border).top.color, BBColors.dark.line);
  });

  testWidgets('BBTextField: surfaceField with a line outline, a 2 px brandEdge ring while focused', (tester) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(kitHost(const BBTextField(hint: 'Search'), brightness: b));
      final t = b == Brightness.dark ? BBTokens.dark : BBTokens.light;
      BoxDecoration box() => _firstBox(tester, find.byType(BBTextField));
      expect(box().color, t.colors.surfaceField);
      expect((box().border! as Border).top.color, t.colors.line);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect((box().border! as Border).top.color, t.brandEdge);
      expect((box().border! as Border).top.width, 2);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect((box().border! as Border).top.color, t.colors.line);
    }
  });

  test('surfaceSunken is never a field fill (spec §2.2)', () {
    // Recessed, non-field uses only: the neutral pill and icon tile, the off switch track, and the theme plumbing.
    const allowed = {
      'lib/ui/kit/tokens.dart',
      'lib/ui/kit/bb_theme.dart',
      'lib/ui/kit/bb_pill.dart',
      'lib/ui/kit/bb_icon_tile.dart',
      'lib/ui/kit/bb_switch.dart',
    };
    final offenders = [
      for (final f in Directory('lib/ui').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') &&
            !allowed.contains(f.path.replaceAll(r'\', '/')) &&
            f.readAsStringSync().contains('surfaceSunken'))
          f.path,
    ];
    expect(offenders, isEmpty, reason: 'Fields use context.bb.field(), not surfaceSunken: $offenders');
  });

  test('bright green is a fill only: no icon, text or cursor uses colors.brand (spec §2.1)', () {
    final greenForeground = RegExp(r'(Icon\(|copyWith\(color:|cursorColor:|TextStyle\()[^;]*colors\.brand\b(?!Ink|Soft)');
    final offenders = [
      for (final f in Directory('lib/ui').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart'))
          for (final (i, line) in f.readAsLinesSync().indexed)
            if (greenForeground.hasMatch(line)) '${f.path}:${i + 1}: ${line.trim()}',
    ];
    expect(offenders, isEmpty, reason: 'Use bb.brandEdge (icons) or colors.brandInk (text):\n${offenders.join('\n')}');
  });
}
