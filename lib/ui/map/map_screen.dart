import 'dart:async';
import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../data/gtfs/gtfs_models.dart';
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

  // St. John's fallback center
  static const _defaultLat = 47.5615;
  static const _defaultLon = -52.7126;
  static const _defaultZoom = 13.0;
  static const _tileStyleUrl = 'https://tiles.openfreemap.org/styles/positron';

  // Source/layer IDs
  static const _stopsSourceId = 'stops-source';
  static const _stopsLayerId = 'stops-layer';
  static const _stopsLabelLayerId = 'stops-label-layer';
  static const _busesSourceId = 'buses-source';
  static const _busesLayerId = 'buses-layer';
  static const _busesLabelLayerId = 'buses-label-layer';
  static const _selectedStopSourceId = 'selected-stop-source';
  static const _selectedStopLayerId = 'selected-stop-layer';
  static const _routeShapeSourceId = 'route-shape-source';
  static const _routeShapeLayerId = 'route-shape-layer';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      _ticker?.start();
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
        _updateBuses(next.value ?? {});
      }
    });

    final gtfsAsync = ref.watch(gtfsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _centerOnSelectedStop,
          ),
        ],
      ),
      body: gtfsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) => MapLibreMap(
          initialCameraPosition: CameraPosition(
            target: _getInitialCenter(),
            zoom: _defaultZoom,
          ),
          styleString: _tileStyleUrl,
          onMapCreated: (controller) {
            _controller = controller;
          },
          onStyleLoadedCallback: () {
            _onStyleReady();
          },
          onMapClick: _onMapClick,
          trackCameraPosition: true,
          logoEnabled: false,
        ),
      ),
    );
  }

  Future<void> _onStyleReady() async {
    final controller = _controller;
    if (controller == null) return;

    _styleLoaded = true;

    await _addStopsLayer(controller);
    await _addSelectedStopLayer(controller);
    await _addRouteShapeLayer(controller);
    await _addBusesLayer(controller);

    // Start animation ticker
    _ticker = Ticker(_onTick);
    _ticker!.start();

    // Initial bus update
    final tracking = ref.read(busTrackingStreamProvider).value ?? {};
    _updateBuses(tracking);
  }

  Future<void> _addStopsLayer(MapLibreMapController controller) async {
    final repo = ref.read(gtfsRepositoryProvider).asData?.value;
    if (repo == null) return;

    final features = repo.stopsById.values.map((stop) {
      return {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [stop.stopLon, stop.stopLat],
        },
        'properties': {
          'stopId': stop.stopId,
          'stopName': stop.stopName,
        },
      };
    }).toList();

    final geojson = {
      'type': 'FeatureCollection',
      'features': features,
    };

    await controller.addGeoJsonSource(_stopsSourceId, geojson);

    await controller.addCircleLayer(
      _stopsSourceId,
      _stopsLayerId,
      const CircleLayerProperties(
        circleRadius: 5.0,
        circleColor: '#4FC3F7',
        circleOpacity: 0.7,
        circleStrokeWidth: 1.0,
        circleStrokeColor: '#FFFFFF',
        circleStrokeOpacity: 0.5,
      ),
      minzoom: 14,
    );

    await controller.addSymbolLayer(
      _stopsSourceId,
      _stopsLabelLayerId,
      const SymbolLayerProperties(
        textField: [Expressions.get, 'stopName'],
        textSize: 11.0,
        textOffset: [
          Expressions.literal,
          [0.0, 1.5],
        ],
        textAnchor: 'top',
        textMaxWidth: 8.0,
        textColor: '#CCCCCC',
        textHaloColor: '#000000',
        textHaloWidth: 1.0,
      ),
      minzoom: 15,
    );
  }

  Future<void> _addSelectedStopLayer(MapLibreMapController controller) async {
    await controller.addGeoJsonSource(_selectedStopSourceId, _emptyFeatureCollection());

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
    final settings = ref.read(settingsProvider);
    if (settings.selectedStopId == null || _controller == null) return;

    final stop = ref.read(stopInfoProvider(settings.selectedStopId!));
    if (stop == null) return;

    _controller!.setGeoJsonSource(_selectedStopSourceId, {
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
    await controller.addGeoJsonSource(_routeShapeSourceId, _emptyFeatureCollection());

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
    await controller.addGeoJsonSource(_busesSourceId, _emptyFeatureCollection());

    await controller.addCircleLayer(
      _busesSourceId,
      _busesLayerId,
      const CircleLayerProperties(
        circleRadius: 10.0,
        circleColor: [
          Expressions.match,
          [Expressions.get, 'status'],
          'active', '#4FC3F7',
          'stopped', '#FFB74D',
          'stale', '#9E9E9E',
          'offRoute', '#EF5350',
          'backtracking', '#FFB74D',
          '#4FC3F7',
        ],
        circleStrokeWidth: 2.0,
        circleStrokeColor: '#FFFFFF',
      ),
    );

    await controller.addSymbolLayer(
      _busesSourceId,
      _busesLabelLayerId,
      const SymbolLayerProperties(
        textField: [Expressions.get, 'routeNumber'],
        textSize: 10.0,
        textAllowOverlap: true,
        textIgnorePlacement: true,
        textColor: '#000000',
      ),
      minzoom: 11,
    );
  }

  void _updateBuses(Map<String, BusTrackingState> tracking) {
    if (_controller == null) return;

    final engine = ref.read(busMotionEngineProvider);
    if (engine == null) return;

    final interpolated = engine.interpolate(DateTime.now());

    final features = tracking.entries.map((entry) {
      final state = entry.value;
      final pos = interpolated[entry.key];
      final lat = pos?.$1 ?? state.smoothedLat;
      final lon = pos?.$2 ?? state.smoothedLon;

      return {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [lon, lat],
        },
        'properties': {
          'routeRun': state.routeRun,
          'routeNumber': '${state.routeNumber}',
          'vehicleId': state.vehicleId,
          'headsign': state.headsign,
          'status': state.status.name,
        },
      };
    }).toList();

    _controller!.setGeoJsonSource(_busesSourceId, {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  void _onTick(Duration elapsed) {
    if (!_styleLoaded) return;
    final tracking = ref.read(busTrackingStreamProvider).value ?? {};
    _updateBuses(tracking);
  }

  Future<void> _onMapClick(Point<double> point, LatLng coordinates) async {
    if (_controller == null) return;

    // Check buses first (they're on top visually)
    final busFeatures = await _controller!.queryRenderedFeatures(
      point,
      [_busesLayerId],
      null,
    );
    if (busFeatures.isNotEmpty) {
      final feature = busFeatures.first;
      final props = _extractProperties(feature);
      final routeRun = props?['routeRun'] as String?;
      if (routeRun != null) {
        final tracking = ref.read(busTrackingStreamProvider).value ?? {};
        final bus = tracking[routeRun];
        if (bus != null) {
          _showBusSheet(bus);
          return;
        }
      }
    }

    // Then check stops
    final stopFeatures = await _controller!.queryRenderedFeatures(
      point,
      [_stopsLayerId],
      null,
    );
    if (stopFeatures.isNotEmpty) {
      final feature = stopFeatures.first;
      final props = _extractProperties(feature);
      final stopId = props?['stopId'] as String?;
      if (stopId != null) {
        final stop = ref.read(stopInfoProvider(stopId));
        if (stop != null) {
          _showStopSheet(stop);
          return;
        }
      }
    }
  }

  Map<String, dynamic>? _extractProperties(dynamic feature) {
    if (feature is Map) {
      // GeoJSON feature structure: { "type": "Feature", "properties": {...}, ... }
      final props = feature['properties'];
      if (props is Map) {
        return Map<String, dynamic>.from(props);
      }
      // Some platforms return properties at the top level
      return Map<String, dynamic>.from(feature);
    }
    return null;
  }

  void _centerOnSelectedStop() {
    final settings = ref.read(settingsProvider);
    if (settings.selectedStopId == null) return;
    final stop = ref.read(stopInfoProvider(settings.selectedStopId!));
    if (stop == null || _controller == null) return;

    _controller!.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(stop.stopLat, stop.stopLon), 15),
    );
  }

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
    ).then((_) {
      _clearRouteShape();
    });
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
          'geometry': {
            'type': 'LineString',
            'coordinates': coordinates,
          },
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
    return {
      'type': 'FeatureCollection',
      'features': <dynamic>[],
    };
  }
}
