import 'dart:async';

import 'package:busboard_nl/ui/kit/bb_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

Widget _host(DraggableScrollableController controller, {bool reduceMotion = false}) {
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
    final controller = DraggableScrollableController();
    await tester.pumpWidget(_host(controller));
    expect(controller.size, closeTo(0.15, 0.001));

    await tester.drag(find.text('row 0'), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(0.5, 0.01));
  });

  testWidgets('still snaps with reduce motion on (no zero-duration assert)', (tester) async {
    final controller = DraggableScrollableController();
    await tester.pumpWidget(_host(controller, reduceMotion: true));
    await tester.drag(find.text('row 0'), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.size, closeTo(0.5, 0.01));
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
      final controller = DraggableScrollableController();
      await tester.pumpWidget(_host(controller));
      await settle(tester);
      expect(ticks, 0);
    });

    testWidgets('ticks once when a drag settles on half, and again on returning to peek', (tester) async {
      mockHaptics(tester);
      final controller = DraggableScrollableController();
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
      final controller = DraggableScrollableController();
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
