import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/home/home_shell.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

/// Android back across the two tabs (spec 2026-10-15 §2.4), and the Map tab's sheet sitting on the tab bar (§4).
final _now = DateTime(2026, 10, 12, 13, 0);

class _StopC extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(selectedStopId: 'C');
}

final _overrides = [
  settingsProvider.overrideWith(_StopC.new),
  stopArrivalsProvider.overrideWith((ref, id) async => [
        ArrivalRow(
          routeShortName: '1',
          headsign: 'Downtown',
          scheduledTime: GtfsTime.parse('13:05:00'),
          minutesAway: 4,
          isLive: true,
          vehicleNumber: '2573',
          tripId: '1-4',
        ),
      ]),
];

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeShell)));

/// System back, as Android sends it. True when the app handled it; false lets the system leave the app.
Future<bool> _back(WidgetTester tester) async {
  final handled = await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  return handled;
}

Rect _rect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

void main() {
  testWidgets('on the Board, back leaves the app, even with a card open on the map behind it', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map, overrides: _overrides);
    _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeShell.boardTabKey));
    await tester.pumpAndSettle();
    expect(await _back(tester), isFalse, reason: 'the system leaves the app');
    expect(_c(tester).read(homeTabProvider), HomeTab.board, reason: 'back never switches tabs');
    expect(_c(tester).read(homeSheetProvider), const StopSheet('B'), reason: "the map's card is left alone");
  });

  testWidgets('on the Map, back steps down one level, then leaves; it never switches to the Board', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map, overrides: _overrides);
    _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('B'));
    await tester.pumpAndSettle();
    expect(await _back(tester), isTrue);
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
    await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(await _back(tester), isTrue, reason: 'the pulled-up sheet comes down to its bar');
    expect(await _back(tester), isFalse);
    expect(_c(tester).read(homeTabProvider), HomeTab.map);
  });

  testWidgets('a follow started on the Board: back on the Map stops it, then leaves', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.board, overrides: _overrides);
    await tester.tap(find.byType(ArrivalRowTile).first);
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeTabProvider), HomeTab.map);
    expect(await _back(tester), isTrue);
    expect(_c(tester).read(followProvider), isNull);
    expect(await _back(tester), isFalse);
    expect(_c(tester).read(homeTabProvider), HomeTab.map, reason: 'not back to the Board');
  });

  testWidgets('over the Board, a pushed page pops first, then back leaves', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.board, overrides: _overrides);
    unawaited(GoRouter.of(routerElement(tester)).push('/settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(await _back(tester), isTrue);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(_c(tester).read(homeTabProvider), HomeTab.board);
    expect(await _back(tester), isFalse);
  });

  group('the Map tab sits on the tab bar (spec 2026-10-15 §4)', () {
    testWidgets('the bar rests on the tab bar, and pulled to full it stays above it', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPadding);
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map, overrides: _overrides);
      final tabBar = tester.getRect(find.byKey(BBTabBar.capsuleKey));
      expect(tabBar.bottom, 844 - 34 - BBTabBar.gap, reason: 'the capsule floats above the home indicator');
      expect(tabBar.left, BBTabBar.sideInset);
      expect(tabBar.right, 390 - BBTabBar.sideInset);
      expect(_rect(tester, BBSheet.cardKey).bottom, closeTo(tabBar.top - BBSpace.s, 1),
          reason: 'the bar rests 8 pt above the capsule');
      await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -800));
      await tester.pumpAndSettle();
      final card = _rect(tester, BBSheet.cardKey);
      expect(card.bottom, closeTo(tabBar.top - BBSpace.s, 1));
      expect(card.top, greaterThanOrEqualTo(47), reason: 'full height stays under the status bar');
    });

    testWidgets('the map runs under the capsule, and its credit sits above it', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPadding);
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map, overrides: _overrides);
      final capsule = tester.getRect(find.byKey(BBTabBar.capsuleKey));
      expect(tester.getRect(find.byKey(const ValueKey('stub-map'))).bottom, 844, reason: 'to the bottom edge');
      expect(tester.getRect(find.text('© OpenStreetMap · OpenFreeMap')).bottom, lessThanOrEqualTo(capsule.top));
      // The map still takes a touch beside the capsule.
      expect(find.byKey(const ValueKey('stub-map')).hitTestable(at: const Alignment(-0.97, 0.99)), findsOneWidget);
    });

    testWidgets('a pan tucks a card down to its peek, still above the tab bar', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map, overrides: _overrides);
      _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('B'));
      await tester.pumpAndSettle();
      final half = _rect(tester, BBSheet.cardKey).top;
      await tester.dragFrom(const Offset(60, 200), const Offset(0, 40));
      await tester.pumpAndSettle();
      final card = _rect(tester, BBSheet.cardKey);
      expect(card.top, greaterThan(half + 100), reason: 'tucked down');
      expect(card.bottom, closeTo(tester.getRect(find.byType(BBTabBar)).top - BBSpace.s, 1));
      expect(_c(tester).read(homeSheetProvider), const StopSheet('B'));
    });

    testWidgets('following and panned: Back to bus sits above the follow card, clear of the tab bar', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, tab: HomeTab.map, overrides: _overrides);
      _c(tester).read(followProvider.notifier).follow('2573');
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(60, 300), const Offset(0, 60));
      await tester.pumpAndSettle();
      final back = tester.getRect(find.text('Back to bus 2573'));
      expect(back.bottom, lessThanOrEqualTo(_rect(tester, BBSheet.cardKey).top), reason: 'above the follow card');
      expect(back.bottom, lessThan(tester.getRect(find.byType(BBTabBar)).top));
      expect(tester.getRect(find.text('Following bus 2573')).top, greaterThanOrEqualTo(0));
    });
  });
}
