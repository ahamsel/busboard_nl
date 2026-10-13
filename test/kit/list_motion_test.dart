import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

Widget _list(List<String> ids, {bool reduce = false, bool slide = true}) {
  final list = BBListMotion(
    slide: slide,
    child: Column(children: [
      for (final (i, id) in ids.indexed)
        BBListItem(key: ValueKey(id), index: i, child: SizedBox(height: 50, child: Text(id))),
    ]),
  );
  return kitHost(reduce
      ? Builder(
          builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: list))
      : list);
}

Finder _fade(String id) => find.descendant(of: find.byKey(ValueKey(id)), matching: find.byType(FadeTransition));

double _opacity(WidgetTester tester, String id) => tester.widget<FadeTransition>(_fade(id)).opacity.value;

RenderBBSlideOnMove _slide(WidgetTester tester, String id) => tester
    .renderObject<RenderBBSlideOnMove>(find.descendant(of: find.byKey(ValueKey(id)), matching: find.byType(BBSlideOnMove)));

void main() {
  testWidgets('the first items enter one after another, 40 ms apart', (tester) async {
    await tester.pumpWidget(_list(['a', 'b', 'c']));
    await tester.pump(); // the entrance's first tick
    await tester.pump(const Duration(milliseconds: 30));
    expect(_opacity(tester, 'a'), greaterThan(0));
    expect(_opacity(tester, 'b'), 0, reason: 'its 40 ms delay has not passed');
    expect(_opacity(tester, 'c'), 0);
    await tester.pumpAndSettle();
    for (final id in ['a', 'b', 'c']) {
      expect(_opacity(tester, id), 1);
    }
  });

  testWidgets('the stagger stops growing after 8 steps', (tester) async {
    final ids = [for (var i = 0; i < 12; i++) 'r$i'];
    await tester.pumpWidget(_list(ids));
    await tester.pump();
    // Items 8–11 all wait 8 × 40 ms = 320 ms; at 330 ms they have all started.
    await tester.pump(const Duration(milliseconds: 330));
    expect(_opacity(tester, 'r8'), greaterThan(0));
    expect(_opacity(tester, 'r11'), _opacity(tester, 'r8'));
  });

  testWidgets('items that appear later (a live refresh) show at once', (tester) async {
    await tester.pumpWidget(_list(['a']));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_list(['a', 'b']));
    expect(_fade('b'), findsNothing);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('a reordered item slides from its old place to its new one', (tester) async {
    await tester.pumpWidget(_list(['a', 'b']));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_list(['b', 'a']));
    expect(_slide(tester, 'a').lastShift.dy, closeTo(-50, 0.5), reason: 'painted where it was');
    expect(_slide(tester, 'b').lastShift.dy, closeTo(50, 0.5));
    await tester.pump(const Duration(milliseconds: 110));
    expect(_slide(tester, 'a').lastShift.dy, inExclusiveRange(-50, 0));
    await tester.pumpAndSettle();
    expect(_slide(tester, 'a').lastShift, Offset.zero);
    expect(tester.getTopLeft(find.text('a')).dy, greaterThan(tester.getTopLeft(find.text('b')).dy));
  });

  testWidgets('Reduce Motion: no entrance and no slide', (tester) async {
    await tester.pumpWidget(_list(['a', 'b'], reduce: true));
    expect(_fade('a'), findsNothing);
    await tester.pumpWidget(_list(['b', 'a'], reduce: true));
    expect(_slide(tester, 'a').lastShift, Offset.zero);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('slide: false never slides (lazily built scrolling lists)', (tester) async {
    await tester.pumpWidget(_list(['a', 'b'], slide: false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_list(['b', 'a'], slide: false));
    expect(_slide(tester, 'a').lastShift, Offset.zero);
  });
}
