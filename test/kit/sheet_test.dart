import 'dart:async';

import 'package:busboard_nl/ui/kit/bb_sheet.dart';
import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

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

void main() {
  testWidgets('starts at peek and snaps up to half when dragged', (tester) async {
    final controller = BBSheetController();
    await tester.pumpWidget(_host(controller));
    expect(controller.size, closeTo(0.15, 0.001));

    await tester.drag(find.text('row 0'), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.5, 0.01));
  });

  testWidgets('still snaps with reduce motion on (no zero-duration assert)', (tester) async {
    final controller = BBSheetController();
    await tester.pumpWidget(_host(controller, reduceMotion: true));
    await tester.drag(find.text('row 0'), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.size, closeTo(0.5, 0.01));
  });

  testWidgets('floating card: inset 8 on both sides, lifted by bottomInset, rounded on every corner', (tester) async {
    // _host lays out a 390 x 800 box; make the test surface that size so the
    // card's rect is measured against the box edges, not a centred 800 x 600 view.
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    unawaited(controller.animateToDetent(BBSheetDetent.full));
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
    unawaited(controller.animateToDetent(BBSheetDetent.half));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.5, 0.01));
    unawaited(controller.animateToDetent(BBSheetDetent.full));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.9, 0.01));
    unawaited(controller.collapse());
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.15, 0.01));
  });

  testWidgets('animateToDetent works with reduce motion', (tester) async {
    final controller = BBSheetController();
    await tester.pumpWidget(_host(controller, reduceMotion: true));
    unawaited(controller.animateToDetent(BBSheetDetent.half));
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

  group('haptics', () {
    late int ticks;

    void mockHaptics(WidgetTester tester) {
      ticks = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') ticks++;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
    }

    testWidgets('no tick at startup', (tester) async {
      mockHaptics(tester);
      final controller = BBSheetController();
      await tester.pumpWidget(_host(controller));
      await settle(tester);
      expect(ticks, 0);
    });

    testWidgets('ticks once when a drag settles on half, and again on returning to peek', (tester) async {
      mockHaptics(tester);
      final controller = BBSheetController();
      await tester.pumpWidget(_host(controller));

      await tester.drag(find.text('row 0'), const Offset(0, -260));
      await settle(tester);
      expect(controller.size, closeTo(0.5, 0.01));
      expect(ticks, 1);

      await tester.drag(find.text('row 0'), const Offset(0, 300));
      await settle(tester);
      expect(controller.size, closeTo(0.15, 0.01));
      expect(ticks, 2);
    });

    testWidgets('programmatic animation to full ticks once, not when crossing half', (tester) async {
      mockHaptics(tester);
      final controller = BBSheetController();
      await tester.pumpWidget(_host(controller));

      unawaited(controller.animateTo(0.9, duration: const Duration(milliseconds: 300), curve: Curves.linear));
      // Fine-grained frames so the extent is sampled right at the half crossing.
      for (var i = 0; i < 320; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await settle(tester);
      expect(controller.size, closeTo(0.9, 0.01));
      expect(ticks, 1);
    });
  });

  test('rejects unordered fractions', () {
    expect(() => BBSheet(slivers: const [], peekFraction: 0.6, halfFraction: 0.5), throwsAssertionError);
  });
}
