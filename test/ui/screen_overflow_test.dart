import 'dart:async';
import 'dart:io';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/domain/map/follow_tracker.dart';
import 'package:busboard_nl/domain/map/route_geometry.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/data/trip_planner/saved_place_store.dart';
import 'package:busboard_nl/data/trip_planner/saved_trip_store.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/saved_place_providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/trip_planner/journey_card.dart';
import 'package:busboard_nl/ui/home/stop_sheet.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/bus_card.dart';
import 'package:busboard_nl/ui/map/follow_card.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../helpers/fake_alerts.dart';
import '../trip_planner/test_network.dart';

/// Large-text guard: every Phase 2 screen is scrolled to its end at 2x text on
/// the two smallest supported phones, and any layout exception fails the test.
const _sizes = [Size(320, 568), Size(360, 640)];

const _longStopName = 'Elizabeth Avenue at Allandale Road Westbound';
const _stop = StopInfo(stopId: '1150', stopName: _longStopName, stopLat: 47.57, stopLon: -52.73);
const _routes = ['1', '2', '3', '6', '9', '10', '10A', '11', '12'];

GtfsRepository _repo() {
  final repo = GtfsRepository()..stopsById['1150'] = _stop;
  final times = <StopTimeRow>[];
  for (var i = 0; i < _routes.length; i++) {
    repo.routesById['r$i'] = RouteInfo(routeId: 'r$i', routeShortName: _routes[i], routeLongName: '');
    repo.tripsById['t$i'] = TripInfo(tripId: 't$i', routeId: 'r$i', serviceId: 's', tripHeadsign: '', directionId: 0);
    times.add(StopTimeRow(
        tripId: 't$i', arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1));
  }
  repo.stopTimesByStopId['1150'] = times;
  return repo;
}

ServiceAlert _alert(String header, {String description = ''}) => ServiceAlert(
      sourceIds: {header},
      header: header,
      description: description,
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.detour,
      severity: ServiceAlertSeverity.warning,
      activePeriods: [
        ServiceAlertPeriod(
          start: DateTime.now().subtract(const Duration(days: 1)),
          end: DateTime.now().add(const Duration(days: 20)),
        ),
      ],
      targets: const [
        ServiceAlertTarget(routeId: '10'),
        ServiceAlertTarget(routeId: '10A'),
        ServiceAlertTarget(routeId: '29'),
        ServiceAlertTarget(stopId: '1150'),
        ServiceAlertTarget(stopId: '9999'),
      ],
    );

ServiceUpdates _updates(List<ServiceAlert> alerts) => ServiceUpdates(
      alerts: alerts,
      serviceStatus: const MetrobusServiceStatus(
          serviceOperating: true, serviceId: '1', day: 'Weekday', message: 'Weekday service operating'),
      fetchedAt: DateTime(2026, 10, 4),
      feedTimestamp: null,
    );

final _failing = MockClient((_) async => http.Response('down', 500));
final _emptyKiosk = MockClient((_) async => http.Response('{"arrivals":[]}', 200));

class _Screen {
  const _Screen(this.name, this.build, {this.afterPump});
  final String name;
  final Widget Function(WidgetTester tester) build;

  /// Runs once after the first settle, e.g. to expand a collapsed section.
  final Future<void> Function(WidgetTester tester)? afterPump;
}

// The way the map screen hosts a card: header and body as sliver boxes.
Widget _card(Widget header, Widget body) => CustomScrollView(
      slivers: [SliverToBoxAdapter(child: header), SliverToBoxAdapter(child: body)],
    );

ArrivalRow _arrival(int minutes, {bool live = true}) => ArrivalRow(
      routeShortName: '10A',
      headsign: 'Signal Hill Road via Elizabeth Avenue',
      scheduledTime: GtfsTime.parse('09:52:00'),
      predictedTime: live ? GtfsTime.parse('09:55:00') : null,
      minutesAway: minutes,
      liveStatus: live ? LiveStatus.behind : null,
      isLive: live,
      tripId: 't',
      vehicleNumber: '2134',
      isEnhanced: false,
      routeRun: '10A-1',
      currentLocation: _longStopName,
    );

final _arrivals = [_arrival(2), _arrival(9), _arrival(17, live: false)];

BusTrackingState _bus({BusStatus status = BusStatus.stale}) => BusTrackingState(
      routeRun: 'Rt 10',
      vehicleId: '2573',
      routeNumber: 10,
      headsign: 'Signal Hill Road via Elizabeth Avenue',
      lat: 47.56,
      lon: -52.71,
      heading: 270,
      speedKmh: 29,
      lastGpsTime: DateTime.now().subtract(const Duration(minutes: 3)),
      status: status,
      lastUpdateTime: DateTime.now(),
      schedDiffMins: -12,
    );

FollowSnapshot _followSnapshot({bool arrived = false}) => FollowSnapshot(
      vehicleId: '2573',
      bus: _bus(status: BusStatus.active),
      tripId: 't1',
      stale: false,
      lastSeenAgo: const Duration(seconds: 10),
      stops: [
        for (var i = 0; i < 8; i++)
          TripStop(
            stopId: 's$i',
            name: 'Elizabeth Avenue at Allandale Road Westbound, stop $i',
            sequence: i + 1,
            progress: i / 8,
            departureSeconds: 43200 + i * 240,
          ),
      ],
      busIndex: 1,
      yourStopIndex: 5,
      stopsToYourStop: 4,
      arrived: arrived,
      ended: null,
    );

Widget _followCard({bool arrived = false}) {
  final snapshot = _followSnapshot(arrived: arrived);
  return _card(
    FollowCardHeader(
      snapshot: snapshot,
      yourStopName: _longStopName,
      minutesToYourStop: 14,
      tripHeadsign: 'Signal Hill Road via Elizabeth Avenue',
      onStop: () {},
      onSeeAll: () {},
    ),
    FollowCardBody(snapshot: snapshot),
  );
}

List<Override> _mapOverrides({List<ArrivalRow> arrivals = const []}) => [
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
      stopArrivalsProvider.overrideWith((ref, stopId) async => arrivals),
      busTrackingStreamProvider.overrideWith((ref) => Stream.value({'2573': _bus()})),
      serviceUpdatesProvider.overrideWith(
          (ref) => Stream.value(_updates([_alert('Water Street detour', description: 'Routes 10 and 10A use Harbour Drive.')]))),
    ];

class _Places extends SavedPlacesNotifier {
  @override
  Future<List<SavedPlace>> build() async => [
        SavedPlace(
            id: 'home',
            name: 'Home',
            icon: SavedPlaceIcon.home,
            place: StopPlace(stopId: '1150', name: _longStopName)),
        SavedPlace(
            id: 'work',
            name: 'Memorial University of Newfoundland',
            icon: SavedPlaceIcon.work,
            place: StopPlace(stopId: '1150', name: _longStopName)),
      ];
}

class _Trips extends SavedTripsNotifier {
  @override
  Future<List<SavedTrip>> build() async => [
        SavedTrip(
            id: 't1',
            name: 'To the Avalon Mall and back again',
            from: StopPlace(stopId: '1150', name: _longStopName),
            to: StopPlace(stopId: '1150', name: _longStopName)),
      ];
}

class _UpdatedAt extends StopArrivalsUpdatedAtNotifier {
  @override
  Map<String, DateTime> build() => {'1150': DateTime(2026, 10, 12, 21, 52, 4)};
}

class _StopCSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(selectedStopId: 'C');
}

/// The home sheet with a stop, arrivals, saved places and a trip, an alert on the stop and two nearby stops.
List<Override> _homeOverrides({List<ArrivalRow> arrivals = const []}) => [
      ..._mapOverrides(arrivals: arrivals),
      savedPlacesProvider.overrideWith(_Places.new),
      savedTripsProvider.overrideWith(_Trips.new),
      savedTripNextProvider('t1').overrideWith((ref) async => const []),
      nearestStopsProvider.overrideWith((ref) async => const [
            NearbyStop(stop: _stop, distanceMeters: 80),
            NearbyStop(stop: _stop, distanceMeters: 640),
          ]),
    ];

Widget _app(Widget screen, List<Override> overrides) {
  final container = ProviderContainer(retry: (_, _) => null, overrides: overrides);
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: BBTheme.light(), builder: _scaled, routerConfig: _router(screen)),
  );
}

Widget _scaled(BuildContext context, Widget? app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
      child: app!,
    );

GoRouter _router(Widget screen) => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/alerts', builder: (_, _) => const SizedBox()),
    ]);

final _screens = <_Screen>[
  _Screen('stop sheet (alert + failing live feed)', (t) {
    SharedPreferences.setMockInitialValues({});
    useInMemoryAlertStore();
    return _app(_card(StopSheetContent.header('1150'), StopSheetContent.body('1150')), [
      ...fakeAlertOverrides,
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
      timetrackApiProvider.overrideWithValue(TimeTrackApi(client: _failing)),
      metrobusMobileApiProvider.overrideWithValue(MetrobusMobileApi(client: _emptyKiosk)),
      serviceUpdatesProvider.overrideWith((ref) => Stream.value(_updates([
            _alert('Water Street detour', description: 'Routes 10 and 10A use Harbour Drive.'),
            _alert('Second alert'),
          ]))),
    ]);
  }),
  _Screen('alerts (data)', (t) {
    SharedPreferences.setMockInitialValues({});
    return _app(const AlertsScreen(), [
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
      serviceUpdatesProvider.overrideWith((ref) => Stream.value(_updates([
            for (var i = 0; i < 4; i++)
              _alert('Water Street detour number $i',
                  description: 'Routes 10, 10A and 29 use Harbour Drive between Duckworth Street and Prescott Street.'),
          ]))),
    ]);
  }),
  _Screen('alerts (error)', (t) {
    SharedPreferences.setMockInitialValues({});
    return _app(const AlertsScreen(), [
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
      serviceUpdatesProvider.overrideWith((ref) => Stream<ServiceUpdates>.error(const SocketException(
          'Failed host lookup: busboard.example.com (OS Error: nodename nor servname provided, or not known, errno = 8), address = busboard.example.com, port = 443'))),
    ]);
  }),
  _Screen('stop sheet (3 arrivals, alert)', (t) {
    SharedPreferences.setMockInitialValues({});
    return _app(
      _card(StopSheetContent.header('1150'), StopSheetContent.body('1150')),
      _mapOverrides(arrivals: _arrivals),
    );
  }),
  _Screen('map: bus card (technical details open, alert)', (t) {
    SharedPreferences.setMockInitialValues({});
    return _app(
      _card(const BusCardHeader(vehicleId: '2573'), const BusCardBody(vehicleId: '2573')),
      _mapOverrides(),
    );
  }, afterPump: (tester) async {
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.text('29 km/h'), findsOneWidget, reason: 'technical details are open');
  }),
  _Screen('home: sheet (your stop, 3 arrivals, saved place, alert, saved trip, nearby with 9 routes)', (t) {
    SharedPreferences.setMockInitialValues({'selectedStopId': '1150'});
    return _app(
      _card(HomeSheetContent.header(), HomeSheetContent.body()),
      _homeOverrides(arrivals: _arrivals),
    );
  }),
  _Screen('home: sheet (your stop, 2 arrivals)', (t) {
    SharedPreferences.setMockInitialValues({'selectedStopId': '1150'});
    return _app(
      _card(HomeSheetContent.header(), HomeSheetContent.body()),
      _homeOverrides(arrivals: _arrivals.take(2).toList()),
    );
  }),
  _Screen('home: sheet (no stop chosen, nothing saved)', (t) {
    SharedPreferences.setMockInitialValues({});
    return _app(
      _card(HomeSheetContent.header(onChooseStop: () {}), HomeSheetContent.body()),
      _mapOverrides(),
    );
  }),
  _Screen('map: follow card (8 long stops, your stop 4 away)', (t) => _app(_followCard(), const [])),
  _Screen('map: follow card (arrived)', (t) => _app(_followCard(arrived: true), const [])),
  _Screen('settings', (t) {
    SharedPreferences.setMockInitialValues({});
    return _app(const SettingsScreen(), [
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
    ]);
  }),
];

/// Drags the first scrollable up repeatedly (past its end), failing on any
/// exception recorded by the framework (RenderFlex overflow, etc.).
Future<void> _scrollThrough(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 14; i++) {
    await tester.drag(scrollable, const Offset(0, -300), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull, reason: 'after drag ${i + 1}');
  }
}

void main() {
  setUpAll(loadAppFonts);

  for (final size in _sizes) {
    for (final screen in _screens) {
      testWidgets('${screen.name} at ${size.width.toInt()}x${size.height.toInt()}, 2.0x text', (tester) async {
        tester.view.physicalSize = Size(size.width * 3, size.height * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(screen.build(tester));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'initial layout');
        await screen.afterPump?.call(tester);
        expect(tester.takeException(), isNull, reason: 'after setup');
        await _scrollThrough(tester);

        // Unmount and let the board's refresh timer / request timeouts drain.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 11));
      });
    }
  }

  // The real app's stop sheet and trip options at 2x text, on a small phone, in both themes (spec §4.5). The stop
  // sheet's live line puts the "updated" time next to the state, so it also runs with a live list on the narrowest
  // supported width (the header must wrap rather than overflow).
  Future<void> scrollSheet(WidgetTester tester) async {
    final list = find.descendant(of: find.byKey(BBSheet.cardKey), matching: find.byType(Scrollable)).first;
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, -300), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'after drag ${i + 1}');
    }
  }

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    final liveRows = [_arrival(2), _arrival(9), _arrival(17)];

    for (final (size, live) in [(const Size(360, 640), false), (const Size(320, 640), true)]) {
      testWidgets('the stop sheet at ${size.width.toInt()}x${size.height.toInt()}, 2.0x text, $theme${live ? ', live' : ''}',
          (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await pumpPlannerApp(
          tester,
          net: TestNetwork(),
          now: DateTime(2026, 10, 12, 13, 0),
          initial: '/board/1150',
          textScale: 2.0,
          use24h: false,
          theme: dark ? BBTheme.dark() : BBTheme.light(),
          repoFuture: Future.value(_repo()),
          alerts: [_alert('Water Street detour', description: 'Routes 10 and 10A use Harbour Drive.')],
          overrides: [
            metrobusMobileApiProvider.overrideWithValue(MetrobusMobileApi(client: _emptyKiosk)),
            stopArrivalsProvider.overrideWith((ref, id) async => live ? liveRows : const <ArrivalRow>[]),
            if (live) stopArrivalsUpdatedAtProvider.overrideWith(_UpdatedAt.new),
          ],
        );
        expect(tester.takeException(), isNull, reason: 'initial layout at peek');
        if (live) {
          expect(find.textContaining('updated'), findsOneWidget, reason: 'the live line shows the refresh time');
          // The state label keeps one line (the time wraps instead of crushing it to a letter a line).
          expect(tester.getRect(find.text('Live')).height, lessThan(40), reason: 'Live stays on one line');
        }
        await tester.drag(find.byType(BBPill).first, const Offset(0, -700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'at full');
        await scrollSheet(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 11));
      });
    }

    testWidgets('the trip options at 360x640, 2.0x text, $theme', (tester) async {
      tester.view.physicalSize = const Size(360, 640) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpPlannerApp(
        tester,
        net: TestNetwork(),
        now: DateTime(testDay.year, testDay.month, testDay.day, 8, 1),
        textScale: 2.0,
        theme: dark ? BBTheme.dark() : BBTheme.light(),
      );
      final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      c.read(planQueryProvider.notifier).setTrip(
            StopPlace(stopId: 'A', name: 'Stop A'),
            StopPlace(stopId: 'C', name: 'Stop C'),
          );
      c.read(homeSheetProvider.notifier).open(const OptionsSheet());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at peek');
      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('Map sheet'));
      await tester.pumpAndSettle();
      handle.dispose();
      expect(tester.takeException(), isNull, reason: 'at half');
      await tester.drag(find.byType(BBSheet), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at full');
      expect(find.byType(JourneyCard), findsWidgets);
      await scrollSheet(tester);
    });
  }

  // The home at its peek: the real screen, so the peek is the sheet's own. Where to?, the first saved place and the
  // top of Your stop must be visible (on screen, inside the peeking sheet) however large the text, with two saved
  // places and an alert for you (spec §3.1).
  Future<void> pumpHomeAtPeek(
    WidgetTester tester, {
    required Size size,
    required double textScale,
    required bool dark,
    bool tip = false,
  }) =>
      pumpPlannerApp(
        tester,
        net: TestNetwork(),
        now: DateTime(2026, 10, 12, 13, 0),
        initial: '/',
        textScale: textScale,
        homeTipSeen: !tip,
        theme: dark ? BBTheme.dark() : BBTheme.light(),
        alerts: [
          ServiceAlert(
            sourceIds: const {'a'},
            header: 'Water Street detour on routes 1 and 2 between Duckworth Street and Prescott Street',
            description: 'Routes 1 and 2 use Harbour Drive.',
            cause: ServiceAlertCause.construction,
            effect: ServiceAlertEffect.detour,
            severity: ServiceAlertSeverity.warning,
            activePeriods: [ServiceAlertPeriod(end: DateTime(2099))],
            targets: const [ServiceAlertTarget(routeId: '1')],
          ),
        ],
        nearby: const [NearbyStop(stop: _stop, distanceMeters: 80)],
        overrides: [
          settingsProvider.overrideWith(_StopCSettings.new),
          savedPlacesProvider.overrideWith(_Places.new),
          savedTripsProvider.overrideWith(_Trips.new),
          savedTripNextProvider('t1').overrideWith((ref) async => const []),
          stopArrivalsProvider.overrideWith((ref, id) async => _arrivals),
        ],
      );

  /// What the rider can see at peek: the sheet card, clipped to the screen.
  void expectVisibleAtPeek(WidgetTester tester, Finder f, String what, Size size) {
    expect(f, findsOneWidget, reason: what);
    final card = tester.getRect(find.byKey(BBSheet.cardKey));
    final r = tester.getRect(f);
    expect(r.top, greaterThanOrEqualTo(card.top), reason: '$what starts inside the sheet');
    expect(r.top, lessThan(size.height), reason: '$what starts on screen');
    expect(r.top, lessThan(card.bottom), reason: '$what starts inside the peeking sheet');
  }

  for (final dark in [false, true]) {
    testWidgets('home at peek, 360x640, 2.0x text, ${dark ? 'dark' : 'light'}', (tester) async {
      final handle = tester.ensureSemantics();
      const size = Size(360, 640);
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await pumpHomeAtPeek(tester, size: size, textScale: 2.0, dark: dark);
      expect(tester.takeException(), isNull, reason: 'initial layout');

      final whereTo = find.byKey(HomeSheetContent.whereToKey);
      expectVisibleAtPeek(tester, whereTo, 'Where to?', size);
      expect(whereTo.hitTestable(), findsOneWidget, reason: 'Where to? can be tapped at peek');
      expectVisibleAtPeek(tester, find.text('Home'), 'the first saved place', size);
      expectVisibleAtPeek(tester, find.bySemanticsLabel(RegExp('^Your stop')), 'the top of Your stop', size);

      // Pulled up to full, the whole sheet scrolls without overflowing.
      await tester.drag(whereTo, const Offset(0, -700));
      await tester.pumpAndSettle();
      await _scrollThrough(tester);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  }

  testWidgets('home at peek, 390x844, 1.0x text: Your stop and the next bus are whole above the bottom', (tester) async {
    final handle = tester.ensureSemantics();
    const size = Size(390, 844);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHomeAtPeek(tester, size: size, textScale: 1.0, dark: false);
    final card = tester.getRect(find.byKey(BBSheet.cardKey));
    final yourStop = tester.getRect(find.bySemanticsLabel(RegExp('^Your stop')));
    final firstBus = tester.getRect(find.byType(ArrivalRowTile).first);
    for (final (name, r) in [('Your stop', yourStop), ('the first bus', firstBus)]) {
      expect(r.top, greaterThanOrEqualTo(card.top), reason: name);
      expect(r.bottom, lessThanOrEqualTo(card.bottom), reason: '$name is whole inside the peeking sheet');
      expect(r.bottom, lessThanOrEqualTo(size.height), reason: '$name is on screen');
    }
    handle.dispose();
  });

  // The one-time tip sits above Where to?. Your stop may fall below the fold while it shows (it is one-time), but
  // nothing overflows and the way to dismiss it is on screen.
  testWidgets('home at peek, 360x640, 1.0x text, with the one-time tip: no overflow, Where to? and Got it on screen',
      (tester) async {
    final handle = tester.ensureSemantics();
    const size = Size(360, 640);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHomeAtPeek(tester, size: size, textScale: 1.0, dark: false, tip: true);
    expect(tester.takeException(), isNull, reason: 'initial layout');
    expect(find.textContaining("Everything's on the map now"), findsOneWidget);
    expectVisibleAtPeek(tester, find.byKey(HomeSheetContent.whereToKey), 'Where to?', size);
    expectVisibleAtPeek(tester, find.text('Got it'), 'Got it', size);
    expect(find.text('Got it').hitTestable(), findsOneWidget, reason: 'Got it can be tapped at peek');
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  // At 2x text the tip is taller than the peek: it still reads in full (no line is cut), nothing overflows, and once
  // pulled up its Got it can be tapped.
  for (final dark in [false, true]) {
    testWidgets('the one-time tip at 360x640, 2.0x text, ${dark ? 'dark' : 'light'}', (tester) async {
      const size = Size(360, 640);
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await pumpHomeAtPeek(tester, size: size, textScale: 2.0, dark: dark, tip: true);
      expect(tester.takeException(), isNull, reason: 'initial layout');
      final tip = find.textContaining('Your Board is still here');
      expect(tip, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(tip).didExceedMaxLines, isFalse, reason: 'the tip is cut short');
      // Pulled up by the tip itself (at peek it may hide everything under it).
      await tester.drag(find.byKey(BBSheet.handleKey), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('Got it').hitTestable(), findsOneWidget, reason: 'Got it can be tapped');
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(tip, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
