import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/domain/location/nearest_stop_service.dart';
import 'package:busboard_nl/domain/trip_planner/timetable_index.dart';
import 'package:busboard_nl/routing/router.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
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

/// Pumps the app's real route tree (shell, four tabs) on [net] at [now], starting at [initial].
/// The live feed answers 503, so plans use timetable times; the map is a plain box ([mapView], when given, builds it).
Future<void> pumpPlannerApp(
  WidgetTester tester, {
  required TestNetwork net,
  required DateTime now,
  String initial = '/plan',
  double textScale = 1,
  GeolocatorPlatform? geolocator,
  http.Client? liveClient,
  MapViewBuilder? mapView,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  useInMemoryAlertStore();
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
              Stream.value(ServiceUpdates(alerts: const [], serviceStatus: null, fetchedAt: now, feedTimestamp: null)),
        ),
        gtfsRepositoryProvider.overrideWith((ref) async => net.repo),
        nearestStopsProvider.overrideWith((ref) async => const <NearbyStop>[]),
        plannerClockProvider.overrideWithValue(() => now),
        // Isolate.run never finishes under testWidgets' fake async.
        timetableIndexBuilderProvider.overrideWithValue((repo, day) async => TimetableIndex.build(repo, day)),
        timetrackApiProvider.overrideWithValue(
          TimeTrackApi(client: liveClient ?? MockClient((_) async => http.Response('', 503))),
        ),
        mapViewBuilderProvider.overrideWithValue(mapView ?? StubMap().build),
        ...fakeAlertOverrides,
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: BBTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
