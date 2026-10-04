import 'package:busboard_nl/ui/kit/bb_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

Widget _host(DraggableScrollableController controller, {bool reduceMotion = false}) {
  return kitHost(
    MediaQuery(
      data: MediaQueryData(size: const Size(390, 800), disableAnimations: reduceMotion),
      child: SizedBox(
        height: 800,
        child: Stack(children: [
          BBSheet(
            controller: controller,
            peekFraction: 0.15,
            slivers: [
              SliverList.builder(itemCount: 30, itemBuilder: (_, i) => SizedBox(height: 44, child: Text('row $i'))),
            ],
          ),
        ]),
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

  test('rejects unordered fractions', () {
    expect(() => BBSheet(slivers: const [], peekFraction: 0.6, halfFraction: 0.5), throwsAssertionError);
  });
}
