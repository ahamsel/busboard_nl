import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/stop_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

/// The app reopens the way the rider left it: a stop's Board (its sheet at full height) open when the app went to
/// the background is open again after a cold start. Only the stop id is kept, on the phone.
const _key = 'board_open.v1';
final _now = DateTime(2026, 10, 12, 13, 0);

ArrivalRow _arrival(int minutes) => ArrivalRow(
      routeShortName: '1',
      headsign: 'Downtown',
      scheduledTime: GtfsTime.parse('13:05:00'),
      minutesAway: minutes,
      isLive: false,
      tripId: '1-$minutes',
    );

final List<Override> _overrides = [
  stopArrivalsProvider.overrideWith((ref, id) async => [for (var m = 2; m < 40; m += 6) _arrival(m)]),
];

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeScreen)));

Future<String?> _saved() => SharedPreferencesAsync().getString(_key);

/// The app goes to the background, as the phone reports it.
Future<void> _background(WidgetTester tester) async {
  for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await tester.pumpAndSettle();
}

Future<void> _foreground(WidgetTester tester) async {
  for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await tester.pumpAndSettle();
}

double _area(WidgetTester tester) => tester.view.physicalSize.height / tester.view.devicePixelRatio - 2 * BBSpace.s;

void _expectAt(WidgetTester tester, double Function(BBSheet) fraction, String what) {
  final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
  expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(fraction(sheet) * _area(tester), 1),
      reason: 'the sheet is at $what');
}

/// The stop's Board: its sheet pulled to full height.
Future<void> _openBoard(WidgetTester tester, String stopId) async {
  _c(tester).read(homeSheetProvider.notifier).openBoard(stopId);
  await tester.pumpAndSettle();
  _expectAt(tester, (s) => s.fullFraction, 'full');
}

void main() {
  tearDown(() => TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  testWidgets("a stop's Board at full height is remembered when the app goes to the background", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await _openBoard(tester, 'C');
    await _background(tester);
    expect(await _saved(), 'C');
  });

  testWidgets('a stop sheet at half is not a Board: nothing is remembered', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/board/C', overrides: _overrides);
    _expectAt(tester, (s) => s.halfFraction, 'half');
    await _background(tester);
    expect(await _saved(), isNull);
  });

  testWidgets('remembered, then collapsed below full: forgotten', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await _openBoard(tester, 'C');
    await _background(tester);
    await _foreground(tester);
    expect(await _saved(), 'C');
    final full = tester.getRect(find.byKey(BBSheet.cardKey)).height;
    final half = tester.widget<BBSheet>(find.byType(BBSheet)).halfFraction * _area(tester);
    await tester.timedDrag(find.text('STOP C'), Offset(0, full - half), const Duration(seconds: 1));
    await tester.pumpAndSettle();
    _expectAt(tester, (s) => s.halfFraction, 'half');
    expect(await _saved(), isNull);
  });

  testWidgets('remembered, then closed: forgotten', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await _openBoard(tester, 'C');
    await _background(tester);
    await _foreground(tester);
    expect(await _saved(), 'C');
    await tester.tap(find.byKey(StopSheetContent.closeKey));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
    expect(await _saved(), isNull);
  });

  testWidgets('remembered, then back: forgotten', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides);
    await _openBoard(tester, 'C');
    await _background(tester);
    await _foreground(tester);
    expect(await _saved(), 'C');
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
    expect(await _saved(), isNull);
  });

  testWidgets("a cold start with a remembered Board opens home with that stop's sheet at full height", (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides, asyncPrefs: {_key: 'C'});
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    expect(_c(tester).read(homeSheetProvider.notifier).stack, hasLength(2), reason: 'home is under it');
    _expectAt(tester, (s) => s.fullFraction, 'full');
  });

  testWidgets('a remembered stop that no longer exists opens plain home and is forgotten', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides, asyncPrefs: {_key: 'GONE'});
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
    expect(await _saved(), isNull);
  });

  testWidgets('a Board link at launch (a notification tap) wins over the remembered Board', (tester) async {
    await pumpPlannerApp(tester,
        net: TestNetwork(), now: _now, initial: '/board/A', overrides: _overrides, asyncPrefs: {_key: 'C'});
    expect(_c(tester).read(homeSheetProvider), const StopSheet('A'));
    _expectAt(tester, (s) => s.halfFraction, 'half');
    expect(await _saved(), isNull);
  });

  testWidgets('on the tablet panel (no detents) a stop shown in the panel is its Board', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPlannerApp(tester, net: TestNetwork(), now: _now, initial: '/board/C', overrides: _overrides);
    await _background(tester);
    expect(await _saved(), 'C');
  });

  testWidgets('a restore that fails (no schedule) still forgets the Board at the next background', (tester) async {
    final schedule = Completer<GtfsRepository>();
    await pumpPlannerApp(tester,
        net: TestNetwork(), now: _now, overrides: _overrides, asyncPrefs: {_key: 'C'}, repoFuture: schedule.future, settle: false);
    schedule.completeError(StateError('no schedule'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load the schedule"), findsOneWidget);
    await _background(tester);
    expect(await _saved(), isNull, reason: 'a stale Board would reopen on a later good start');
  });

  for (final link in ['A', 'C']) {
    testWidgets('a Board link for stop $link landing after the restore wins: at half, and the Board is forgotten',
        (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: _now, overrides: _overrides, asyncPrefs: {_key: 'C'});
      expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
      _expectAt(tester, (s) => s.fullFraction, 'full');

      GoRouter.of(routerElement(tester)).go('/board/$link');
      await tester.pumpAndSettle();
      expect(_c(tester).read(homeSheetProvider), StopSheet(link));
      expect(_c(tester).read(homeSheetProvider.notifier).stack, hasLength(2), reason: 'one card over home');
      _expectAt(tester, (s) => s.halfFraction, 'half');
      expect(await _saved(), isNull);
    });
  }

  testWidgets('the restore waits for the launch check: a notification that launched the app opens alone',
      (tester) async {
    final checked = Completer<bool>();
    await pumpPlannerApp(tester,
        net: TestNetwork(), now: _now, overrides: _overrides, asyncPrefs: {_key: 'C'}, launchLinkChecked: checked);
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>(), reason: 'no Board before the check is done');

    // The plugin answers late with the notification's Board link.
    GoRouter.of(routerElement(tester)).go('/board/A');
    checked.complete(true);
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('A'));
    expect(_c(tester).read(homeSheetProvider.notifier).stack, hasLength(2));
    _expectAt(tester, (s) => s.halfFraction, 'half');
    expect(await _saved(), isNull);
  });

  testWidgets('with no launch link, the restore goes ahead once the check is done', (tester) async {
    final checked = Completer<bool>();
    await pumpPlannerApp(tester,
        net: TestNetwork(), now: _now, overrides: _overrides, asyncPrefs: {_key: 'C'}, launchLinkChecked: checked);
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
    checked.complete(false);
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    _expectAt(tester, (s) => s.fullFraction, 'full');
  });
}
