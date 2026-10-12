import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/saved_place_providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/stop_card.dart';
import 'package:busboard_nl/ui/stop_picker/near_me_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planner_app.dart';
import '../trip_planner/test_network.dart';

final _now = DateTime(2026, 10, 12, 13, 0);

/// TestNetwork stop C is served by route 1 (which ends there) and route 2 (which starts there).
const _stopC = StopInfo(stopId: 'C', stopName: 'Stop C', stopLat: 47.5700, stopLon: -52.7500);

class _FixedSettings extends SettingsNotifier {
  _FixedSettings(this.stopId);
  final String? stopId;
  @override
  AppSettings build() => AppSettings(selectedStopId: stopId);
}

class _FixedPlaces extends SavedPlacesNotifier {
  _FixedPlaces(this.places);
  final List<SavedPlace> places;
  @override
  Future<List<SavedPlace>> build() async => places;
  @override
  Future<void> remove(String id) async => state = AsyncData([for (final p in places) if (p.id != id) p]);
}

class _FixedTrips extends SavedTripsNotifier {
  _FixedTrips(this.trips);
  final List<SavedTrip> trips;
  @override
  Future<List<SavedTrip>> build() async => trips;
}

final _home = SavedPlace(
  id: 'home',
  name: 'Home',
  icon: SavedPlaceIcon.home,
  place: StopPlace(stopId: 'A', name: 'Stop A'),
);

final _toWork = SavedTrip(
  id: 'trip-1',
  name: 'To work',
  from: StopPlace(stopId: 'A', name: 'Stop A'),
  to: StopPlace(stopId: 'E', name: 'Stop E'),
);

ServiceAlert _alertOnRoute1() => ServiceAlert(
      sourceIds: const {'a'},
      header: 'Detour on 1',
      description: 'Use Harbour Drive.',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
      targets: const [ServiceAlertTarget(routeId: '1')],
    );

ArrivalRow _arrival(int minutes) => ArrivalRow(
      routeShortName: '1',
      headsign: 'Downtown',
      scheduledTime: GtfsTime.parse('13:05:00'),
      predictedTime: null,
      minutesAway: minutes,
      liveStatus: null,
      isLive: false,
      tripId: '1-$minutes',
      vehicleNumber: null,
      isEnhanced: false,
      routeRun: '1-1',
    );

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeScreen)));

/// The real home on the test network, at its home sheet.
Future<void> _pumpHome(
  WidgetTester tester, {
  String? stopId = 'C',
  List<SavedPlace> places = const [],
  List<SavedTrip> trips = const [],
  List<ServiceAlert> alerts = const [],
  List<NearbyStop> nearby = const [],
  List<ArrivalRow> arrivals = const [],
  List<Override> overrides = const [],
}) =>
    pumpPlannerApp(
      tester,
      net: TestNetwork(),
      now: _now,
      appRoutes: true,
      initial: '/',
      alerts: alerts,
      nearby: nearby,
      overrides: [
        settingsProvider.overrideWith(() => _FixedSettings(stopId)),
        savedPlacesProvider.overrideWith(() => _FixedPlaces(places)),
        savedTripsProvider.overrideWith(() => _FixedTrips(trips)),
        for (final t in trips) savedTripNextProvider(t.id).overrideWith((ref) async => const []),
        stopArrivalsProvider.overrideWith((ref, id) async => arrivals),
        ...overrides,
      ],
    );

/// Pulls the sheet to its full height, where saved trips and nearby stops are.
Future<void> _pullUp(WidgetTester tester) async {
  await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -700));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('at peek: Where to, saved places, alerts for you and your stop, with no taps', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpHome(
      tester,
      places: [_home],
      alerts: [_alertOnRoute1()],
      arrivals: [_arrival(4), _arrival(12)],
    );
    expect(find.byKey(HomeSheetContent.whereToKey), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.textContaining('Detour on 1'), findsOneWidget);
    expect(find.text('Stop C'), findsWidgets);
    expect(find.byType(ArrivalsPreview), findsOneWidget);
    // Present is not enough: each is on screen and inside the peeking sheet, with no taps.
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final card = tester.getRect(find.byKey(BBSheet.cardKey));
    for (final (name, f) in [
      ('Where to?', find.byKey(HomeSheetContent.whereToKey)),
      ('the saved place', find.text('Home')),
      ('the alert for you', find.textContaining('Detour on 1')),
      ('your stop', find.bySemanticsLabel(RegExp(r'^Your stop, Stop C'))),
      ('the next bus', find.byType(ArrivalRowTile).first),
    ]) {
      final r = tester.getRect(f);
      expect(r.top, greaterThanOrEqualTo(card.top), reason: name);
      expect(r.bottom, lessThanOrEqualTo(card.bottom), reason: '$name is whole inside the peeking sheet');
      expect(r.bottom, lessThanOrEqualTo(screen.height), reason: '$name is on screen');
    }
    handle.dispose();
  });

  testWidgets('an alert that is not on your stop or its routes stays out of the header', (tester) async {
    final elsewhere = ServiceAlert(
      sourceIds: const {'b'},
      header: 'Detour on 9',
      description: '',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
      targets: const [ServiceAlertTarget(routeId: '9')],
    );
    await _pumpHome(tester, alerts: [elsewhere]);
    expect(find.textContaining('Detour on 9'), findsNothing);
  });

  testWidgets('a saved place opens trip options to it', (tester) async {
    await _pumpHome(tester, places: [_home]);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), isA<OptionsSheet>());
    final draft = _c(tester).read(planQueryProvider);
    expect(draft.to, StopPlace(stopId: 'A', name: 'Stop A'));
    expect(draft.from, isNull);
  });

  testWidgets('a saved place keeps the start that was already chosen', (tester) async {
    await _pumpHome(tester, places: [_home]);
    _c(tester).read(planQueryProvider.notifier).setFrom(StopPlace(stopId: 'G', name: 'Stop G'));
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(planQueryProvider).from, StopPlace(stopId: 'G', name: 'Stop G'));
    expect(_c(tester).read(planQueryProvider).to, StopPlace(stopId: 'A', name: 'Stop A'));
  });

  testWidgets('a long-press on a saved place offers Remove, and Cancel keeps it', (tester) async {
    await _pumpHome(tester, places: [_home]);
    await tester.longPress(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    await tester.longPress(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsNothing);
    expect(_c(tester).read(homeSheetProvider), isA<HomeSheetHome>());
  });

  testWidgets('a saved place offers Remove to a screen reader as a long-press action', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpHome(tester, places: [_home]);
    final chip = find.bySemanticsLabel('Go to Home');
    expect(tester.getSemantics(chip).getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
    tester.semantics.longPress(find.semantics.byLabel('Go to Home'));
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsNothing);
    handle.dispose();
  });

  testWidgets('an alert for you is one line, and opens Alerts', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpHome(tester, alerts: [_alertOnRoute1()]);
    final row = find.bySemanticsLabel('Alert: Detour on 1. Open alerts');
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Service alerts'), findsWidgets);
    handle.dispose();
  });

  testWidgets('your stop opens its sheet', (tester) async {
    await _pumpHome(tester, arrivals: [_arrival(4)]);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Your stop, Stop C')));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
  });

  testWidgets('a saved trip opens its options', (tester) async {
    await _pumpHome(tester, trips: [_toWork]);
    await _pullUp(tester);
    await tester.tap(find.text('To work'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), isA<OptionsSheet>());
    final draft = _c(tester).read(planQueryProvider);
    expect(draft.from, StopPlace(stopId: 'A', name: 'Stop A'));
    expect(draft.to, StopPlace(stopId: 'E', name: 'Stop E'));
  });

  testWidgets('a nearby stop opens its sheet, and does not become your stop', (tester) async {
    await _pumpHome(tester, stopId: null, nearby: const [NearbyStop(stop: _stopC, distanceMeters: 80)]);
    await _pullUp(tester);
    await tester.tap(find.text('Stop C · 80m'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(homeSheetProvider), const StopSheet('C'));
    expect(_c(tester).read(settingsProvider).selectedStopId, isNull, reason: 'the star on the stop sheet does that');
  });

  testWidgets('no stop chosen: "Choose your stop" pulls the sheet up to the nearby stops', (tester) async {
    await _pumpHome(tester, stopId: null, nearby: const [NearbyStop(stop: _stopC, distanceMeters: 80)]);
    expect(find.text('Choose your stop'), findsOneWidget);
    final before = tester.getRect(find.byKey(BBSheet.cardKey)).top;
    await tester.tap(find.text('Choose your stop'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, lessThan(before));
    expect(find.text('Stop C · 80m'), findsOneWidget);
  });

  group('the nearby list', () {
    const mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.57, stopLon: -52.73);

    GtfsRepository repoWithRoutes(List<String> names) {
      final repo = GtfsRepository();
      repo.stopsById['1150'] = mun;
      final times = <StopTimeRow>[];
      for (var i = 0; i < names.length; i++) {
        repo.routesById['r$i'] = RouteInfo(routeId: 'r$i', routeShortName: names[i], routeLongName: '');
        repo.tripsById['t$i'] =
            TripInfo(tripId: 't$i', routeId: 'r$i', serviceId: 's', tripHeadsign: '', directionId: 0);
        times.add(StopTimeRow(
            tripId: 't$i', arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1));
      }
      repo.stopTimesByStopId['1150'] = times;
      return repo;
    }

    /// MUN Centre served by route 10 both ways, route 1 one way and route 24, whose only trip ends here.
    GtfsRepository repoWithDirections() {
      final repo = GtfsRepository();
      repo.stopsById['1150'] = mun;
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
        repo.tripsById[trip] =
            TripInfo(tripId: trip, routeId: route, serviceId: 's', tripHeadsign: headsign, directionId: 0);
        repo.stopTimesByStopId.putIfAbsent('1150', () => []).add(StopTimeRow(
            tripId: trip, arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1));
        repo.stopTimesByStopId.putIfAbsent('9000', () => []).add(StopTimeRow(
            tripId: trip, arrivalTime: '08:10:00', departureTime: '08:10:00', stopId: '9000', stopSequence: 2));
      }
      repo.tripsById['e'] =
          const TripInfo(tripId: 'e', routeId: 'r24', serviceId: 's', tripHeadsign: 'MUN EXPRESS', directionId: 0);
      repo.stopTimesByStopId['1150']!.add(const StopTimeRow(
          tripId: 'e', arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 5));
      return repo;
    }

    Future<void> pumpList(
      WidgetTester tester, {
      required GtfsRepository Function() repo,
      FutureOr<List<NearbyStop>> Function()? nearby,
      double textScale = 1.0,
    }) async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          gtfsRepositoryProvider.overrideWith((ref) => repo()),
          nearestStopsProvider.overrideWith((ref) async => nearby == null ? const <NearbyStop>[] : await nearby()),
        ],
        child: MaterialApp(
          theme: BBTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(body: SingleChildScrollView(child: NearMeList())),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a pill for every route serving the stop', (tester) async {
      final names = ['1', '2', '3', '6', '9', '10', '10A', '11', '12'];
      await pumpList(tester,
          repo: () => repoWithRoutes(names), nearby: () => const [NearbyStop(stop: mun, distanceMeters: 80)]);
      expect(find.byType(RouteBadge), findsNWidgets(9));
      expect(find.text('10A'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('rows have the stop, its number and distance, and a spoken label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester,
          repo: () => repoWithRoutes(['10']), nearby: () => const [NearbyStop(stop: mun, distanceMeters: 80)]);
      expect(find.text('MUN Centre'), findsOneWidget);
      expect(find.text('Stop 1150 · 80m'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('MUN Centre, stop 1150, 80m away, routes 10')), findsOneWidget);
      expect(find.byType(RouteBadge), findsOneWidget);
      handle.dispose();
    });

    testWidgets('shows where each route goes from the stop', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester,
          repo: repoWithDirections, nearby: () => const [NearbyStop(stop: mun, distanceMeters: 80)]);
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
      await pumpList(tester,
          repo: repoWithDirections, nearby: () => const [NearbyStop(stop: mun, distanceMeters: 80)], textScale: 2.0);
      expect(tester.takeException(), isNull);
      expect(find.text('Downtown · Kelsey Drive'), findsOneWidget);
    });

    testWidgets('empty and error states', (tester) async {
      await pumpList(tester, repo: () => repoWithRoutes(['10']), nearby: () => const []);
      expect(find.text('No stops found within 800m.'), findsOneWidget);
      await pumpList(tester,
          repo: () => repoWithRoutes(['10']), nearby: () => Future<List<NearbyStop>>.error(Exception('gps off')));
      // Riverpod retries a failed provider with backoff before surfacing the error.
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.text('Unable to get location'), findsOneWidget);
      expect(find.text('Please enable location services and grant permission.'), findsOneWidget);
    });
  });
}
