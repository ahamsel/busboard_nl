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
  final Map<String, Circle> _busAnnotations = {};
  Map<String, BusTrackingState>? _pendingAnnotationTracking;
  bool _annotationUpdateInFlight = false;
  DateTime? _lastAnnotationRenderAt;
  static const _annotationFrameInterval = Duration(milliseconds: 120);
  bool _myLocationEnabled = false;
  int _lastLoggedBusCount = -1;

  // Route filter: empty = show all
  Set<int> _activeRouteFilter = {};
  bool _legendExpanded = false;

  // St. John's fallback center
  static const _defaultLat = 47.5615;
  static const _defaultLon = -52.7126;
  static const _defaultZoom = 13.0;
  static const _tileStyleUrl = 'https://tiles.openfreemap.org/styles/positron';

  // Source/layer IDs
  static const _stopsSourceId = 'stops-source';
  static const _stopsLayerId = 'stops-layer';
  static const _stopsLabelLayerId = 'stops-label-layer';
  static const _selectedStopSourceId = 'selected-stop-source';
  static const _selectedStopLayerId = 'selected-stop-layer';
  static const _routeShapeSourceId = 'route-shape-source';
  static const _routeShapeLayerId = 'route-shape-layer';

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
    _busAnnotations.clear();
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
    final engine = ref.watch(busMotionEngineProvider);
    final diagnostics = engine?.diagnostics;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Map'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _activeRouteFilter.isEmpty ? null : Colors.amber,
            ),
            onPressed: _showRouteFilter,
          ),
          if (ref.watch(settingsProvider.select((s) => s.selectedStopId)) !=
              null)
            IconButton(
              icon: const Icon(Icons.place),
              tooltip: 'Go to selected stop',
              onPressed: _centerOnSelectedStop,
            ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _goToMyLocation,
          ),
        ],
      ),
      body: gtfsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) => Stack(
          children: [
            MapLibreMap(
              initialCameraPosition: CameraPosition(
                target: _getInitialCenter(),
                zoom: _defaultZoom,
              ),
              styleString: _tileStyleUrl,
              onMapCreated: (controller) {
                _controller = controller;
                _log('Map created');
              },
              onStyleLoadedCallback: () {
                _log('Style loaded callback fired');
                _onStyleReady();
              },
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
                    color: Colors.white.withValues(alpha: 0.92),
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
                            _legendRow(Colors.red, 'Bus'),
                            const SizedBox(height: 4),
                            _legendRow(const Color(0xFF4FC3F7), 'Stop'),
                            const SizedBox(height: 4),
                            _legendRow(
                              const Color(0xFFFFD54F),
                              'Selected stop',
                            ),
                            const SizedBox(height: 4),
                            _legendRow(
                              const Color(0xFFFFD54F),
                              'Bus route',
                              isLine: true,
                            ),
                            if (kDebugMode) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: 170,
                                height: 1,
                                color: Colors.black.withValues(alpha: 0.1),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Jump p50/p90: ${_metricPair(diagnostics?.correctionP50Meters, diagnostics?.correctionP90Meters)}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                              Text(
                                'Innovation p50/p90: ${_metricPair(diagnostics?.innovationP50Meters, diagnostics?.innovationP90Meters)}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                              Text(
                                'Tune: a=${_fmtNum(diagnostics?.kalmanAccelStdMps2, 2)} m=${_fmtNum(diagnostics?.kalmanMeasurementStdM, 1)} b=${diagnostics?.blendDurationMs ?? 0}ms',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ],
                        )
                      : const Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Colors.black54,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Style + Layer Setup ────────────────────────────────────

  Future<void> _onStyleReady() async {
    final controller = _controller;
    if (controller == null) return;

    _styleLoaded = false;
    _busAnnotations.clear();
    _pendingAnnotationTracking = null;
    _annotationUpdateInFlight = false;
    _lastAnnotationRenderAt = null;

    final sw = Stopwatch()..start();

    // Register feature tap handler — on Android, tapping a GeoJSON feature
    // sends feature#onTap instead of map#onMapClick, so we must handle both.
    controller.onFeatureTapped.clear();
    controller.onFeatureTapped.add(_onFeatureTapped);

    await _addStopsLayer(controller);
    _log('Stops layer added (${sw.elapsedMilliseconds}ms)');

    await _addSelectedStopLayer(controller);
    await _addRouteShapeLayer(controller);

    _styleLoaded = true;
    _log('Style ready (${sw.elapsedMilliseconds}ms), buses via annotations');

    // Start animation ticker
    _ticker?.dispose();
    _ticker = Ticker(_onTick);
    _ticker!.start();

    // Initial bus update
    final tracking = ref.read(busTrackingStreamProvider).value ?? {};
    _log('Initial tracking: ${tracking.length} vehicles');
    _queueAnnotationUpdate(tracking);
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

  // ─── Bus Updates (annotation-based) ─────────────────────────

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

    final engine = ref.read(busMotionEngineProvider);
    if (engine == null) return;

    final interpolated = engine.interpolate(DateTime.now());

    // Apply route filter
    final filtered = _activeRouteFilter.isEmpty
        ? tracking
        : Map.fromEntries(
            tracking.entries.where(
              (e) => _activeRouteFilter.contains(e.value.routeNumber),
            ),
          );

    final nextKeys = filtered.keys.toSet();
    final existingKeys = _busAnnotations.keys.toList();

    // Remove stale annotations.
    for (final key in existingKeys) {
      if (nextKeys.contains(key)) continue;
      final circle = _busAnnotations.remove(key);
      if (circle == null) continue;
      try {
        await controller.removeCircle(circle);
      } catch (_) {}
    }

    for (final entry in filtered.entries) {
      final state = entry.value;
      final pos = interpolated[entry.key];
      final lat = pos?.$1 ?? state.smoothedLat;
      final lon = pos?.$2 ?? state.smoothedLon;
      final target = LatLng(lat, lon);

      final existing = _busAnnotations[entry.key];
      if (existing == null) {
        try {
          final circle = await controller.addCircle(
            CircleOptions(
              geometry: target,
              circleRadius: 9.0,
              circleColor: '#E53935',
              circleStrokeWidth: 2.5,
              circleStrokeColor: '#FFFFFF',
            ),
          );
          _busAnnotations[entry.key] = circle;
        } catch (_) {}
      } else {
        try {
          await controller.updateCircle(
            existing,
            CircleOptions(geometry: target),
          );
        } catch (_) {}
      }
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
    // (buses are annotations, not GeoJSON layers, so they use _handleTap)
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
    final engine = ref.read(busMotionEngineProvider);
    if (engine == null || tracking.isEmpty) return null;

    final interpolated = engine.interpolate(DateTime.now());
    BusTrackingState? closest;
    var closestDist = double.infinity;

    for (final entry in tracking.entries) {
      final pos = interpolated[entry.key];
      final lat = pos?.$1 ?? entry.value.smoothedLat;
      final lon = pos?.$2 ?? entry.value.smoothedLon;
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

  Widget _legendRow(Color color, String label, {bool isLine = false}) {
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
          style: const TextStyle(fontSize: 11, color: Colors.black87),
        ),
      ],
    );
  }

  String _metricPair(double? a, double? b) {
    if (a == null || b == null) return 'n/a';
    return '${a.toStringAsFixed(1)}m / ${b.toStringAsFixed(1)}m';
  }

  String _fmtNum(double? value, int decimals) {
    if (value == null) return 'n/a';
    return value.toStringAsFixed(decimals);
  }

  void _showRouteFilter() {
    final tracking = ref.read(busTrackingStreamProvider).value ?? {};
    final allRoutes = tracking.values.map((s) => s.routeNumber).toSet().toList()
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
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Filter Routes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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
                      backgroundColor: Colors.grey.shade200,
                      selectedColor: Colors.red.shade100,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: active ? Colors.red.shade700 : Colors.grey,
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
}
