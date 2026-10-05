import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../domain/map/bus_tracking_state.dart';
import '../../domain/map/delayed_track_renderer.dart';
import '../../domain/map/heading_smoother.dart';
import '../kit/kit.dart';
import 'map_surface.dart';
import 'marker_images.dart';

/// One bus as the map draws it this frame.
class BusMarker {
  const BusMarker({
    required this.vehicleId,
    required this.lat,
    required this.lon,
    required this.heading,
    required this.label,
    required this.hue,
    required this.stale,
  });

  final String vehicleId;
  final double lat;
  final double lon;
  final double heading;
  final String label;
  final RouteHue hue;
  final bool stale;
}

/// The number on a bus badge: the route number, else the route from
/// "Rt 10A"-style routeRun when that is digits plus an optional letter, else "?".
String busLabel(BusTrackingState s) {
  if (s.routeNumber > 0) return '${s.routeNumber}';
  final run = s.routeRun.replaceFirst(RegExp(r'^rt\s*', caseSensitive: false), '').split('-').first.trim();
  return RegExp(r'^[0-9]+[A-Za-z]?$').hasMatch(run) ? run : '?';
}

/// Markers for this frame. The renderer's drawn position wins; a bus it has
/// not drawn yet uses its latest fix. Stale buses stay, flagged for a grey
/// badge (spec §3.2). An empty [routeFilter] shows every route.
List<BusMarker> busMarkers({
  required Map<String, BusTrackingState> tracking,
  required Map<String, RenderedBus> drawn,
  required Set<int> routeFilter,
  required HeadingSmoother headings,
  required DateTime now,
}) {
  final out = <BusMarker>[];
  for (final MapEntry(key: id, value: s) in tracking.entries) {
    if (routeFilter.isNotEmpty && !routeFilter.contains(s.routeNumber)) continue;
    final pos = drawn[id];
    final label = busLabel(s);
    out.add(BusMarker(
      vehicleId: id,
      lat: pos?.lat ?? s.lat,
      lon: pos?.lon ?? s.lon,
      heading: headings.smooth(id, pos?.heading ?? s.heading, now),
      label: label,
      hue: RoutePalette.ofName(label),
      stale: s.status == BusStatus.stale,
    ));
  }
  headings.prune({for (final m in out) m.vehicleId});
  return out;
}

Map<String, dynamic> _collection(List<Map<String, dynamic>> features) => {'type': 'FeatureCollection', 'features': features};

Map<String, dynamic> _point(double lat, double lon, Map<String, dynamic> properties, {String? id}) => {
      'type': 'Feature',
      'id': ?id,
      'geometry': {
        'type': 'Point',
        'coordinates': [lon, lat],
      },
      'properties': properties,
    };

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Sources, layers and marker images of the Harbour map (spec §3.2), bottom to
/// top: stops, your stop, bus notches, bus badges. [install] runs after every
/// style load (a style switch clears everything natively); updates are cheap
/// GeoJSON swaps that register any new marker image first.
class MapLayers {
  MapLayers(this.surface, {required this.brightness, required this.pixelRatio});

  final MapSurface surface;
  final Brightness brightness;
  final double pixelRatio;

  static const stopsSource = 'bb-stops';
  static const stopsLayer = 'bb-stops-layer';
  static const myStopSource = 'bb-my-stop';
  static const myStopLayer = 'bb-my-stop-layer';
  static const busesSource = 'bb-buses';
  static const notchLayer = 'bb-bus-notch';
  static const badgeLayer = 'bb-bus-badge';
  static const double stopsMinZoom = 14.5;

  final _images = <String>{};

  Future<void> install({required Iterable<StopInfo> stops}) async {
    _images.clear();
    await surface.addImage(MarkerImages.myStopId, await MarkerImages.myStop(brightness: brightness, pixelRatio: pixelRatio));
    _images.add(MarkerImages.myStopId);

    await surface.addGeoJsonSource(stopsSource, _collection([
      for (final s in stops) _point(s.stopLat, s.stopLon, {'stopId': s.stopId}),
    ]));
    await surface.addCircleLayer(
      stopsSource,
      stopsLayer,
      CircleLayerProperties(
        circleRadius: 3.5,
        circleColor: '#FFFFFF',
        circleStrokeWidth: 1.5,
        circleStrokeColor: _hex(RoutePalette.ink),
      ),
      minzoom: stopsMinZoom,
    );

    await surface.addGeoJsonSource(myStopSource, _collection(const []));
    await surface.addSymbolLayer(
      myStopSource,
      myStopLayer,
      const SymbolLayerProperties(iconImage: MarkerImages.myStopId, iconAllowOverlap: true, iconIgnorePlacement: true),
    );

    await surface.addGeoJsonSource(busesSource, _collection(const []));
    await surface.addSymbolLayer(
      busesSource,
      notchLayer,
      const SymbolLayerProperties(
        iconImage: [Expressions.get, 'notch'],
        iconRotate: [Expressions.get, 'heading'],
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        symbolSortKey: [Expressions.get, 'sort'],
      ),
    );
    await surface.addSymbolLayer(
      busesSource,
      badgeLayer,
      const SymbolLayerProperties(
        iconImage: [Expressions.get, 'badge'],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        symbolSortKey: [Expressions.get, 'sort'],
      ),
    );
  }

  /// Registers [id] once. It joins [_images] only after the surface accepted
  /// it, so a failed render or add is retried on the next update. A failure is
  /// logged and swallowed: one bad image must not stop the other buses.
  Future<void> _ensureImage(String id, Future<Uint8List> Function() render) async {
    if (_images.contains(id)) return;
    try {
      await surface.addImage(id, await render());
      _images.add(id);
    } catch (e) {
      if (kDebugMode) debugPrint('MapLayers: could not register image $id: $e');
    }
  }

  Future<void> updateBuses(List<BusMarker> markers) async {
    final features = <Map<String, dynamic>>[];
    for (final m in markers) {
      final badge = MarkerImages.badgeId(m.label, stale: m.stale, brightness: brightness);
      await _ensureImage(
        badge,
        () => MarkerImages.badge(label: m.label, hue: m.hue, stale: m.stale, brightness: brightness, pixelRatio: pixelRatio),
      );
      final notch = MarkerImages.notchId(m.hue, stale: m.stale);
      await _ensureImage(notch, () => MarkerImages.notch(hue: m.hue, stale: m.stale, pixelRatio: pixelRatio));
      features.add(_point(m.lat, m.lon, {
        'vehicleId': m.vehicleId,
        'badge': badge,
        'notch': notch,
        'heading': m.heading,
        'sort': m.stale ? 0 : 1,
      }, id: m.vehicleId));
    }
    await surface.setGeoJsonSource(busesSource, _collection(features));
  }

  Future<void> updateMyStop(StopInfo? stop) => surface.setGeoJsonSource(
        myStopSource,
        _collection([if (stop != null) _point(stop.stopLat, stop.stopLon, {'stopId': stop.stopId})]),
      );
}
