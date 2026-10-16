import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/bus_card.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.57, stopLon: -52.73);

GtfsRepository _repo() => GtfsRepository()
  ..stopsById['1150'] = _mun
  ..tripsById['t-16'] = const TripInfo(
    tripId: 't-16',
    routeId: 'r16',
    serviceId: 's',
    tripHeadsign: 'Downtown',
    directionId: 0,
  );

BusTrackingState _bus({int? schedDiffMins = -1, BusStatus status = BusStatus.active, int routeNumber = 10, String routeRun = 'Rt 10', String headsign = 'Downtown', String? tripId}) =>
    BusTrackingState(
      routeRun: routeRun,
      vehicleId: '2573',
      routeNumber: routeNumber,
      headsign: headsign,
      currentTripId: tripId,
      lat: 47.56,
      lon: -52.71,
      heading: 90,
      speedKmh: 29,
      lastGpsTime: DateTime.now().subtract(const Duration(seconds: 12)),
      status: status,
      lastUpdateTime: DateTime.now(),
      schedDiffMins: schedDiffMins,
    );

Future<void> _host(
  WidgetTester tester, {
  required Widget header,
  required Widget body,
  List<ArrivalRow> arrivals = const [],
  Map<String, Object> prefs = const {},
  Map<String, BusTrackingState> buses = const {},
  double textScale = 1,
  double width = 390,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => CustomScrollView(
        slivers: [SliverToBoxAdapter(child: header), SliverToBoxAdapter(child: body)],
      ),
    ),
    GoRoute(path: '/board/:id', builder: (_, s) => Text('BOARD ${s.pathParameters['id']}')),
    GoRoute(path: '/alerts', builder: (_, _) => const Text('ALERTS')),
    GoRoute(path: '/plan', builder: (_, _) => const Text('PLAN')),
  ]);
  tester.view.physicalSize = Size(width * 3, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
      stopArrivalsProvider.overrideWith((ref, stopId) async => arrivals),
      busTrackingStreamProvider.overrideWith((ref) => Stream.value(buses)),
    ],
    child: MaterialApp.router(
      theme: BBTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('delay and age wording', () {
    expect(delayText(0), 'on time');
    expect(delayText(2), '2 min early');
    expect(delayText(-1), '1 min late');
    expect(delayText(null), '');
    expect(agoText(const Duration(seconds: 12)), '12 s ago');
    expect(agoText(const Duration(minutes: 3, seconds: 5)), '3 min ago');
  });

  testWidgets('bus card: route, destination, bus number and lateness', (tester) async {
    await _host(tester,
        header: const BusCardHeader(vehicleId: '2573'), body: const BusCardBody(vehicleId: '2573'), buses: {'2573': _bus()});
    expect(find.bySemanticsLabel('Route 10'), findsOneWidget);
    expect(find.text('to Downtown'), findsOneWidget);
    expect(find.text('Bus 2573 · 1 min late'), findsOneWidget);
  });

  testWidgets("bus card: the feed's all-caps destination reads in title case", (tester) async {
    await _host(tester,
        header: const BusCardHeader(vehicleId: '2573'),
        body: const BusCardBody(vehicleId: '2573'),
        buses: {'2573': _bus(headsign: 'AVALON MALL - MUN CENTRE - DOWNTOWN')});
    expect(find.text('to Avalon Mall - MUN Centre - Downtown'), findsOneWidget);
  });

  testWidgets('bus card Follow button follows this bus and closes the selection', (tester) async {
    await _host(tester,
        header: const BusCardHeader(vehicleId: '2573'), body: const BusCardBody(vehicleId: '2573'), buses: {'2573': _bus()});
    final container = ProviderScope.containerOf(tester.element(find.byType(BusCardBody)));
    container.read(homeSheetProvider.notifier).open(const BusSheet('2573'));
    expect(find.text('Follow'), findsOneWidget);
    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(container.read(followProvider), const FollowTarget('2573'));
    expect(container.read(homeSheetProvider), isA<HomeSheetHome>());
  });

  testWidgets('with no headsign in the live feed, the destination comes from its trip', (tester) async {
    await _host(tester,
        header: const BusCardHeader(vehicleId: '2573'),
        body: const BusCardBody(vehicleId: '2573'),
        buses: {'2573': _bus(headsign: '', tripId: 't-16')});
    expect(find.text('to Downtown'), findsOneWidget);
  });

  testWidgets('a bus whose trip is unknown falls back to its route', (tester) async {
    await _host(tester,
        header: const BusCardHeader(vehicleId: '2573'),
        body: const BusCardBody(vehicleId: '2573'),
        buses: {'2573': _bus(headsign: '', tripId: 'nope')});
    expect(find.text('Route 10'), findsWidgets);
    expect(find.textContaining('to '), findsNothing);
  });

  testWidgets('a bus with no route number wears the same badge as on the map', (tester) async {
    await _host(tester,
        header: const BusCardHeader(vehicleId: '2573'),
        body: const BusCardBody(vehicleId: '2573'),
        buses: {'2573': _bus(routeNumber: 0, routeRun: 'Rt 10A')});
    expect(find.bySemanticsLabel('Route 10A'), findsOneWidget);
  });

  testWidgets('technical details start collapsed and open on tap', (tester) async {
    await _host(tester,
        header: const BusCardHeader(vehicleId: '2573'), body: const BusCardBody(vehicleId: '2573'), buses: {'2573': _bus()});
    expect(find.text('29 km/h'), findsNothing);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.text('29 km/h'), findsOneWidget);
    expect(find.textContaining('s ago'), findsOneWidget);
  });

  testWidgets('a bus that has gone away shows a plain message', (tester) async {
    await _host(tester, header: const BusCardHeader(vehicleId: '9999'), body: const BusCardBody(vehicleId: '9999'));
    expect(find.text('This bus is no longer reporting'), findsOneWidget);
  });
}
