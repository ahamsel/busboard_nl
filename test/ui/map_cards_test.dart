import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/bus_card.dart';
import 'package:busboard_nl/ui/map/my_stop_card.dart';
import 'package:busboard_nl/ui/map/stop_card.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/rendering.dart' show RenderParagraph;
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
  GtfsRepository? repo,
  DateTime? now,
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
      gtfsRepositoryProvider.overrideWith((ref) async => repo ?? _repo()),
      if (now != null) plannerClockProvider.overrideWithValue(() => now),
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

  testWidgets('stop card: name, number, and the two actions', (tester) async {
    await _host(tester, header: const StopCardHeader(stop: _mun), body: const StopCardBody(stop: _mun));
    expect(find.text('MUN Centre'), findsOneWidget);
    expect(find.text('Stop 1150'), findsOneWidget);
    await tester.tap(find.text('Set as my stop'));
    await tester.pumpAndSettle();
    expect(find.text('Your stop'), findsOneWidget, reason: 'it is now your stop');
    await tester.tap(find.text('Open board'));
    await tester.pumpAndSettle();
    expect(find.text('BOARD 1150'), findsOneWidget);
  });

  testWidgets('stop card: Plan a trip from here starts a plan from this stop on the Plan tab', (tester) async {
    await _host(tester, header: const StopCardHeader(stop: _mun), body: const StopCardBody(stop: _mun));
    final open = tester.getTopLeft(find.text('Open board')).dy;
    expect(tester.getTopLeft(find.text('Plan a trip from here')).dy, greaterThan(open), reason: 'under Open board');
    expect(find.bySemanticsLabel('Plan a trip from here'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(StopCardBody)));
    await tester.tap(find.text('Plan a trip from here'));
    await tester.pumpAndSettle();
    expect(container.read(planQueryProvider).from, StopPlace(stopId: '1150', name: 'MUN Centre'));
    expect(find.text('PLAN'), findsOneWidget);
  });

  testWidgets('stop card: at 2x text on 320 pt, Plan a trip from here reads in full', (tester) async {
    await _host(tester,
        header: const StopCardHeader(stop: _mun), body: const StopCardBody(stop: _mun), textScale: 2, width: 320);
    expect(tester.renderObject<RenderParagraph>(find.text('Plan a trip from here')).didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stop card with no arrivals says so', (tester) async {
    await _host(tester, header: const StopCardHeader(stop: _mun), body: const StopCardBody(stop: _mun));
    expect(find.text('No buses due soon'), findsOneWidget);
  });

  ArrivalRow row({required String route, required bool live, String? vehicle}) => ArrivalRow(
        routeShortName: route,
        headsign: 'Downtown',
        scheduledTime: GtfsTime.parse('09:52:00'),
        minutesAway: 4,
        isLive: live,
        tripId: 't-$route',
        vehicleNumber: vehicle,
      );

  /// MUN Centre on weekday service only, its first bus 06:30 and its last 17:00 (2026-10-16 is a Friday).
  GtfsRepository weekdayRepo() {
    final repo = _repo();
    repo.calendarsById['wk'] = ServiceCalendar(
      serviceId: 'wk',
      monday: true,
      tuesday: true,
      wednesday: true,
      thursday: true,
      friday: true,
      saturday: false,
      sunday: false,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
    );
    repo.tripsById['wk-am'] =
        const TripInfo(tripId: 'wk-am', routeId: 'r16', serviceId: 'wk', tripHeadsign: 'Downtown', directionId: 0);
    repo.tripsById['wk-pm'] =
        const TripInfo(tripId: 'wk-pm', routeId: 'r16', serviceId: 'wk', tripHeadsign: 'Downtown', directionId: 0);
    for (final (trip, time) in [('wk-am', '06:30:00'), ('wk-pm', '17:00:00')]) {
      repo.stopTimesByStopId['1150'] = [
        ...?repo.stopTimesByStopId['1150'],
        StopTimeRow(tripId: trip, arrivalTime: time, departureTime: time, stopId: '1150', stopSequence: 1),
      ];
    }
    return repo;
  }

  group('with no bus due', () {
    final fridayNight = DateTime(2026, 10, 16, 23, 0);
    final thursdayNight = DateTime(2026, 10, 15, 23, 0);

    testWidgets('stop card: at night it names the first bus', (tester) async {
      final handle = tester.ensureSemantics();
      await _host(tester,
          header: const StopCardHeader(stop: _mun),
          body: const StopCardBody(stop: _mun),
          repo: weekdayRepo(),
          now: thursdayNight);
      expect(find.text('First bus 6:30 AM'), findsOneWidget);
      expect(find.text('No buses due soon'), findsNothing);
      expect(find.bySemanticsLabel('First bus 6:30 AM'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('stop card: over a weekend it names the weekday, in full for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await _host(tester,
          header: const StopCardHeader(stop: _mun),
          body: const StopCardBody(stop: _mun),
          repo: weekdayRepo(),
          now: fridayNight);
      expect(find.text('First bus Mon 6:30 AM'), findsOneWidget);
      expect(find.bySemanticsLabel('First bus Monday 6:30 AM'), findsOneWidget);
      expect(find.bySemanticsLabel('First bus Mon 6:30 AM'), findsNothing);
      handle.dispose();
    });

    testWidgets('stop card: a gap in the day keeps "No buses due soon"', (tester) async {
      // Midday Friday: the next bus (17:00) is not the day's first.
      await _host(tester,
          header: const StopCardHeader(stop: _mun),
          body: const StopCardBody(stop: _mun),
          repo: weekdayRepo(),
          now: DateTime(2026, 10, 16, 9, 0));
      expect(find.text('No buses due soon'), findsOneWidget);
    });

    testWidgets('stop card: with no service in the schedule at all it keeps "No buses due soon"', (tester) async {
      // The default repository has no stop times.
      await _host(tester, header: const StopCardHeader(stop: _mun), body: const StopCardBody(stop: _mun), now: fridayNight);
      expect(find.text('No buses due soon'), findsOneWidget);
    });

    testWidgets('your-stop card: at night it names the first bus', (tester) async {
      await _host(tester,
          header: MyStopCard.header(),
          body: MyStopCard.body(),
          prefs: {'selectedStopId': '1150'},
          repo: weekdayRepo(),
          now: fridayNight);
      expect(find.text('First bus Mon 6:30 AM'), findsOneWidget);
      expect(find.text('No buses due soon'), findsNothing);
    });

    testWidgets('a bus due keeps the rows and no first-bus line', (tester) async {
      await _host(tester,
          header: const StopCardHeader(stop: _mun),
          body: const StopCardBody(stop: _mun),
          arrivals: [row(route: '21', live: true, vehicle: '2573')],
          repo: weekdayRepo(),
          now: fridayNight);
      expect(find.textContaining('First bus'), findsNothing);
    });
  });

  testWidgets('stop card: tapping a live row follows that bus and closes the card', (tester) async {
    await _host(tester,
        header: const StopCardHeader(stop: _mun),
        body: const StopCardBody(stop: _mun),
        arrivals: [row(route: '21', live: true, vehicle: '2573')]);
    final container = ProviderScope.containerOf(tester.element(find.byType(StopCardBody)));
    container.read(mapSelectionProvider.notifier).select(const StopSelection('1150'));
    await tester.tap(find.text('Downtown'));
    await tester.pumpAndSettle();
    expect(container.read(followProvider), const FollowTarget('2573'));
    expect(container.read(mapSelectionProvider), isNull);
    expect(find.text('BOARD 1150'), findsNothing, reason: 'the rider stays on the map');
  });

  testWidgets('stop card: the Follow pill does what tapping the row does', (tester) async {
    await _host(tester,
        header: const StopCardHeader(stop: _mun),
        body: const StopCardBody(stop: _mun),
        arrivals: [row(route: '21', live: true, vehicle: '2573')]);
    final container = ProviderScope.containerOf(tester.element(find.byType(StopCardBody)));
    container.read(mapSelectionProvider.notifier).select(const StopSelection('1150'));
    expect(find.textContaining('Follow 2573'), findsOneWidget);
    await tester.tap(find.byKey(ArrivalRowTile.followKey));
    await tester.pumpAndSettle();
    expect(container.read(followProvider), const FollowTarget('2573'));
    expect(container.read(mapSelectionProvider), isNull);
    expect(find.text('BOARD 1150'), findsNothing, reason: 'the rider stays on the map');
  });

  testWidgets('stop card: scheduled and number-less rows follow nothing and say why', (tester) async {
    await _host(tester,
        header: const StopCardHeader(stop: _mun),
        body: const StopCardBody(stop: _mun),
        arrivals: [
          row(route: '5', live: false, vehicle: '2574'),
          row(route: '6', live: true),
          row(route: '7', live: true, vehicle: ''),
        ]);
    final container = ProviderScope.containerOf(tester.element(find.byType(StopCardBody)));
    expect(find.byKey(ArrivalRowTile.followKey), findsNothing);
    await tester.tap(find.byType(ArrivalRowTile).at(0));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(ArrivalRowTile.notLiveYet), findsOneWidget);
    await tester.tap(find.byType(ArrivalRowTile).at(1));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(ArrivalRowTile.noNumberYet), findsOneWidget);
    expect(find.text(ArrivalRowTile.notLiveYet), findsNothing, reason: 'one toast at a time');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(container.read(followProvider), isNull);
  });

  testWidgets('stop card: only live rows announce the follow hint', (tester) async {
    final handle = tester.ensureSemantics();
    await _host(tester,
        header: const StopCardHeader(stop: _mun),
        body: const StopCardBody(stop: _mun),
        arrivals: [row(route: '21', live: true, vehicle: '2573'), row(route: '5', live: false)]);
    expect(
      find.semantics.byLabel('Route 21 Downtown, live, 4 minutes'),
      isSemantics(
        label: 'Route 21 Downtown, live, 4 minutes',
        isButton: true,
        hasTapAction: true,
        onTapHint: 'follow bus 2573 on the map',
      ),
    );
    expect(
      find.semantics.byLabel('Route 5 Downtown, scheduled, 4 minutes'),
      isSemantics(label: 'Route 5 Downtown, scheduled, 4 minutes', isButton: true, hasTapAction: true),
    );
    handle.dispose();
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
    container.read(mapSelectionProvider.notifier).select(const BusSelection('2573'));
    expect(find.text('Follow'), findsOneWidget);
    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(container.read(followProvider), const FollowTarget('2573'));
    expect(container.read(mapSelectionProvider), isNull);
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

  testWidgets('your-stop card invites you to choose a stop when there is none', (tester) async {
    await _host(tester, header: MyStopCard.header(), body: MyStopCard.body());
    expect(find.text('Choose a stop to see its next buses'), findsOneWidget);
  });

  testWidgets('your-stop card names your stop', (tester) async {
    await _host(tester, header: MyStopCard.header(), body: MyStopCard.body(), prefs: {'selectedStopId': '1150'});
    expect(find.text('MUN Centre'), findsOneWidget);
  });
}
