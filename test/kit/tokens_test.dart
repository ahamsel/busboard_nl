import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text styles use Figtree, no decoration, tabular minutes', () {
    final t = BBText.of(BBColors.light);
    for (final s in [t.display, t.title, t.headline, t.body, t.label, t.caption, t.minutes, t.minutesUnit]) {
      expect(s.fontFamily, BBText.family);
      expect(s.decoration, TextDecoration.none);
      // A solid style, so a strike-through added later never inherits the fallback's double line.
      expect(s.decorationStyle, TextDecorationStyle.solid);
    }
    expect(t.minutes.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(t.minutes.fontSize, 26);
    expect(t.minutes.fontWeight, FontWeight.w800);
  });

  testWidgets('BBMotion.of returns zero when animations are disabled', (tester) async {
    late Duration normal;
    late Duration reduced;
    await tester.pumpWidget(Builder(builder: (context) {
      normal = BBMotion.of(context, BBMotion.standard);
      return MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(builder: (inner) {
          reduced = BBMotion.of(inner, BBMotion.standard);
          return const SizedBox();
        }),
      );
    }));
    expect(normal, BBMotion.standard);
    expect(reduced, Duration.zero);
  });

  testWidgets('context.bb resolves the theme extension', (tester) async {
    late BBTokens tokens;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [BBTokens.dark]),
      home: Builder(builder: (context) {
        tokens = context.bb;
        return const SizedBox();
      }),
    ));
    expect(tokens.isDark, isTrue);
    expect(tokens.colors.bg, BBColors.dark.bg);
  });
}
