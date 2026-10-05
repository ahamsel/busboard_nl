import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:maplibre_gl/maplibre_gl.dart';

/// The slice of MapLibre the map layers use, so layer setup and updates are
/// tested against a fake. [MapLibreSurface] adapts a live controller.
abstract interface class MapSurface {
  Future<void> addImage(String name, Uint8List bytes);
  Future<void> addGeoJsonSource(String id, Map<String, dynamic> data);
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> data);
  Future<void> addCircleLayer(String sourceId, String layerId, CircleLayerProperties properties, {double? minzoom});
  Future<void> addSymbolLayer(String sourceId, String layerId, SymbolLayerProperties properties, {double? minzoom});
  Future<void> addLineLayer(String sourceId, String layerId, LineLayerProperties properties);
  Future<void> removeLayer(String layerId);
  Future<void> removeSource(String sourceId);
}

/// Camera moves the screen makes (my location, your stop).
abstract interface class MapCamera {
  double get zoom;
  Future<void> moveTo(LatLng target, double zoom, {required bool animate});
  Future<LatLng?> myLocation();

  /// Shows both points with [padding] kept clear (sheet, chips).
  Future<void> fitBounds(LatLng a, LatLng b, {required EdgeInsets padding, required bool animate});
}

class MapLibreSurface implements MapSurface, MapCamera {
  MapLibreSurface(this.controller);

  final MapLibreMapController controller;

  @override
  Future<void> addImage(String name, Uint8List bytes) => controller.addImage(name, bytes);

  @override
  Future<void> addGeoJsonSource(String id, Map<String, dynamic> data) => controller.addGeoJsonSource(id, data);

  @override
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> data) => controller.setGeoJsonSource(id, data);

  @override
  Future<void> addCircleLayer(String sourceId, String layerId, CircleLayerProperties properties, {double? minzoom}) =>
      controller.addCircleLayer(sourceId, layerId, properties, minzoom: minzoom, enableInteraction: false);

  @override
  Future<void> addSymbolLayer(String sourceId, String layerId, SymbolLayerProperties properties, {double? minzoom}) =>
      controller.addSymbolLayer(sourceId, layerId, properties, minzoom: minzoom, enableInteraction: false);

  @override
  Future<void> addLineLayer(String sourceId, String layerId, LineLayerProperties properties) =>
      controller.addLineLayer(sourceId, layerId, properties, enableInteraction: false);

  @override
  Future<void> removeLayer(String layerId) => controller.removeLayer(layerId);

  @override
  Future<void> removeSource(String sourceId) => controller.removeSource(sourceId);

  @override
  double get zoom => controller.cameraPosition?.zoom ?? 13;

  @override
  Future<void> moveTo(LatLng target, double zoom, {required bool animate}) async {
    final update = CameraUpdate.newLatLngZoom(target, zoom);
    if (animate) {
      await controller.animateCamera(update);
    } else {
      await controller.moveCamera(update);
    }
  }

  @override
  Future<void> fitBounds(LatLng a, LatLng b, {required EdgeInsets padding, required bool animate}) async {
    final bounds = LatLngBounds(
      southwest: LatLng(math.min(a.latitude, b.latitude), math.min(a.longitude, b.longitude)),
      northeast: LatLng(math.max(a.latitude, b.latitude), math.max(a.longitude, b.longitude)),
    );
    final update = CameraUpdate.newLatLngBounds(
      bounds,
      left: padding.left,
      top: padding.top,
      right: padding.right,
      bottom: padding.bottom,
    );
    if (animate) {
      await controller.animateCamera(update);
    } else {
      await controller.moveCamera(update);
    }
  }

  @override
  Future<LatLng?> myLocation() => controller.requestMyLocationLatLng();
}
