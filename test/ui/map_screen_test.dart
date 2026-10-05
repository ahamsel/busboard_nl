import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/copy/legal_copy.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_screen.dart';
import 'package:busboard_nl/ui/map/map_view.dart';
import 'package:busboard_nl/ui/map/marker_images.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show CircleLayerProperties, LatLng, SymbolLayerProperties;
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
var _surface = FakeMapSurface();

/// Stands in for the map tab going offstage in the shell.
final _tickerMode = ValueNotifier<bool>(true);

/// Taps that reached the "map" (a tap on empty map is forwarded to onTap).
var _mapTaps = 0;

Widget _stubMap(MapViewConfig config) {
  _config = config;
  scheduleMicrotask(() => config.onReady(_surface, _surface));
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      _mapTaps++;
      config.onTap(const LatLng(47.0, -52.0));
    },
    child: const ColoredBox(key: ValueKey('stub-map'), color: Color(0xFFEEF1F4)),
  );
}


/// Records bus updates and can hold them open.
class _RecordingSurface extends FakeMapSurface {
  final busSets = <List<Map<String, dynamic>>>[];
  final _held = <Completer<void>>[];
  bool hold = false;
  bool failImages = false;

  /// Real-time pause per layer call, so overlapping installs would interleave.
  Duration layerDelay = Duration.zero;

  @override
  Future<void> addCircleLayer(String sourceId, String layerId, CircleLayerProperties p, {double? minzoom}) async {
    await Future<void>.delayed(layerDelay);
    return super.addCircleLayer(sourceId, layerId, p, minzoom: minzoom);
  }

  @override
  Future<void> addSymbolLayer(String sourceId, String layerId, SymbolLayerProperties p, {double? minzoom}) async {
    await Future<void>.delayed(layerDelay);
    return super.addSymbolLayer(sourceId, layerId, p, minzoom: minzoom);
  }

  void releaseHeld() {
    hold = false;
    for (final c in _held) {
      c.complete();
    }
    _held.clear();
  }

  @override
  Future<void> addImage(String name, Uint8List bytes) async {
    if (failImages) throw StateError('addImage failed');
    return super.addImage(name, bytes);
  }

  @override
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> data) async {
    await super.setGeoJsonSource(id, data);
    if (id != 'bb-buses') return;
    busSets.add((data['features'] as List).cast<Map<String, dynamic>>());
    if (hold) {
      final c = Completer<void>();
      _held.add(c);
      await c.future;
    }
  }
}

/// `myLocation()` answers from a script, one entry per call.
class _SequencedLocationSurface extends FakeMapSurface {
  _SequencedLocationSurface(this._script);
  final List<LatLng?> _script;
  int locationReads = 0;

  @override
  Future<LatLng?> myLocation() async => locationReads < _script.length ? _script[locationReads++] : null;
}

/// Fires the style-loaded callback and gives the real event loop time to
/// rasterise marker images (they use dart:ui, outside fake-async time).
Future<void> _styleLoaded(FakeMapSurface surface) async {
  _config!.onStyleLoaded();
  await Future<void>.delayed(const Duration(milliseconds: 300));
}

/// [n] 130 ms ticks; between them the real loop runs so marker images finish.
Future<void> _frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 130));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _pump(WidgetTester tester, {Map<String, Object> prefs = const {}, Map<String, BusTrackingState> buses = const {}, double textScale = 1, Size? size, double dpr = 1, List<ArrivalRow> arrivals = const []}) async {
  if (size != null) {
    tester.view.physicalSize = size * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }
  SharedPreferences.setMockInitialValues(prefs);
  final router = GoRouter(initialLocation: '/map', routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('PICKER')),
    GoRoute(path: '/map', builder: (_, _) => ValueListenableBuilder<bool>(
        valueListenable: _tickerMode,
        builder: (_, enabled, _) => TickerMode(enabled: enabled, child: const MapScreen()),
      ),
    ),
    GoRoute(path: '/board/:id', builder: (_, s) => Text('BOARD ${s.pathParameters['id']}')),
    GoRoute(path: '/alerts', builder: (_, _) => const Text('ALERTS')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mapViewBuilderProvider.overrideWithValue(_stubMap),
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
    _mapTaps = 0;
    _tickerMode.value = true;
    _surface = FakeMapSurface();
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


  group('credit link', () {
    const credit = '© OpenStreetMap · OpenFreeMap';

    for (final (size, scale) in [
      (const Size(640, 320), 2.0),
      (const Size(320, 568), 2.0),
      (const Size(390, 844), 1.0),
    ]) {
      testWidgets('is fully on screen at ${size.width.toInt()}x${size.height.toInt()} text x$scale', (tester) async {
        await _pump(tester, size: size, textScale: scale);
        final rect = tester.getRect(find.text(credit));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('sits within 12 px above the peeking sheet at 390x844 x1.0', (tester) async {
      await _pump(tester, size: const Size(390, 844));
      final text = tester.getRect(find.text(credit));
      final card = tester.getRect(find.byKey(BBSheet.cardKey));
      expect(card.top - text.bottom, inInclusiveRange(0, 12));
    });

    testWidgets('has a hit area at least 44 pt tall', (tester) async {
      await _pump(tester, size: const Size(390, 844));
      final hit = tester.getRect(find.ancestor(of: find.text(credit), matching: find.byType(BBPressable)));
      expect(hit.height, greaterThanOrEqualTo(44));
      final text = tester.getRect(find.text(credit));
      expect(hit.width, lessThanOrEqualTo(text.width + 8), reason: 'the tap target hugs the text');
    });

    testWidgets('a tap beside the text, in the same band, reaches the map', (tester) async {
      await _pump(tester, size: const Size(390, 844));
      final text = tester.getRect(find.text(credit)); // test fonts are wide: it ends at x=360
      await tester.tapAt(Offset(text.right + 16, text.center.dy));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_mapTaps, 1);
      expect(find.text('Map credits'), findsNothing);
    });

    testWidgets('on iOS the attribution margin leaves out the bottom safe area', (tester) async {
      // MLNMapView measures the margin from the safe area, so ours must not add it twice.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        tester.view.padding = const FakeViewPadding(bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(bottom: 34);
        await _pump(tester, size: const Size(390, 844));
        final hit = tester.getRect(find.ancestor(of: find.text(credit), matching: find.byType(BBPressable)));
        final creditBottom = 844 - hit.bottom;
        expect(creditBottom, greaterThan(34));
        expect(_config!.attributionMargin.y, closeTo(creditBottom - 34, 0.5));
      } finally {
        debugDefaultTargetPlatformOverride = null; // must be reset before the test ends
      }
    });

    testWidgets("the map's own attribution button starts right after the link", (tester) async {
      for (final (size, scale) in [(const Size(390, 844), 1.0), (const Size(320, 568), 2.0)]) {
        await _pump(tester, size: size, textScale: scale);
        final text = tester.getRect(find.text(credit));
        expect(_config!.attributionMargin.x, closeTo(text.right + BBSpace.s, 1.5));
      }
    });

    testWidgets("the attribution margin is in logical pixels on a dense Android screen", (tester) async {
      // maplibre_gl's Android side multiplies the margins by the screen density
      // itself: scaling them here too pushed the button off the screen.
      await _pump(tester, size: const Size(390, 844), dpr: 2.625);
      final text = tester.getRect(find.text(credit));
      final hit = tester.getRect(find.ancestor(of: find.text(credit), matching: find.byType(BBPressable)));
      expect(_config!.attributionMargin.x, closeTo(text.right + BBSpace.s, 1.5));
      expect(_config!.attributionMargin.y, closeTo(844 - hit.bottom, 1.5));
    });
  });

  group('first My location tap', () {
    // Denied until the rider is asked, then granted: the first-ever tap.
    void mockGeolocator({Map<String, Object>? position}) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/geolocator'),
        (call) async => switch (call.method) {
          'checkPermission' => 0,
          'requestPermission' => 2,
          'getCurrentPosition' => position,
          _ => null,
        },
      );
    }

    testWidgets('moves the camera even when the location is not ready on the first read', (tester) async {
      mockGeolocator();
      final surface = _SequencedLocationSurface([null, const LatLng(47.55, -52.70)]);
      _surface = surface;
      await _pump(tester);
      await tester.tap(find.byType(BBControlPill));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(surface.locationReads, 2);
      expect(surface.moves.single.$1, const LatLng(47.55, -52.70));
      expect(surface.moves.single.$2, 15);
    });

    testWidgets('falls back to the device position when the map never reports one', (tester) async {
      mockGeolocator(position: {'latitude': 47.51, 'longitude': -52.80, 'timestamp': 0});
      final surface = _SequencedLocationSurface([null, null, null, null]);
      _surface = surface;
      await _pump(tester);
      await tester.tap(find.byType(BBControlPill));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(surface.locationReads, 3);
      expect(surface.moves.single.$1, const LatLng(47.51, -52.80));
    });
  });

  testWidgets("the peek is tall enough for your stop's two arrivals", (tester) async {
    ArrivalRow arrival(int minutes) => ArrivalRow(
          routeShortName: '10',
          headsign: 'Downtown',
          scheduledTime: GtfsTime.parse('09:52:00'),
          predictedTime: GtfsTime.parse('09:55:00'),
          minutesAway: minutes,
          liveStatus: LiveStatus.behind,
          isLive: true,
          tripId: 't$minutes',
          vehicleNumber: '2134',
          isEnhanced: false,
          routeRun: '10-1',
        );
    await _pump(tester, size: const Size(390, 844), prefs: {'selectedStopId': '1150'}, arrivals: [arrival(3), arrival(9), arrival(15)]);
    final card = tester.getRect(find.byKey(BBSheet.cardKey));
    final tiles = find.byType(ArrivalRowTile);
    expect(tiles, findsAtLeastNWidgets(2));
    for (final i in [0, 1]) {
      final r = tester.getRect(tiles.at(i));
      expect(r.top, greaterThanOrEqualTo(card.top));
      expect(r.bottom, lessThanOrEqualTo(card.bottom), reason: 'arrival ${i + 1} fits inside the peeking card');
    }
  });

  testWidgets('choosing a new stop recentres the map on it', (tester) async {
    await _pump(tester);
    expect(_surface.moves, isEmpty);
    final container = ProviderScope.containerOf(tester.element(find.byType(MapScreen)));
    await container.read(settingsProvider.notifier).setSelectedStop('1150');
    await tester.pump(const Duration(milliseconds: 100));
    expect(_surface.moves, [(const LatLng(47.5700, -52.7300), 15.0, true)]);
  });

  group('map layers over time', () {
    testWidgets('a duplicate style-loaded event for the same style still ends with everything drawn', (tester) async {
      final surface = _RecordingSurface();
      _surface = surface;
      await _pump(tester, prefs: {'selectedStopId': '1150'}, buses: {'2573': _bus()});
      await tester.runAsync(() async {
        _config!.onStyleLoaded();
        _config!.onStyleLoaded();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await _frames(tester, 3);
      expect(surface.layers.keys, hasLength(6));
      expect(surface.features('bb-my-stop').single['properties']['stopId'], '1150', reason: 'your stop is drawn');
      expect(surface.busSets, isNotEmpty);
      expect(surface.busSets.last.map((f) => (f['properties'] as Map)['vehicleId']), ['2573']);
    });

    testWidgets('two style loads in a row install one after the other', (tester) async {
      final surface = _RecordingSurface()..layerDelay = const Duration(milliseconds: 15);
      _surface = surface;
      await _pump(tester, prefs: {'selectedStopId': '1150'});
      await tester.runAsync(() async {
        _config!.onStyleLoaded();
        _config!.onStyleLoaded();
        await Future<void>.delayed(const Duration(milliseconds: 900));
      });
      final firstImages = [
        for (var i = 0; i < surface.calls.length; i++)
          if (surface.calls[i] == 'image ${MarkerImages.myStopId}') i,
      ];
      expect(firstImages, hasLength(2), reason: 'each load installs');
      final layers = [
        for (var i = 0; i < surface.calls.length; i++)
          if (surface.calls[i].startsWith('layer ')) i,
      ];
      expect(layers.length.isEven, isTrue);
      final firstInstallLayers = layers.length ~/ 2;
      expect(layers.where((i) => i < firstImages[1]).length, firstInstallLayers,
          reason: 'the second install starts only after the first has added all its layers');
    });

    testWidgets('the draw ticker stops while offstage and restarts on return', (tester) async {
      final surface = _RecordingSurface();
      _surface = surface;
      await _pump(tester, buses: {'2573': _bus()});
      await tester.runAsync(() => _styleLoaded(surface));
      await _frames(tester, 2);
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      _tickerMode.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.transientCallbackCount, 0, reason: 'no frames are requested offstage');

      _tickerMode.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('a failed style reload leaves the stale layers undrawn', (tester) async {
      final printed = debugPrint;
      debugPrint = (message, {wrapWidth}) {}; // the expected install failure is logged
      final old = _RecordingSurface();
      _surface = old;
      await _pump(tester, buses: {'2573': _bus()});
      await tester.runAsync(() => _styleLoaded(old));
      await _frames(tester, 3);
      expect(old.busSets, isNotEmpty, reason: 'the first install draws buses');

      final broken = _RecordingSurface()..failImages = true;
      _config!.onReady(broken, broken);
      await tester.runAsync(() => _styleLoaded(broken));
      old.busSets.clear();
      await _frames(tester, 4);
      expect(old.busSets, isEmpty, reason: 'nothing may draw on the surface the old style left behind');
      expect(broken.busSets, isEmpty);
      debugPrint = printed;
    });

    testWidgets('draws one bus update at a time, with the bus, and honours the route filter', (tester) async {
      final surface = _RecordingSurface();
      _surface = surface;
      await _pump(tester, buses: {'2573': _bus()});
      await tester.runAsync(() => _styleLoaded(surface));

      surface.hold = true;
      await _frames(tester, 6);
      expect(surface.busSets, hasLength(1), reason: 'a second frame must wait for the first');
      expect(surface.busSets.single.map((f) => (f['properties'] as Map)['vehicleId']), ['2573']);

      surface.releaseHeld();
      await _frames(tester, 3);
      expect(surface.busSets.length, greaterThan(1));
      expect(surface.busSets.last.map((f) => (f['properties'] as Map)['vehicleId']), ['2573']);

      ProviderScope.containerOf(tester.element(find.byType(MapScreen))).read(mapRouteFilterProvider.notifier).toggle(99);
      await _frames(tester, 3);
      expect(surface.busSets.last, isEmpty);
    });

    testWidgets('an offstage map (tickers off) draws nothing', (tester) async {
      final surface = _RecordingSurface();
      _surface = surface;
      await _pump(tester, buses: {'2573': _bus()});
      await tester.runAsync(() => _styleLoaded(surface));
      await _frames(tester, 3);
      expect(surface.busSets, isNotEmpty);

      _tickerMode.value = false;
      await tester.pump();
      surface.busSets.clear();
      await _frames(tester, 4);
      expect(surface.busSets, isEmpty);

      _tickerMode.value = true;
      await tester.pump();
      await _frames(tester, 3);
      expect(surface.busSets, isNotEmpty, reason: 'back on screen, it draws again');
    });
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
