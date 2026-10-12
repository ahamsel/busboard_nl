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
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/');
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
}
