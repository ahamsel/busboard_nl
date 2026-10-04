import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _alert = ServiceAlert(
  sourceIds: {'a'},
  header: 'Water Street Detour',
  description: '',
  cause: ServiceAlertCause.construction,
  effect: ServiceAlertEffect.detour,
  severity: ServiceAlertSeverity.warning,
  activePeriods: [],
  targets: [],
);

const _boardKey = ValueKey('board-content');
const _mapKey = ValueKey('map-content');
const _alertsKey = ValueKey('alerts-content');

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/', builder: (_, _) => const SizedBox.expand(key: _boardKey, child: Text('PICKER')), routes: [
                GoRoute(path: 'board/:id', builder: (_, s) => Text('BOARD ${s.pathParameters['id']}')),
              ]),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/map', builder: (_, _) => const SizedBox.expand(key: _mapKey, child: Text('MAP')))]),
            StatefulShellBranch(routes: [GoRoute(path: '/alerts', builder: (_, _) => const SizedBox.expand(key: _alertsKey, child: Text('ALERTS')))]),
          ],
        ),
      ],
    );

Future<GoRouter> _pump(WidgetTester tester, {EdgeInsets padding = EdgeInsets.zero, EdgeInsets viewInsets = EdgeInsets.zero}) async {
  final router = _router();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      serviceUpdatesProvider.overrideWith((ref) => Stream.value(ServiceUpdates(
            alerts: const [_alert],
            serviceStatus: null,
            fetchedAt: DateTime(2026, 10, 4),
            feedTimestamp: null,
          ))),
    ],
    child: MaterialApp.router(
      theme: BBTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(padding: padding, viewPadding: padding, viewInsets: viewInsets),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('shows the floating nav bar with Board / Map / Alerts and the alert count', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(find.byType(BBNavBar), findsOneWidget);
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.bySemanticsLabel('Alerts, 1 active'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tapping a tab switches branch', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.text('MAP'), findsOneWidget);
    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('ALERTS'), findsOneWidget);
  });

  testWidgets('re-tapping the current tab resets the branch to its root', (tester) async {
    final router = await _pump(tester);
    router.push('/board/1150');
    await tester.pumpAndSettle();
    expect(find.text('BOARD 1150'), findsOneWidget);
    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();
    expect(find.text('PICKER'), findsOneWidget);
  });

  double screenHeight(WidgetTester tester) =>
      tester.view.physicalSize.height / tester.view.devicePixelRatio;

  double reserved(WidgetTester tester) =>
      BBNavBar.reservedHeight(tester.element(find.byType(BBNavBar)));

  testWidgets('map content sits above the bar; board and alerts run under it', (
    tester,
  ) async {
    await _pump(tester);
    final height = screenHeight(tester);
    final r = reserved(tester);
    expect(r, BBNavBar.height + BBNavBar.gap);

    expect(tester.getRect(find.byKey(_boardKey)).bottom, height);

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_mapKey)).bottom, height - r);

    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_alertsKey)).bottom, height);
  });

  testWidgets(
    'the map content clears the bottom safe area as well as the bar',
    (tester) async {
      await _pump(tester, padding: const EdgeInsets.only(bottom: 34));
      final height = screenHeight(tester);
      final ctx = tester.element(find.byType(BBNavBar));
      expect(reserved(tester), BBNavBar.heightFor(ctx) + BBNavBar.gap + 34);

      expect(tester.getRect(find.byKey(_boardKey)).bottom, height);
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(_mapKey)).bottom,
        height - (BBNavBar.heightFor(ctx) + BBNavBar.gap + 34),
      );
      // The bar's own box spans the pill, the gap and the home-indicator inset.
      final bar = tester.getRect(find.byType(BBNavBar));
      expect(bar.bottom, height);
      expect(bar.height, BBNavBar.heightFor(ctx) + BBNavBar.gap + 34);
    },
  );

  testWidgets('the keyboard does not push the bar up or grow the map padding', (
    tester,
  ) async {
    await _pump(tester, viewInsets: const EdgeInsets.only(bottom: 300));
    final height = screenHeight(tester);
    final r = reserved(tester);
    expect(r, BBNavBar.height + BBNavBar.gap);

    final bar = tester.getRect(find.byType(BBNavBar));
    expect(bar.bottom, height);
    expect(bar.top, height - r);
    expect(tester.getRect(find.byKey(_boardKey)).bottom, height);

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_mapKey)).bottom, height - r);
  });
}
