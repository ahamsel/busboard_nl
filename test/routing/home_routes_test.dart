import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeScreen)));

void main() {
  final now = DateTime(2026, 10, 12, 13, 0);

  for (final path in ['/', '/map', '/plan', '/plan/journey']) {
    testWidgets('$path opens home at its home sheet', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: now, initial: path);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
      expect(find.byType(BBNavBar), findsNothing);
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
  });
}
