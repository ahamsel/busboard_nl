import 'package:busboard_nl/data/trip_planner/saved_place_store.dart' show SavedPlaceIcon;
import 'package:busboard_nl/ui/home/home_sheet.dart' show HomeSheetContent, savedPlaceIconData;
import 'package:busboard_nl/ui/home/home_stop_line.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/home_tab_provider.dart';
import 'package:busboard_nl/ui/board/board_tab.dart';
import 'package:busboard_nl/ui/home/home_shell.dart';
import 'package:busboard_nl/ui/home/stop_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/test_network.dart';

/// "Open board" (spec 2026-10-15 §2.3): on home's Your stop, on the bar's stop line and in every stop card's header,
/// it switches to the Board tab, showing that stop. The card's old "Show map" is gone.
final _now = DateTime(2026, 10, 12, 13, 0);

class _FixedSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(selectedStopId: 'C');
}

ArrivalRow _arrival(int minutes) => ArrivalRow(
      routeShortName: '1',
      headsign: 'Downtown',
      scheduledTime: GtfsTime.parse('13:05:00'),
      minutesAway: minutes,
      isLive: false,
      tripId: '1-$minutes',
    );

final List<Override> _overrides = [
  settingsProvider.overrideWith(_FixedSettings.new),
  stopArrivalsProvider.overrideWith((ref, id) async => [for (var m = 2; m < 60; m += 6) _arrival(m)]),
];

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeShell)));

final _openBoard = find.bySemanticsLabel('Open board, Stop C');

/// The Board tab is showing [stopId].
void _expectBoardOn(WidgetTester tester, String stopId) {
  expect(_c(tester).read(homeTabProvider), HomeTab.board);
  expect(find.byType(BoardTab), findsOneWidget, reason: 'the Board is the tab showing');
  expect(find.text('STOP $stopId'), findsOneWidget);
}

void main() {
  // The app's own fonts, for the large-text check.
  setUpAll(loadAppFonts);

  test("a saved place's icon never looks like Open board's, and each kind has its own", () {
    final icons = [for (final i in SavedPlaceIcon.values) savedPlaceIconData(i)];
    expect(icons, isNot(contains(BBIcons.board)));
    expect(icons.toSet(), hasLength(icons.length));
  });

  testWidgets('Open board looks the same on home as in the stop sheet: the filled button', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    final onHome = tester.widget<BBButton>(find.ancestor(of: _openBoard, matching: find.byType(BBButton)).first);
    expect(onHome.kind, BBButtonKind.primary, reason: 'not a text-only link');
    _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
    await tester.pumpAndSettle();
    final inSheet = tester.widget<BBButton>(find.ancestor(of: _openBoard, matching: find.byType(BBButton)).first);
    expect(inSheet.kind, onHome.kind);
  });

  testWidgets("the bar's stop line switches to the Board, on your stop", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await tester.tap(find.byKey(HomeStopLine.lineKey));
    await tester.pumpAndSettle();
    _expectBoardOn(tester, 'C');
  });

  testWidgets("pulled up, home's Your stop has Open board, which switches to the Board on it", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_openBoard.hitTestable(), findsOneWidget);
    await tester.tap(_openBoard);
    await tester.pumpAndSettle();
    _expectBoardOn(tester, 'C');
  });

  testWidgets("a stop card's Open board switches to the Board on that stop; the card stays on the map",
      (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/stop/B', overrides: _overrides);
    await tester.tap(find.bySemanticsLabel('Open board, Stop B'));
    await tester.pumpAndSettle();
    _expectBoardOn(tester, 'B');
    expect(_c(tester).read(homeSheetProvider), const StopSheet('B'), reason: 'back on the map, the card is there');
  });

  testWidgets('pulled up to full, a stop card still says Open board: there is no Show map', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/stop/C', overrides: _overrides);
    await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.fullFraction * homeSheetArea(tester), 1));
    expect(find.byKey(StopSheetContent.openBoardKey), findsOneWidget);
    expect(find.text('Show map'), findsNothing);
  });

  testWidgets('at 2x text on a 320 wide phone, Open board reads in full, light and dark', (tester) async {
    for (final theme in [BBTheme.light(), BBTheme.dark()]) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpPlannerApp(tester,
          net: TestNetwork(), now: _now, textScale: 2, theme: theme, initial: '/stop/C', overrides: _overrides);
      await tester.drag(find.byType(BBPill).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final label = find.descendant(of: find.byKey(StopSheetContent.openBoardKey), matching: find.text('Open board'));
      expect(label, findsOneWidget, reason: 'Open board reads in full');
      await tester.tap(find.byKey(StopSheetContent.openBoardKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _expectBoardOn(tester, 'C');
    }
  });

  testWidgets("on the tablet panel, home's Open board switches to the Board", (tester) async {
    tester.view.physicalSize = const Size(1024, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await tester.tap(_openBoard);
    await tester.pumpAndSettle();
    _expectBoardOn(tester, 'C');
  });
}
