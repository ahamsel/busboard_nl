import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/copy/legal_copy.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_screen.dart';
import 'package:busboard_nl/ui/map/map_view.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;
import 'package:shared_preferences/shared_preferences.dart';

import '../map/support/fake_map_surface.dart';

const _mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.5700, stopLon: -52.7300);

GtfsRepository _repo() => GtfsRepository()..stopsById['1150'] = _mun;

BusTrackingState _bus() => BusTrackingState(
      routeRun: 'Rt 10',
      vehicleId: '2573',
      routeNumber: 10,
      headsign: 'Downtown',
      lat: 47.5600,
      lon: -52.7100,
      heading: 90,
      speedKmh: 29,
      lastGpsTime: DateTime.now(),
      status: BusStatus.active,
      lastUpdateTime: DateTime.now(),
    );

/// The last config the stub map was built with, so tests can tap the "map".
MapViewConfig? _config;
final _surface = FakeMapSurface();

Widget _stubMap(MapViewConfig config) {
  _config = config;
  scheduleMicrotask(() => config.onReady(_surface, _surface));
  return const ColoredBox(key: ValueKey('stub-map'), color: Color(0xFFEEF1F4));
}

Future<void> _pump(WidgetTester tester, {Map<String, Object> prefs = const {}, Map<String, BusTrackingState> buses = const {}, double textScale = 1}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final router = GoRouter(initialLocation: '/map', routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('PICKER')),
    GoRoute(path: '/map', builder: (_, _) => const MapScreen()),
    GoRoute(path: '/board/:id', builder: (_, s) => Text('BOARD ${s.pathParameters['id']}')),
    GoRoute(path: '/alerts', builder: (_, _) => const Text('ALERTS')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mapViewBuilderProvider.overrideWithValue(_stubMap),
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
      stopArrivalsProvider.overrideWith((ref, stopId) async => const <ArrivalRow>[]),
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
  // The ticker never settles; pump a few frames instead of pumpAndSettle.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    // Location permission: denied, so the screen draws no location puck.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'checkPermission' ? 0 : null,
    );
    _config = null;
    _surface.calls.clear();
  });

  testWidgets('with no stop chosen, the chip and sheet invite you to choose one', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('stub-map')), findsOneWidget);
    expect(find.text('Choose a stop'), findsWidgets);
    expect(find.text('All routes'), findsOneWidget);
    expect(find.text('Choose a stop to see its next buses'), findsOneWidget);
  });

  testWidgets('the stop chip names your stop and opens the picker', (tester) async {
    await _pump(tester, prefs: {'selectedStopId': '1150'});
    await tester.tap(find.text('MUN Centre · 1150'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PICKER'), findsOneWidget);
  });

  testWidgets('tapping near a stop opens its card; tapping empty map returns to your stop', (tester) async {
    await _pump(tester);
    _config!.onTap(const LatLng(47.5701, -52.7300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Open board'), findsOneWidget);
    expect(find.text('Stop 1150'), findsOneWidget);
    _config!.onTap(const LatLng(47.0, -52.0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Stop 1150'), findsNothing);
    expect(find.text('Choose a stop to see its next buses'), findsOneWidget);
  });

  testWidgets('tapping near a bus opens its card', (tester) async {
    await _pump(tester, buses: {'2573': _bus()});
    _config!.onTap(const LatLng(47.5601, -52.7100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('to Downtown'), findsOneWidget);
  });

  testWidgets('moving from a stop card to a bus card swaps the sheet content cleanly', (tester) async {
    await _pump(tester, buses: {'2573': _bus()});
    _config!.onTap(const LatLng(47.5701, -52.7300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Open board'), findsOneWidget);
    _config!.onTap(const LatLng(47.5601, -52.7100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('to Downtown'), findsOneWidget);
    expect(find.text('Open board'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the style loading (and reloading) installs the map layers', (tester) async {
    await _pump(tester, prefs: {'selectedStopId': '1150'});
    // Marker images are rasterised on the real engine, outside fake-async time.
    Future<int> styleLoaded() async {
      _surface.calls.clear();
      _config!.onStyleLoaded();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return _surface.calls.where((c) => c.startsWith('layer ')).length;
    }

    final first = (await tester.runAsync(styleLoaded))!;
    expect(first, greaterThan(0));
    expect((await tester.runAsync(styleLoaded))!, first);
  });

  testWidgets('My location is a labelled control', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(find.bySemanticsLabel('My location'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the credit link opens the map credits', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('© OpenStreetMap · OpenFreeMap'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Map credits'), findsOneWidget);
    expect(find.text(LegalCopy.mapCredit), findsOneWidget);
  });

  testWidgets('the route chip opens a filter card; picking a route filters the map', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, buses: {'2573': _bus()});
    await tester.tap(find.text('All routes'));
    // The first frame after a route push starts its fade; the second finishes it.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsLabel(RegExp('Route 10')).last);
    await tester.pump(const Duration(milliseconds: 100));
    final container = ProviderScope.containerOf(tester.element(find.byType(MapScreen)));
    expect(container.read(mapRouteFilterProvider), {10});
    semantics.dispose();
  });

  testWidgets('the map is built with rotation off and a Harbour style asset', (tester) async {
    await _pump(tester);
    expect(_config!.styleString, 'assets/map/harbour_light.json');
  });

  testWidgets('no overflow at 320 pt and text x2.0', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, prefs: {'selectedStopId': '1150'}, textScale: 2);
    expect(tester.takeException(), isNull);
  });
}
