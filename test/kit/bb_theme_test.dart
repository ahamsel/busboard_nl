import 'package:busboard_nl/ui/kit/bb_theme.dart';
import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({required TargetPlatform platform}) {
  return MaterialApp(
    theme: BBTheme.light().copyWith(platform: platform),
    scrollBehavior: const BBScrollBehavior(),
    home: Builder(
      builder: (context) => Scaffold(
        body: ListView(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Center(child: Text('PAGE B')))),
              ),
              child: const Text('open'),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  test('themes carry BBTokens and neutralise Material visuals', () {
    for (final (theme, dark) in [(BBTheme.light(), false), (BBTheme.dark(), true)]) {
      final tokens = theme.extension<BBTokens>()!;
      expect(tokens.isDark, dark);
      expect(theme.scaffoldBackgroundColor, tokens.colors.bg);
      expect(theme.colorScheme.primary, tokens.colors.brand);
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.textTheme.bodyMedium!.fontFamily, BBText.family);
      for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(theme.pageTransitionsTheme.builders[p], isA<BBPageTransitionsBuilder>());
      }
    }
  });

  testWidgets('same bouncing physics on Android and iOS, no glow', (tester) async {
    for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
      await tester.pumpWidget(_app(platform: p));
      final ctx = tester.element(find.byType(ListView));
      final physics = ScrollConfiguration.of(ctx).getScrollPhysics(ctx);
      expect(physics, isA<BouncingScrollPhysics>(), reason: '$p');
      expect(find.byType(GlowingOverscrollIndicator), findsNothing);
      expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    }
  });

  testWidgets('iOS: edge swipe pops a pushed route', (tester) async {
    await tester.pumpWidget(_app(platform: TargetPlatform.iOS));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE B'), findsOneWidget);

    await tester.dragFrom(const Offset(5, 300), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('PAGE B'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('iOS: a short edge swipe springs back and keeps the page', (tester) async {
    await tester.pumpWidget(_app(platform: TargetPlatform.iOS));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('PAGE B'), findsOneWidget);
  });

  testWidgets('iOS: edge swipe on the root route does nothing', (tester) async {
    await tester.pumpWidget(_app(platform: TargetPlatform.iOS));
    await tester.dragFrom(const Offset(5, 300), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('Android: no edge-swipe detector is installed', (tester) async {
    await tester.pumpWidget(_app(platform: TargetPlatform.android));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BBEdgeSwipeBack), findsNothing);
    await tester.dragFrom(const Offset(5, 300), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('PAGE B'), findsOneWidget);
  });
}
