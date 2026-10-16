import 'package:busboard_nl/ui/board/arrival_board_screen.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:busboard_nl/ui/stop_picker/stop_picker_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

GoRouter _router(WidgetTester tester) => GoRouter.of(tester.element(find.byType(BBNavBar)));

/// On iPhone, a page pushed over the tabs closes with a drag from the left edge, as in any iOS app: go_router 18 no
/// longer recognises Flutter's MaterialApp, so without a page builder of our own every route lost the theme's page
/// transition, and with it the edge swipe.
void main() {
  final now = DateTime(testDay.year, testDay.month, testDay.day, 8, 1);

  for (final (path, page) in [('/settings', SettingsScreen), ('/board/A', ArrivalBoardScreen)]) {
    testWidgets('iOS: a drag from the left edge closes $path and returns to the stop picker', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/');
        expect(find.byType(StopPickerScreen), findsOneWidget);
        _router(tester).push(path);
        await tester.pumpAndSettle();
        expect(find.byType(page), findsOneWidget);

        await tester.dragFrom(const Offset(4, 420), const Offset(300, 0));
        await tester.pumpAndSettle();
        expect(find.byType(page), findsNothing, reason: 'the swipe left $path open');
        expect(find.byType(StopPickerScreen), findsOneWidget);
        expect(_router(tester).state.uri.toString(), '/');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });
  }

  testWidgets('a pushed page comes in with the theme transition, not all at once', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/');
    _router(tester).push('/settings');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.ancestor(of: find.byType(SettingsScreen), matching: find.byType(FadeTransition)),
      findsWidgets,
      reason: "the theme's fade and slide",
    );
    await tester.pumpAndSettle();
  });

  testWidgets('Android: system back still closes a pushed page', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/');
    _router(tester).push('/settings');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(StopPickerScreen), findsOneWidget);
  });
}
