import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast_test.dart' show contrast;
import 'kit_test_helpers.dart';

/// [top] drawn over [bottom].
Color _over(Color top, Color bottom) => Color.alphaBlend(top, bottom);

void main() {
  test('light keeps the ink-green scrims; dark uses black, heavier', () {
    expect(BBScrim.soft, const Color(0x3313261A));
    expect(BBScrim.strong, const Color(0x6613261A));
    expect(BBScrim.softDark.withValues(alpha: 1), const Color(0xFF000000));
    expect(BBScrim.strongDark.withValues(alpha: 1), const Color(0xFF000000));
    expect(BBScrim.strongDark.a, greaterThan(BBScrim.softDark.a));
    expect(BBScrim.strongDark.a, greaterThanOrEqualTo(0.55));
  });

  testWidgets('strongOf and softOf follow the theme brightness', (tester) async {
    for (final b in Brightness.values) {
      late BuildContext context;
      await tester.pumpWidget(kitHost(Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }), brightness: b));
      final dark = b == Brightness.dark;
      expect(BBScrim.strongOf(context), dark ? BBScrim.strongDark : BBScrim.strong, reason: b.name);
      expect(BBScrim.softOf(context), dark ? BBScrim.softDark : BBScrim.soft, reason: b.name);
    }
  });

  test('dark: a dialog on surface is lifted off the sheet it covers (>= 1.2:1; its top highlight and shadow add the rest)', () {
    final c = BBColors.dark;
    final covered = _over(BBScrim.strongDark, c.surface);
    expect(contrast(c.surface, covered), greaterThanOrEqualTo(1.2));
    // Not so heavy that the screen behind goes black: the rider should still see where they were.
    expect(BBScrim.strongDark.a, lessThanOrEqualTo(0.65));
    // Light is tuned already: the dialog is white over a dimmed white sheet.
    final lc = BBColors.light;
    expect(contrast(lc.surface, _over(BBScrim.strong, lc.surface)), greaterThanOrEqualTo(1.3));
  });

  testWidgets('BBDialog and the picker dim with the same strong scrim, light and dark', (tester) async {
    for (final b in Brightness.values) {
      final strong = b == Brightness.dark ? BBScrim.strongDark : BBScrim.strong;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(kitHost(
        Builder(
          builder: (context) => Column(children: [
            BBButton(
              label: 'dialog',
              onPressed: () => BBDialog.show<void>(context, title: 'Sure?', actions: const [
                BBDialogAction(label: 'OK', value: null, primary: true),
              ]),
            ),
            BBButton(
              label: 'picker',
              onPressed: () => showBBWhenPicker(
                context,
                title: 'Leave by',
                initial: DateTime(2026, 10, 7, 9),
                first: DateTime(2026, 10, 7, 8),
                last: DateTime(2026, 10, 9),
                use24h: true,
              ),
            ),
          ]),
        ),
        brightness: b,
      ));
      await tester.tap(find.text('dialog'));
      await tester.pumpAndSettle();
      expect(topScrim(tester), strong, reason: '${b.name} dialog');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('picker'));
      await tester.pumpAndSettle();
      expect(topScrim(tester), strong, reason: '${b.name} picker');
      await tester.tap(find.byKey(BBWhenPicker.closeKey));
      await tester.pumpAndSettle();
    }
  });
}
