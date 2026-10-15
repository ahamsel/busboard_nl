import 'dart:async';
import 'dart:math' as math;

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/gtfs_time.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/trip_planner/journey.dart';
import 'package:busboard_nl/domain/trip_planner/place.dart';
import 'package:busboard_nl/domain/trip_planner/trip_planner.dart';
import 'package:busboard_nl/state/journey_on_map_provider.dart';
import 'package:busboard_nl/state/map_pick_provider.dart';
import 'package:busboard_nl/state/trip_planner_providers.dart';
import 'package:busboard_nl/ui/map/map_layers.dart';
import 'package:busboard_nl/ui/trip_planner/journey_card.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/state/follow_providers.dart';
import 'package:busboard_nl/state/home_sheet_provider.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/state/seen_flags.dart';
import 'package:busboard_nl/ui/copy/legal_copy.dart';
import 'package:busboard_nl/ui/arrival_alerts/alert_bell.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/home/home_screen.dart';
import 'package:busboard_nl/ui/home/home_tip.dart';
import 'package:busboard_nl/ui/home/home_sheet.dart';
import 'package:busboard_nl/ui/home/home_stop_line.dart';
import 'package:busboard_nl/ui/home/options_sheet.dart';
import 'package:busboard_nl/ui/map/follow_card.dart';
import 'package:busboard_nl/ui/map/map_view.dart';
import 'package:busboard_nl/ui/home/stop_sheet.dart';
import 'package:busboard_nl/ui/search/search_screen.dart';
import 'package:busboard_nl/ui/map/marker_images.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show CircleLayerProperties, LatLng, LineLayerProperties, SymbolLayerProperties;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_alerts.dart';
import '../helpers/planner_app.dart';
import '../kit/kit_test_helpers.dart';
import '../map/support/fake_map_surface.dart';
import '../map/support/out_and_back.dart';
import '../trip_planner/test_network.dart';

const _mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.5700, stopLon: -52.7300);

GtfsRepository _repo() => GtfsRepository()..stopsById['1150'] = _mun;

BusTrackingState _bus({double lat = 47.5600, double lon = -52.7100}) => BusTrackingState(
      routeRun: 'Rt 10',
      vehicleId: '2573',
      routeNumber: 10,
      headsign: 'Downtown',
      lat: lat,
      lon: lon,
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


/// Where [at] is drawn with the camera at [target]/[zoom] (north-up, MapLibre's 512-point world), on [view].
Offset onScreen(LatLng at, LatLng target, double zoom, Size view) {
  double mercX(double lon) => (lon + 180) / 360;
  double mercY(double lat) {
    final r = lat * math.pi / 180;
    return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
  }

  final world = 512 * math.pow(2, zoom);
  return Offset(
    view.width / 2 + (mercX(at.longitude) - mercX(target.longitude)) * world,
    view.height / 2 + (mercY(at.latitude) - mercY(target.latitude)) * world,
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

  /// Route line pushes that drew a line (not the clears).
  int routePushes = 0;

  @override
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> data) async {
    await super.setGeoJsonSource(id, data);
    if (id == 'bb-route' && (data['features'] as List).isNotEmpty) routePushes++;
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

Future<void> _pump(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  Map<String, BusTrackingState> buses = const {},
  double textScale = 1,
  Size? size,
  double dpr = 1,
  List<ArrivalRow> arrivals = const [],
  GtfsRepository Function()? repo,
  Stream<Map<String, BusTrackingState>>? busStream,
  bool disableAnimations = false,
  bool barHintSeen = true,
  List<Override> overrides = const [],
}) async {
  // Not flutter_test's 800x600, which is a tablet to the home screen: the tests here are of the phone layout.
  tester.view.physicalSize = (size ?? const Size(390, 844)) * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  useInMemoryAlertStore();
  final router = GoRouter(initialLocation: '/map', routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('PICKER')),
    GoRoute(path: '/map', builder: (_, _) => ValueListenableBuilder<bool>(
        valueListenable: _tickerMode,
        builder: (_, enabled, _) => TickerMode(enabled: enabled, child: const HomeScreen()),
      ),
    ),
    GoRoute(path: '/board/:id', builder: (_, s) => Text('BOARD ${s.pathParameters['id']}')),
    GoRoute(path: '/alerts', builder: (_, _) => const Text('ALERTS')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mapViewBuilderProvider.overrideWithValue(_stubMap),
      gtfsRepositoryProvider.overrideWith((ref) async => (repo ?? _repo)()),
      stopArrivalsProvider.overrideWith((ref, stopId) async => arrivals),
      busTrackingStreamProvider.overrideWith((ref) => busStream ?? Stream.value(buses)),
      // The bar's one-time lift moves the sheet: off unless a test asks for it.
      if (barHintSeen) barHintSeenProvider.overrideWith(() => SeenFlagNotifier.seen(barHintSeenKey)),
      ...fakeAlertOverrides,
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: BBTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: disableAnimations),
        child: child!,
      ),
    ),
  ));
  // The ticker never settles; pump a few frames instead of pumpAndSettle.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The bar hint's flag, held until [gate] completes, so a test can watch the lift from its start.
class _HeldFlag extends SeenFlagNotifier {
  _HeldFlag(this.gate) : super(barHintSeenKey);
  final Completer<bool> gate;
  @override
  Future<bool> build() => gate.future;
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
    expect(find.text('Choose your stop'), findsOneWidget);
    expect(find.text('All routes'), findsOneWidget);
    expect(find.byKey(HomeSheetContent.whereToKey), findsOneWidget);
  });

  testWidgets('tapping near a stop opens its card; tapping empty map returns to your stop', (tester) async {
    await _pump(tester);
    _config!.onTap(const LatLng(47.5701, -52.7300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(StopSheetContent.refreshKey), findsOneWidget);
    expect(find.text('STOP 1150'), findsOneWidget);
    _config!.onTap(const LatLng(47.0, -52.0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('STOP 1150'), findsNothing);
    expect(find.text('Choose your stop'), findsOneWidget);
  });

  testWidgets('tapping near a bus opens its card', (tester) async {
    await _pump(tester, buses: {'2573': _bus()});
    _config!.onTap(const LatLng(47.5601, -52.7100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('to Downtown'), findsOneWidget);
  });

  testWidgets("a bus's card has a Close button that returns to the home sheet (F2)", (tester) async {
    await _pump(tester, buses: {'2573': _bus()});
    _config!.onTap(const LatLng(47.5601, -52.7100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('to Downtown'), findsNothing);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    expect(container.read(homeSheetProvider), isA<HomeSheetHome>());
  });

  testWidgets('a stop sheet opened from outside the map centres the map on the stop (F1, spec §3.2)', (tester) async {
    await _pump(tester);
    expect(_surface.moves, isEmpty);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    // As a notification, a nearby stop or the search's See its buses does.
    container.read(homeSheetProvider.notifier).open(const StopSheet('1150'));
    await tester.pump(const Duration(milliseconds: 100));
    final (target, zoom, animate) = _surface.moves.single;
    expect((zoom, animate), (15.0, true));
    // South of the stop, so the stop is drawn above the card.
    expect(target.longitude, closeTo(-52.7300, 1e-9));
    expect(target.latitude, lessThan(47.5700));
  });

  testWidgets('a stop card at half shows its stop between the chips and the card, not under the card', (tester) async {
    await _pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    container.read(homeSheetProvider.notifier).open(const StopSheet('1150'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final (target, zoom, _) = _surface.moves.single;
    expect(zoom, 15);
    final view = tester.getSize(find.byType(HomeScreen));
    final stop = onScreen(const LatLng(47.5700, -52.7300), target, zoom, view);
    final chipsBottom = tester.getRect(find.widgetWithText(BBChip, 'All routes')).bottom;
    final cardTop = tester.getRect(find.byKey(BBSheet.cardKey)).top;
    expect(stop.dy, inExclusiveRange(chipsBottom, cardTop), reason: 'the stop is drawn above the card at half');
    expect(stop.dy, closeTo((chipsBottom + cardTop) / 2, 2), reason: 'in the middle of what the chips and card leave');
    expect(stop.dx, closeTo(view.width / 2, 1));
  });

  testWidgets('a stop card opened zoomed in keeps the zoom; zoomed out, it comes to 15', (tester) async {
    await _pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    _surface.zoom = 17;
    container.read(homeSheetProvider.notifier).open(const StopSheet('1150'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_surface.moves.last.$2, 17);
    container.read(homeSheetProvider.notifier).home();
    await tester.pump(const Duration(milliseconds: 100));
    _surface.zoom = 12;
    container.read(homeSheetProvider.notifier).open(const StopSheet('1150'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_surface.moves.last.$2, 15);
  });

  testWidgets('on a tablet a stop card centres its stop on the map beside the panel', (tester) async {
    await _pump(tester, size: const Size(1024, 768));
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    container.read(homeSheetProvider.notifier).open(const StopSheet('1150'));
    await tester.pump(const Duration(milliseconds: 100));
    final (target, zoom, _) = _surface.moves.single;
    final view = tester.getSize(find.byType(HomeScreen));
    final stop = onScreen(const LatLng(47.5700, -52.7300), target, zoom, view);
    final panelRight = tester.getRect(find.byKey(const ValueKey('home-side-panel'))).right;
    final chipsBottom = tester.getRect(find.widgetWithText(BBChip, 'All routes')).bottom;
    expect(stop.dx, greaterThan(panelRight), reason: 'the stop is not under the panel');
    expect(stop.dx, closeTo((panelRight + view.width) / 2, 12), reason: 'it is in the middle of the map beside it');
    expect(stop.dy, closeTo((chipsBottom + view.height) / 2, 2));
  });

  testWidgets('with Reduce Motion the stop sheet\'s camera move jumps', (tester) async {
    await _pump(tester, disableAnimations: true);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    container.read(homeSheetProvider.notifier).open(const StopSheet('1150'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_surface.moves.single.$3, isFalse);
  });

  testWidgets('a bus parked on your stop (a terminal) is still tappable under the star', (tester) async {
    final parked = _bus(lat: _mun.stopLat, lon: _mun.stopLon);
    await _pump(tester, prefs: {'selectedStopId': '1150'}, buses: {'2573': parked});
    _config!.onTap(const LatLng(47.5700, -52.7300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('to Downtown'), findsOneWidget);
  });

  testWidgets('moving from a stop card to a bus card swaps the sheet content cleanly', (tester) async {
    await _pump(tester, buses: {'2573': _bus()});
    _config!.onTap(const LatLng(47.5701, -52.7300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(StopSheetContent.refreshKey), findsOneWidget);
    _config!.onTap(const LatLng(47.5601, -52.7100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('to Downtown'), findsOneWidget);
    expect(find.byKey(StopSheetContent.refreshKey), findsNothing);
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

    testWidgets('pings where the map centred on the rider, twice, then stops (spec §3.2)', (tester) async {
      mockGeolocator();
      final surface = _SequencedLocationSurface([const LatLng(47.55, -52.70)]);
      _surface = surface;
      await _pump(tester);
      expect(find.byType(BBPing), findsNothing);
      await tester.tap(find.byType(BBControlPill));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(surface.moves, hasLength(1));
      expect(find.byKey(BBPing.ringKey), findsOneWidget);
      expect(tester.getCenter(find.byType(BBPing)), tester.getCenter(find.byKey(const ValueKey('stub-map'))));
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(BBPing.ringKey), findsNothing, reason: 'two rings, then gone');
    });

    testWidgets('the first drag of the map cancels the ping, which is a screen overlay that would drift off the dot',
        (tester) async {
      mockGeolocator();
      final surface = _SequencedLocationSurface([const LatLng(47.55, -52.70)]);
      _surface = surface;
      await _pump(tester);
      await tester.tap(find.byType(BBControlPill));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.byKey(BBPing.ringKey), findsOneWidget);
      // A tap is not a camera move: the ping stays. (A point of bare map: the centre is under the sheet.)
      final openMap = tester.getTopLeft(find.byKey(const ValueKey('stub-map'))) + const Offset(195, 250);
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, greaterThan(openMap.dy));
      await tester.tapAt(openMap);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(BBPing.ringKey), findsOneWidget);
      // A pan is.
      await tester.dragFrom(openMap, const Offset(0, -60));
      await tester.pump();
      expect(find.byType(BBPing), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(BBPing), findsNothing, reason: 'it does not come back');
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  testWidgets("the bar shows Where to? and your stop's line in full; pulled up, your stop and its next two buses",
      (tester) async {
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
    final handle = tester.ensureSemantics();
    await _pump(tester, size: const Size(390, 844), prefs: {'selectedStopId': '1150'}, arrivals: [arrival(3), arrival(9), arrival(15)],
        overrides: [homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen())]);
    var card = tester.getRect(find.byKey(BBSheet.cardKey));
    // The bar: Where to? and the stop line, whole inside the resting sheet (spec 2026-10-14 §3.1).
    for (final f in [find.byKey(HomeSheetContent.whereToKey), find.byKey(HomeStopLine.lineKey)]) {
      expect(tester.getRect(f).top, greaterThanOrEqualTo(card.top));
      expect(tester.getRect(f).bottom, lessThanOrEqualTo(card.bottom));
    }
    expect(find.byType(ArrivalRowTile).hitTestable(), findsNothing, reason: 'the buses wait under the bar');
    // Pulled up to half: your stop's header row, then its next two buses (spec §3.3).
    await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    card = tester.getRect(find.byKey(BBSheet.cardKey));
    final tiles = find.byType(ArrivalRowTile);
    final yourStop = tester.getRect(find.bySemanticsLabel('Your stop, MUN Centre. Open its buses'));
    final first = tester.getRect(tiles.at(0));
    expect(yourStop.top, greaterThanOrEqualTo(card.top));
    expect(yourStop.bottom, lessThanOrEqualTo(first.top), reason: 'your stop is above its first bus');
    expect(first.bottom, lessThanOrEqualTo(card.bottom), reason: 'the next bus fits inside the sheet at half');
    expect(tester.getRect(tiles.at(1)).bottom, lessThanOrEqualTo(card.bottom), reason: 'the second bus too');
    handle.dispose();
  });

  testWidgets('choosing a new stop recentres the map on it', (tester) async {
    await _pump(tester);
    expect(_surface.moves, isEmpty);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    await container.read(settingsProvider.notifier).setSelectedStop('1150');
    await tester.pump(const Duration(milliseconds: 100));
    final (target, zoom, animate) = _surface.moves.single;
    expect((zoom, animate), (15.0, true));
    // With no card open the stop is drawn above the home sheet's peek.
    final stop = onScreen(const LatLng(47.5700, -52.7300), target, zoom, tester.getSize(find.byType(HomeScreen)));
    expect(stop.dy, lessThan(tester.getRect(find.byKey(BBSheet.cardKey)).top));
    expect(stop.dy, greaterThan(tester.getRect(find.widgetWithText(BBChip, 'All routes')).bottom));
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
      expect(surface.layers.keys, hasLength(9));
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

      ProviderScope.containerOf(tester.element(find.byType(HomeScreen))).read(mapRouteFilterProvider.notifier).toggle(99);
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
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    expect(container.read(mapRouteFilterProvider), {10});
    semantics.dispose();
  });

  testWidgets('the route filter card dims with the same strong scrim as the other modal cards', (tester) async {
    await _pump(tester, buses: {'2573': _bus()});
    await tester.tap(find.text('All routes'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(topScrim(tester), BBScrim.strong);
  });

  testWidgets('the map is built with rotation off and a Harbour style asset', (tester) async {
    await _pump(tester);
    expect(_config!.styleString, 'assets/map/harbour_light.json');
  });

  group('the bar hint (spec 2026-10-14 §3.6)', () {
    /// Pumps home with the hint not yet seen, lets the flag answer, and records the sheet's top every frame for 1.3 s.
    Future<List<double>> watchHint(WidgetTester tester, {bool reduceMotion = false}) async {
      final gate = Completer<bool>();
      await _pump(tester, prefs: {'selectedStopId': '1150'}, barHintSeen: false, disableAnimations: reduceMotion,
          overrides: [
            barHintSeenProvider.overrideWith(() => _HeldFlag(gate)),
            homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen()),
          ]);
      final tops = [tester.getRect(find.byKey(BBSheet.cardKey)).top];
      gate.complete(false);
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        tops.add(tester.getRect(find.byKey(BBSheet.cardKey)).top);
      }
      return tops;
    }

    testWidgets('the first time the bar shows, the sheet lifts about 24 pt and settles back, and that is stored',
        (tester) async {
      final tops = await watchHint(tester);
      expect(tops.reduce(math.min), lessThanOrEqualTo(tops.first - 20), reason: 'it lifts');
      expect(tops.last, closeTo(tops.first, 0.5), reason: 'and settles back at the bar');
      expect(await SharedPreferencesAsync().getBool(barHintSeenKey), isTrue);
    });

    testWidgets('it plays once: back at the bar after a card, the sheet stays put', (tester) async {
      await watchHint(tester);
      final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      c.read(homeSheetProvider.notifier).open(const StopSheet('1150'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      c.read(homeSheetProvider.notifier).home();
      // A new home sheet measures its bar on its first frames.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final rest = tester.getRect(find.byKey(BBSheet.cardKey)).top;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, closeTo(rest, 0.5));
      }
    });

    testWidgets('a card that opens while the flag is read is never lifted; the hint waits for the bar', (tester) async {
      final gate = Completer<bool>();
      await _pump(tester, prefs: {'selectedStopId': '1150'}, barHintSeen: false, overrides: [
        barHintSeenProvider.overrideWith(() => _HeldFlag(gate)),
        homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen()),
      ]);
      final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      // A notification's stop card arrives first.
      c.read(homeSheetProvider.notifier).open(const StopSheet('1150'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final half = tester.getRect(find.byKey(BBSheet.cardKey)).top;
      gate.complete(false);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, half, reason: 'the card is not nudged');
      }
      expect(await SharedPreferencesAsync().getBool(barHintSeenKey), isNull, reason: 'not shown yet');
      // Back at the bar, it plays.
      c.read(homeSheetProvider.notifier).home();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final tops = <double>[];
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        tops.add(tester.getRect(find.byKey(BBSheet.cardKey)).top);
      }
      expect(await SharedPreferencesAsync().getBool(barHintSeenKey), isTrue);
      expect(tops.last, closeTo(tops.reduce(math.max), 0.5), reason: 'it settles back at the bar');
    });

    testWidgets('never under Reduce Motion, and nothing is stored', (tester) async {
      final tops = await watchHint(tester, reduceMotion: true);
      expect(tops.reduce(math.max) - tops.reduce(math.min), lessThan(0.5));
      expect(await SharedPreferencesAsync().getBool(barHintSeenKey), isNull);
    });
  });

  group('the sheet tucks away on map gestures (spec 2026-10-14 §3.4)', () {
    double top(WidgetTester tester) => tester.getRect(find.byKey(BBSheet.cardKey)).top;
    ProviderContainer container(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));

    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Home with your stop, the tip seen, and the home sheet pulled from its bar up to half. Returns the bar's top.
    Future<double> homeAtHalf(WidgetTester tester, {bool reduceMotion = false}) async {
      await _pump(tester, prefs: {'selectedStopId': '1150'}, disableAnimations: reduceMotion,
          overrides: [homeTipSeenProvider.overrideWith(() => HomeTipSeenNotifier.seen())]);
      final bar = top(tester);
      await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -300));
      await frames(tester);
      expect(top(tester), lessThan(bar - 200), reason: 'the home sheet is up at half');
      return bar;
    }

    /// A pan on bare map: left of the map buttons, between the chips and the sheet at half.
    Future<void> panMap(WidgetTester tester) async {
      await tester.dragFrom(const Offset(60, 170), const Offset(0, 40));
      await frames(tester);
    }

    testWidgets('a pan lowers the home sheet to its bar', (tester) async {
      final bar = await homeAtHalf(tester);
      await panMap(tester);
      expect(top(tester), closeTo(bar, 1));
    });

    testWidgets('a pan lowers a stop card to its own lowest position, and the card stays', (tester) async {
      await _pump(tester, prefs: {'selectedStopId': '1150'});
      container(tester).read(homeSheetProvider.notifier).open(const StopSheet('1150'));
      await frames(tester);
      final card = tester.widget<BBSheet>(find.byType(BBSheet));
      final area = 844 - 2 * BBSpace.s;
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(card.halfFraction * area, 1));
      await panMap(tester);
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(card.peekFraction * area, 1));
      expect(container(tester).read(homeSheetProvider), const StopSheet('1150'));
    });

    testWidgets('a tap, or a move shorter than a pan, leaves the sheet where it is', (tester) async {
      await _pump(tester, prefs: {'selectedStopId': '1150'});
      container(tester).read(homeSheetProvider.notifier).open(const StopSheet('1150'));
      await frames(tester);
      final half = top(tester);
      final gesture = await tester.startGesture(const Offset(60, 170));
      await gesture.moveBy(const Offset(0, 10));
      await frames(tester);
      expect(top(tester), half);
      await gesture.cancel();
    });

    testWidgets('not while choosing on the map', (tester) async {
      await homeAtHalf(tester);
      container(tester).read(mapPickProvider.notifier).start(MapPick.to);
      await frames(tester);
      final half = top(tester);
      await panMap(tester);
      expect(top(tester), half);
    });

    testWidgets('not on the tablet side panel, which has no detents', (tester) async {
      await _pump(tester, size: const Size(1024, 768), prefs: {'selectedStopId': '1150'});
      final panel = tester.getRect(find.byKey(const ValueKey('home-side-panel')));
      await tester.dragFrom(const Offset(800, 400), const Offset(0, 40));
      await frames(tester);
      expect(find.byType(BBSheet), findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('home-side-panel'))), panel);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a drag that starts on the sheet is the sheet's own: pulled up to full, it stays", (tester) async {
      await homeAtHalf(tester);
      await tester.drag(find.byKey(HomeSheetContent.whereToKey), const Offset(0, -400));
      await frames(tester);
      final full = top(tester);
      final sheet = tester.widget<BBSheet>(find.byType(BBSheet));
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).height, closeTo(sheet.fullFraction * (844 - 2 * BBSpace.s), 1));
      await frames(tester);
      expect(top(tester), full);
    });

    testWidgets('a two-finger pinch lowers the sheet once, to its bar', (tester) async {
      final bar = await homeAtHalf(tester);
      final a = await tester.startGesture(const Offset(60, 150), pointer: 1);
      final b = await tester.startGesture(const Offset(60, 190), pointer: 2);
      for (var i = 0; i < 4; i++) {
        await a.moveBy(const Offset(0, -8));
        await b.moveBy(const Offset(0, 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await frames(tester);
      expect(top(tester), closeTo(bar, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('with Reduce Motion the sheet jumps down', (tester) async {
      final bar = await homeAtHalf(tester, reduceMotion: true);
      await tester.dragFrom(const Offset(60, 170), const Offset(0, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(top(tester), closeTo(bar, 1));
    });
  });

  testWidgets('no overflow at 320 pt and text x2.0', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, prefs: {'selectedStopId': '1150'}, textScale: 2);
    expect(tester.takeException(), isNull);
  });

  group('follow mode', () {
    /// [along] places the fix that far along the out-and-back shape when it
    /// differs from [progress] (a bus labelled with another trip); [lat]
    /// moves it off the shape.
    BusTrackingState followed({
      String id = '2573',
      double progress = 100,
      double? along,
      double lat = 47.5600,
      String trip = outAndBackTripId,
      BusStatus status = BusStatus.active,
      DateTime? gps,
    }) =>
        BusTrackingState(
          routeRun: 'Rt 10',
          vehicleId: id,
          routeNumber: 10,
          headsign: 'Loop',
          currentTripId: trip,
          shapeId: outAndBackShapeId,
          lat: lat,
          lon: lonAt(along ?? progress),
          heading: 90,
          progress: progress,
          speedKmh: 29,
          lastGpsTime: gps ?? DateTime.now(),
          status: status,
          lastUpdateTime: gps ?? DateTime.now(),
        );

    late StreamController<Map<String, BusTrackingState>> feed;
    late _RecordingSurface surface;

    ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));

    Future<void> pumpFollow(
      WidgetTester tester, {
      BusTrackingState? bus,
      bool disableAnimations = false,
      List<Override> overrides = const [],
      _RecordingSurface? surfaceOverride,
      Size size = const Size(390, 844),
      double textScale = 1,
      List<ArrivalRow> arrivals = const [],
      Map<String, Object> prefs = const {'selectedStopId': 's2'},
    }) async {
      feed = StreamController<Map<String, BusTrackingState>>();
      addTearDown(feed.close);
      surface = surfaceOverride ?? _RecordingSurface();
      _surface = surface;
      await _pump(
        tester,
        size: size,
        textScale: textScale,
        prefs: prefs,
        repo: outAndBackRepo,
        busStream: feed.stream,
        arrivals: arrivals,
        disableAnimations: disableAnimations,
        overrides: overrides,
      );
      feed.add({'2573': bus ?? followed()});
      await tester.pump();
      await tester.runAsync(() => _styleLoaded(surface));
    }

    Future<void> startFollowing(WidgetTester tester) async {
      containerOf(tester).read(followProvider.notifier).follow('2573');
      await _frames(tester, 3);
    }

    Future<void> realSecond(WidgetTester tester) =>
        tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1150))).then((_) => null);

    Future<void> pan(WidgetTester tester) async {
      await tester.dragFrom(tester.getCenter(find.byKey(const ValueKey('stub-map'))), const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('following shows the top chip and the follow card, and no stop or bus card', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      expect(find.text('Following bus 2573'), findsOneWidget);
      expect(find.textContaining('stops to'), findsOneWidget);
      expect(find.text('Stop following'), findsOneWidget);
      expect(find.byKey(StopSheetContent.refreshKey), findsNothing);
      expect(find.text('Follow'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the follow card's half is a card's, not the home sheet's tall one: the bus stays in view", (
      tester,
    ) async {
      await pumpFollow(tester);
      expect(tester.widget<BBSheet>(find.byType(BBSheet)).halfFraction, greaterThanOrEqualTo(0.75));
      await startFollowing(tester);
      final card = tester.widget<BBSheet>(find.byType(BBSheet));
      expect(card.halfFraction, closeTo(math.max(0.5, card.peekFraction + 0.05), 0.0001));
      expect(card.halfFraction, lessThan(0.75));
    });

    for (final scale in [1.0, 1.3, 1.6, 2.0, 2.5, 3.0]) {
      testWidgets('at 320x640 text x$scale both follow actions are inside the peeking card', (tester) async {
        await pumpFollow(tester, size: const Size(320, 640), textScale: scale);
        await startFollowing(tester);
        final card = tester.getRect(find.byKey(BBSheet.cardKey));
        for (final label in ['See all stops', 'Stop following']) {
          final button = find.ancestor(of: find.text(label), matching: find.byType(BBButton));
          expect(button, findsOneWidget, reason: label);
          final r = tester.getRect(button);
          expect(r.top, greaterThanOrEqualTo(card.top), reason: '$label starts inside the card');
          expect(r.bottom, lessThanOrEqualTo(card.bottom), reason: '$label ends inside the peeking card');
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a follow already set when the map first builds is followed', (tester) async {
      await pumpFollow(tester, overrides: [followProvider.overrideWith(() => _PresetFollow('2573'))]);
      await _frames(tester, 3);
      expect(find.text('Following bus 2573'), findsOneWidget);
      expect(find.textContaining('stops to'), findsOneWidget);
      expect(surface.features('bb-route'), hasLength(2));
    });

    testWidgets('a follow sits under any sheet: open a stop, back returns to the follow card', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      final container = containerOf(tester);
      container.read(homeSheetProvider.notifier).open(const StopSheet('s3'));
      await _frames(tester, 3);
      expect(find.text('Following bus 2573'), findsOneWidget); // the chip stays
      expect(find.byKey(StopSheetContent.refreshKey), findsOneWidget);
      expect(find.byType(FollowCardHeader), findsNothing);
      container.read(homeSheetProvider.notifier).back();
      await _frames(tester, 3);
      expect(find.byType(FollowCardHeader), findsOneWidget);
      expect(find.byKey(StopSheetContent.refreshKey), findsNothing);
    });

    testWidgets('a follow set from a selected bus clears the selection', (tester) async {
      await pumpFollow(tester);
      containerOf(tester).read(homeSheetProvider.notifier).open(const BusSheet('2573'));
      await tester.pump(const Duration(milliseconds: 100));
      containerOf(tester).read(followProvider.notifier).follow('2573');
      await _frames(tester, 2);
      expect(containerOf(tester).read(homeSheetProvider), isA<HomeSheetHome>());
      expect(find.text('Following bus 2573'), findsOneWidget);
    });

    testWidgets('panning pauses the camera and shows Back to bus; the chip resumes it', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      expect(surface.fits, hasLength(1), reason: 'the first frame frames the bus and your stop');
      expect(find.text('Back to bus 2573'), findsNothing);

      await pan(tester);
      expect(find.text('Back to bus 2573'), findsOneWidget);
      await realSecond(tester); // longer than the camera's one-second interval
      await _frames(tester, 3);
      expect(surface.fits, hasLength(1));
      expect(surface.moves, isEmpty);

      await tester.tap(find.text('Back to bus 2573'));
      await _frames(tester, 3);
      expect(find.text('Back to bus 2573'), findsNothing);
      expect(surface.fits, hasLength(2), reason: 'the camera moves at once on resume');
    });

    testWidgets('Back to bus only shows with the sheet down: pulled up, the sheet covers its spot', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      await pan(tester);
      expect(find.text('Back to bus 2573'), findsOneWidget);
      await tester.drag(find.byType(FollowCardHeader), const Offset(0, -300));
      await _frames(tester, 30);
      expect(find.text('Back to bus 2573'), findsNothing, reason: 'the card is pulled up over that spot');
      expect(find.text('Following bus 2573'), findsOneWidget, reason: 'the top chip still leads back to the bus');
      await tester.drag(find.byType(FollowCardHeader), const Offset(0, 400));
      await _frames(tester, 30);
      expect(find.text('Back to bus 2573'), findsOneWidget, reason: 'down at peek again, it comes back');
    });

    testWidgets('a pan never moves the follow card: it keeps its place (spec 2026-10-14 §3.4)', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      await tester.drag(find.byType(FollowCardHeader), const Offset(0, -300));
      await _frames(tester, 30);
      final pulledUp = tester.getRect(find.byKey(BBSheet.cardKey)).top;
      await tester.dragFrom(const Offset(60, 170), const Offset(0, 40));
      await _frames(tester, 6);
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, pulledUp);
    });

    testWidgets('a plain tap on the map does not pause', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('stub-map'))));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Back to bus 2573'), findsNothing);
    });

    testWidgets('the top chip also resumes a paused follow', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      await pan(tester);
      expect(find.text('Back to bus 2573'), findsOneWidget);
      await tester.tap(find.text('Following bus 2573'));
      await _frames(tester, 3);
      expect(find.text('Back to bus 2573'), findsNothing);
      expect(surface.fits, hasLength(2));
    });

    testWidgets('the camera fits the bus and your stop with the sheet and chips cleared', (tester) async {
      var skew = Duration.zero;
      await pumpFollow(tester, overrides: [mapClockProvider.overrideWithValue(() => DateTime.now().add(skew))]);
      await startFollowing(tester);
      expect(surface.fits, hasLength(1));
      // The first fit runs before the follow card has measured its header;
      // the next one, a second later, uses the settled layout.
      skew = const Duration(milliseconds: 1100);
      await _frames(tester, 3);
      expect(surface.fits, hasLength(2));
      final (bus, stop, padding, animate) = surface.fits.last;
      expect(bus.longitude, closeTo(lonAt(100), 1e-4));
      expect(stop, LatLng(47.560045, lonAt(500)));
      expect(animate, isTrue);
      // Edge air plus half a followed (1.35×) marker, so the badges stay whole.
      expect(padding.left, 64);
      expect(padding.right, 64);
      expect(padding.top, greaterThan(16 + 44), reason: 'below the chips');
      final screenHeight = tester.getBottomLeft(find.byType(HomeScreen)).dy;
      final creditTop = tester.getTopLeft(find.textContaining('OpenStreetMap')).dy;
      expect(padding.bottom, greaterThanOrEqualTo(screenHeight - creditTop + 16), reason: 'above the credit and the peeking sheet');
    });

    testWidgets('on a tablet the camera fit clears the side panel and the follow card is in it', (tester) async {
      var skew = Duration.zero;
      await pumpFollow(tester,
          size: const Size(1024, 768), overrides: [mapClockProvider.overrideWithValue(() => DateTime.now().add(skew))]);
      await startFollowing(tester);
      skew = const Duration(milliseconds: 1100);
      await _frames(tester, 3);
      expect(find.byType(BBSheet), findsNothing);
      final panel = tester.getRect(find.byKey(const ValueKey('home-side-panel')));
      expect(find.descendant(of: find.byKey(const ValueKey('home-side-panel')), matching: find.text('Stop following')), findsOneWidget);
      final (_, _, padding, _) = surface.fits.last;
      expect(padding.left, panel.right + 64, reason: 'the panel, then the edge air');
      expect(padding.right, 64);
      expect(padding.bottom, 64, reason: 'no sheet to clear');
      expect(padding.top, greaterThan(16 + 44));
    });

    testWidgets('on a tablet See all stops scrolls the panel down to the stop list', (tester) async {
      await pumpFollow(tester, size: const Size(1024, 300));
      await startFollowing(tester);
      final scrollable = find.descendant(of: find.byKey(const ValueKey('home-side-panel')), matching: find.byType(Scrollable));
      ScrollPosition position() => tester.state<ScrollableState>(scrollable).position;
      expect(position().maxScrollExtent, greaterThan(0), reason: 'the card is taller than the panel');
      expect(position().pixels, 0);
      await tester.tap(find.text('See all stops'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100)); // the scroll animation
      }
      expect(position().pixels, greaterThan(0));
    });

    testWidgets('while following, the route is drawn as a driven and an ahead part', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      final parts = surface.features('bb-route');
      expect(parts.map((f) => (f['properties'] as Map)['part']), ['driven', 'ahead']);
    });

    testWidgets('Reduce Motion makes the camera jump instead of animating', (tester) async {
      await pumpFollow(tester, disableAnimations: true);
      await startFollowing(tester);
      expect(surface.fits, hasLength(1));
      await pan(tester);
      await tester.tap(find.text('Back to bus 2573'));
      await _frames(tester, 3);
      expect(surface.fits, hasLength(2));
      expect(surface.fits.map((f) => f.$4), [false, false]);
      expect(surface.moves, isEmpty);
    });

    testWidgets('a stale followed bus shows Last seen', (tester) async {
      await pumpFollow(tester, bus: followed(status: BusStatus.stale, gps: DateTime.now().subtract(const Duration(seconds: 75))));
      await startFollowing(tester);
      expect(find.textContaining('Last seen 1 min ago'), findsOneWidget);
      expect(containerOf(tester).read(followProvider), isNotNull);
    });

    testWidgets('a bus that is not in the feed yet shows Finding bus', (tester) async {
      await pumpFollow(tester);
      feed.add(const {});
      await tester.pump();
      await startFollowing(tester);
      expect(find.text('Finding bus 2573…'), findsOneWidget);
    });

    testWidgets('a trip change while the bus is still on the old shape keeps following', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      // The feed rolls the trip over early; the fix is still on the old trip,
      // 300 m along it (its progress on the new trip means nothing here).
      feed.add({'2573': followed(trip: 'some-other-trip', progress: 20, along: 300)});
      await realSecond(tester);
      await _frames(tester, 3);
      expect(containerOf(tester).read(followProvider), isNotNull);
      expect(find.byKey(BBToast.cardKey), findsNothing);
      expect(find.text('Following bus 2573'), findsOneWidget);
      expect(find.text('1 stop to s2'), findsOneWidget, reason: "placed on the old trip's stops from the live fix");
      final driven = (surface.features('bb-route').first['geometry'] as Map)['coordinates'] as List;
      expect((driven.last as List).first, closeTo(lonAt(300), 1e-4), reason: "the old trip's line, split at the live fix");
    });

    testWidgets('a trip change once the bus has left the old shape ends the follow with a toast and clears the route', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      expect(surface.features('bb-route'), hasLength(2));
      feed.add({'2573': followed(trip: 'some-other-trip', lat: 47.58)});
      await _frames(tester, 3);
      expect(find.text('Bus 2573 has finished its trip'), findsOneWidget);
      expect(containerOf(tester).read(followProvider), isNull);
      expect(surface.features('bb-route'), isEmpty);
      expect(find.text('Following bus 2573'), findsNothing);
      await tester.pump(const Duration(seconds: 5)); // the toast's timer
    });

    testWidgets('after following ends, the camera stops and the Back chip goes', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      await pan(tester);
      expect(find.text('Back to bus 2573'), findsOneWidget);
      feed.add({'2573': followed(trip: 'some-other-trip', lat: 47.58)});
      await _frames(tester, 3);
      expect(containerOf(tester).read(followProvider), isNull);
      expect(find.text('Back to bus 2573'), findsNothing);
      final calls = surface.fits.length + surface.moves.length;
      await realSecond(tester);
      await _frames(tester, 4);
      expect(surface.fits.length + surface.moves.length, calls);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Stop following ends the follow and clears the route, without a toast', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      await tester.tap(find.text('Stop following'));
      await _frames(tester, 2);
      expect(containerOf(tester).read(followProvider), isNull);
      expect(surface.features('bb-route'), isEmpty);
      expect(find.byKey(BBToast.cardKey), findsNothing);
      expect(find.text('Following bus 2573'), findsNothing);
    });

    testWidgets('See all stops opens the sheet to its full height', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      final before = tester.getRect(find.byKey(BBSheet.cardKey)).top;
      await tester.tap(find.text('See all stops'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Full is 90% of the area under the status bar.
      expect(tester.getRect(find.byKey(BBSheet.cardKey)).top, lessThan(before - 400));
    });

    testWidgets('a style reload while following draws the route again', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      await tester.runAsync(() => _styleLoaded(surface));
      expect(surface.features('bb-route'), hasLength(2), reason: 'the new style starts empty; the route is pushed back at once');
    });

    Future<double> sheetTop(WidgetTester tester) async => tester.getRect(find.byKey(BBSheet.cardKey)).top;

    // The sheet's animations need a few frames to run to the end.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> expandSheet(WidgetTester tester) async {
      await tester.tap(find.text('See all stops'));
      await settle(tester);
    }

    testWidgets('while following, taps near a bus or a stop are ignored and leave the sheet alone', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      await expandSheet(tester);
      final open = await sheetTop(tester);
      _config!.onTap(LatLng(47.560045, lonAt(500)));
      await settle(tester);
      expect(find.byKey(StopSheetContent.refreshKey), findsNothing);
      expect(await sheetTop(tester), open);
      _config!.onTap(LatLng(47.5601, lonAt(100)));
      await settle(tester);
      expect(containerOf(tester).read(homeSheetProvider), isA<HomeSheetHome>());
      expect(find.text('Following bus 2573'), findsOneWidget);
      expect(await sheetTop(tester), open);
    });

    testWidgets('a stop sheet over a follow: tapping another stop replaces it and the follow keeps running', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      final container = containerOf(tester);
      container.read(homeSheetProvider.notifier).open(const StopSheet('s3'));
      await _frames(tester, 3);
      expect(find.byKey(StopSheetContent.refreshKey), findsOneWidget);
      _config!.onTap(LatLng(47.560045, lonAt(500)));
      await settle(tester);
      expect(container.read(homeSheetProvider.notifier).stack, [const HomeSheetHome(), const StopSheet('s2')]);
      expect(container.read(followProvider), isNotNull);
      expect(find.text('Following bus 2573'), findsOneWidget);
    });

    testWidgets('while following, a tap on empty map collapses the sheet to peek', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      final peek = await sheetTop(tester);
      await expandSheet(tester);
      expect(await sheetTop(tester), lessThan(peek - 100));
      _config!.onTap(const LatLng(47.0, -52.0));
      await settle(tester);
      expect(await sheetTop(tester), peek);
    });

    testWidgets('the followed bus is still drawn when the route filter excludes its route', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      containerOf(tester).read(mapRouteFilterProvider.notifier).toggle(99);
      await _frames(tester, 3);
      expect(surface.busSets.last.map((f) => (f['properties'] as Map)['vehicleId']), ['2573']);
    });

    testWidgets('a two-finger pinch pauses', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      final a = await tester.startGesture(const Offset(150, 300));
      final b = await tester.startGesture(const Offset(250, 300));
      await a.moveBy(const Offset(-30, 0));
      await b.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await a.up();
      await b.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Back to bus 2573'), findsOneWidget);
    });

    testWidgets('a 10 px jitter does not pause', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      final g = await tester.startGesture(const Offset(200, 300));
      await g.moveBy(const Offset(6, 8));
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Back to bus 2573'), findsNothing);
    });

    testWidgets('switching straight from one bus to another follows the new one and draws its route', (tester) async {
      await pumpFollow(tester);
      feed.add({'2573': followed(), '2574': followed(id: '2574', progress: 300)});
      await tester.pump();
      await startFollowing(tester);
      await pan(tester);
      expect(find.text('Back to bus 2573'), findsOneWidget);
      containerOf(tester).read(followProvider.notifier).follow('2574');
      await _frames(tester, 3);
      expect(find.text('Following bus 2574'), findsOneWidget);
      expect(find.text('Back to bus 2573'), findsNothing);
      expect(find.text('Back to bus 2574'), findsNothing);
      final driven = (surface.features('bb-route').first['geometry'] as Map)['coordinates'] as List;
      expect((driven.last as List).first, closeTo(lonAt(300), 1e-4), reason: 'the line is split at bus 2574');
    });

    testWidgets('a follow that ends while the style is being reinstalled leaves no route on the new style', (tester) async {
      final gated = _RouteGateSurface();
      await pumpFollow(tester, surfaceOverride: gated);
      await startFollowing(tester);
      expect(gated.features('bb-route'), hasLength(2));
      gated.gate = Completer<void>();
      await tester.runAsync(() async {
        _config!.onStyleLoaded();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      expect(gated.routePushWaiting, isTrue, reason: 'the install is waiting to redraw the route');
      containerOf(tester).read(followProvider.notifier).stop();
      await tester.runAsync(() async {
        gated.gate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      expect(gated.features('bb-route'), isEmpty);
    });

    group('across an app pause (C1)', () {
      // Through every state between, as a phone goes: the arrival alerts' lifecycle listener (alive whenever home is)
      // asserts each step is to a neighbouring state.
      Future<void> lockFor(WidgetTester tester, Duration locked, void Function(Duration) setSkew) async {
        for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
          tester.binding.handleAppLifecycleStateChanged(s);
        }
        await tester.pump();
        setSkew(locked);
        for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
          tester.binding.handleAppLifecycleStateChanged(s);
        }
        await _frames(tester, 3);
      }

      testWidgets('6 min locked: the follow waits for a fresh poll, then endings work again', (tester) async {
        var skew = Duration.zero;
        DateTime now() => DateTime.now().add(skew);
        await pumpFollow(tester, overrides: [mapClockProvider.overrideWithValue(now)]);
        await startFollowing(tester);
        expect(find.textContaining('stops to'), findsOneWidget);

        await lockFor(tester, const Duration(minutes: 6), (d) => skew = d);
        expect(containerOf(tester).read(followProvider), isNotNull, reason: 'the pre-lock fix is not judged');
        expect(find.byKey(BBToast.cardKey), findsNothing);
        expect(find.text('Following bus 2573'), findsOneWidget);

        feed.add({'2573': followed(gps: now())});
        await _frames(tester, 3);
        expect(containerOf(tester).read(followProvider), isNotNull);
        expect(find.textContaining('stops to'), findsOneWidget);

        feed.add(const {});
        await _frames(tester, 3);
        expect(find.text('Lost contact with bus 2573'), findsOneWidget);
        expect(containerOf(tester).read(followProvider), isNull);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('Follow, then lock before the first poll: still finding the bus after', (tester) async {
        var skew = Duration.zero;
        DateTime now() => DateTime.now().add(skew);
        await pumpFollow(tester, overrides: [mapClockProvider.overrideWithValue(now)]);
        feed.add(const {});
        await tester.pump();
        await startFollowing(tester);
        expect(find.text('Finding bus 2573…'), findsOneWidget);

        await lockFor(tester, const Duration(minutes: 6), (d) => skew = d);
        expect(containerOf(tester).read(followProvider), isNotNull);
        expect(find.byKey(BBToast.cardKey), findsNothing);

        // A fresh poll without the bus: the 60 s search starts again from it.
        feed.add(const {});
        await _frames(tester, 3);
        expect(find.text('Finding bus 2573…'), findsOneWidget);
        expect(find.byKey(BBToast.cardKey), findsNothing);

        feed.add({'2573': followed(gps: now())});
        await _frames(tester, 3);
        expect(find.textContaining('stops to'), findsOneWidget);
      });
    });

    testWidgets('near your stop the camera centres the bus and stop in the band above the sheet', (tester) async {
      var skew = Duration.zero;
      await pumpFollow(tester, bus: followed(progress: 420), overrides: [mapClockProvider.overrideWithValue(() => DateTime.now().add(skew))]);
      await startFollowing(tester);
      // The first move runs before the follow card has measured its header; the next, a second later, uses the settled layout.
      skew = const Duration(milliseconds: 1100);
      await _frames(tester, 3);
      expect(surface.moves, hasLength(2));
      final (target, zoom, _) = surface.moves.last;
      expect(zoom, 16.5);
      // Where a point lands on screen with the camera at [target]/[zoom] (north-up, MapLibre's 512-point world).
      double mercY(double lat) {
        final r = lat * math.pi / 180;
        return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
      }

      final screenH = tester.getBottomLeft(find.byType(HomeScreen)).dy;
      final world = 512 * math.pow(2, zoom);
      double screenY(double lat) => screenH / 2 + (mercY(lat) - mercY(target.latitude)) * world;
      // The band between the chip row (the right-hand buttons sit beside the map, not over the framing) and the peeking sheet.
      final chipsBottom = tester.getRect(find.widgetWithText(BBChip, 'All routes')).bottom;
      final sheetTop = tester.getRect(find.byKey(BBSheet.cardKey)).top;
      final bus = screenY(47.5600);
      final stop = screenY(47.560045);
      expect(bus, inInclusiveRange(chipsBottom, sheetTop), reason: 'the bus is drawn between the chips and the sheet');
      expect(stop, inInclusiveRange(chipsBottom, sheetTop), reason: 'and so is your stop');
      // Centred in what the chips and the sheet leave: not pushed down by the buttons' column, which is not in the way.
      expect((bus + stop) / 2, closeTo((chipsBottom + sheetTop) / 2, 40));
    });

    testWidgets('the route line is not pushed again while the bus has not moved', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      final pushes = surface.routePushes;
      expect(pushes, greaterThan(0));
      await realSecond(tester);
      await _frames(tester, 3);
      expect(surface.routePushes, pushes);
    });

    testWidgets('a follow from a planned trip counts to its boarding stop, not the saved one', (tester) async {
      await pumpFollow(tester); // the saved stop is s2
      containerOf(tester).read(followProvider.notifier).follow('2573', stopId: 's3');
      await _frames(tester, 3);
      expect(find.textContaining(RegExp(r'^(\d+ stops?|Next stop:?) .*s3$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^(\d+ stops?|Next stop:?) .*s2$')), findsNothing);
      expect(find.text("Your stop isn't on this trip"), findsNothing);
    });

    List<String> markedStops() => [for (final f in surface.features('bb-my-stop')) f['properties']['stopId'] as String];

    testWidgets('a follow from a planned trip marks its boarding stop, and the saved stop comes back after', (tester) async {
      await pumpFollow(tester); // the saved stop is s2
      expect(markedStops(), ['s2']);
      containerOf(tester).read(followProvider.notifier).follow('2573', stopId: 's3');
      await _frames(tester, 3);
      expect(markedStops(), ['s3'], reason: 'the boarding stop is your stop for the follow');
      containerOf(tester).read(followProvider.notifier).stop();
      await _frames(tester, 3);
      expect(markedStops(), ['s2']);
    });

    testWidgets('with no saved stop, a planned follow marks its boarding stop and clears it after', (tester) async {
      await pumpFollow(tester, prefs: const {});
      expect(markedStops(), isEmpty);
      containerOf(tester).read(followProvider.notifier).follow('2573', stopId: 's3');
      await _frames(tester, 3);
      expect(markedStops(), ['s3']);
      containerOf(tester).read(followProvider.notifier).stop();
      await _frames(tester, 3);
      expect(markedStops(), isEmpty);
    });

    testWidgets('a follow from the Board keeps the saved stop marked', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      expect(markedStops(), ['s2']);
    });

    testWidgets('choosing a new stop during a planned follow marks it once the follow ends', (tester) async {
      await pumpFollow(tester);
      containerOf(tester).read(followProvider.notifier).follow('2573', stopId: 's3');
      await _frames(tester, 3);
      await containerOf(tester).read(settingsProvider.notifier).setSelectedStop('s1');
      await _frames(tester, 3);
      expect(markedStops(), ['s3'], reason: 'the follow keeps its own stop');
      containerOf(tester).read(followProvider.notifier).stop();
      await _frames(tester, 3);
      expect(markedStops(), ['s1']);
    });

    testWidgets('a style reload during a planned follow draws the boarding stop', (tester) async {
      await pumpFollow(tester);
      containerOf(tester).read(followProvider.notifier).follow('2573', stopId: 's3');
      await _frames(tester, 3);
      await tester.runAsync(() => _styleLoaded(surface));
      await _frames(tester, 3);
      expect(markedStops(), ['s3']);
    });

    testWidgets('following the same bus for another stop keeps the route line drawn', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      expect(surface.features('bb-route'), isNotEmpty);
      // The same bus, now from a planned trip boarding at s3; the bus has not moved.
      containerOf(tester).read(followProvider.notifier).follow('2573', stopId: 's3');
      await _frames(tester, 3);
      expect(surface.features('bb-route').map((f) => (f['properties'] as Map)['part']), ['driven', 'ahead']);
      expect(find.textContaining(RegExp(r'^(\d+ stops?|Next stop:?) .*s3$')), findsOneWidget);
    });

    testWidgets('a follow from the Board still counts to the saved stop', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      expect(find.textContaining(RegExp(r'^(\d+ stops?|Next stop:?) .*s2$')), findsOneWidget);
    });

    testWidgets('the Following chip tells screen readers it brings the camera back to the bus', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpFollow(tester);
      await startFollowing(tester);
      expect(find.bySemanticsLabel('Following bus 2573. Back to the bus'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('choosing a new stop while following leaves the camera to the follow', (tester) async {
      await pumpFollow(tester);
      await startFollowing(tester);
      await containerOf(tester).read(settingsProvider.notifier).setSelectedStop('s3');
      await tester.pump(const Duration(milliseconds: 100));
      await realSecond(tester);
      await _frames(tester, 3);
      expect(surface.moves.where((m) => m.$2 == 15.0), isEmpty, reason: 'no recentre on the stop at zoom 15');
    });

    for (final scale in [1.0, 1.3, 1.6, 2.0]) {
      testWidgets('the alert bell sits in the follow card and nothing overflows at 320 pt, text x$scale', (tester) async {
        final arrival = ArrivalRow(
          routeShortName: '10',
          headsign: 'Downtown',
          scheduledTime: GtfsTime.parse('09:52:00'),
          predictedTime: GtfsTime.parse('09:55:00'),
          minutesAway: 12,
          liveStatus: LiveStatus.behind,
          isLive: true,
          tripId: 't12',
          vehicleNumber: '2573',
          isEnhanced: false,
          routeRun: '10-1',
        );
        await pumpFollow(tester, size: const Size(320, 640), textScale: scale, arrivals: [arrival]);
        await startFollowing(tester);
        final bell = find.bySemanticsLabel('Alert me before route 10 arrives');
        expect(bell, findsOneWidget);
        final card = tester.getRect(find.byKey(BBSheet.cardKey));
        expect(tester.getRect(bell).bottom, lessThanOrEqualTo(card.bottom));
        for (final label in ['See all stops', 'Stop following']) {
          final r = tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(BBButton)));
          expect(r.bottom, lessThanOrEqualTo(card.bottom), reason: '$label stays in the peek with the bell');
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets("the bell is for the followed bus's arrival, even when another is listed first", (tester) async {
      ArrivalRow arrival(String trip, String vehicle, int minutes) => ArrivalRow(
            routeShortName: '10',
            headsign: 'Downtown',
            scheduledTime: GtfsTime.parse('09:52:00'),
            predictedTime: GtfsTime.parse('09:55:00'),
            minutesAway: minutes,
            liveStatus: LiveStatus.behind,
            isLive: true,
            tripId: trip,
            vehicleNumber: vehicle,
            isEnhanced: false,
            routeRun: '10-1',
          );
      await pumpFollow(tester, arrivals: [arrival('t99', '9999', 6), arrival('t12', '2573', 12)]);
      await startFollowing(tester);
      final bell = tester.widget<AlertBell>(find.byType(AlertBell));
      expect(bell.arrival.tripId, 't12');
      expect(bell.arrival.vehicleNumber, '2573');
    });

    testWidgets('no overflow at 320 pt and text x2.0 while following', (tester) async {
      await pumpFollow(tester, size: const Size(320, 640), textScale: 2);
      await startFollowing(tester);
      // The tall peek covers the map's middle: pan low on the left edge, clear of the chips.
      await tester.dragFrom(const Offset(20, 200), const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Back to bus 2573'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('planning from the map', () {
    // Real glyph widths, so the 2x text checks measure what a phone shows.
    setUpAll(loadAppFonts);
    final eight = DateTime(testDay.year, testDay.month, testDay.day, 8, 1);
    // Also while the search is pushed over home.
    ProviderContainer container(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(HomeScreen, skipOffstage: false)));

    testWidgets('a long-press on a stop opens a sheet named for it; Plan to here opens options to it', (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: eight, initial: '/', mapView: map.build);
      map.longPress(47.5700, -52.7500);
      await tester.pumpAndSettle();
      expect(find.text('Stop C'), findsOneWidget);
      expect(find.text('Plan from here'), findsOneWidget);
      await tester.tap(find.text('Plan to here'));
      await tester.pumpAndSettle();
      final c = container(tester);
      expect(c.read(planQueryProvider).to, StopPlace(stopId: 'C', name: 'Stop C'));
      expect(c.read(planQueryProvider).from, isNull, reason: 'location is off: the start stays empty');
      expect(c.read(homeSheetProvider), isA<OptionsSheet>());
      expect(find.byType(SearchScreen), findsNothing);
    });

    testWidgets('Plan to here starts from the phone\'s position when there is no start', (tester) async {
      final map = StubMap();
      await pumpPlannerApp(
        tester,
        net: TestNetwork(),
        now: eight,
        initial: '/',
        mapView: map.build,
        geolocator: FixedGeolocator(47.5601, -52.7501),
      );
      map.longPress(47.5700, -52.7500);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan to here'));
      await tester.pumpAndSettle();
      final draft = container(tester).read(planQueryProvider);
      expect(draft.to, StopPlace(stopId: 'C', name: 'Stop C'));
      expect(draft.from, isA<PinPlace>().having((p) => p.label, 'label', 'My location'));
    });

    testWidgets('the long-press card dims with the same strong scrim as the other modal cards', (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: eight, initial: '/', mapView: map.build);
      map.longPress(47.5700, -52.7500);
      await tester.pumpAndSettle();
      expect(find.text('Plan from here'), findsOneWidget);
      expect(topScrim(tester), BBScrim.strong);
    });

    testWidgets('a long-press far from any stop drops a pin; Plan from here sets the start and opens the search',
        (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: eight, initial: '/', mapView: map.build);
      map.longPress(47.0, -52.0);
      await tester.pumpAndSettle();
      expect(find.text('Dropped pin'), findsOneWidget);
      await tester.tap(find.text('Plan from here'));
      await tester.pumpAndSettle();
      final from = container(tester).read(planQueryProvider).from;
      expect(from, isA<PinPlace>().having((p) => p.label, 'label', 'Dropped pin').having((p) => p.lat, 'lat', 47.0));
      expect(tester.widget<SearchScreen>(find.byType(SearchScreen)).end, MapPick.to, reason: 'next: where to');
    });

    testWidgets('Plan to here starts a fresh trip: no old start, leaving now (F3, Ruling 14)', (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: eight, initial: '/', mapView: map.build);
      final c = container(tester);
      c.read(planQueryProvider.notifier)
        ..setTrip(StopPlace(stopId: 'A', name: 'Stop A'), StopPlace(stopId: 'E', name: 'Stop E'))
        ..setMode(PlanMode.arriveBy)
        ..setTime(eight.add(const Duration(hours: 1)));
      map.longPress(47.5700, -52.7500);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan to here'));
      await tester.pumpAndSettle();
      final draft = c.read(planQueryProvider);
      expect(draft.to, StopPlace(stopId: 'C', name: 'Stop C'));
      expect(draft.from, isNull, reason: 'location is off: no start, not the old one');
      expect(draft.mode, PlanMode.leaveNow);
      expect(draft.time, isNull);
    });

    testWidgets('Plan from here starts a fresh trip from the press, leaving now, and its search keeps that start',
        (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: eight, initial: '/', mapView: map.build);
      final c = container(tester);
      c.read(planQueryProvider.notifier)
        ..setTrip(StopPlace(stopId: 'A', name: 'Stop A'), StopPlace(stopId: 'E', name: 'Stop E'))
        ..setMode(PlanMode.arriveBy);
      map.longPress(47.5700, -52.7500);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan from here'));
      await tester.pumpAndSettle();
      expect(c.read(planQueryProvider).mode, PlanMode.leaveNow);
      await tester.enterText(find.byKey(SearchScreen.fieldKey), 'Stop E');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Stop E (E)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go here'));
      await tester.pumpAndSettle();
      final draft = c.read(planQueryProvider);
      expect(draft.from, StopPlace(stopId: 'C', name: 'Stop C'));
      expect(draft.to, StopPlace(stopId: 'E', name: 'Stop E'));
      expect(draft.mode, PlanMode.leaveNow);
    });

    testWidgets('a destination picked on the map from Where to? starts a fresh trip (F3)', (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: eight, initial: '/', mapView: map.build);
      final c = container(tester);
      c.read(planQueryProvider.notifier)
        ..setTrip(StopPlace(stopId: 'A', name: 'Stop A'), StopPlace(stopId: 'E', name: 'Stop E'))
        ..setMode(PlanMode.arriveBy);
      await tester.tap(find.byKey(HomeSheetContent.whereToKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose on map'));
      await tester.pumpAndSettle();
      map.tap(47.5700, -52.7500); // Stop C
      await tester.pumpAndSettle();
      final draft = c.read(planQueryProvider);
      expect(draft.to, StopPlace(stopId: 'C', name: 'Stop C'));
      expect(draft.from, isNull);
      expect(draft.mode, PlanMode.leaveNow);
    });

    testWidgets('a destination picked on the map from the options keeps their start (F3)', (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: eight, initial: '/', mapView: map.build);
      final c = container(tester);
      c.read(planQueryProvider.notifier).setTrip(StopPlace(stopId: 'A', name: 'Stop A'), StopPlace(stopId: 'E', name: 'Stop E'));
      c.read(homeSheetProvider.notifier).open(const OptionsSheet());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OptionsSheetContent.toRowKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose on map'));
      await tester.pumpAndSettle();
      map.tap(47.5700, -52.7500); // Stop C
      await tester.pumpAndSettle();
      final draft = c.read(planQueryProvider);
      expect(draft.to, StopPlace(stopId: 'C', name: 'Stop C'));
      expect(draft.from, StopPlace(stopId: 'A', name: 'Stop A'));
    });

    testWidgets('a stop 60 m away is too far to count: the press drops a pin', (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: eight, initial: '/', mapView: map.build);
      map.longPress(47.5700 + 60 / 111320, -52.7500); // 60 m north of C
      await tester.pumpAndSettle();
      expect(find.text('Dropped pin'), findsOneWidget);
    });

    testWidgets('pick mode: the banner asks for the start, and a tap at a stop sets it and keeps the sheet',
        (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: eight, initial: '/', mapView: map.build);
      final c = container(tester);
      c.read(planQueryProvider.notifier).setDestination(StopPlace(stopId: 'C', name: 'Stop C'));
      c.read(homeSheetProvider.notifier).open(const OptionsSheet());
      c.read(mapPickProvider.notifier).start(MapPick.from);
      await tester.pumpAndSettle();
      expect(find.text('Tap the map to choose your starting point'), findsOneWidget);
      expect(find.bySemanticsLabel('Cancel choosing on the map'), findsOneWidget);
      map.tap(47.5600, -52.7500);
      await tester.pumpAndSettle();
      expect(c.read(planQueryProvider).from, StopPlace(stopId: 'A', name: 'Stop A'));
      expect(c.read(mapPickProvider), isNull);
      expect(c.read(homeSheetProvider), isA<OptionsSheet>());
      expect(find.text('Tap the map to choose your starting point'), findsNothing);
    });

    testWidgets('pick mode for the destination says so, and Cancel ends it with nothing set', (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: eight, initial: '/', mapView: map.build);
      final c = container(tester);
      c.read(mapPickProvider.notifier).start(MapPick.to);
      await tester.pumpAndSettle();
      expect(find.text('Tap the map to choose your destination'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.read(mapPickProvider), isNull);
      expect(find.text('Tap the map to choose your destination'), findsNothing);
      expect(c.read(planQueryProvider).to, isNull);
      expect(c.read(homeSheetProvider), isA<HomeSheetHome>());
    });

    testWidgets('system back in pick mode ends the pick instead of leaving the app', (tester) async {
      await pumpPlannerApp(tester, net: TestNetwork(), now: eight, initial: '/');
      final c = container(tester);
      c.read(mapPickProvider.notifier).start(MapPick.to);
      await tester.pumpAndSettle();
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(c.read(mapPickProvider), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    for (final size in const [Size(320, 568), Size(390, 844)]) {
      testWidgets('at 2x text on ${size.width.toInt()} wide the banner, the sheet and Hide trip read in full', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        void readsInFull(String text) {
          expect(find.text(text), findsOneWidget);
          final p = tester.renderObject<RenderParagraph>(find.text(text));
          expect(p.didExceedMaxLines, isFalse, reason: '"$text" is cut short');
        }

        final map = StubMap();
        await pumpPlannerApp(
          tester,
          net: TestNetwork(),
          now: eight,
          initial: '/',
          textScale: 2,
          mapView: map.build,
        );
        container(tester).read(mapPickProvider.notifier).start(MapPick.from);
        await tester.pumpAndSettle();
        readsInFull('Tap the map to choose your starting point');
        readsInFull('Cancel');
        map.longPress(47.0, -52.0);
        await tester.pumpAndSettle();
        for (final t in ['Dropped pin', 'Plan from here', 'Plan to here']) {
          readsInFull(t);
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(BBIcons.close));
        await tester.pumpAndSettle();
        final c = container(tester);
        c.read(journeyOnMapProvider.notifier).show(Journey(serviceDate: testDay, legs: [
          RideLeg(routeId: '1', tripId: '1-0', boardStopId: 'A', alightStopId: 'C', departs: 8 * 3600, arrives: 8 * 3600 + 600, stopCount: 2),
        ]));
        await tester.pumpAndSettle();
        readsInFull('Hide trip');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a new destination picked on the map never shows the old results in the options', (tester) async {
      final map = StubMap();
      await pumpPlannerApp(tester, net: TestNetwork(), now: eight, initial: '/', mapView: map.build);
      final c = container(tester);
      c.read(planQueryProvider.notifier).setTrip(StopPlace(stopId: 'A', name: 'Stop A'), StopPlace(stopId: 'C', name: 'Stop C'));
      c.read(homeSheetProvider.notifier).open(const OptionsSheet());
      await tester.pumpAndSettle();
      await tester.drag(find.bySemanticsLabel('Map sheet'), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.byType(JourneyCard), findsWidgets);
      // As the options' destination search does with Choose on map: the trip keeps its start.
      c.read(mapPickProvider.notifier).start(MapPick.to, keepStart: true);
      await tester.pumpAndSettle();
      expect(find.text('Tap the map to choose your destination'), findsOneWidget);
      map.tap(47.5800, -52.7500); // Stop E
      void onlyNewResults() {
        for (final card in tester.widgetList<JourneyCard>(find.byType(JourneyCard, skipOffstage: false))) {
          final last = card.journey.legs.whereType<RideLeg>().last;
          expect(last.alightStopId, 'E', reason: 'a card for the old destination is on screen');
        }
      }

      await tester.pump();
      onlyNewResults();
      await tester.pump();
      onlyNewResults();
      await tester.pumpAndSettle();
      expect(c.read(homeSheetProvider), isA<OptionsSheet>());
      await tester.drag(find.bySemanticsLabel('Map sheet'), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.byType(JourneyCard), findsWidgets);
      onlyNewResults();
    });
  });

  group('a planned journey on the map', () {
    String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

    /// Stop A → C on route 1 (with a shape), C → E on route 2 (none), from a pin south of A.
    GtfsRepository network() {
      final net = TestNetwork();
      final t = net.repo.tripsById['1-0']!;
      net.repo.tripsById['1-0'] = TripInfo(
        tripId: t.tripId,
        routeId: t.routeId,
        serviceId: t.serviceId,
        tripHeadsign: t.tripHeadsign,
        directionId: 0,
        shapeId: 'S1',
      );
      final points = [
        for (var i = 0; i <= 6; i++)
          ShapePoint(shapeId: 'S1', lat: 47.5550 + i * 0.0050, lon: -52.7500, sequence: i),
      ];
      net.repo.shapesById['S1'] = points;
      net.repo.shapeCumulativeDistances['S1'] = cumulativeFor(points);
      return net.repo;
    }

    Journey journey() => Journey(serviceDate: testDay, legs: [
          WalkLeg(fromStopId: null, toStopId: 'A', seconds: 120, startSeconds: 8 * 3600 - 120),
          RideLeg(routeId: '1', tripId: '1-0', boardStopId: 'A', alightStopId: 'C', departs: 8 * 3600, arrives: 8 * 3600 + 600, stopCount: 2),
          RideLeg(routeId: '2', tripId: '2-1', boardStopId: 'C', alightStopId: 'E', departs: 8 * 3600 + 1200, arrives: 8 * 3600 + 1680, stopCount: 2),
        ]);

    testWidgets('draws each ride cut to its stops in its colour, the walks dotted, fits it, and hides on request', (
      tester,
    ) async {
      final surface = _RecordingSurface();
      _surface = surface;
      await _pump(tester, repo: network);
      final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      container.read(planQueryProvider.notifier).setFrom(PinPlace(lat: 47.5590, lon: -52.7500, label: 'Dropped pin'));
      container.read(journeyOnMapProvider.notifier).show(journey());
      await tester.runAsync(() => _styleLoaded(surface));
      await _frames(tester, 2);

      final rides = surface.features(MapLayers.journeySource);
      expect(rides, hasLength(2));
      final first = (rides[0]['geometry'] as Map)['coordinates'] as List;
      expect((first.first as List)[1], closeTo(47.5600, 1e-6), reason: 'cut at the stop the rider gets on at');
      expect((first.last as List)[1], closeTo(47.5700, 1e-6), reason: 'cut at the stop the rider gets off at');
      expect((rides[0]['properties'] as Map)['color'], hex(RoutePalette.ofName('1').line));
      expect((rides[1]['properties'] as Map)['color'], hex(RoutePalette.ofName('2').line));
      final second = (rides[1]['geometry'] as Map)['coordinates'] as List;
      expect([for (final p in second) (p as List)[1]], [47.5700, 47.5750, 47.5800],
          reason: 'with no shape, the line runs stop to stop');
      final walks = surface.features(MapLayers.journeyWalkSource);
      expect(walks, hasLength(1));
      expect((walks.single['geometry'] as Map)['coordinates'], [
        [-52.7500, 47.5590],
        [-52.7500, 47.5600],
      ]);
      expect(surface.layers[MapLayers.journeyWalkLayer], isA<LineLayerProperties>()
          .having((p) => p.lineDasharray, 'dashes', isNotNull));
      expect(surface.fits, isNotEmpty, reason: 'the camera fits the journey');
      final (a, b, _, _) = surface.fits.last;
      expect(math.min(a.latitude, b.latitude), closeTo(47.5590, 1e-6));
      expect(math.max(a.latitude, b.latitude), closeTo(47.5800, 1e-6));

      await tester.tap(find.bySemanticsLabel('Hide the trip from the map'));
      await _frames(tester, 2);
      expect(container.read(journeyOnMapProvider), isNull);
      expect(surface.features(MapLayers.journeySource), isEmpty);
      expect(surface.features(MapLayers.journeyWalkSource), isEmpty);
      expect(find.text('Hide trip'), findsNothing);
    });

    testWidgets('the fit keeps the journey clear of the Hide trip chip', (tester) async {
      final surface = _RecordingSurface();
      _surface = surface;
      await _pump(tester, repo: network);
      final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      container.read(journeyOnMapProvider.notifier).show(journey());
      await tester.runAsync(() => _styleLoaded(surface));
      await _frames(tester, 3);
      final (_, _, padding, _) = surface.fits.last;
      final hideBottom = tester.getRect(find.widgetWithText(BBChip, 'Hide trip')).bottom;
      expect(padding.top, greaterThanOrEqualTo(hideBottom + 16), reason: 'a fitted marker is not drawn under the chip');
    });

    testWidgets('a journey shown before the style loads is drawn once it does', (tester) async {
      final surface = _RecordingSurface();
      _surface = surface;
      await _pump(tester, repo: network, overrides: [
        journeyOnMapProvider.overrideWith(() => _PresetJourney(journey())),
      ]);
      expect(find.text('Hide trip'), findsOneWidget);
      await tester.runAsync(() => _styleLoaded(surface));
      await _frames(tester, 2);
      expect(surface.features(MapLayers.journeySource), hasLength(2));
      expect(surface.fits, isNotEmpty);
    });
  });
}

/// Holds the route line's redraw until [gate] completes, so a test can end the
/// follow while an install is waiting on it.
class _RouteGateSurface extends _RecordingSurface {
  Completer<void>? gate;
  bool routePushWaiting = false;

  @override
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> data) async {
    final g = gate;
    if (id == 'bb-route' && g != null && (data['features'] as List).isNotEmpty) {
      routePushWaiting = true;
      await g.future;
    }
    return super.setGeoJsonSource(id, data);
  }
}

class _PresetFollow extends FollowNotifier {
  _PresetFollow(this.id);
  final String id;

  @override
  FollowTarget? build() => FollowTarget(id);
}

class _PresetJourney extends JourneyOnMapNotifier {
  _PresetJourney(this.journey);
  final Journey journey;

  @override
  Journey? build() => journey;
}
