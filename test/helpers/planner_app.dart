import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/platform/alert_runner.dart';
import 'package:busboard_nl/routing/router.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/alerts/alerts_screen.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_view.dart';
import 'package:busboard_nl/ui/settings/settings_screen.dart';
import 'package:busboard_nl/ui/trip_planner/journey_detail_screen.dart';
import 'package:busboard_nl/ui/trip_planner/plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;
import 'package:shared_preferences/shared_preferences.dart';

import '../trip_planner/test_network.dart';
import 'fake_alerts.dart';

/// A phone whose location is switched off (the default for planner tests).
class LocationOffGeolocator extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;
  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.deniedForever;
  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.deniedForever;
}

/// A phone that knows where it is and lets the app ask.
class FixedGeolocator extends GeolocatorPlatform {
  FixedGeolocator(this.lat, this.lon);
  final double lat;
  final double lon;

  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.whileInUse;
  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async => Position(
    latitude: lat,
    longitude: lon,
    timestamp: DateTime(2026),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

/// A phone that lets the app ask but never gets a fix: like the real plugins, it gives up with a
/// [TimeoutException] once the request's time limit runs out (and never, without one).
class NoFixGeolocator extends GeolocatorPlatform {
  final requests = <LocationSettings?>[];

  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.whileInUse;
  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    requests.add(locationSettings);
    final limit = locationSettings?.timeLimit;
    if (limit == null) return Completer<Position>().future;
    return Future.delayed(limit, () => throw TimeoutException('no fix', limit));
  }
}

/// A stand-in for MapLibre that keeps the config it was last built with, so a test can tap or long-press the "map".
class StubMap {
  MapViewConfig? config;

  Widget build(MapViewConfig c) {
    config = c;
    return const ColoredBox(key: ValueKey('stub-map'), color: Color(0xFFEEF1F4));
  }

  void tap(double lat, double lon) => config!.onTap(LatLng(lat, lon));
  void longPress(double lat, double lon) => config!.onLongPress!(LatLng(lat, lon));
}

/// The screens that Tasks 7 and 8 of the map-first home replace (Plan, Journey detail), each on its
/// old path, so their tests keep running while the app's own router sends those paths home. A test of the
/// home itself uses the app's router (`appRoutes: true`).
GoRouter plannerTestRouter(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(path: '/', builder: (context, state) => HomeScreen(pick: state.uri.queryParameters['pick'])),
    GoRoute(path: '/map', builder: (context, state) => HomeScreen(pick: state.uri.queryParameters['pick'])),
    GoRoute(path: '/alerts', builder: (context, state) => const AlertsScreen()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(
      path: '/plan',
      builder: (context, state) => const PlanScreen(),
      routes: [
        GoRoute(
          path: 'journey',
          // A deep link or a restored route carries no journey: back to the planner.
          redirect: (context, state) => state.extra is Journey ? null : '/plan',
          builder: (context, state) => JourneyDetailScreen(journey: state.extra! as Journey),
        ),
      ],
    ),
  ],
);

/// An element under the router and the providers, for `GoRouter.of` and `ProviderScope.containerOf`.
Element routerElement(WidgetTester tester) => tester.element(find.byType(Navigator).first);

/// Pumps the planner screens ([plannerTestRouter]), or with [appRoutes] the app's real route tree, on [net] at
/// [now] ([clock], when given, tells the time instead), starting at [initial].
/// [alertRunner], when given, takes the arrival alerts (a quiet one otherwise).
/// The live feed answers 503, so plans use timetable times; the map is a plain box ([mapView], when given, builds it).
Future<void> pumpPlannerApp(
  WidgetTester tester, {
  required TestNetwork net,
  required DateTime now,
  DateTime Function()? clock,
  String initial = '/plan',
  double textScale = 1,
  GeolocatorPlatform? geolocator,
  http.Client? liveClient,
  MapViewBuilder? mapView,
  List<Override> overrides = const [],
  bool settle = true,
  bool appRoutes = false,
  List<ServiceAlert> alerts = const [],
  Future<GtfsRepository>? repoFuture,
  ThemeData? theme,
  List<NearbyStop> nearby = const [],
  AlertRunner? alertRunner,
}) async {
  SharedPreferences.setMockInitialValues({});
  useInMemoryAlertStore();
  final previousGeo = GeolocatorPlatform.instance;
  GeolocatorPlatform.instance = geolocator ?? LocationOffGeolocator();
  addTearDown(() => GeolocatorPlatform.instance = previousGeo);

  final router = appRoutes ? buildAppRouter(initialLocation: initial) : plannerTestRouter(initial);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        serviceUpdatesProvider.overrideWith(
          (ref) =>
              Stream.value(ServiceUpdates(alerts: alerts, serviceStatus: null, fetchedAt: now, feedTimestamp: null)),
        ),
        // [repoFuture], when given, holds the schedule (a cold start) until it completes.
        gtfsRepositoryProvider.overrideWith((ref) => repoFuture ?? Future.value(net.repo)),
        nearestStopsProvider.overrideWith((ref) async => nearby),
        plannerClockProvider.overrideWithValue(clock ?? () => now),
        // Isolate.run never finishes under testWidgets' fake async.
        timetableIndexBuilderProvider.overrideWithValue((repo, day) async => TimetableIndex.build(repo, day)),
        timetrackApiProvider.overrideWithValue(
          TimeTrackApi(client: liveClient ?? MockClient((_) async => http.Response('', 503))),
        ),
        mapViewBuilderProvider.overrideWithValue(mapView ?? StubMap().build),
        // Home is the only screen now: no live-bus poll timer outlives the test.
        busTrackingStreamProvider.overrideWith((ref) => Stream.value(const <String, BusTrackingState>{})),
        ...fakeAlertOverridesWith(alertRunner),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: theme ?? BBTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
