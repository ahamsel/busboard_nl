import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/map_buttons.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeScreen)));

ArrivalRow _row(int minutes) => ArrivalRow(
      routeShortName: '1',
      headsign: 'Downtown',
      scheduledTime: GtfsTime.parse('13:05:00'),
      minutesAway: minutes,
      isLive: false,
      tripId: '1-$minutes',
    );

/// The stop's departures, whatever the stop.
final _rows = stopArrivalsProvider.overrideWith((ref, id) async => [_row(4), _row(12), _row(20)]);

/// [f] is whole inside the sheet's card and on screen: what the rider sees without pulling the sheet.
void _expectInView(WidgetTester tester, Finder f, String what) {
  final card = tester.getRect(find.byKey(BBSheet.cardKey));
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final r = tester.getRect(f);
  expect(r.top, greaterThanOrEqualTo(card.top), reason: '$what starts inside the sheet');
  expect(r.bottom, lessThanOrEqualTo(card.bottom), reason: '$what ends inside the sheet');
  expect(r.bottom, lessThanOrEqualTo(screen.height), reason: '$what is on screen');
}

void main() {
  final now = DateTime(2026, 10, 12, 13, 0);

  for (final path in ['/', '/map', '/plan', '/plan/journey']) {
    testWidgets('$path opens home at its home sheet', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: path);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
    });
  }

  testWidgets('/plan/journey with a journey as extra (an old link) also lands on home at its home sheet', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/');
    final j = Journey(serviceDate: testDay, legs: [
      RideLeg(routeId: '1', tripId: '1-0', boardStopId: 'A', alightStopId: 'C', departs: 8 * 3600, arrives: 8 * 3600 + 600, stopCount: 2),
    ]);
    GoRouter.of(routerElement(tester)).go('/plan/journey', extra: j);
    await tester.pumpAndSettle();
    expect(GoRouter.of(routerElement(tester)).state.uri.toString(), '/');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
  });

  for (final path in ['/board/1150', '/stop/1150']) {
    testWidgets('$path opens home with that stop\'s sheet', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: path);
      expect(_c(tester).read(homeSheetProvider), const StopSheet('1150'));
    });
  }

  testWidgets('a board link opens the stop sheet at half, with its next buses in view (F1, spec §3.2)', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/board/C', overrides: [_rows]);
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    _expectInView(tester, find.byType(ArrivalRowTile).first, 'the next bus');
  });

  testWidgets('/alerts pushes the Alerts screen over home, and its back returns', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/');
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Alerts')));
    await tester.pumpAndSettle();
    expect(find.text('Service alerts'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the Alerts button counts the active alerts in its label', (tester) async {
    final alert = ServiceAlert(
      sourceIds: const {'a'},
      header: 'Water Street Detour',
      description: 'Use Harbour Drive.',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
      targets: const [ServiceAlertTarget(routeId: '3')],
    );
    await pumpPlannerApp(
      tester,
      net: TestNetwork(),
      now: now,
      initial: '/',
      alerts: [alert],
    );
    expect(find.bySemanticsLabel('Alerts, 1 active'), findsOneWidget);
  });

  testWidgets('the gear opens Settings', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/');
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('system back walks the sheet stack, then leaves (Review Focus 2)', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/board/1150');
    expect(_c(tester).read(homeSheetProvider), const StopSheet('1150'));
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue); // handled: the sheet went back
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
    expect(find.byType(HomeScreen), findsOneWidget);
    // At the home sheet the app does not handle back: the system may leave it.
    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  testWidgets('system back from a journey goes to its options, then home, then leaves', (tester) async {
    await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/');
    final j = Journey(serviceDate: testDay, legs: [
      RideLeg(routeId: '1', tripId: '1-0', boardStopId: 'A', alightStopId: 'C', departs: 8 * 3600, arrives: 8 * 3600 + 600, stopCount: 2),
    ]);
    final sheets = _c(tester).read(homeSheetProvider.notifier);
    sheets.open(const OptionsSheet());
    sheets.open(JourneySheet(j));
    await tester.pumpAndSettle();
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), isA<OptionsSheet>());
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  testWidgets('at 2x text the alerts count stays small on the bell and All routes reads in full (D4)', (tester) async {
    final alert = ServiceAlert(
      sourceIds: const {'a'},
      header: 'Water Street Detour',
      description: 'Use Harbour Drive.',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
      targets: const [ServiceAlertTarget(routeId: '3')],
    );
    /// The count's rect, from the bell button's top left.
    Future<Rect> badgeAt(double scale) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: '/', alerts: [alert], textScale: scale);
      final bell = tester.getRect(find.bySemanticsLabel('Alerts, 1 active'));
      return tester.getRect(find.descendant(of: find.byType(MapButtons), matching: find.text('1'))).shift(-bell.topLeft);
    }

    final capped = await badgeAt(1.3);
    final large = await badgeAt(2);
    // The count stops growing at 1.3x: past that it would cover the bell it sits on.
    expect(large, capped, reason: 'the count keeps growing with the text');
    expect(large.bottom, lessThan(44 * 0.75), reason: 'the count reaches down over the bell');
    expect(tester.renderObject<RenderParagraph>(find.text('All routes')).didExceedMaxLines, isFalse,
        reason: 'All routes is cut short');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a board link before the schedule loads shows the stop sheet loading, then its rows (Review Focus 1)',
      (tester) async {
    // 'C' is a stop of TestNetwork; 1150 is not, and an unknown stop shows no card.
    final net = TestNetwork();
    final schedule = Completer<GtfsRepository>();
    await pumpPlannerApp(
      tester,
      net: net,
      now: now,
      initial: '/board/C',
      repoFuture: schedule.future,
      settle: false,
      overrides: [_rows],
    );
    await tester.pump();
    await tester.pump();
    // The schedule is still pending: the sheet is already the stop's, and the home says it is loading.
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    expect(find.byType(BBLoading), findsOneWidget);
    expect(find.bySemanticsLabel('Loading the map'), findsOneWidget);
    expect(find.textContaining('Stop C'), findsNothing);
    schedule.complete(net.repo);
    await tester.pumpAndSettle();
    expect(find.byType(BBLoading), findsNothing);
    expect(find.textContaining('Stop C'), findsWidgets);
    // Once the schedule is in, the stop sheet is at half with its departures in view (F1).
    _expectInView(tester, find.byType(ArrivalRowTile).first, 'the next bus');
  });
}
