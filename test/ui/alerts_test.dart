import 'dart:io';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/alerts/service_alert_card.dart';
import 'package:busboard_nl/ui/copy/legal_copy.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import '../kit/kit_test_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceAlert _alert(
  String header, {
  ServiceAlertEffect effect = ServiceAlertEffect.detour,
  ServiceAlertSeverity severity = ServiceAlertSeverity.warning,
  List<ServiceAlertPeriod> periods = const [],
  List<ServiceAlertTarget> targets = const [],
  String description = '',
}) =>
    ServiceAlert(
      sourceIds: {header},
      header: header,
      description: description,
      cause: ServiceAlertCause.construction,
      effect: effect,
      severity: severity,
      activePeriods: periods,
      targets: targets,
    );

final _now = DateTime.now();

Future<void> _pumpScreen(WidgetTester tester, List<ServiceAlert> alerts) async {
  final repo = GtfsRepository()
    ..stopsById['3080'] = const StopInfo(stopId: '3080', stopName: 'Freshwater Rd', stopLat: 0, stopLon: 0);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => repo),
      serviceUpdatesProvider.overrideWith((ref) => Stream.value(ServiceUpdates(
            alerts: alerts,
            serviceStatus: const MetrobusServiceStatus(
              serviceOperating: true, serviceId: '1', day: 'Weekday', message: 'Weekday service operating'),
            fetchedAt: _now,
            feedTimestamp: null,
          ))),
    ],
    child: MaterialApp(theme: BBTheme.light(), home: const AlertsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  test('tone and icon mapping', () {
    expect(ServiceAlertCard.toneOf(_alert('a', effect: ServiceAlertEffect.noService, severity: ServiceAlertSeverity.info)),
        BBPillTone.danger);
    expect(ServiceAlertCard.toneOf(_alert('a', severity: ServiceAlertSeverity.severe, effect: ServiceAlertEffect.other)),
        BBPillTone.danger);
    expect(ServiceAlertCard.toneOf(_alert('a')), BBPillTone.warn);
    expect(ServiceAlertCard.toneOf(_alert('a', effect: ServiceAlertEffect.other, severity: ServiceAlertSeverity.info)),
        BBPillTone.brand);
    expect(ServiceAlertCard.iconOf(_alert('a')), BBIcons.detour);
    expect(ServiceAlertCard.iconOf(_alert('a', effect: ServiceAlertEffect.unknown)), BBIcons.alerts);
  });

  test('period label: starts / until / active now / none', () {
    final now = DateTime(2026, 10, 4, 12);
    expect(ServiceAlertCard.periodLabel(_alert('a'), now), isNull);
    expect(ServiceAlertCard.periodLabel(_alert('a', periods: [ServiceAlertPeriod(start: DateTime(2026, 10, 5, 7, 10))]), now),
        'Starts Oct 5, 7:10 AM');
    expect(ServiceAlertCard.periodLabel(_alert('a', periods: [ServiceAlertPeriod(end: DateTime(2026, 11, 1, 12, 44))]), now),
        'Until Nov 1, 12:44 PM');
    expect(ServiceAlertCard.periodLabel(_alert('a', periods: [ServiceAlertPeriod(start: DateTime(2026, 1, 1))]), now),
        'Active now');
  });

  testWidgets('screen: status card, active section, routes and stops, footer', (tester) async {
    await _pumpScreen(tester, [
      _alert('Water Street Detour',
          description: 'Routes 3 and 10 use Harbour Drive.',
          targets: const [ServiceAlertTarget(routeId: '10'), ServiceAlertTarget(routeId: '3'), ServiceAlertTarget(stopId: '3080'), ServiceAlertTarget(stopId: '9999')]),
    ]);
    expect(find.text('Service alerts'), findsOneWidget);
    expect(tester.widget<ListView>(find.byType(ListView)).physics, isA<AlwaysScrollableScrollPhysics>());
    expect(find.text('Weekday service operating'), findsOneWidget);
    expect(find.text('Active now'), findsOneWidget);
    expect(find.text('Water Street Detour'), findsOneWidget);
    expect(find.byType(RouteBadge), findsNWidgets(2));
    expect(find.text('Freshwater Rd · 3080'), findsOneWidget);
    expect(find.text('Stop 9999'), findsOneWidget);
    expect(find.text('Routes 3 and 10 use Harbour Drive.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text(LegalCopy.footer), 200);
    expect(find.text(LegalCopy.footer), findsOneWidget);
  });

  testWidgets('no active alerts card; ended alerts are not "Upcoming"', (tester) async {
    await _pumpScreen(tester, [
      _alert('Old detour', periods: [ServiceAlertPeriod(start: DateTime(2020), end: DateTime(2020, 2))]),
      _alert('Future detour', periods: [ServiceAlertPeriod(start: _now.add(const Duration(days: 2)))]),
    ]);
    expect(find.text('No active service alerts.'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Future detour'), findsOneWidget);
    expect(find.text('Old detour'), findsNothing);
  });

  testWidgets('error state with retry', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
        serviceUpdatesProvider.overrideWith((ref) => Stream<ServiceUpdates>.error(Exception('offline'))),
      ],
      child: MaterialApp(theme: BBTheme.light(), home: const AlertsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Could not load service alerts'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('compact tappable card shows a chevron and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: BBTheme.light(),
      home: Center(child: ServiceAlertCard(alert: _alert('Detour'), compact: true, onTap: () => taps++)),
    ));
    expect(find.byIcon(BBIcons.chevronRight), findsOneWidget);
    await tester.tap(find.text('Detour'));
    expect(taps, 1);
  });

  testWidgets('error state scrolls at large text so Retry stays reachable', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var builds = 0;
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
        serviceUpdatesProvider.overrideWith((ref) {
          builds++;
          return Stream<ServiceUpdates>.error(const SocketException(
              'Failed host lookup: \'busboard.example.com\' (OS Error: nodename nor servname provided, or not known, errno = 8), address = busboard.example.com, port = 443'));
        }),
      ],
      child: MaterialApp(
        theme: BBTheme.light(),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
          child: app!,
        ),
        home: const AlertsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(builds, 1);
    await tester.scrollUntilVisible(find.text('Retry'), 100, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Retry'));
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(builds, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading state is pull-to-refresh-able', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
        serviceUpdatesProvider.overrideWith((ref) => const Stream<ServiceUpdates>.empty()),
      ],
      child: MaterialApp(theme: BBTheme.light(), home: const AlertsScreen()),
    ));
    await tester.pump();
    expect(find.byType(BBRefresh), findsOneWidget);
    expect(find.byType(BBLoading), findsOneWidget);
  });

  testWidgets('period row does not overflow at large text on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: BBTheme.light(),
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
        child: app!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ServiceAlertCard(
            alert: _alert('Water Street Detour', periods: [
              ServiceAlertPeriod(start: DateTime.now().add(const Duration(days: 2)), end: DateTime.now().add(const Duration(days: 9))),
            ]),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
