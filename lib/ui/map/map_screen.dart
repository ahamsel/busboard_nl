import 'dart:async';
import 'dart:math' show Point;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../data/gtfs/gtfs_models.dart';
import '../../domain/location/nearest_stop_service.dart';
import '../../domain/map/bus_tracking_state.dart';
import '../../domain/map/delayed_track_renderer.dart';
import '../../state/providers.dart';
import 'stop_bottom_sheet.dart';
import 'bus_bottom_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  MapLibreMapController? _controller;
  Ticker? _ticker;
  bool _styleLoaded = false;
  Map<String, BusTrackingState>? _pendingAnnotationTracking;
  bool _annotationUpdateInFlight = false;
  DateTime? _lastAnnotationRenderAt;
  static const _annotationFrameInterval = Duration(milliseconds: 120);
  bool _myLocationEnabled = false;
  int _lastLoggedBusCount = -1;
  Map<String, RenderedBus> _lastDrawn = const {};

  // Route filter: empty = show all
  Set<int> _activeRouteFilter = {};
  bool _legendExpanded = false;

  // St. John's fallback center
  static const _defaultLat = 47.5615;
  static const _defaultLon = -52.7126;
  static const _defaultZoom = 13.0;
  static const _lightStyleUrl = 'https://tiles.openfreemap.org/styles/positron';
  static const _darkStyleUrl = 'https://tiles.openfreemap.org/styles/dark';

  // Source/layer IDs
  static const _stopsSourceId = 'stops-source';
  static const _stopsLayerId = 'stops-layer';
  static const _stopsLabelLayerId = 'stops-label-layer';
  static const _selectedStopSourceId = 'selected-stop-source';
  static const _selectedStopLayerId = 'selected-stop-layer';
  static const _routeShapeSourceId = 'route-shape-source';
  static const _routeShapeLayerId = 'route-shape-layer';
  static const _busesSourceId = 'buses-source';
  static const _busesLayerId = 'buses-layer';
  static const _busLabelsLayerId = 'bus-labels-layer';

  void _log(String msg) {
    if (kDebugMode) debugPrint('[Map] $msg');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enableMyLocationPuck());
  }

  @override
  void dispose() {
    _ticker?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_ticker != null && !_ticker!.isActive) {
        _ticker!.start();
      }
    } else if (state == AppLifecycleState.paused) {
      _ticker?.stop();
    }
  }

  LatLng _getInitialCenter() {
    final settings = ref.read(settingsProvider);
    if (settings.selectedStopId != null) {
      final stop = ref.read(stopInfoProvider(settings.selectedStopId!));
      if (stop != null) {
        return LatLng(stop.stopLat, stop.stopLon);
      }
    }
    return const LatLng(_defaultLat, _defaultLon);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(busTrackingStreamProvider, (prev, next) {
      if (_styleLoaded) {
        _queueAnnotationUpdate(next.value ?? {});
      }
    });
    ref.listen<String?>(settingsProvider.select((s) => s.selectedStopId), (
      prev,
      next,
    ) {
      if (_styleLoaded && prev != next) {
        _updateSelectedStop();
        if (next != null) {
          _centerOnSelectedStop();
        }
      }
    });

    final gtfsAsync = ref.watch(gtfsRepositoryProvider);
    ref.watch(busTrackingStreamProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Live Map')),
      body: gtfsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) => Stack(
          children: [
            MapLibreMap(
              styleString: _getStyleUrl(theme.brightness),
              onStyleLoadedCallback: _onStyleLoaded,
              initialCameraPosition: CameraPosition(
                target: _getInitialCenter(),
                zoom: _defaultZoom,
              ),
              onMapCreated: _onMapCreated,
              onMapClick: _onMapClick,
              trackCameraPosition: true,
              myLocationEnabled: _myLocationEnabled,
              myLocationRenderMode: MyLocationRenderMode.normal,
              logoEnabled: false,
            ),
            // Legend
            Positioned(
              bottom: 16,
              left: 12,
              child: GestureDetector(
                onTap: () => setState(() => _legendExpanded = !_legendExpanded),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.cardColor.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: _legendExpanded
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _legendRow(Colors.red, 'Bus', theme),
                            const SizedBox(height: 4),
                            _legendRow(const Color(0xFF4FC3F7), 'Stop', theme),
                            const SizedBox(height: 4),
                            _legendRow(
                              const Color(0xFFFFD54F),
                              'Selected stop',
                              theme,
                            ),
                            const SizedBox(height: 4),
                            _legendRow(
                              const Color(0xFFFFD54F),
                              'Bus route',
                              theme,
                              isLine: true,
                            ),
                          ],
                        )
                      : Icon(
                          Icons.info_outline,
                          size: 20,
                          color: theme.iconTheme.color?.withValues(alpha: 0.7),
                        ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MapFloatButton(
                      icon: Icons.layers_outlined,
                      onPressed: _showMapThemeSheet,
                      tooltip: 'Map Layers',
                    ),
                    const SizedBox(height: 12),
                    _MapFloatButton(
                      icon: _activeRouteFilter.isEmpty
                          ? Icons.filter_alt_outlined
                          : Icons.filter_alt,
                      onPressed: _showRouteFilter,
                      tooltip: 'Filter Routes',
                      active: _activeRouteFilter.isNotEmpty,
                    ),
                    if (ref.watch(
                          settingsProvider.select((s) => s.selectedStopId),
                        ) !=
                        null) ...[
                      const SizedBox(height: 12),
                      _MapFloatButton(
                        icon: Icons.place,
                        onPressed: _centerOnSelectedStop,
                        tooltip: 'Selected Stop',
                      ),
                    ],
                    const SizedBox(height: 12),
                    _MapFloatButton(
                      icon: Icons.my_location,
                      onPressed: _goToMyLocation,
                      tooltip: 'My Location',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Style + Layer Setup ────────────────────────────────────

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    _log('Style loaded');

    // Re-add sources and layers because style reload clears them
    await _initializeMapResources();

    // Start animation ticker if not already running
    if (_ticker == null) {
      _ticker = Ticker(_onTick);
      _ticker!.start();
    } else if (!_ticker!.isActive) {
      _ticker!.start();
    }

    // Trigger immediate bus update
    final tracking = ref.read(busTrackingStreamProvider).value ?? {};
    _queueAnnotationUpdate(tracking);
  }

  Future<void> _initializeMapResources() async {
    final controller = _controller;
    if (controller == null) return;

    try {
      // Register feature tap handler — on Android, tapping a GeoJSON feature
      // sends feature#onTap instead of map#onMapClick, so we must handle both.
      controller.onFeatureTapped.clear();
      controller.onFeatureTapped.add(_onFeatureTapped);

      await _addStopsLayer(controller);
      await _addSelectedStopLayer(controller);
      await _addRouteShapeLayer(controller);
      await _addBusesLayer(controller);
    } catch (e) {
      _log('Error initializing map resources: $e');
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    _log('Map created');
    // _onStyleLoaded will be called by the map widget itself
  }

  Future<void> _addStopsLayer(MapLibreMapController controller) async {
    final repo = ref.read(gtfsRepositoryProvider).asData?.value;
    if (repo == null) {
      _log('addStopsLayer: repo is null');
      return;
    }

    final features = repo.stopsById.values.map((stop) {
      return {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [stop.stopLon, stop.stopLat],
        },
        'properties': {'stopId': stop.stopId, 'stopName': stop.stopName},
      };
    }).toList();

    _log('Adding ${features.length} stops to source');

    final geojson = {'type': 'FeatureCollection', 'features': features};
    await controller.addGeoJsonSource(_stopsSourceId, geojson);

    // Stop circles — small but visible
    await controller.addCircleLayer(
      _stopsSourceId,
      _stopsLayerId,
      const CircleLayerProperties(
        circleRadius: [
          Expressions.interpolate,
          ['linear'],
          [Expressions.zoom],
          11,
          2.0,
          14,
          5.0,
          16,
          7.0,
        ],
        circleColor: '#4FC3F7',
        circleOpacity: [
          Expressions.interpolate,
          ['linear'],
          [Expressions.zoom],
          11,
          0.3,
          13,
          0.6,
          15,
          0.8,
        ],
        circleStrokeWidth: 1.0,
        circleStrokeColor: '#FFFFFF',
        circleStrokeOpacity: 0.6,
      ),
    );

    // Stop labels with name + ID
    await controller.addSymbolLayer(
      _stopsSourceId,
      _stopsLabelLayerId,
      const SymbolLayerProperties(
        textField: [
          Expressions.concat,
          [Expressions.get, 'stopName'],
          '\n#',
          [Expressions.get, 'stopId'],
        ],
        textSize: 11.0,
        textOffset: [
          Expressions.literal,
          [0.0, 1.5],
        ],
        textAnchor: 'top',
        textMaxWidth: 8.0,
        textColor: '#333333',
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.5,
      ),
      minzoom: 14,
    );
  }

  Future<void> _addSelectedStopLayer(MapLibreMapController controller) async {
    await controller.addGeoJsonSource(
      _selectedStopSourceId,
      _emptyFeatureCollection(),
    );

    await controller.addCircleLayer(
      _selectedStopSourceId,
      _selectedStopLayerId,
      const CircleLayerProperties(
        circleRadius: 12.0,
        circleColor: '#FFD54F',
        circleOpacity: 0.3,
        circleStrokeWidth: 2.0,
        circleStrokeColor: '#FFD54F',
      ),
    );

    _updateSelectedStop();
  }

  void _updateSelectedStop() {
    final controller = _controller;
    if (controller == null) return;

    final settings = ref.read(settingsProvider);
    final stopId = settings.selectedStopId;
    if (stopId == null) {
      controller.setGeoJsonSource(
        _selectedStopSourceId,
        _emptyFeatureCollection(),
      );
      return;
    }

    final stop = ref.read(stopInfoProvider(stopId));
    if (stop == null) {
      controller.setGeoJsonSource(
        _selectedStopSourceId,
        _emptyFeatureCollection(),
      );
      return;
    }

    _log('Selected stop updated: ${stop.stopName} (#$stopId)');
    controller.setGeoJsonSource(_selectedStopSourceId, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [stop.stopLon, stop.stopLat],
          },
          'properties': {'stopId': stop.stopId},
        },
      ],
    });
  }

  Future<void> _addRouteShapeLayer(MapLibreMapController controller) async {
    await controller.addGeoJsonSource(
      _routeShapeSourceId,
      _emptyFeatureCollection(),
    );

    await controller.addLineLayer(
      _routeShapeSourceId,
      _routeShapeLayerId,
      const LineLayerProperties(
        lineColor: '#FFD54F',
        lineWidth: 3.0,
        lineOpacity: 0.6,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
  }

  Future<void> _addBusesLayer(MapLibreMapController controller) async {
    await controller.addGeoJsonSource(
      _busesSourceId,
      _emptyFeatureCollection(),
    );

    await controller.addCircleLayer(
      _busesSourceId,
      _busesLayerId,
      const CircleLayerProperties(
        circleRadius: 9.0,
        circleColor: '#E53935',
        circleStrokeWidth: 2.5,
        circleStrokeColor: '#FFFFFF',
      ),
    );

    // Use the font stack advertised by the OpenFreeMap style. Labels live in
    // their own layer so each route number can be rendered above its red dot
    // without depending on the native annotation manager.
    await controller.addSymbolLayer(
      _busesSourceId,
      _busLabelsLayerId,
      const SymbolLayerProperties(
        textField: [Expressions.get, 'label'],
        textFont: ['Noto Sans Bold'],
        textSize: 10.5,
        textOffset: [
          Expressions.literal,
          [0.0, 1.35],
        ],
        textAnchor: 'top',
        textColor: '#8B1111',
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.5,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
    );
  }

  // ─── Bus Updates ─────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (!_styleLoaded) return;
    final now = DateTime.now();
    final last = _lastAnnotationRenderAt;
    if (last == null || now.difference(last) >= _annotationFrameInterval) {
      _lastAnnotationRenderAt = now;
      final tracking = ref.read(busTrackingStreamProvider).value ?? {};
      _queueAnnotationUpdate(tracking);
    }
  }

  void _queueAnnotationUpdate(Map<String, BusTrackingState> tracking) {
    _pendingAnnotationTracking = tracking;
    if (_annotationUpdateInFlight) return;
    _annotationUpdateInFlight = true;
    unawaited(_flushAnnotationUpdates());
  }

  Future<void> _flushAnnotationUpdates() async {
    try {
      while (_pendingAnnotationTracking != null) {
        final snapshot = _pendingAnnotationTracking!;
        _pendingAnnotationTracking = null;
        await _renderBusAnnotations(snapshot);
      }
    } finally {
      _annotationUpdateInFlight = false;
    }
  }

  Future<void> _renderBusAnnotations(
    Map<String, BusTrackingState> tracking,
  ) async {
    final controller = _controller;
    if (controller == null) return;

    final renderer = ref.read(busTrackRendererProvider);
    final store = ref.read(busTrackStoreProvider);
    if (renderer == null || store == null) return;

    // The renderer is stateful per vehicle (never-backward mark, slewed
    // delay, continuity limiter), so it gets every track, once per frame, and
    // the output is filtered here. The drawn positions are kept for tap
    // hit-testing, which must not advance the renderer.
    final drawn = renderer.renderAll(store.tracks.values, DateTime.now());
    _lastDrawn = drawn;

    // The store keeps a bus that has gone unseen: it is stale after 90 s
    // without a new fix and dropped after 5 min, and the renderer drops its
    // state with the track. A stale bus is not a live map dot, which keeps a
    // replaced bus and its stale predecessor from being shown as one route
    // "jumping" between two physical vehicles.
    final filtered = Map.fromEntries(
      tracking.entries.where(
        (entry) =>
            entry.value.status != BusStatus.stale &&
            (_activeRouteFilter.isEmpty ||
                _activeRouteFilter.contains(entry.value.routeNumber)),
      ),
    );

    final features = <Map<String, dynamic>>[];
    for (final entry in filtered.entries) {
      final state = entry.value;
      final pos = drawn[entry.key];
      final lat = pos?.lat ?? state.smoothedLat;
      final lon = pos?.lon ?? state.smoothedLon;

      features.add({
        'type': 'Feature',
        'id': entry.key,
        'geometry': {
          'type': 'Point',
          'coordinates': [lon, lat],
        },
        'properties': {
          'trackingKey': entry.key,
          'route': state.routeNumber,
          'label': '${state.routeNumber}',
        },
      });
    }

    try {
      await controller.setGeoJsonSource(_busesSourceId, {
        'type': 'FeatureCollection',
        'features': features,
      });
    } catch (error) {
      _log('Could not update bus map layer: $error');
    }

    if (filtered.length != _lastLoggedBusCount) {
      _lastLoggedBusCount = filtered.length;
      _log('Rendering ${filtered.length} bus annotations');
    }
  }

  // ─── Tap Detection (distance-based, reliable on touch) ─────

  /// Tap radius in meters, scales with zoom so it feels right at any level.
  double _tapRadiusMeters() {
    final zoom = _controller?.cameraPosition?.zoom ?? _defaultZoom;
    // At zoom 13 → ~200m, zoom 15 → ~50m, zoom 17 → ~12m
    return 200.0 / (1 << ((zoom - 13).clamp(0, 5).toInt()));
  }

  /// Called by native MapLibre when a GeoJSON feature is tapped directly.
  /// On Android this fires INSTEAD of onMapClick for feature taps.
  void _onFeatureTapped(
    Point<double> point,
    LatLng coordinates,
    String id,
    String layerId,
    Annotation? annotation,
  ) {
    _log('FEATURE TAP: layer=$layerId id=$id');

    // Use layerId to know exactly what was tapped — no guessing
    if (layerId == _stopsLayerId ||
        layerId == _stopsLabelLayerId ||
        layerId == _selectedStopLayerId) {
      // Tapped a stop feature — find the nearest stop
      final radius = _tapRadiusMeters();
      final stop = _findNearestStop(coordinates, radius);
      if (stop != null) {
        _log('  HIT stop: ${stop.stopName} (#${stop.stopId})');
        _showStopSheet(stop);
        return;
      }
    }

    // For any other layer or miss, fall back to distance-based search
    // Bus and stop layers are checked independently because they carry
    // different feature metadata.
    _handleTap(coordinates);
  }

  Future<void> _onMapClick(Point<double> point, LatLng coordinates) async {
    _log('MAP CLICK (empty area tap)');
    _handleTap(coordinates);
  }

  /// Generic tap handler for empty-area taps — checks buses first, then stops.
  void _handleTap(LatLng coordinates) {
    if (_controller == null) {
      _log('Tap ignored: controller is null');
      return;
    }

    final zoom = _controller?.cameraPosition?.zoom ?? _defaultZoom;
    final radius = _tapRadiusMeters();
    _log(
      'TAP at (${coordinates.latitude.toStringAsFixed(5)}, '
      '${coordinates.longitude.toStringAsFixed(5)}) '
      'zoom=${zoom.toStringAsFixed(1)} radius=${radius.toStringAsFixed(0)}m',
    );

    // Check buses first (they render on top)
    final tappedBus = _findNearestBus(coordinates, radius);
    if (tappedBus != null) {
      _log(
        '  HIT bus: route ${tappedBus.routeNumber} (${tappedBus.vehicleId})',
      );
      _showBusSheet(tappedBus);
      return;
    }

    // Clear any visible route shape when tapping non-bus
    _clearRouteShape();

    // Then check stops
    final tappedStop = _findNearestStop(coordinates, radius);
    if (tappedStop != null) {
      _log('  HIT stop: ${tappedStop.stopName} (#${tappedStop.stopId})');
      _showStopSheet(tappedStop);
      return;
    }

    _log('  MISS: nothing within ${radius.toStringAsFixed(0)}m');
    _showDebugSnack('No stop/bus within ${radius.toStringAsFixed(0)}m');
  }

  void _showDebugSnack(String msg) {
    if (!kDebugMode || !mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  BusTrackingState? _findNearestBus(LatLng tap, double radiusMeters) {
    final tracking = ref.read(busTrackingStreamProvider).value ?? {};
    if (tracking.isEmpty) return null;

    // Hit-test against what was last drawn; calling the renderer here would
    // advance its per-vehicle state at a different time than the frame loop.
    final drawn = _lastDrawn;
    BusTrackingState? closest;
    var closestDist = double.infinity;

    for (final entry in tracking.entries) {
      if (entry.value.status == BusStatus.stale) continue;
      final pos = drawn[entry.key];
      final lat = pos?.lat ?? entry.value.smoothedLat;
      final lon = pos?.lon ?? entry.value.smoothedLon;
      final dist = NearestStopService.haversineDistance(
        tap.latitude,
        tap.longitude,
        lat,
        lon,
      );
      if (dist < radiusMeters && dist < closestDist) {
        closestDist = dist;
        closest = entry.value;
      }
    }
    return closest;
  }

  StopInfo? _findNearestStop(LatLng tap, double radiusMeters) {
    final repo = ref.read(gtfsRepositoryProvider).asData?.value;
    if (repo == null) return null;

    StopInfo? closest;
    var closestDist = double.infinity;

    for (final stop in repo.stopsById.values) {
      final dist = NearestStopService.haversineDistance(
        tap.latitude,
        tap.longitude,
        stop.stopLat,
        stop.stopLon,
      );
      if (dist < radiusMeters && dist < closestDist) {
        closestDist = dist;
        closest = stop;
      }
    }
    return closest;
  }

  // ─── Navigation ─────────────────────────────────────────────

  void _centerOnSelectedStop() {
    final settings = ref.read(settingsProvider);
    if (settings.selectedStopId == null) return;
    final stop = ref.read(stopInfoProvider(settings.selectedStopId!));
    if (stop == null || _controller == null) return;

    _controller!.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(stop.stopLat, stop.stopLon), 15),
    );
  }

  Future<void> _enableMyLocationPuck() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final granted =
        permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
    if (!granted || !mounted) return;

    setState(() {
      _myLocationEnabled = true;
    });
  }

  Future<void> _goToMyLocation() async {
    if (!_myLocationEnabled) {
      await _enableMyLocationPuck();
      if (!_myLocationEnabled) return;
    }

    final controller = _controller;
    if (controller == null) return;

    final myLocation = await controller.requestMyLocationLatLng();
    if (myLocation != null) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(myLocation, 15),
      );
    }
  }

  // ─── Legend & Filter ──────────────────────────────────────────

  Widget _legendRow(
    Color color,
    String label,
    ThemeData theme, {
    bool isLine = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLine)
          Container(width: 14, height: 3, color: color)
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface),
        ),
      ],
    );
  }

  void _showRouteFilter() {
    final tracking = ref.read(busTrackingStreamProvider).value ?? {};
    final allRoutes =
        tracking.values
            .where((state) => state.status != BusStatus.stale)
            .map((state) => state.routeNumber)
            .toSet()
            .toList()
          ..sort();

    if (allRoutes.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Filter Routes',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() => _activeRouteFilter = {});
                        setSheetState(() {});
                      },
                      child: const Text('Show All'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: allRoutes.map((route) {
                    final active =
                        _activeRouteFilter.isEmpty ||
                        _activeRouteFilter.contains(route);
                    return FilterChip(
                      label: Text('$route'),
                      selected: active && _activeRouteFilter.isNotEmpty,
                      onSelected: (_) {
                        setState(() {
                          if (_activeRouteFilter.isEmpty) {
                            // First tap: show only this route
                            _activeRouteFilter = {route};
                          } else if (_activeRouteFilter.contains(route)) {
                            _activeRouteFilter = Set.from(_activeRouteFilter)
                              ..remove(route);
                            if (_activeRouteFilter.isEmpty) {
                              // Removed last filter — show all
                            }
                          } else {
                            _activeRouteFilter = Set.from(_activeRouteFilter)
                              ..add(route);
                          }
                        });
                        setSheetState(() {});
                      },
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      selectedColor: Theme.of(context).colorScheme.error,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: (active && _activeRouteFilter.isNotEmpty)
                            ? Theme.of(context).colorScheme.onError
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Bottom Sheets ──────────────────────────────────────────

  void _showStopSheet(StopInfo stop) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StopBottomSheet(stop: stop),
    );
  }

  void _showBusSheet(BusTrackingState bus) {
    if (bus.shapeId != null) {
      _drawRouteShape(bus.shapeId!);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => BusBottomSheet(bus: bus),
    );
    // Route shape stays visible after sheet dismisses —
    // cleared when tapping another bus, a stop, or empty space.
  }

  void _drawRouteShape(String shapeId) {
    final repo = ref.read(gtfsRepositoryProvider).asData?.value;
    if (repo == null || _controller == null) return;

    final points = repo.shapesById[shapeId];
    if (points == null || points.isEmpty) return;

    final coordinates = points.map((p) => [p.lon, p.lat]).toList();

    _controller!.setGeoJsonSource(_routeShapeSourceId, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {'type': 'LineString', 'coordinates': coordinates},
          'properties': <String, dynamic>{},
        },
      ],
    });
  }

  void _clearRouteShape() {
    _controller?.setGeoJsonSource(
      _routeShapeSourceId,
      _emptyFeatureCollection(),
    );
  }

  Map<String, dynamic> _emptyFeatureCollection() {
    return {'type': 'FeatureCollection', 'features': <dynamic>[]};
  }

  String _getStyleUrl(Brightness appBrightness) {
    final mapMode = ref.watch(settingsProvider.select((s) => s.mapThemeMode));
    final effectiveBrightness = mapMode == null
        ? appBrightness
        : (mapMode == ThemeMode.dark ? Brightness.dark : Brightness.light);

    return effectiveBrightness == Brightness.dark
        ? _darkStyleUrl
        : _lightStyleUrl;
  }

  void _showMapThemeSheet() {
    final currentMode = ref.read(settingsProvider).mapThemeMode;
    // null = auto, ThemeMode.light, ThemeMode.dark

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text('Map Theme', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.brightness_auto),
              title: const Text('Match App Theme (Auto)'),
              trailing: currentMode == null ? const Icon(Icons.check) : null,
              onTap: () {
                ref.read(settingsProvider.notifier).setMapThemeMode(null);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.light_mode),
              title: const Text('Always Light'),
              trailing: currentMode == ThemeMode.light
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setMapThemeMode(ThemeMode.light);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode),
              title: const Text('Always Dark'),
              trailing: currentMode == ThemeMode.dark
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setMapThemeMode(ThemeMode.dark);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _MapFloatButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool active;

  const _MapFloatButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      width: 44,
      height: 44,
      child: FloatingActionButton(
        heroTag: null, // No animation hero needed for these
        onPressed: onPressed,
        tooltip: tooltip,
        elevation: 2,
        backgroundColor: active ? colorScheme.primary : theme.cardColor,
        foregroundColor: active
            ? colorScheme.onPrimary
            : theme.iconTheme.color?.withValues(alpha: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 22),
      ),
    );
  }
}
