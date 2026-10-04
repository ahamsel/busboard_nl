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

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/', builder: (_, _) => const Text('PICKER'), routes: [
                GoRoute(path: 'board/:id', builder: (_, s) => Text('BOARD ${s.pathParameters['id']}')),
              ]),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/map', builder: (_, _) => const Text('MAP'))]),
            StatefulShellBranch(routes: [GoRoute(path: '/alerts', builder: (_, _) => const Text('ALERTS'))]),
          ],
        ),
      ],
    );

Future<GoRouter> _pump(WidgetTester tester) async {
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
    child: MaterialApp.router(theme: BBTheme.light(), routerConfig: router),
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

  testWidgets('map tab content sits above the bar; other tabs run under it', (tester) async {
    await _pump(tester);
    final barTop = tester.getTopLeft(find.byType(BBNavBar)).dy;
    expect(tester.getBottomLeft(find.text('PICKER')).dy, greaterThan(0));
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    final mapPadding = tester.widget<Padding>(
      find.ancestor(of: find.text('MAP'), matching: find.byType(Padding)).first,
    );
    expect((mapPadding.padding as EdgeInsets).bottom, greaterThan(0));
    expect(barTop, greaterThan(0));
  });
}
