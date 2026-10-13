import 'package:busboard_nl/ui/kit/bb_pressable.dart';
import 'package:busboard_nl/ui/kit/bb_segmented.dart';
import 'package:busboard_nl/ui/kit/bb_switch.dart';
import 'package:busboard_nl/ui/kit/bb_text_field.dart';
import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    expect(tester.getSemantics(find.text('Two')), isSemantics(
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
    expect(tester.getSemantics(find.byType(BBSwitch)), isSemantics(
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

  testWidgets('BBTextField decoration is border-less, unpadded and lets the hint wrap to two lines', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(kitHost(const BBTextField(hint: 'Stop name or number on the pole'), brightness: brightness));
      final d = tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
      expect(d.border, InputBorder.none, reason: '${brightness.name} border');
      expect(d.enabledBorder, InputBorder.none, reason: '${brightness.name} enabledBorder');
      expect(d.focusedBorder, InputBorder.none, reason: '${brightness.name} focusedBorder');
      expect(d.contentPadding, EdgeInsets.zero, reason: '${brightness.name} contentPadding');
      expect(d.filled, isFalse, reason: '${brightness.name} filled');
      expect(d.hintMaxLines, 2, reason: '${brightness.name} hintMaxLines');
    }
  });

  testWidgets('a long hint wraps instead of truncating at text scale 2.0', (tester) async {
    await tester.pumpWidget(kitHost(
      const BBTextField(hint: 'Stop name or number on the pole'),
      textScale: 2.0,
      width: 260,
    ));
    final hint = tester.widget<Text>(find.text('Stop name or number on the pole'));
    expect(hint.maxLines, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BBTextField works without a Material ancestor', (tester) async {
    // kitHost provides only a ColoredBox, so this fails if the field relies on
    // an ambient Material (as TextField does).
    final typed = <String>[];
    await tester.pumpWidget(kitHost(BBTextField(hint: 'Search', onChanged: typed.add)));
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), 'abc');
    expect(typed.last, 'abc');
  });

  group('with the app fonts', () {
    setUpAll(loadAppFonts);

    RenderParagraph paragraph(WidgetTester tester, String label) =>
        tester.renderObject<RenderParagraph>(find.text(label));

    testWidgets('a BBSegmented label too long for one line wraps to two at 2x text, centred', (tester) async {
      await tester.pumpWidget(
        kitHost(
          BBSegmented<int>(
            segments: const [
              BBSegment(value: 0, label: 'Leave now'),
              BBSegment(value: 1, label: 'Leave by'),
              BBSegment(value: 2, label: 'Arrive by'),
            ],
            selected: 0,
            onChanged: (_) {},
          ),
          textScale: 2,
          width: 320,
        ),
      );
      final p = paragraph(tester, 'Leave now');
      expect(p.didExceedMaxLines, isFalse);
      expect(p.textAlign, TextAlign.center);
      final lineHeight = p.getFullHeightForCaret(const TextPosition(offset: 0));
      expect(p.size.height, greaterThan(lineHeight * 1.5), reason: 'two lines');
      // Every segment takes the tallest one's height, and still at least 44.
      final heights = {
        for (final l in ['Leave now', 'Leave by', 'Arrive by'])
          tester.getSize(find.ancestor(of: find.text(l), matching: find.byType(Expanded))).height,
      };
      expect(heights, hasLength(1));
      expect(heights.single, greaterThanOrEqualTo(44));
    });

    testWidgets('a BBSegmented label that fits stays on one line', (tester) async {
      await tester.pumpWidget(
        kitHost(
          BBSegmented<String>(
            segments: const [
              BBSegment(value: 'near', label: 'Near me'),
              BBSegment(value: 'id', label: 'Stop number'),
            ],
            selected: 'near',
            onChanged: (_) {},
          ),
        ),
      );
      final p = paragraph(tester, 'Stop number');
      expect(p.size.height, lessThan(p.getFullHeightForCaret(const TextPosition(offset: 0)) * 1.5));
      final pressable = find.ancestor(of: find.text('Near me'), matching: find.byType(BBPressable));
      expect(tester.getSize(pressable).height, 44);
    });
  });

  testWidgets('BBSegmented segments are at least 44 tall to tap', (tester) async {
    await tester.pumpWidget(kitHost(BBSegmented<String>(
      segments: const [BBSegment(value: 'near', label: 'Near me'), BBSegment(value: 'id', label: 'Stop number')],
      selected: 'near',
      onChanged: (_) {},
    )));
    final pressable = find.ancestor(of: find.text('Near me'), matching: find.byType(BBPressable));
    expect(tester.getSize(pressable).height, greaterThanOrEqualTo(44));
  });

  testWidgets('the selection pill is a brand-soft fill with a 1.5 px brand-edge border, in both modes', (tester) async {
    for (final (brightness, tokens) in [(Brightness.light, BBTokens.light), (Brightness.dark, BBTokens.dark)]) {
      final colors = tokens.colors;
      await tester.pumpWidget(kitHost(
        BBSegmented<String>(
          segments: const [BBSegment(value: 'near', label: 'Near me'), BBSegment(value: 'id', label: 'Stop number')],
          selected: 'near',
          onChanged: (_) {},
        ),
        brightness: brightness,
      ));
      await tester.pumpAndSettle();
      final pill = tester
          .widget<DecoratedBox>(find.descendant(of: find.byKey(BBSegmented.pillKey), matching: find.byType(DecoratedBox)))
          .decoration as BoxDecoration;
      expect(pill.color, colors.brandSoft, reason: '${brightness.name} pill fill');
      expect((pill.border! as Border).top.color, tokens.brandEdge, reason: '${brightness.name} pill edge');
      expect((pill.border! as Border).top.width, 1.5);
      expect(tester.widget<Text>(find.text('Near me')).style!.color, colors.brandInk);
      expect(tester.widget<Text>(find.text('Stop number')).style!.color, colors.muted);
    }
  });

  Widget slidingHost({bool reduce = false}) {
    var selected = 'near';
    final control = StatefulBuilder(
      builder: (context, setState) => BBSegmented<String>(
        segments: const [BBSegment(value: 'near', label: 'Near me'), BBSegment(value: 'id', label: 'Stop number')],
        selected: selected,
        onChanged: (v) => setState(() => selected = v),
      ),
    );
    return kitHost(reduce
        ? Builder(
            builder: (context) =>
                MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: control))
        : control);
  }

  Rect pillRect(WidgetTester tester) =>
      tester.getRect(find.descendant(of: find.byKey(BBSegmented.pillKey), matching: find.byType(DecoratedBox)));
  Rect segmentRect(WidgetTester tester, String label) =>
      tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(Expanded)));

  testWidgets('the selection pill slides to the tapped segment', (tester) async {
    await tester.pumpWidget(slidingHost());
    expect(pillRect(tester).center.dx, closeTo(segmentRect(tester, 'Near me').center.dx, 1));
    await tester.tap(find.text('Stop number'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(pillRect(tester).center.dx,
        inExclusiveRange(segmentRect(tester, 'Near me').center.dx, segmentRect(tester, 'Stop number').center.dx));
    await tester.pumpAndSettle();
    expect(pillRect(tester).center.dx, closeTo(segmentRect(tester, 'Stop number').center.dx, 1));
  });

  testWidgets('Reduce Motion: the pill moves at once', (tester) async {
    await tester.pumpWidget(slidingHost(reduce: true));
    await tester.tap(find.text('Stop number'));
    await tester.pump();
    expect(pillRect(tester).center.dx, closeTo(segmentRect(tester, 'Stop number').center.dx, 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('BBSegmented scales a pressed segment', (tester) async {
    await tester.pumpWidget(kitHost(BBSegmented<String>(
      segments: const [BBSegment(value: 'near', label: 'Near me'), BBSegment(value: 'id', label: 'Stop number')],
      selected: 'near',
      onChanged: (_) {},
    )));
    final g = await tester.startGesture(tester.getCenter(find.text('Stop number')));
    await tester.pump(const Duration(milliseconds: 200));
    final scale = tester.widget<AnimatedScale>(
      find.ancestor(of: find.text('Stop number'), matching: find.byType(AnimatedScale)).first,
    );
    expect(scale.scale, 0.98);
    await g.up();
  });

  testWidgets('off BBSwitch draws a visible muted outline and thumb in both modes', (tester) async {
    for (final (brightness, colors) in [(Brightness.light, BBColors.light), (Brightness.dark, BBColors.dark)]) {
      await tester.pumpWidget(kitHost(BBSwitch(value: false, onChanged: (_) {}), brightness: brightness));
      await tester.pumpAndSettle();
      final decorations = tester
          .widgetList<DecoratedBox>(find.descendant(of: find.byType(BBSwitch), matching: find.byType(DecoratedBox)))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .toList();
      final thumb = decorations.singleWhere((d) => d.shape == BoxShape.circle);
      final track = decorations.singleWhere((d) => d.shape == BoxShape.rectangle && d.border != null);
      expect(thumb.color, colors.muted, reason: '${brightness.name} off thumb');
      expect((track.border! as Border).top.color, colors.muted, reason: '${brightness.name} off track outline');
      expect((track.border! as Border).top.width, 1.5);
    }
  });

  testWidgets('BBSwitch hit area is at least 44x44', (tester) async {
    await tester.pumpWidget(kitHost(BBSwitch(value: false, onChanged: (_) {})));
    final size = tester.getSize(find.byType(BBSwitch));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('disabled BBSwitch ignores taps and reports disabled', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(kitHost(const BBSwitch(value: false, onChanged: null, semanticLabel: 'x')));
    await tester.tap(find.byType(BBSwitch));
    expect(tester.getSemantics(find.byType(BBSwitch)), isSemantics(label: 'x', isEnabled: false));
    handle.dispose();
  });
}
