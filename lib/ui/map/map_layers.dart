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

/// How a bus is drawn while a bus is being followed (spec §3.2).
enum MarkerEmphasis { normal, followed, dimmed }

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
    this.emphasis = MarkerEmphasis.normal,
  });

  final String vehicleId;
  final double lat;
  final double lon;
  final double heading;
  final String label;
  final RouteHue hue;
  final bool stale;
  final MarkerEmphasis emphasis;
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
/// badge (spec §3.2). An empty [routeFilter] shows every route. While
/// [followedVehicleId] is set, that bus is [MarkerEmphasis.followed] and every
/// other bus [MarkerEmphasis.dimmed].
List<BusMarker> busMarkers({
  required Map<String, BusTrackingState> tracking,
  required Map<String, RenderedBus> drawn,
  required Set<int> routeFilter,
  required HeadingSmoother headings,
  required DateTime now,
  String? followedVehicleId,
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
      emphasis: followedVehicleId == null
          ? MarkerEmphasis.normal
          : (id == followedVehicleId ? MarkerEmphasis.followed : MarkerEmphasis.dimmed),
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
/// top: followed route (casing, line), stops, your stop, bus notches, bus
/// badges. [install] runs after every style load (a style switch clears
/// everything natively); updates are cheap GeoJSON swaps that register any new marker image first.
class MapLayers {
  MapLayers(this.surface, {required this.brightness, required this.pixelRatio});

  final MapSurface surface;
  final Brightness brightness;
  final double pixelRatio;

  static const routeSource = 'bb-route';
  static const routeCasingLayer = 'bb-route-casing';
  static const routeLineLayer = 'bb-route-line';
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
    // onStyleLoaded can fire more than once for the same native style (the iOS
    // plugin re-applies the style on creation), so a second install finds our
    // layers and sources already there. Clear them first, layers before the
    // sources they draw from; on a fresh style there is nothing to remove.
    for (final layer in [badgeLayer, notchLayer, myStopLayer, stopsLayer, routeLineLayer, routeCasingLayer]) {
      try {
        await surface.removeLayer(layer);
      } catch (_) {}
    }
    for (final source in [busesSource, myStopSource, stopsSource, routeSource]) {
      try {
        await surface.removeSource(source);
      } catch (_) {}
    }
    _images.clear();
    await surface.addImage(MarkerImages.myStopId, await MarkerImages.myStop(brightness: brightness, pixelRatio: pixelRatio));
    _images.add(MarkerImages.myStopId);

    await surface.addGeoJsonSource(routeSource, _collection(const []));
    await surface.addLineLayer(
      routeSource,
      routeCasingLayer,
      LineLayerProperties(
        lineColor: _hex(RoutePalette.ink),
        lineWidth: 9.0,
        lineOpacity: [
          Expressions.multiply,
          0.3,
          [Expressions.get, 'opacity'],
        ],
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await surface.addLineLayer(
      routeSource,
      routeLineLayer,
      const LineLayerProperties(
        lineColor: [Expressions.get, 'color'],
        lineWidth: 6.0,
        lineOpacity: [Expressions.get, 'opacity'],
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );

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
        iconSize: [Expressions.get, 'scale'],
        iconOpacity: [Expressions.get, 'opacity'],
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
        iconSize: [Expressions.get, 'scale'],
        iconOpacity: [Expressions.get, 'opacity'],
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

  /// The ids of [m]'s two images.
  (String badge, String notch) _imageIds(BusMarker m) =>
      (MarkerImages.badgeId(m.label, stale: m.stale, brightness: brightness), MarkerImages.notchId(m.hue, stale: m.stale));

  bool _hasImages(BusMarker m) {
    final (badge, notch) = _imageIds(m);
    return _images.contains(badge) && _images.contains(notch);
  }

  Map<String, dynamic> _busFeature(BusMarker m) {
    final (badge, notch) = _imageIds(m);
    return _point(m.lat, m.lon, {
      'vehicleId': m.vehicleId,
      'badge': badge,
      'notch': notch,
      'heading': m.heading,
      'scale': m.emphasis == MarkerEmphasis.followed ? 1.35 : 1.0,
      'opacity': m.emphasis == MarkerEmphasis.dimmed ? 0.35 : 1.0,
      'sort': m.emphasis == MarkerEmphasis.followed ? 2 : (m.stale ? 0 : 1),
    }, id: m.vehicleId);
  }

  /// Draws [markers]. Marker images are made one at a time, and on a busy or
  /// slow device (an emulator takes seconds per image) a whole fleet's worth
  /// would keep every bus off the map for a minute or more. So the buses whose
  /// images are already registered are published first, and again each time
  /// another route's images arrive; the last publish has every marker.
  Future<void> updateBuses(List<BusMarker> markers) async {
    var published = markers.where(_hasImages).length;
    if (published > 0 && published < markers.length) {
      await surface.setGeoJsonSource(busesSource, _collection([for (final m in markers.where(_hasImages)) _busFeature(m)]));
    }
    for (final m in markers) {
      if (_hasImages(m)) continue;
      final (badge, notch) = _imageIds(m);
      await _ensureImage(
        badge,
        () => MarkerImages.badge(label: m.label, hue: m.hue, stale: m.stale, brightness: brightness, pixelRatio: pixelRatio),
      );
      await _ensureImage(notch, () => MarkerImages.notch(hue: m.hue, stale: m.stale, pixelRatio: pixelRatio));
      final ready = markers.where(_hasImages).length;
      if (ready > published && ready < markers.length) {
        published = ready;
        await surface.setGeoJsonSource(busesSource, _collection([for (final b in markers.where(_hasImages)) _busFeature(b)]));
      }
    }
    await surface.setGeoJsonSource(busesSource, _collection([for (final m in markers) _busFeature(m)]));
  }

  Future<void> updateMyStop(StopInfo? stop) => surface.setGeoJsonSource(
        myStopSource,
        _collection([if (stop != null) _point(stop.stopLat, stop.stopLon, {'stopId': stop.stopId})]),
      );

  /// The followed trip's line (spec §3.2): the part already driven at 40%.
  Future<void> updateRoute({required List<List<double>> driven, required List<List<double>> ahead, required Color color}) {
    Map<String, dynamic> line(List<List<double>> coords, String part, double opacity) => {
          'type': 'Feature',
          'geometry': {'type': 'LineString', 'coordinates': coords},
          'properties': {'part': part, 'opacity': opacity, 'color': _hex(color)},
        };
    return surface.setGeoJsonSource(routeSource, _collection([line(driven, 'driven', 0.4), line(ahead, 'ahead', 1.0)]));
  }

  Future<void> clearRoute() => surface.setGeoJsonSource(routeSource, _collection(const []));
}
