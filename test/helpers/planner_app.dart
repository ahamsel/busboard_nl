import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/platform/alert_runner.dart';
import 'package:busboard_nl/routing/router.dart';
import 'package:busboard_nl/state/board_open_store.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/seen_flags.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/home/home_tip.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

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
/// [color] is the map's land colour (the light Harbour land by default).
class StubMap {
  StubMap({this.color = const Color(0xFFEEF0F2)});

  final Color color;
  MapViewConfig? config;

  Widget build(MapViewConfig c) {
    config = c;
    return ColoredBox(key: const ValueKey('stub-map'), color: color);
  }

  void tap(double lat, double lon) => config!.onTap(LatLng(lat, lon));
  void longPress(double lat, double lon) => config!.onLongPress!(LatLng(lat, lon));
}

/// An element under the router and the providers, for `GoRouter.of` and `ProviderScope.containerOf`.
Element routerElement(WidgetTester tester) => tester.element(find.byType(Navigator).first);

/// Pumps the app's route tree on [net] at [now] ([clock], when given, tells the time instead), starting at [initial].
/// [use24h], when given, sets the device's clock format. [alertRunner], when given, takes the arrival alerts (a quiet one otherwise).
/// [asyncPrefs] is what SharedPreferencesAsync holds at launch. [launchLinkChecked], when given, is the app's check for
/// a notification that launched it (already done, with no link, otherwise). [reduceMotion] turns on the OS Reduce Motion setting.
/// The one-time home tip is already seen unless [homeTipSeen] is false (it sits above "Where to?" and moves the peek),
/// and so is the bar's one-time lift unless [barHintSeen] is false.
/// The live feed answers 503, so plans use timetable times; the map is a plain box ([mapView], when given, builds it).
Future<void> pumpPlannerApp(
  WidgetTester tester, {
  required TestNetwork net,
  required DateTime now,
  DateTime Function()? clock,
  String initial = '/',
  double textScale = 1,
  GeolocatorPlatform? geolocator,
  http.Client? liveClient,
  MapViewBuilder? mapView,
  List<Override> overrides = const [],
  bool settle = true,
  List<ServiceAlert> alerts = const [],
  Future<GtfsRepository>? repoFuture,
  ThemeData? theme,
  List<NearbyStop> nearby = const [],
  AlertRunner? alertRunner,
  bool? use24h,
  bool homeTipSeen = true,
  bool barHintSeen = true,
  Map<String, Object> asyncPrefs = const {},
  Completer<bool>? launchLinkChecked,
  bool reduceMotion = false,
}) async {
  // flutter_test's own 800x600 is a tablet to the home screen (its side panel starts at 700): a test that has not
  // picked a size gets a phone, so the sheet is a pull-up sheet. A test that sets its own size keeps it.
  if (tester.view.physicalSize == const Size(2400, 1800) && tester.view.devicePixelRatio == 3) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  SharedPreferences.setMockInitialValues({});
  useInMemoryAlertStore();
  // What SharedPreferencesAsync holds at launch (a cold start's saved state).
  if (asyncPrefs.isNotEmpty) SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(asyncPrefs);
  final previousGeo = GeolocatorPlatform.instance;
  GeolocatorPlatform.instance = geolocator ?? LocationOffGeolocator();
  addTearDown(() => GeolocatorPlatform.instance = previousGeo);

  final router = buildAppRouter(initialLocation: initial);
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
        // No live buses unless a test overrides this: the real poll's timer would outlive the test.
        busTrackingStreamProvider.overrideWith((ref) => Stream.value(const <String, BusTrackingState>{})),
        launchLinkCheckedProvider.overrideWithValue(launchLinkChecked ?? (Completer<bool>()..complete(false))),
        if (homeTipSeen) homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen()),
        if (barHintSeen) barHintSeenProvider.overrideWith(() => SeenFlagNotifier.seen(barHintSeenKey)),
        ...fakeAlertOverridesWith(alertRunner),
        ...overrides,
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: theme ?? BBTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
            alwaysUse24HourFormat: use24h ?? MediaQuery.of(context).alwaysUse24HourFormat,
          ),
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
