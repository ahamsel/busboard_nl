import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/search/search_screen.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

/// On iPhone, every page pushed over home closes with a drag from the left edge, as in any iOS app.
void main() {
  final now = DateTime(2026, 10, 12, 13, 0);

  for (final (path, page) in [
    ('/settings', SettingsScreen),
    ('/alerts', AlertsScreen),
    ('/search', SearchScreen),
  ]) {
    testWidgets('iOS: a drag from the left edge closes $path and returns to home', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpPlannerApp(tester, net: TestNetwork(), now: now);
        final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
        c.read(homeSheetProvider.notifier).open(const StopSheet('C'));
        await tester.pumpAndSettle();
        GoRouter.of(routerElement(tester)).push(path);
        await tester.pumpAndSettle();
        expect(find.byType(page), findsOneWidget);

        await tester.dragFrom(const Offset(4, 420), const Offset(300, 0));
        await tester.pumpAndSettle();
        expect(find.byType(page), findsNothing, reason: 'the swipe left $path open');
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(GoRouter.of(routerElement(tester)).state.uri.toString(), '/');
        // The swipe closes the page only: the sheet below keeps its stop.
        expect(c.read(homeSheetProvider), const StopSheet('C'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('Android: system back closes a pushed page, then walks the sheet stack as before', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/stop/C');
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    GoRouter.of(routerElement(tester)).push('/settings');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(c.read(homeSheetProvider), const StopSheet('C'));
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
    expect(await tester.binding.handlePopRoute(), isFalse);
  });
}
