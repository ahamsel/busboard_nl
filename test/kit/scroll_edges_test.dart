import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

Widget _page({double textScale = 1, bool reduce = false}) {
  final page = SizedBox(
    height: 600,
    child: BBScrollPage(
      title: 'Service alerts',
      large: true,
      onBack: () {},
      body: (context, topInset) => ListView(
        padding: EdgeInsets.only(top: topInset),
        children: [for (var i = 0; i < 40; i++) SizedBox(height: 44, child: Text('row $i'))],
      ),
    ),
  );
  return kitHost(
    reduce
        ? Builder(
            builder: (context) =>
                MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: page))
        : page,
    textScale: textScale,
  );
}

BoxDecoration _bar(WidgetTester tester) =>
    tester.widget<DecoratedBox>(find.byKey(BBScrollPage.barKey)).decoration as BoxDecoration;

BackdropFilter _frost(WidgetTester tester) =>
    tester.widget<BackdropFilter>(find.ancestor(of: find.byKey(BBScrollPage.barKey), matching: find.byType(BackdropFilter)));

double? _titleSize(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(find.text('Service alerts')).text.style!.fontSize;

Widget _sheet({bool fadeUnderHeader = false}) => kitHost(MediaQuery(
      data: const MediaQueryData(size: Size(390, 800)),
      child: SizedBox(
        height: 800,
        child: Stack(children: [
          BBSheet(
            peekFraction: 0.15,
            initialFraction: 0.9,
            fadeUnderHeader: fadeUnderHeader,
            header: const SizedBox(height: 48, child: Text('MUN Centre')),
            slivers: [
              SliverList.builder(itemCount: 40, itemBuilder: (_, i) => SizedBox(height: 44, child: Text('row $i'))),
            ],
          ),
        ]),
      ),
    ));

/// Whether the bottom fade is painting (the fade widget is private; `on` is its one field).
bool fadeOn(WidgetTester tester) => (tester.widget(find.byKey(BBSheet.fadeKey)) as dynamic).on as bool;

BoxDecoration _header(WidgetTester tester) =>
    tester.widget<DecoratedBox>(find.byKey(BBSheet.headerKey)).decoration as BoxDecoration;

void main() {
  group('BBScrollPage (spec §5)', () {
    testWidgets('at rest: the large title, no frost, no hairline; the first row starts below the bar', (tester) async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle(); // the bar is measured after its first frame
      expect(_titleSize(tester), BBTokens.light.text.display.fontSize);
      expect(_frost(tester).enabled, isFalse);
      expect(_bar(tester).border, isNull);
      expect(tester.getTopLeft(find.text('row 0')).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(BBScrollPage.barKey)).dy - 0.5));
    });

    testWidgets('the very first frame already starts the content below the bar, before the bar is measured',
        (tester) async {
      for (final scale in [1.0, 2.0]) {
        for (final back in [true, false]) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(kitHost(
            SizedBox(
              height: 600,
              child: BBScrollPage(
                // Short, so the test font (one em per letter) keeps it on one line even at 2×.
                title: 'Stops',
                large: true,
                onBack: back ? () {} : null,
                body: (context, topInset) => ListView(
                  padding: EdgeInsets.only(top: topInset),
                  children: [for (var i = 0; i < 40; i++) SizedBox(height: 44, child: Text('row $i'))],
                ),
              ),
            ),
            textScale: scale,
          ));
          // No settle: this is the first frame, and the measured inset has not arrived.
          final barBottom = tester.getBottomLeft(find.byKey(BBScrollPage.barKey)).dy;
          final rowTop = tester.getTopLeft(find.text('row 0')).dy;
          expect(rowTop, greaterThanOrEqualTo(barBottom - 0.5), reason: '${scale}x back=$back: row under the bar');
          expect(rowTop, lessThanOrEqualTo(barBottom + 2), reason: '${scale}x back=$back: not a big gap either');
        }
      }
    });

    testWidgets('after scrolling 40 px: the title condenses, the bar frosts and gets a hairline', (tester) async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();
      await tester.drag(find.text('row 3'), const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(_titleSize(tester), BBTokens.light.text.title.fontSize);
      expect(_frost(tester).enabled, isTrue);
      expect(_bar(tester).color, BBColors.light.bg.withValues(alpha: 0.8));
      expect((_bar(tester).border! as Border).bottom.color, BBColors.light.line);

      await tester.drag(find.text('row 3'), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(_titleSize(tester), BBTokens.light.text.display.fontSize, reason: 'back at the top it is large again');
      expect(_bar(tester).border, isNull);
    });

    testWidgets('Reduce Motion: the title switches at once; frost and hairline stay', (tester) async {
      await tester.pumpWidget(_page(reduce: true));
      await tester.pumpAndSettle();
      await tester.drag(find.text('row 3'), const Offset(0, -40));
      await tester.pump();
      expect(_titleSize(tester), BBTokens.light.text.title.fontSize);
      expect(_frost(tester).enabled, isTrue);
      expect((_bar(tester).border! as Border).bottom.color, BBColors.light.line);
    });

    testWidgets('returning to the top: the first row never dips while the title grows back', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(kitHost(SizedBox(
        height: 600,
        child: BBScrollPage(
          title: 'Service alerts',
          large: true,
          onBack: () {},
          body: (context, topInset) => ListView(
            controller: controller,
            padding: EdgeInsets.only(top: topInset),
            children: [for (var i = 0; i < 40; i++) SizedBox(height: 44, child: Text('row $i'))],
          ),
        ),
      )));
      await tester.pumpAndSettle();
      final settled = tester.getTopLeft(find.text('row 0')).dy;
      controller.jumpTo(200);
      await tester.pumpAndSettle();
      expect(_titleSize(tester), BBTokens.light.text.title.fontSize);

      controller.jumpTo(0);
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getTopLeft(find.text('row 0')).dy, greaterThanOrEqualTo(settled - 0.01),
            reason: 'frame $i: row 0 must not rise above its resting place');
      }
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('row 0')).dy, closeTo(settled, 0.01));
    });

    testWidgets('content starts below the bar at 2× text', (tester) async {
      await tester.pumpWidget(_page(textScale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.text('row 0')).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(BBScrollPage.barKey)).dy - 0.5));
    });
  });

  group('BBSheet header and fades (spec §5)', () {
    testWidgets('a hairline and a soft shadow appear under the header once the list scrolls', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_sheet());
      await tester.pumpAndSettle();
      expect(_header(tester).border, isNull);
      expect(_header(tester).boxShadow, isNull);
      await tester.drag(find.text('row 5'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect((_header(tester).border! as Border).bottom.color, BBColors.light.line);
      expect(_header(tester).boxShadow, isNotEmpty);
    });

    testWidgets('home: the list fades under the header once it scrolls', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_sheet(fadeUnderHeader: true));
      await tester.pumpAndSettle();
      double fade() => tester.widget<AnimatedOpacity>(
              find.descendant(of: find.byKey(BBSheet.topFadeKey), matching: find.byType(AnimatedOpacity)))
          .opacity;
      expect(fade(), 0);
      await tester.drag(find.text('row 5'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(fade(), 1);
    });

    testWidgets('the bottom fade follows content that changes without a scroll', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget sheet(int rows) => kitHost(MediaQuery(
            data: const MediaQueryData(size: Size(390, 800)),
            child: SizedBox(
              height: 800,
              child: Stack(children: [
                BBSheet(
                  peekFraction: 0.15,
                  initialFraction: 0.9,
                  header: const SizedBox(height: 48, child: Text('MUN Centre')),
                  slivers: [
                    SliverList.builder(itemCount: rows, itemBuilder: (_, i) => SizedBox(height: 44, child: Text('row $i'))),
                  ],
                ),
              ]),
            ),
          ));
      await tester.pumpWidget(sheet(3));
      await tester.pumpAndSettle();
      expect(fadeOn(tester), isFalse, reason: 'nothing below: no fade');
      await tester.pumpWidget(sheet(40));
      await tester.pumpAndSettle();
      expect(fadeOn(tester), isTrue, reason: 'rows were added: the fade turns on with no scroll');
      await tester.pumpWidget(sheet(3));
      await tester.pumpAndSettle();
      expect(fadeOn(tester), isFalse, reason: 'rows were removed: the fade turns off');
    });

    testWidgets('the fade comes and goes without losing the scroll position', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_sheet());
      await tester.pumpAndSettle();
      expect(fadeOn(tester), isTrue);
      final state = tester.state<ScrollableState>(find.byType(Scrollable));

      state.position.jumpTo(120);
      await tester.pumpAndSettle();
      expect(fadeOn(tester), isTrue);
      expect(state.position.pixels, 120);

      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(fadeOn(tester), isFalse, reason: 'at the end of the list: no fade, no offscreen layer');
      expect(tester.state<ScrollableState>(find.byType(Scrollable)), same(state), reason: 'the list keeps its state');
      final end = state.position.maxScrollExtent;
      expect(state.position.pixels, end);

      state.position.jumpTo(end - 100);
      await tester.pumpAndSettle();
      expect(fadeOn(tester), isTrue);
      expect(tester.state<ScrollableState>(find.byType(Scrollable)), same(state));
      expect(state.position.pixels, end - 100);
    });

    test('the bottom fade covers the last 24 px, and nothing when off', () {
      expect(BBSheet.fadeStops(400, on: true), [0, 1 - 24 / 400, 1]);
      expect(BBSheet.fadeStops(400, on: false), [0, 1, 1]);
      expect(BBSheet.fadeStops(10, on: true), [0, 1, 1], reason: 'too short to fade');
    });
  });

  testWidgets('BBRefresh draws its pull indicator below topInset', (tester) async {
    await tester.pumpWidget(kitHost(SizedBox(
      height: 600,
      child: BBRefresh(
        topInset: 100,
        onRefresh: () async {},
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [for (var i = 0; i < 30; i++) SizedBox(height: 44, child: Text('row $i'))],
        ),
      ),
    )));
    final g = await tester.startGesture(tester.getCenter(find.text('row 2')));
    await g.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(tester.getTopLeft(find.byType(BBRouteDots)).dy, greaterThanOrEqualTo(tester.getTopLeft(find.byType(BBRefresh)).dy + 100));
    await g.up();
    await tester.pumpAndSettle();
  });
}
