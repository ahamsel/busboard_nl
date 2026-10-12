import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

final _now = DateTime(2026, 10, 12, 13, 0);

void main() {
  testWidgets('at 1024x768 the sheet is a left panel and the map controls sit to its right', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/');
    expect(find.byType(BBSheet), findsNothing);
    final panel = tester.getRect(find.byKey(const ValueKey('home-side-panel')));
    expect(panel.left, lessThan(20));
    expect(panel.width, homeSidePanelWidth);
    expect(find.byKey(HomeSheetContent.whereToKey), findsOneWidget);
    expect(find.bySemanticsLabel('Map sheet'), findsOneWidget, reason: 'the panel is named like the sheet');
    expect(tester.getRect(find.bySemanticsLabel('Settings')).left, greaterThan(panel.right));
    expect(tester.getRect(find.text('All routes')).left, greaterThan(panel.right), reason: 'the chips clear the panel');
    expect(tester.getRect(find.textContaining('OpenStreetMap')).left, greaterThan(panel.right), reason: 'so does the credit');
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('at 390 wide it is the pull-up sheet', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/');
    expect(find.byType(BBSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('home-side-panel')), findsNothing);
  });

  testWidgets('699 wide is still the sheet and 700 the panel', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(699, 900);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/');
    expect(find.byType(BBSheet), findsOneWidget);
    tester.view.physicalSize = const Size(homeSidePanelBreakpoint, 900);
    await tester.pumpAndSettle();
    expect(find.byType(BBSheet), findsNothing);
    expect(find.byKey(const ValueKey('home-side-panel')), findsOneWidget);
  });

  testWidgets('a stop opens in the panel, Choose your stop scrolls to the stops, and back returns home', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final net = TestNetwork();
    await pumpPlannerApp(
      tester,
      net: net,
      now: _now,
      initial: '/',
      nearby: [NearbyStop(stop: net.repo.stopsById['A']!, distanceMeters: 80)],
    );
    final panel = find.byKey(const ValueKey('home-side-panel'));
    await tester.tap(find.text('Choose your stop'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    container.read(homeSheetProvider.notifier).open(const StopSheet('C'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: panel, matching: find.text('Stop C')), findsWidgets);
    expect(find.byKey(HomeSheetContent.whereToKey), findsNothing);

    container.read(homeSheetProvider.notifier).back();
    await tester.pumpAndSettle();
    expect(find.byKey(HomeSheetContent.whereToKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Choose your stop scrolls the panel down to the nearby stops', (tester) async {
    tester.view.physicalSize = const Size(1024, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final net = TestNetwork();
    await pumpPlannerApp(
      tester,
      net: net,
      now: _now,
      initial: '/',
      nearby: [
        for (final (i, id) in ['A', 'B', 'C', 'D', 'E', 'F'].indexed)
          NearbyStop(stop: net.repo.stopsById[id]!, distanceMeters: 80.0 + i * 40),
      ],
    );
    final panel = find.byKey(const ValueKey('home-side-panel'));
    final scrollable = find.descendant(of: panel, matching: find.byType(Scrollable));
    ScrollPosition position() => tester.state<ScrollableState>(scrollable).position;
    expect(position().pixels, 0);
    expect(position().maxScrollExtent, greaterThan(0), reason: 'the panel is taller than the screen leaves it');
    await tester.tap(find.text('Choose your stop'));
    await tester.pumpAndSettle();
    expect(position().pixels, greaterThan(0), reason: 'scrolled past the header');
    final nearest = tester.getRect(find.text('Stop A · 80m'));
    expect(nearest.top, greaterThanOrEqualTo(tester.getRect(panel).top));
    expect(nearest.bottom, lessThanOrEqualTo(tester.getRect(panel).bottom), reason: 'the nearest stop is in view');
  });

  testWidgets("the panel's stop sheet has a Close button back to the home sheet (F2)", (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/');
    final panel = find.byKey(const ValueKey('home-side-panel'));
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    container.read(homeSheetProvider.notifier).open(const StopSheet('C'));
    await tester.pumpAndSettle();
    final close = find.descendant(of: panel, matching: find.bySemanticsLabel('Close'));
    expect(close, findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(container.read(homeSheetProvider), isA<HomeSheetHome>());
    expect(find.byKey(HomeSheetContent.whereToKey), findsOneWidget);
  });

  testWidgets('the panel stands clear of a notch at the left', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(left: 40);
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/');
    final panel = tester.getRect(find.byKey(const ValueKey('home-side-panel')));
    expect(panel.left, 40 + BBSpace.s);
    expect(tester.getRect(find.text('All routes')).left, greaterThan(panel.right));
  });
}
