import 'package:busboard_nl/data/trip_planner/saved_place_store.dart' show SavedPlaceIcon;
import 'package:busboard_nl/ui/home/home_sheet.dart' show HomeSheetContent, savedPlaceIconData;
import 'package:busboard_nl/ui/home/home_stop_line.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../trip_planner/test_network.dart';

/// "Open board" (riders used to the old Board tab): on home's Your stop, on the bar's stop line and in every stop
/// sheet's header, it opens the stop's sheet at full height, its Board; on the tablet panel it scrolls to the departures.
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

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeScreen)));

final _openBoard = find.bySemanticsLabel('Open board, Stop C');

/// The sheet card's height against its full detent.
void _expectAtFull(WidgetTester tester) {
  final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
  final area = homeSheetArea(tester);
  expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.fullFraction * area, 1),
      reason: 'the sheet is at full height');
}

void main() {
  // The app's own fonts, for the large-text check.
  setUpAll(loadAppFonts);

  test("a saved place's icon never looks like Open board's, and each kind has its own", () {
    final icons = [for (final i in SavedPlaceIcon.values) savedPlaceIconData(i)];
    expect(icons, isNot(contains(BBIcons.board)));
    expect(icons.toSet(), hasLength(icons.length));
  });

  testWidgets('Open board looks the same on home as in the stop sheet: the filled green button', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    final onHome = tester.widget<BBButton>(find.ancestor(of: _openBoard, matching: find.byType(BBButton)).first);
    expect(onHome.kind, BBButtonKind.primary, reason: 'not a text-only link while the Board is closed');
    _c(tester).read(homeSheetProvider.notifier).open(const StopSheet('C'));
    await tester.pumpAndSettle();
    final inSheet = tester.widget<BBButton>(find.ancestor(of: _openBoard, matching: find.byType(BBButton)).first);
    expect(inSheet.kind, onHome.kind);
  });

  testWidgets("the bar's stop line opens the stop's sheet at full height (spec 2026-10-14 §3.2)", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await tester.tap(find.byKey(HomeStopLine.lineKey));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    _expectAtFull(tester);
  });

  testWidgets("pulled up, home's Your stop has Open board, which opens the stop's sheet at full height", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_openBoard.hitTestable(), findsOneWidget);
    await tester.tap(_openBoard);
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    _expectAtFull(tester);
  });

  testWidgets("a stop sheet's header has Open board, which pulls the sheet from half to full", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/board/C', overrides: _overrides);
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    final area = homeSheetArea(tester);
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * area, 1));
    expect(_openBoard, findsOneWidget);
    await tester.tap(_openBoard);
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    expect(_c(tester).read(homeSheetProvider.notifier).stack, hasLength(2), reason: 'still one card over home');
    _expectAtFull(tester);
  });

  testWidgets('with the Board open the button turns into Show map, which brings the sheet back to half over the stop',
      (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/board/C', overrides: _overrides);
    await tester.tap(_openBoard);
    await tester.pumpAndSettle();
    _expectAtFull(tester);
    expect(_openBoard, findsNothing, reason: 'no button that does nothing while the Board is open');
    final showMap = find.bySemanticsLabel('Show the map, Stop C');
    expect(showMap, findsOneWidget);
    // Scrolled down the departures, it still works: the header button is pinned.
    await tester.drag(find.byType(ArrivalRowTile).at(2), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(showMap);
    await tester.pumpAndSettle();
    final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
    final area = homeSheetArea(tester);
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.halfFraction * area, 1),
        reason: 'the sheet is back at half, the map above it');
    expect(_openBoard, findsOneWidget, reason: 'and the button is Open board again');
    expect(showMap, findsNothing);
  });

  testWidgets('dragging the Board down below full turns Show map back into Open board', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/board/C', overrides: _overrides);
    await tester.tap(_openBoard);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Show the map, Stop C'), findsOneWidget);
    await tester.drag(find.byKey(BBSheet.cardKey), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(_openBoard, findsOneWidget);
  });

  testWidgets('at 2x text on a 320 wide phone, Open board and Show map read in full, light and dark',
      (tester) async {
    for (final theme in [BBTheme.light(), BBTheme.dark()]) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, textScale: 2, theme: theme, overrides: _overrides);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(HomeStopLine.lineKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Show map'), findsOneWidget, reason: 'the Board open, its button reads Show map in full');
      _expectAtFull(tester);
      await tester.tap(find.bySemanticsLabel('Show the map, Stop C'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Open board'), findsOneWidget, reason: 'and Open board reads in full too');
    }
  });

  group('on the tablet panel', () {
    ScrollPosition panelScroll(WidgetTester tester) => tester
        .state<ScrollableState>(find.descendant(
          of: find.byKey(const ValueKey('home-side-panel')),
          matching: find.byType(Scrollable),
        ))
        .position;

    void expectDeparturesInView(WidgetTester tester) {
      final panel = tester.getRect(find.byKey(const ValueKey('home-side-panel')));
      final first = tester.getRect(find.byType(ArrivalRowTile).first);
      expect(panelScroll(tester).pixels, greaterThan(0), reason: 'scrolled past the header');
      expect(first.top, greaterThanOrEqualTo(panel.top));
      expect(first.bottom, lessThanOrEqualTo(panel.bottom), reason: 'the next bus is in view');
    }

    testWidgets("home's Open board opens the stop in the panel, scrolled to its departures", (tester) async {
      tester.view.physicalSize = const Size(1024, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
      await tester.tap(_openBoard);
      await tester.pumpAndSettle();
      expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
      expectDeparturesInView(tester);
    });

    testWidgets("the stop's own Open board scrolls the panel to its departures", (tester) async {
      tester.view.physicalSize = const Size(1024, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/board/C', overrides: _overrides);
      expect(panelScroll(tester).pixels, 0);
      await tester.tap(_openBoard);
      await tester.pumpAndSettle();
      expectDeparturesInView(tester);
    });
  });
}
