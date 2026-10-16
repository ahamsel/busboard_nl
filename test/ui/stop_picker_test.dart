import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/stop_picker/stop_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.57, stopLon: -52.73);

GtfsRepository _repo() {
  final repo = GtfsRepository();
  repo.stopsById['1150'] = _mun;
  repo.routesById['r10'] = const RouteInfo(routeId: 'r10', routeShortName: '10', routeLongName: '');
  repo.tripsById['t1'] = const TripInfo(tripId: 't1', routeId: 'r10', serviceId: 's', tripHeadsign: '', directionId: 0);
  repo.stopTimesByStopId['1150'] = const [
    StopTimeRow(tripId: 't1', arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1),
  ];
  return repo;
}

Future<void> _pump(
  WidgetTester tester, {
  required FutureOr<GtfsRepository> Function() gtfs,
  FutureOr<List<NearbyStop>> Function()? nearby,
  Map<String, Object> prefs = const {},
  double textScale = 1.0,
  double keyboardInset = 0,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const StopPickerScreen(), routes: [
      GoRoute(path: 'board/:id', builder: (_, s) => Text('BOARD ${s.pathParameters['id']}')),
    ]),
    GoRoute(path: '/settings', builder: (_, _) => const Text('SETTINGS')),
  ]);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      gtfsRepositoryProvider.overrideWith((ref) => gtfs()),
      nearestStopsProvider.overrideWith((ref) async => nearby == null ? const <NearbyStop>[] : await nearby()),
    ],
    child: MaterialApp.router(
      theme: BBTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

GtfsRepository _repoWithRoutes(List<String> names) {
  final repo = GtfsRepository();
  repo.stopsById['1150'] = _mun;
  final times = <StopTimeRow>[];
  for (var i = 0; i < names.length; i++) {
    repo.routesById['r$i'] = RouteInfo(routeId: 'r$i', routeShortName: names[i], routeLongName: '');
    repo.tripsById['t$i'] = TripInfo(tripId: 't$i', routeId: 'r$i', serviceId: 's', tripHeadsign: '', directionId: 0);
    times.add(StopTimeRow(tripId: 't$i', arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1));
  }
  repo.stopTimesByStopId['1150'] = times;
  return repo;
}

/// MUN Centre served by route 10 both ways, route 1 one way and route 24,
/// whose only trip ends here.
GtfsRepository _repoWithDirections() {
  final repo = GtfsRepository();
  repo.stopsById['1150'] = _mun;
  for (final r in ['1', '10', '24']) {
    repo.routesById['r$r'] = RouteInfo(routeId: 'r$r', routeShortName: r, routeLongName: '');
  }
  final trips = [
    ('a', 'r10', 'AVALON MALL - MUN CENTRE - DOWNTOWN'),
    ('b', 'r10', 'AVALON MALL - MUN CENTRE - DOWNTOWN'),
    ('c', 'r10', 'MUN CENTRE - AVALON MALL - KELSEY DRIVE'),
    ('d', 'r1', 'MUN-CNA-MI'),
  ];
  for (final (trip, route, headsign) in trips) {
    repo.tripsById[trip] = TripInfo(tripId: trip, routeId: route, serviceId: 's', tripHeadsign: headsign, directionId: 0);
    repo.stopTimesByStopId.putIfAbsent('1150', () => []).add(StopTimeRow(
        tripId: trip, arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1));
    repo.stopTimesByStopId.putIfAbsent('9000', () => []).add(StopTimeRow(
        tripId: trip, arrivalTime: '08:10:00', departureTime: '08:10:00', stopId: '9000', stopSequence: 2));
  }
  repo.tripsById['e'] = const TripInfo(tripId: 'e', routeId: 'r24', serviceId: 's', tripHeadsign: 'MUN EXPRESS', directionId: 0);
  repo.stopTimesByStopId['1150']!.add(const StopTimeRow(
      tripId: 'e', arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 5));
  return repo;
}

void main() {
  testWidgets('near-me shows a pill for every route serving the stop', (tester) async {
    final names = ['1', '2', '3', '6', '9', '10', '10A', '11', '12'];
    await _pump(tester, gtfs: () => _repoWithRoutes(names), nearby: () => const [NearbyStop(stop: _mun, distanceMeters: 80)]);
    expect(find.byType(RouteBadge), findsNWidgets(9));
    expect(find.text('10A'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('header, stop entry and near-me rows with route pills', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, gtfs: _repo, nearby: () => const [NearbyStop(stop: _mun, distanceMeters: 80)]);
    expect(find.text('Choose a stop'), findsOneWidget);
    expect(find.text('Stop number on the pole'), findsOneWidget);
    expect(find.text('MUN Centre'), findsOneWidget);
    expect(find.text('Stop 1150 · 80m'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('MUN Centre, stop 1150, 80m away, routes 10')), findsOneWidget);
    expect(find.byType(RouteBadge), findsOneWidget);
    handle.dispose();
  });

  testWidgets('near-me shows where each route goes from the stop', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, gtfs: _repoWithDirections, nearby: () => const [NearbyStop(stop: _mun, distanceMeters: 80)]);
    expect(find.byType(RouteBadge), findsNWidgets(3));
    expect(find.text('Downtown · Kelsey Drive'), findsOneWidget);
    expect(find.text('MI'), findsOneWidget);
    // Route 24 only ends here: chip, no destination.
    expect(find.text('24'), findsOneWidget);
    expect(
      find.bySemanticsLabel('MUN Centre, stop 1150, 80m away, routes 1 to MI, 10 to Downtown or Kelsey Drive, 24'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('long destinations fit a 320pt phone at text scale 2.0', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, gtfs: _repoWithDirections, nearby: () => const [NearbyStop(stop: _mun, distanceMeters: 80)],
        textScale: 2.0);
    expect(tester.takeException(), isNull);
    expect(find.text('Downtown · Kelsey Drive'), findsOneWidget);
  });

  testWidgets('stop entry validates and navigates (saving the stop first)', (tester) async {
    await _pump(tester, gtfs: _repo);
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(find.text('Please enter a stop ID'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '115');
    await tester.pump();
    expect(find.text('Please enter a stop ID'), findsNothing); // cleared on edit
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(find.text('Stop ID must be 4 digits'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1150');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.text('BOARD 1150'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('selectedStopId'), '1150');
  });

  testWidgets('the stop number field keeps its name for screen readers once a number is typed', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, gtfs: _repo);
    await tester.enterText(find.byType(TextField), '1150');
    await tester.pumpAndSettle(); // the hint has faded out
    final field = tester.getSemantics(find.byType(EditableText));
    expect(field.label, 'Stop number on the pole', reason: 'a stable name, read with the typed value');
    expect(field.value, '1150');
    handle.dispose();
  });

  testWidgets('tapping a near-me stop saves it and opens its board', (tester) async {
    await _pump(tester, gtfs: _repo, nearby: () => const [NearbyStop(stop: _mun, distanceMeters: 80)]);
    await tester.tap(find.text('MUN Centre'));
    await tester.pumpAndSettle();
    expect(find.text('BOARD 1150'), findsOneWidget);
  });

  testWidgets('last stop card opens the saved stop', (tester) async {
    await _pump(tester, gtfs: _repo, prefs: {'selectedStopId': '1150'});
    expect(find.text('Last stop'), findsOneWidget);
    await tester.tap(find.text('Last stop'));
    await tester.pumpAndSettle();
    expect(find.text('BOARD 1150'), findsOneWidget);
  });

  group('a quick double tap opens one Board (the second tap lands before the Board shows)', () {
    Future<void> doubleTap(WidgetTester tester, Finder target) async {
      await tester.tap(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> expectOneBoardThenAgain(WidgetTester tester, Finder target) async {
      expect(find.text('BOARD 1150', skipOffstage: false), findsOneWidget);
      // One back returns to the picker, and the same tap opens the Board again.
      GoRouter.of(tester.element(find.text('BOARD 1150'))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(StopPickerScreen), findsOneWidget);
      expect(find.text('BOARD 1150', skipOffstage: false), findsNothing);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('BOARD 1150'), findsOneWidget);
    }

    testWidgets('a near-me stop', (tester) async {
      await _pump(tester, gtfs: _repo, nearby: () => const [NearbyStop(stop: _mun, distanceMeters: 80)]);
      // Once visited, the stop is also the last stop card above Near me.
      final nearMe = find.text('MUN Centre').last;
      await doubleTap(tester, nearMe);
      await expectOneBoardThenAgain(tester, nearMe);
    });

    testWidgets('the last stop card', (tester) async {
      await _pump(tester, gtfs: _repo, prefs: {'selectedStopId': '1150'});
      await doubleTap(tester, find.text('Last stop'));
      await expectOneBoardThenAgain(tester, find.text('Last stop'));
    });

    testWidgets('Go', (tester) async {
      // A stop already saved, so its card is there before and after (a new card would rebuild the field empty).
      await _pump(tester, gtfs: _repo, prefs: {'selectedStopId': '1150'});
      await tester.enterText(find.byType(TextField), '1150');
      await doubleTap(tester, find.text('Go'));
      await expectOneBoardThenAgain(tester, find.text('Go'));
    });
  });

  testWidgets('settings is reachable while GTFS is loading', (tester) async {
    final handle = tester.ensureSemantics();
    final never = Completer<GtfsRepository>();
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const StopPickerScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const Text('SETTINGS')),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [gtfsRepositoryProvider.overrideWith((ref) => never.future)],
      child: MaterialApp.router(theme: BBTheme.light(), routerConfig: router),
    ));
    await tester.pump();
    expect(find.text('Loading schedule data...'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('GTFS error shows retry', (tester) async {
    await _pump(tester, gtfs: () => Future<GtfsRepository>.error(Exception('offline')));
    expect(find.text('Failed to load schedule'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a schedule that fails to reload keeps the picker, Near me and its route pills on the one loaded',
      (tester) async {
    // Settings, Refresh schedule, while offline: the second load fails (Settings says so in a toast).
    var loads = 0;
    await _pump(
      tester,
      gtfs: () => ++loads > 1 ? Future<GtfsRepository>.error(Exception('offline')) : _repo(),
      nearby: () => const [NearbyStop(stop: _mun, distanceMeters: 80)],
    );
    expect(find.text('MUN Centre'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    ProviderScope.containerOf(tester.element(find.byType(StopPickerScreen))).invalidate(gtfsRepositoryProvider);
    await tester.pumpAndSettle();
    expect(loads, greaterThanOrEqualTo(2), reason: 'the reload ran (and failed, as do its retries)');
    expect(find.text('Failed to load schedule'), findsNothing, reason: 'not an error until a relaunch');
    expect(find.text('MUN Centre'), findsOneWidget);
    expect(find.text('10'), findsOneWidget, reason: 'the route pills stay too');
    expect(find.text('Stop number'), findsOneWidget);
  });

  testWidgets('near-me empty and error states', (tester) async {
    await _pump(tester, gtfs: _repo, nearby: () => const []);
    expect(find.text('No stops found within 800m.'), findsOneWidget);
    await _pump(tester, gtfs: _repo, nearby: () => Future<List<NearbyStop>>.error(Exception('gps off')));
    // Riverpod retries a failed provider with backoff before surfacing the error.
    // The spinner's ticker used to keep frames coming through that wait;
    // the static skeleton does not, so advance the clock explicitly.
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('Unable to get location'), findsOneWidget);
    expect(find.text('Please enable location services and grant permission.'), findsOneWidget);
  });

  testWidgets('no overflow at text scale 2.0 on a 320pt phone', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, gtfs: _repo, nearby: () => const [NearbyStop(stop: _mun, distanceMeters: 80)],
        prefs: {'selectedStopId': '1150'}, textScale: 2.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('last near-me row can scroll above an open keyboard', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 700 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final stops = [
      for (var i = 0; i < 8; i++) const NearbyStop(stop: _mun, distanceMeters: 80),
    ];
    await _pump(tester, gtfs: _repo, nearby: () => stops, keyboardInset: 300);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getRect(find.text('MUN Centre').last).bottom, lessThanOrEqualTo(screenHeight - 300));
  });
}
