import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  testWidgets('shows the floating nav bar with two tabs, Board and Map', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(find.byType(BBNavBar), findsOneWidget);
    expect(tester.widget<BBNavBar>(find.byType(BBNavBar)).items.map((i) => i.label), ['Board', 'Map']);
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Alerts'), findsNothing, reason: 'Alerts and Plan are pages now, opened from the top buttons');
    expect(find.text('Plan'), findsNothing);
    handle.dispose();
  });

  testWidgets('tapping a tab switches branch', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.text('MAP'), findsOneWidget);
    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();
    expect(find.text('PICKER'), findsOneWidget);
  });

  testWidgets('a switch of tab made by an action (Follow on the Board) is said to screen readers; a tab tap is not',
      (tester) async {
    final said = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (m) async {
      final event = m as Map<Object?, Object?>;
      if (event['type'] == 'announce') said.add((event['data']! as Map<Object?, Object?>)['message']! as String);
      return null;
    });
    addTearDown(() =>
        tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
    final router = await _pump(tester);
    router.go('/map'); // as Follow on the Board does
    await tester.pumpAndSettle();
    expect(find.text('MAP'), findsOneWidget);
    expect(said, ['Map tab'], reason: 'the Board was taken away: say where the rider is now');
    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();
    expect(said, ['Map tab'], reason: 'a tab the rider tapped needs no announcement');
    router.go('/board/1150'); // as Open board on the map does
    await tester.pumpAndSettle();
    expect(said, ['Map tab'], reason: 'already on the Board tab');
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    router.go('/board/1150');
    await tester.pumpAndSettle();
    expect(said, ['Map tab', 'Board tab']);
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

  testWidgets('every branch runs under the bar, the map included', (
    tester,
  ) async {
    await _pump(tester);
    final height = screenHeight(tester);
    final r = reserved(tester);
    expect(r, BBNavBar.height + BBNavBar.gap);

    expect(tester.getRect(find.byKey(_boardKey)).bottom, height);

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_mapKey)).bottom, height);
  });

  testWidgets(
    'the map runs under the bar (it lays out its own sheet)',
    (tester) async {
      await _pump(tester, padding: const EdgeInsets.only(bottom: 34));
      final height = screenHeight(tester);
      final ctx = tester.element(find.byType(BBNavBar));
      expect(reserved(tester), BBNavBar.heightFor(ctx) + BBNavBar.gap + 34);

      expect(tester.getRect(find.byKey(_boardKey)).bottom, height);
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_mapKey)).bottom, height);
      // The bar's own box spans the pill, the gap and the home-indicator inset.
      final bar = tester.getRect(find.byType(BBNavBar));
      expect(bar.bottom, height);
      expect(bar.height, BBNavBar.heightFor(ctx) + BBNavBar.gap + 34);
    },
  );

  testWidgets('the keyboard does not push the bar up', (
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
    expect(tester.getRect(find.byKey(_mapKey)).bottom, height);
  });
}
